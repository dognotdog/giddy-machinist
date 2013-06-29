//
//  SlicedOutline.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 23.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath_fixp.h"

@class PolygonSkeletizer, GfxMesh, FixPolygonClosedSegment, NSBezierPath;

@interface SlicedOutline : NSObject
@property(nonatomic, strong) FixPolygonClosedSegment* outline;
@property(nonatomic, strong) NSArray* holes;
@property(nonatomic, strong) PolygonSkeletizer* skeleton;

@property(nonatomic, strong) NSArray* allNestedPaths;

- (void) recursivelyNestPaths;

- (void) generateSkeletonWithMergeThreshold: (double) mergeThreshold;
- (void) addPathsToSkeletizer: (PolygonSkeletizer*) sk;

- (NSArray*) booleanIntersectOutline: (SlicedOutline*) other;

@end
