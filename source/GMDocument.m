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

#import "FoundationExtensions.h"

@implementation GMDocument

@synthesize statusTextView;

- (id)init
{
    self = [super init];
    if (self) {
		// Add your subclass-specific initialization here.
    }
    return self;
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
	
	
	[self.pathView resetPaths];
	[self.pathView generatePathsWithMachineCommands: interpreter.machineCommands];
	
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

@end
