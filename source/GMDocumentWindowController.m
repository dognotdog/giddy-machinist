//
//  GMDocumentWindowController.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 15.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "GMDocumentWindowController.h"

#import "GMDocument.h"
#import "LayerInspectorWindowController.h"
#import "PathView2D.h"
#import "ModelView3D.h"
#import "Slicer.h"
#import "LayerInspectorView.h"
#import "Slicer.h"
#import "SlicedOutline.h"
#import "PolygonSkeletizer.h"

#import "FoundationExtensions.h"

@interface GMDocumentWindowController ()

@end

@implementation GMDocumentWindowController

@synthesize layerSelector, layerView;

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
	
}

- (void) windowDidBecomeMain: (NSNotification*) notification
{
	LayerInspectorWindowController* inspector = [LayerInspectorWindowController sharedInspector];
	[self.document addWindowController: inspector];
}

- (void) layerDidLoad: (SlicedLayer*) layer
{
	self.modelView.layers = [self.modelView.layers dictionaryBySettingObject: [layer layerMesh] forKey: [NSNumber numberWithDouble: layer.layerZ]];
	[self layersChanged];

}

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
	
	NSMutableArray* outlinePaths = [NSMutableArray array];
	NSMutableArray* cyclePaths = [NSMutableArray array];
	NSMutableArray* spokePaths = [NSMutableArray array];
	
	//for (SlicedOutline* outline in slice.outlinePaths)
	SlicedOutline* outline = [slice.outlinePaths objectAtIndex: [self.outlineSelector indexOfSelectedItem]];
	{
		PolygonSkeletizer* skeletizer = [[PolygonSkeletizer alloc] init];
		skeletizer.mergeThreshold = slice.mergeThreshold;
		skeletizer.extensionLimit = [self.extensionLimitField doubleValue];
		skeletizer.emitCallback = ^(PolygonSkeletizer* skel, NSBezierPath* bpath)
		{
			SuppressSelfCaptureWarning([layerView addOffsetOutlinePath: bpath]);
		};
		[outline addPathsToSkeletizer: skeletizer];
		[skeletizer generateSkeleton];
		
		[outlinePaths addObjectsFromArray: [skeletizer outlineDisplayPaths]];
		[spokePaths addObjectsFromArray: [skeletizer spokeDisplayPaths]];
		[cyclePaths addObjectsFromArray: [skeletizer motorcycleDisplayPaths]];
	}
	
	layerView.motorcyclePaths = cyclePaths;
	layerView.spokePaths = spokePaths;
	layerView.outlinePaths = outlinePaths;
	
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
	if ([self currentLayer].outlinePaths.count)
		[self.outlineSelector selectItemAtIndex: 0];
	
	[self outlineSelected: self.outlineSelector];
}
- (IBAction) outlineSelected:(NSPopUpButton*)sender
{
	
	layerView.indexOfSelectedOutline = [sender indexOfSelectedItem];
}

- (IBAction) copy:(id)sender
{
	NSPasteboard *pb = [NSPasteboard generalPasteboard];
	[pb declareTypes: @[ NSPasteboardTypePDF ] owner: self];
	[layerView writePDFInsideRect: layerView.bounds toPasteboard: pb];
	
}


@end
