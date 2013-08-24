//
//  GMDocumentWindowController.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 15.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "GMDocumentWindowController.h"

#import "GMDocument.h"
#import "PathView2D.h"
#import "ModelView3D.h"
#import "Slicer.h"
#import "LayerInspectorView.h"
#import "Slicer.h"
#import "SlicedOutline.h"
#import "PolygonSkeletizer.h"
#import "GM3DPrinterDescription.h"
#import "PSWaveFrontSnapshot.h"
#import "MPVector2D.h"
#import "PolySkelVideoGenerator.h"
#import "FixPolygon.h"

#import "FoundationExtensions.h"

@import AVFoundation;
@import CoreVideo;

@class PolygonSkeletizer;

@interface GMDocumentWindowController ()

@end

@implementation GMDocumentWindowController
{
	PolygonSkeletizer* skeletizer;
}


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
	
	[self addObserver: self forKeyPath: @"waveFrontPhaseCount" options: NSKeyValueObservingOptionNew context: nil];
	[self addObserver: self forKeyPath: @"displayWaveFrontPhaseNumber" options: NSKeyValueObservingOptionNew context: nil];
	[self.document addObserver: self forKeyPath: @"contourPolygons" options: NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context: nil];

}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == self)
	{
		if ([keyPath isEqualToString: @"waveFrontPhaseCount"])
		{
			if (self.displayWaveFrontPhaseNumber >= self.waveFrontPhaseCount)
			{
				if (self.waveFrontPhaseCount)
					self.displayWaveFrontPhaseNumber = self.waveFrontPhaseCount-1;
				else
					self.displayWaveFrontPhaseNumber = 0;
			}
		}
		if ([keyPath isEqualToString: @"displayWaveFrontPhaseNumber"])
		{
			layerView.needsDisplay = YES;
			
			PolySkelPhase* phase = [skeletizer.doneSteps objectAtIndex: MIN(self.displayWaveFrontPhaseNumber, self.waveFrontPhaseCount-1)];
			
			layerView.markerPaths = @[];
			
			if (phase.location)
			{
				vector_t loc = phase.location.toFloatVector;
				CGPoint X = CGPointMake(loc.farr[0], loc.farr[1]);
				
				NSBezierPath* bpath = [NSBezierPath bezierPathWithOvalInRect: CGRectMake(X.x-1.0, X.y-1.0, 2.0, 2.0)];
				
				layerView.markerPaths = @[bpath];
			}
			
			layerView.motorcyclePaths = phase.motorcyclePaths;
			layerView.activeSpokePaths = phase.activeSpokePaths;
			layerView.terminatedSpokePaths = phase.terminatedSpokePaths;
			[layerView removeAllOffsetOutlinePaths];
			[layerView addOffsetOutlinePaths: phase.waveFrontPaths];

			NSString* logString = [phase.eventLog componentsJoinedByString: @"\n"];
			
			self.statusTextView.string = (logString ? logString : @"no event log");
			
			layerView.needsDisplay = YES;
		}
	}
	else if (object == self.document)
	{
		if ([keyPath isEqualToString: @"contourPolygons"])
		{
			self.modelView.contours = [[self.document contourPolygons] map:^id(FixPolygon* obj) {
				return obj.gfxMesh;
			}];
		}

	}
}

- (void) windowDidBecomeMain: (NSNotification*) notification
{

}

