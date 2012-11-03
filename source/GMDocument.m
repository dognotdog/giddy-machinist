//
//  Document.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 31.08.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import "GMDocument.h"

#import "RS274Parser.h"
#import "RS274Interpreter.h"
#import "PathView2D.h"
#import "ModelView3D.h"
#import "MachineSimulator.h"
#import "gfx.h"
#import "Slicer.h"
#import "SlicedOutline.h"
#import "PolygonSkeletizer.h"

#import "FoundationExtensions.h"


GfxMesh* LoadSTLFileAtPath(NSString* path)
{
	NSData* data = [NSData dataWithContentsOfFile: path];
	if (!data)
		return nil;
	
	const size_t headerLength = 80;
	const size_t trianglesStart = 84;
	const size_t triangleLength = 50;
	
	const void* buf = [data bytes];
	assert([data length] > trianglesStart);
	
	size_t numTris = CFSwapInt32LittleToHost(*(uint32_t*)(buf+headerLength));
	size_t datalen = [data length];
	assert(datalen == trianglesStart+numTris*triangleLength);
	
	vector_t* vertices = calloc(numTris*3, sizeof(*vertices));
	vector_t* colors = calloc(numTris*3, sizeof(*colors));
	vector_t* normals = calloc(numTris*3, sizeof(*normals));
	
	for (size_t i = 0; i < numTris; ++i)
	{
		size_t vertexOffset = trianglesStart+triangleLength*i + 12;
		float n[3];
		memcpy(n, buf+vertexOffset, 12);
		for (size_t j = 0; j < 3; ++j)
		{
			normals[3*i+j] = vCreatePos(n[0], n[1], n[2]);
		}
		
		
		for (size_t j = 0; j < 3; ++j)
		{
			float x[3];
			memcpy(x, buf+vertexOffset+j*12, 12);
			vertices[3*i+j] = vCreatePos(x[0], x[1], x[2]);
		}
		uint16_t color = CFSwapInt16LittleToHost(*(uint16_t*)(buf+vertexOffset+4*12));
		for (size_t j = 0; j < 3; ++j)
		{
			colors[3*i+j] = vCreatePos(((color & 0x001F)*255)/15L, (((color & 0x03E0) >> 5)*255)/15L, (((color & 0x7C0) >> 10)*255)/15L);
		}
		
	}
	
	GfxMesh* mesh = [[GfxMesh alloc] init];
	[mesh addVertices: vertices count: numTris*3];
//	[mesh addColors: colors count: numTris*3];
	[mesh addNormals: normals count: numTris*3];
	free(vertices);
	free(colors);
	free(normals);
	
	uint32_t* indices = calloc(numTris*3, sizeof(*indices));
	
	for (size_t i = 0; i < numTris*3; ++i)
		indices[i]=i;
	
	[mesh addDrawArrayIndices: indices count: numTris*3 withMode: GL_TRIANGLES];
	
	free(indices);
	
	
	return mesh;
}

@implementation GMDocument
{
	NSArray* machineCommands;
	
	dispatch_queue_t processingQueue;
}

@synthesize statusTextView, modelView, pathView;

- (id)init
{
    if (!(self = [super init]))
		return nil;

	processingQueue = dispatch_queue_create("gmdocument.processing", DISPATCH_QUEUE_SERIAL);
	
	
	
	return self;
}

- (void) dealloc
{
	dispatch_release(processingQueue);
}

