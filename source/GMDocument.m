//
//  Document.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 31.08.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import "GMDocument.h"

#import "GMDocumentWindowController.h"

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
#import "STLFile.h"
#import "ShapeUtilities.h"
#import "FixPolygon.h"
#import "PolygonContour.h"


@implementation GMDocument
{
	NSArray* machineCommands;
	
	NSArray* slicedLayers;
	
	NSArray* contourPolygons;
	
	dispatch_queue_t processingQueue;
}

@synthesize mainWindowController, slicedLayers, contourPolygons;

- (id)init
{
    if (!(self = [super init]))
		return nil;

	processingQueue = dispatch_queue_create("gmdocument.processing", DISPATCH_QUEUE_SERIAL);
	
	slicedLayers = @[];
	machineCommands = @[];
	contourPolygons = @[];
	
	return self;
}

- (void) dealloc
{
	dispatch_release(processingQueue);
}

- (void) makeWindowControllers
{
	mainWindowController = [[GMDocumentWindowController alloc] initWithWindowNibName: @"GMDocument"];
	
	[self addWindowController: mainWindowController];
	
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
	
	if ([typeName isEqual: @"com.elmonkey.stl"])
	{
		[self loadSTLFromData: data];
		return YES;
	}
	else if ([typeName isEqual: @"com.adobe.encapsulated-postscript"])
	{
		[self loadEPSFromData: data];
		return YES;
	}
	
	
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
	
	[self.mainWindowController.pathView resetPaths];
	[self.mainWindowController.pathView generatePathsWithMachineCommands: machineCommands];
	
	[self.mainWindowController.modelView generateMovePathWithMachineCommands: machineCommands];
	
	[[self.mainWindowController.statusTextView.textStorage mutableString] appendString: [results description]];
	
	

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

- (void) layerDidLoad: (SlicedLayer*) layer
{	
	for (id wc in self.windowControllers)
	{
		if ([wc respondsToSelector: @selector(layerDidLoad:)])
			[wc layerDidLoad: layer];
	}
	
}



- (void) loadEPSFromData: (NSData*) data
{
	NSBezierPath* bpath = [ShapeUtilities createBezierPathFromData: data];
	
	FixPolygon* polygon = [FixPolygon polygonFromBezierPath: bpath withTransform: nil flatness: 0.1];
	
	PolygonContour* contour = [[PolygonContour alloc] init];
	contour.polygon = polygon;
	[contour generateToolpathWithOffset: 3.0];
	
	
	[self willChangeValueForKey: @"contourPolygons"];
	
	
	
	contourPolygons = [contourPolygons arrayByAddingObject: contour];

	[self didChangeValueForKey: @"contourPolygons"];
}

- (void) loadSTLFromData: (NSData*) data
{
	
	STLFile* stl = [[STLFile alloc] initWithData: data scale: 16 transform: mIdentity()];
	
	GfxMesh* mesh = LoadSTLFileFromData(data);
	
	if (!mesh)
		[[self.mainWindowController.statusTextView.textStorage mutableString] appendString: @"oops, failed to load STL file"];
	
	Slicer* slicer = [[Slicer alloc] init];
	
	NSMutableArray* heights = [NSMutableArray array];
	
	range3d_t bounds = [mesh vertexBounds];
	
	for (double i = bounds.minv.farr[2]+0.5; i < bounds.maxv.farr[2]; i += 1.0)
	{
		[heights addObject: [NSNumber numberWithDouble: i]];
	}
	
	[slicer asyncSliceSTL: stl intoLayers: heights layersWithCallbackOnQueue: dispatch_get_main_queue() block: ^(SlicedLayer* layer) {
		slicedLayers = [slicedLayers arrayByAddingObject: layer];
		[self layerDidLoad: layer];
	}];
	
	/*
	[slicer asyncSliceModel: mesh intoLayers: heights layersWithCallbackOnQueue: dispatch_get_main_queue() block: ^(SlicedLayer* layer) {
		
		slicedLayers = [slicedLayers arrayByAddingObject: layer];
		[self layerDidLoad: layer];
		
	}];
	*/
	/*
	 NSArray* layers = [slicer sliceModel: mesh intoLayers: heights];
	 
	 
	 for (SlicedLayer* layer in layers)
	 [layerMesh appendMesh: [layer layerMesh]];
	 */
	
}

- (void) loadSTLAtPath: (NSString*) path
{
	NSData* data = [NSData dataWithContentsOfFile: path];
	if (!data)
		return;
	
	[self loadSTLFromData: data];
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