- (void) layerDidLoad: (SlicedLayer*) layer
{
	self.modelView.layers = [self.modelView.layers dictionaryBySettingObject: [layer gfxMesh] forKey: [NSNumber numberWithDouble: layer.layerZ]];
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
	
	[self.modelView setNeedsRendering];
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

- (NSUInteger) waveFrontPhaseCount
{
	return skeletizer.doneSteps.count;
}

- (void) prepareLayerSlicing
{
	[layerView removeAllOffsetOutlinePaths];
	[layerView removeAllOffsetBoundaryPaths];
	
	SlicedLayer* slice = [self currentLayer];

	skeletizer = [[PolygonSkeletizer alloc] init];

	SlicedOutline* srcOutline = [slice.outlinePaths objectAtIndex: [self.outlineSelector indexOfSelectedItem]];
	
	NSArray* outlines = @[ srcOutline ];

	if (layerView.clippingOutline)
	{
		outlines = [srcOutline booleanIntersectOutline: layerView.clippingOutline];
	}

	GM3DPrintSettings* settings = [GM3DPrintSettings defaultPrintSettings];

	NSMutableArray* emissionTimes = [NSMutableArray arrayWithCapacity: settings.numPerimeters];
	double extrusionWidth_m = [settings extrusionWidthForExtruder: 0];
	
	double offset_m = 0.5*extrusionWidth_m;
	for (int i = 0; i < settings.numPerimeters; ++i)
	{
		double emit = offset_m + i*extrusionWidth_m;
		[emissionTimes addObject: [NSNumber numberWithDouble: emit*1000.0]]; // scale m -> mm
	}
	

	skeletizer.mergeThreshold = slice.mergeThreshold;
	NSString* extensionString = [self.extensionLimitField stringValue];
	if (!extensionString.length)
		skeletizer.emissionTimes = emissionTimes;
	else
	{
		double limit = [self.extensionLimitField doubleValue];
		skeletizer.extensionLimit = limit;
		extrusionWidth_m = 0.001;
		
		NSMutableArray* times = [NSMutableArray array];
		
		for (double i = 0.0; i < limit; i += 0.5)
		{
			NSNumber* num = [NSNumber numberWithDouble: i];
			[times addObject: num];
		}
		[times addObject: [NSNumber numberWithDouble: limit]];
		skeletizer.emissionTimes = times;
		
	}
		
	
	for (SlicedOutline* outline in outlines)
	{
		[outline addPathsToSkeletizer: skeletizer];
	}

}

- (IBAction) runSlicing: (id) sender
{
	[self prepareLayerSlicing];
	
	GM3DPrintSettings* settings = [GM3DPrintSettings defaultPrintSettings];
	double extrusionWidth_m = [settings extrusionWidthForExtruder: 0];

	
	NSMutableArray* outlinePaths = [NSMutableArray array];
	NSMutableArray* cyclePaths = [NSMutableArray array];
	NSMutableArray* spokePaths = [NSMutableArray array];
	NSMutableArray* snapshots = [NSMutableArray array];
	NSMutableArray* overfillPaths = [NSMutableArray array];
	NSMutableArray* underfillPaths = [NSMutableArray array];
	
	
	__block BOOL isBoundary = NO;
	skeletizer.emitCallback = ^(PolygonSkeletizer* skeletizer, PSWaveFrontSnapshot* snapshot)
	{
		[snapshots addObject: snapshot];
		id bpath = [snapshot waveFrontPath];
		if (isBoundary)
			SuppressSelfCaptureWarning([layerView addOffsetOutlinePath: bpath]);
		else
			SuppressSelfCaptureWarning([layerView addOffsetBoundaryPath: bpath]);
		isBoundary = !isBoundary;
	};
	
	[self willChangeValueForKey: @"waveFrontPhaseCount"];

	[skeletizer generateSkeleton];
	
	[self didChangeValueForKey: @"waveFrontPhaseCount"];

	[outlinePaths addObjectsFromArray: [skeletizer outlineDisplayPaths]];
	[spokePaths addObjectsFromArray: [skeletizer spokeDisplayPaths]];
	[cyclePaths addObjectsFromArray: [skeletizer motorcycleDisplayPaths]];
	
	isBoundary = NO;
	
	
	for (PSWaveFrontSnapshot* snapshot in snapshots)
	{
		//[thinWallPaths addObjectsFromArray: [skeletizer waveFrontOutlinesTerminatedAfter:snapshot.time - 0.5*extrusionWidth_m*1e3 upTo: snapshot.time + 0.5*extrusionWidth_m*1e3]];
		if (isBoundary)
			[overfillPaths addObject: [snapshot thinWallAreaLessThanWidth: 0.5*extrusionWidth_m*1e3 + 0.01]];
		else
			[underfillPaths addObject: [snapshot thinWallAreaLessThanWidth: 0.5*extrusionWidth_m*1e3 + 0.01]];
		isBoundary = !isBoundary;
	}

	layerView.motorcyclePaths = cyclePaths;
	layerView.activeSpokePaths = nil;
	layerView.terminatedSpokePaths = spokePaths;
	layerView.outlinePaths = outlinePaths;
	layerView.underfillPaths = underfillPaths;
	layerView.overfillPaths	= overfillPaths;
	
}

- (IBAction) exportMovie:(id)sender
{
	int result = 0;
	
	NSSavePanel*	panel = [NSSavePanel savePanel];
	[panel setTitle: @"Export Layer Slicing Movie"];
	[panel setAllowedFileTypes: @[@"mov"]];
	
	
	result = [panel runModal];
	if (result == NSOKButton)
	{
		PolySkelVideoGenerator* exporter = [[PolySkelVideoGenerator alloc] init];
		
		[self.progressIndicator startAnimation: self];
		
		[exporter recordMovieToURL: panel.URL withSize: CGSizeMake(1280.0, 720.0) skeleton: skeletizer finishedCallback:^{
			[self.progressIndicator stopAnimation: self];
		}];
			
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
