//
//  LayerInspectorWindowController.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 15.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "LayerInspectorWindowController.h"

#import "GMDocument.h"
#import "LayerInspectorView.h"
#import "Slicer.h"
#import "SlicedOutline.h"
#import "PolygonSkeletizer.h"

@interface LayerInspectorWindowController ()

@end

@implementation LayerInspectorWindowController
{
	PolygonSkeletizer* skeletizer;
}

@synthesize layerView, layerSelector;

+ (LayerInspectorWindowController*) sharedInspector
{
	static dispatch_once_t onceToken;
	static id sharedInspector = nil;
	dispatch_once(&onceToken, ^{
		
		sharedInspector = [[LayerInspectorWindowController alloc] initWithWindowNibName: @"LayerInspectorWindow"];
	});
	
	return sharedInspector;
}

- (id)initWithWindow:(NSWindow *)window
{
    if (!(self = [super initWithWindow:window]))
		return nil;
	
	return self;
}

- (void) setDocument:(NSDocument *)document
{
	[super setDocument: document];
	
	[self layersChanged];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
 	[self layersChanged];
   // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

/*
- (void) setupSkeletizer
{
	skeletizer = [[PolygonSkeletizer alloc] init];
	SlicedLayer* slice = [self currentLayer];
	skeletizer.mergeThreshold = slice.mergeThreshold;
	
	for (SlicedOutline* outline in slice.outlinePaths)
	{
			[outline generateSkeletonWithMergeThreshold: 0.5*mergeThreshold];
	}

	
	[slice addPathsToSkeletizer: skeletizer];
	
	[skeletizer generateSkeleton];

}
*/
- (void) layersChanged
{
	NSArray* layers = [self.document slicedLayers];
	NSArray* keys = [layers map:^id(SlicedLayer* obj) {
		return [NSNumber numberWithDouble: obj.layerZ];
	}];
	
	keys = [keys sortedArrayUsingSelector: @selector(compare:)];
	
	[self.layerSelector removeAllItems];
	[self.layerSelector addItemsWithTitles: [keys map:^id(id obj) { return [NSString stringWithFormat:@"%.3f mm", [obj doubleValue]]; }]];
	if (keys.count)
		[self.layerSelector selectItemAtIndex: 0];
	
	
	[self layerSelected: self.layerSelector];
}

- (SlicedLayer*) currentLayer
{
	NSArray* layers = [self.document slicedLayers];
	if (!layers.count)
		return nil;
	layers = [layers sortedArrayUsingComparator:^NSComparisonResult(SlicedLayer* obj1, SlicedLayer* obj2) {
		float f = obj2.layerZ - obj1.layerZ;
		return f > 0.0 ? NSOrderedAscending : f < 0.0 ? NSOrderedDescending : NSOrderedSame;
	}];
	
	
	return [layers objectAtIndex: self.layerSelector.indexOfSelectedItem];

}

- (IBAction) runSlicing: (id) sender
{
	[layerView removeAllOffsetOutlinePaths];
	SlicedLayer* slice = [self currentLayer];
	
	for (SlicedOutline* outline in slice.outlinePaths)
	{
		skeletizer = [[PolygonSkeletizer alloc] init];
		skeletizer.mergeThreshold = slice.mergeThreshold;
		skeletizer.extensionLimit = [self.extensionLimitField doubleValue];
		skeletizer.emitCallback = ^(PolygonSkeletizer* skel, NSBezierPath* bpath)
		{
			SuppressSelfCaptureWarning([layerView addOffsetOutlinePath: bpath]);
		};
		[outline addPathsToSkeletizer: skeletizer];
		[skeletizer generateSkeleton];
		
		layerView.motorcyclePaths = [skeletizer motorcycleDisplayPaths];
		layerView.spokePaths = [skeletizer spokeDisplayPaths];
	}

}

- (IBAction) displayOptionsChanged:(id)sender
{
	[layerView setNeedsDisplay: YES];
}

- (IBAction) layerSelected:(NSPopUpButton*)sender
{
		
	self.layerView.slice = [self currentLayer];
	
	[self.outlineSelector removeAllItems];
	int k = 0;
	for (SlicedOutline* outline in [self currentLayer].outlinePaths)
		[self.outlineSelector addItemWithTitle: [NSString stringWithFormat:@"Outline #%d", k++]];

	[self outlineSelected: self.outlineSelector];
}
- (IBAction) outlineSelected:(NSPopUpButton*)sender
{
	
	self.layerView.indexOfSelectedOutline = [sender indexOfSelectedItem];
}

- (IBAction) copy:(id)sender
{
	NSPasteboard *pb = [NSPasteboard generalPasteboard];
	[pb declareTypes: @[ NSPasteboardTypePDF ] owner: self];
	[layerView writePDFInsideRect: layerView.bounds toPasteboard: pb];

}

- (void) layerDidLoad: (SlicedLayer*) layer
{
	[self layersChanged];
}

@end
