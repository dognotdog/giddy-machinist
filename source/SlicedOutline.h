//
//  SlicedOutline.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 23.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath_fixp.h"

@class PolygonSkeletizer, GfxMesh;

@interface SlicedLineSegment : NSObject

@property(nonatomic) v3i_t begin, end;
@property(nonatomic,readonly) v3i_t* vertices;
@property(nonatomic,readonly) size_t vertexCount;
@property(nonatomic,readonly) BOOL isClosed;
@property(nonatomic,readonly) BOOL isConvex;
@property(nonatomic,readonly) BOOL isCCW;
@property(nonatomic,readonly) BOOL isSelfIntersecting;
@property(nonatomic,readonly) v3i_t centroid;
@property(nonatomic,readonly) r3i_t	bounds;
@property(nonatomic,readonly) double	area;

- (void) addVertices: (v3i_t*) v count: (size_t) count;
- (void) insertVertexAtBeginning: (v3i_t) v;
- (void) insertVertexAtEnd: (v3i_t) v;

- (SlicedLineSegment*) joinSegment: (SlicedLineSegment*) seg atEnd: (BOOL) atEnd reverse: (BOOL) reverse;

- (NSArray*) booleanIntersectSegment: (SlicedLineSegment*) other;

- (BOOL) closePolygonByMergingEndpoints;
- (void) analyzeSegment;
- (void) reverse;
//- (void) optimizeToThreshold: (double) threshold;
- (void) optimizeColinears: (vmlongfix_t) threshold;


- (BOOL) intersectsPath: (SlicedLineSegment*) segment;
- (BOOL) containsPath: (SlicedLineSegment*) segment;

@end

@interface SlicedOutline : NSObject
@property(nonatomic, strong) SlicedLineSegment* outline;
@property(nonatomic, strong) NSArray* holes;
@property(nonatomic, strong) PolygonSkeletizer* skeleton;

@property(nonatomic, strong) NSArray* allNestedPaths;

- (void) recursivelyNestPaths;

- (void) generateSkeletonWithMergeThreshold: (double) mergeThreshold;
- (void) addPathsToSkeletizer: (PolygonSkeletizer*) sk;


@end
