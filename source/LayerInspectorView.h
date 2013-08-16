//
//  LayerInspectorView.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 15.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class SlicedLayer, SlicedOutline;

@interface LayerInspectorView : NSView

@property(nonatomic, strong) SlicedLayer* slice;
@property(nonatomic, strong) SlicedOutline* clippingOutline;
@property(nonatomic) NSInteger indexOfSelectedOutline;
@property(nonatomic, strong) NSArray* motorcyclePaths;
@property(nonatomic, strong) NSArray* spokePaths;
@property(nonatomic, strong) NSArray* outlinePaths;
@property(nonatomic, strong) NSArray* markerPaths;

//@property(nonatomic, strong) NSArray* thinWallPaths;
@property(nonatomic, strong) NSArray* overfillPaths;
@property(nonatomic, strong) NSArray* underfillPaths;
@property(nonatomic) CGPoint cursor, mouseDragLocationInSlice, mouseDownLocationInSlice, mouseUpLocationInSlice;

- (void) addOffsetOutlinePath: (NSBezierPath*) bpath;
- (void) addOffsetOutlinePaths: (NSArray*) paths;
- (void) removeAllOffsetOutlinePaths;

- (void) addOffsetBoundaryPath: (NSBezierPath*) bpath;
- (void) removeAllOffsetBoundaryPaths;

- (void) drawRect: (NSRect)dirtyRect withOutline: (BOOL) displayOutline withMotorcycles: (BOOL) displayMotorcycles withSpokes: (BOOL) displaySpokes withWavefronts: (BOOL) displayWavefronts withThinWalls: (BOOL) displayThinWalls;

@end