- (NSString *)windowNibName
{
	// Override returning the nib file name of the document
	// If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this method and override -makeWindowControllers instead.
	return @"GMDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)aController
{
	[super windowControllerDidLoadNib:aController];
	// Add any code here that needs to be executed once the windowController has loaded the document's window.
}

+ (BOOL)autosavesInPlace
{
    return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
	// Insert code here to write your document to data of the specified type. If outError != NULL, ensure that you create and set an appropriate error when returning nil.
	// You can also choose to override -fileWrapperOfType:error:, -writeToURL:ofType:error:, or -writeToURL:ofType:forSaveOperation:originalContentsURL:error: instead.
	NSException *exception = [NSException exceptionWithName:@"UnimplementedMethod" reason:[NSString stringWithFormat:@"%@ is unimplemented", NSStringFromSelector(_cmd)] userInfo:nil];
	@throw exception;
	return nil;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
	// Insert code here to read your document from the given data of the specified type. If outError != NULL, ensure that you create and set an appropriate error when returning NO.
	// You can also choose to override -readFromFileWrapper:ofType:error: or -readFromURL:ofType:error: instead.
	// If you override either of these, you should also override -isEntireFileLoaded to return NO if the contents are lazily loaded.
	NSException *exception = [NSException exceptionWithName:@"UnimplementedMethod" reason:[NSString stringWithFormat:@"%@ is unimplemented", NSStringFromSelector(_cmd)] userInfo:nil];
	@throw exception;
	return YES;
}


- (void) loadGCodeAtPath: (NSString*) path
{
	NSString* fileContent = [NSString stringWithContentsOfFile: path encoding: NSASCIIStringEncoding error: nil];
	
	RS274Parser* parser = [[RS274Parser alloc] init];
	[parser parseString: fileContent named: path];
	
	RS274Interpreter* interpreter = [[RS274Interpreter alloc] init];
	
	NSArray* results = [parser.commandBlocks map:^id(id obj) {
		return [interpreter interpretCommandBlock: obj];
	}];
	
	machineCommands = interpreter.machineCommands;
	
	[self.pathView resetPaths];
	[self.pathView generatePathsWithMachineCommands: machineCommands];
	
	[[self.statusTextView.textStorage mutableString] appendString: [results description]];
	
	

}

- (IBAction) importGCode:(id)sender
{
	int result = 0;
	
	NSOpenPanel*	oPanel = [NSOpenPanel openPanel];
	[oPanel setAllowsMultipleSelection: NO];
	[oPanel setTitle: @"Import G-Code File"];
	
	
	result = [oPanel runModal];
	if (result == NSOKButton)
	{
		NSArray*	filesToOpen = [oPanel URLs];
		
		int count = [filesToOpen count];
		
		for (int i = 0; i < count; ++i)
		{
			NSString*	aFile = [[filesToOpen objectAtIndex: i] path];
			
			[self loadGCodeAtPath: aFile];

			break;
		}
	}

}

- (void) loadSTLAtPath: (NSString*) path
{
	
	GfxMesh* mesh = LoadSTLFileAtPath(path);

	if (!mesh)
		[[self.statusTextView.textStorage mutableString] appendString: @"oops, failed to load STL file"];
	
	Slicer* slicer = [[Slicer alloc] init];
	
	NSMutableArray* heights = [NSMutableArray array];
	
	range3d_t bounds = [mesh vertexBounds];
	
	for (double i = bounds.minv.farr[2]+0.5; i < bounds.maxv.farr[2]; i += 1.0)
	{
		[heights addObject: [NSNumber numberWithDouble: i]];
	}
	
	[slicer asyncSliceModel: mesh intoLayers: heights layersWithCallbackOnQueue: dispatch_get_main_queue() block: ^(SlicedLayer* layer) {
		
		modelView.models = [modelView.models arrayByAddingObject: [layer layerMesh]];
		
	}];
	
	/*
	NSArray* layers = [slicer sliceModel: mesh intoLayers: heights];
	
	
	for (SlicedLayer* layer in layers)
		[layerMesh appendMesh: [layer layerMesh]];
	*/
	
}

- (IBAction) importSTL:(id)sender
{
	int result = 0;
	
	NSOpenPanel*	oPanel = [NSOpenPanel openPanel];
	[oPanel setAllowsMultipleSelection: NO];
	[oPanel setAllowedFileTypes: [NSArray arrayWithObjects:@"STL", nil]];
	[oPanel setTitle: @"Import STL 3D Model"];
	
	
	result = [oPanel runModal];
	if (result == NSOKButton)
	{
		NSArray*	filesToOpen = [oPanel URLs];
		
		int count = [filesToOpen count];
		
		for (int i = 0; i < count; ++i)
		{
			NSString*	aFile = [[filesToOpen objectAtIndex: i] path];
			
			[self loadSTLAtPath: aFile];
			
			break;
		}
	}
	
}


- (IBAction) runSimulation:(id)sender
{
	MachineSimulator* machineSim = [[MachineSimulator alloc] init];
	
	
}

@end
