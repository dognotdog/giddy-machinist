//
//  LayerInspectorView.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 15.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class SlicedLayer;

@interface LayerInspectorView : NSView

@property(nonatomic, strong) SlicedLayer* slice;
@property(nonatomic) NSInteger indexOfSelectedOutline;
@property(nonatomic, strong) NSArray* motorcyclePaths;
@property(nonatomic, strong) NSArray* spokePaths;
@property(nonatomic, strong) NSArray* outlinePaths;

- (void) addOffsetOutlinePath: (NSBezierPath*) bpath;
- (void) removeAllOffsetOutlinePaths;


@end
