//
//  SlicedOutline.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 23.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"

@interface SlicedLineSegment : NSObject
@property(nonatomic) vector_t begin, end;
@property(nonatomic,readonly) vector_t* vertices;
@property(nonatomic,readonly) size_t vertexCount;
@property(nonatomic,readonly) BOOL isClosed;
@property(nonatomic,readonly) BOOL isConvex;
@property(nonatomic,readonly) BOOL isCCW;
@property(nonatomic,readonly) BOOL isSelfIntersecting;
@property(nonatomic,readonly) vector_t centroid;
@property(nonatomic,readonly) range3d_t	bounds;
@property(nonatomic,readonly) double	area;

- (void) insertVertexAtBeginning: (vector_t) v;
- (void) insertVertexAtEnd: (vector_t) v;

- (SlicedLineSegment*) joinSegment: (SlicedLineSegment*) seg atEnd: (BOOL) atEnd reverse: (BOOL) reverse;

- (BOOL) closePolygonByMergingEndpoints: (double) threshold;
- (void) analyzeSegment;
- (void) reverse;
- (void) optimizeToThreshold: (double) threshold;


- (BOOL) intersectsPath: (SlicedLineSegment*) segment;
- (BOOL) containsPath: (SlicedLineSegment*) segment;

@end

@interface SlicedOutline : NSObject
@property(nonatomic, strong) SlicedLineSegment* outline;
@property(nonatomic, strong) NSArray* holes;

@property(nonatomic, strong) NSArray* allNestedPaths;

- (void) recursivelyNestPaths;

@end
