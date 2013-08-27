//
//  FixPolygon.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 26.06.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath_fixp.h"

@class GfxMesh;

@class FixPolygonClosedSegment, NSBezierPath;


@interface FixPolygon : NSObject <NSCopying>

/*!
 This is essentially a boolean intersect.
 */
- (FixPolygon*) maskWithPolygon: (FixPolygon*) maskPolygon;

@property(nonatomic, strong) NSArray* segments;

+ (FixPolygon*) polygonFromBezierPath: (NSBezierPath*) bpath withTransform: (NSAffineTransform*) transform flatness: (CGFloat) flatness;

- (GfxMesh*) gfxMesh;

- (r3i_t) bounds;

- (void) reviseWinding;

@end


@interface FixPolygonSegment : NSObject <NSCopying>

@property(nonatomic,readonly) v3i_t* vertices;
@property(nonatomic,readonly) size_t vertexCount;

@property(nonatomic, readonly) v3i_t begin;
@property(nonatomic, readonly) v3i_t end;

@property(nonatomic, readonly) r3i_t bounds;

- (BOOL) isClosed;

- (void) addVertices: (v3i_t*) v count: (size_t) count;
- (void) insertVertexAtBeginning: (v3i_t) v;
- (void) insertVertexAtEnd: (v3i_t) v;

- (void) cleanupDoubleVertices;

- (void) reverse;

- (NSBezierPath*) bezierPath;


@end



@interface FixPolygonOpenSegment : FixPolygonSegment

- (BOOL) isSelfIntersecting;

- (FixPolygonOpenSegment*) joinSegment: (FixPolygonOpenSegment*) seg atEnd: (BOOL) atEnd reverse: (BOOL) reverse;

- (FixPolygonClosedSegment*) closePolygonByMergingEndpoints;
- (FixPolygonClosedSegment*) closePolygonWithoutMergingEndpoints;

@end


@interface FixPolygonClosedSegment : FixPolygonSegment

@property(nonatomic, readonly) BOOL isConvex;
@property(nonatomic, readonly) BOOL isCCW;

- (double) area;

- (BOOL) containsPath: (FixPolygonSegment*) segment;

- (void) analyzeSegment;

- (NSArray*) booleanIntersectSegment: (FixPolygonSegment*) other;

- (void) optimizeColinears: (vmlongfix_t) threshold;

@end
