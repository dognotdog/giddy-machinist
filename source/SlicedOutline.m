//
//  SlicedOutline.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 23.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import "SlicedOutline.h"
#import "Slicer.h"
#import "PolygonSkeletizer.h"
#import "gfx.h"

@implementation SlicedOutline

@synthesize outline, holes, skeleton;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	holes = [[NSArray alloc] init];
	
	return self;
}

- (void) fixHoleWindings
{
	for (SlicedOutline* hole in holes)
	{
		if (hole.outline.isCCW == outline.isCCW)
		{
			//NSLog(@"reversing hole");
			[hole.outline reverse];
			[hole.outline analyzeSegment];
			assert(hole.outline.isCCW != outline.isCCW);
			[hole fixHoleWindings];
		}
	}
}

- (NSArray*) allNestedPaths
{
	NSMutableArray* ary = [NSMutableArray array];
	for (SlicedOutline* hole in holes)
		[ary addObjectsFromArray: [hole allNestedPaths]];
	[ary addObject: outline];
	return ary;
}

- (void) recursivelyNestPaths
{
	
	NSMutableArray* unprocessedHoles = [holes mutableCopy];
	NSMutableArray* outerHoles = [NSMutableArray array];
	while ([unprocessedHoles count])
	{
		SlicedOutline* hole = [unprocessedHoles lastObject];
		[unprocessedHoles removeLastObject];
		BOOL outerHole = YES;
		
		for (SlicedOutline* hole2 in unprocessedHoles)
		{
			if ([hole2.outline containsPath: hole.outline])
			{
				hole2.holes = [hole2.holes arrayByAddingObject: hole];
				outerHole = NO;
				break;
			}
			else if ([hole.outline containsPath: hole2.outline])
			{
				[unprocessedHoles insertObject: hole atIndex: 0];
				outerHole = NO;
				break;
			}
		}
		
		if (outerHole)
			[outerHoles addObject: hole];
	}
	holes = outerHoles;
	
	for (SlicedOutline* hole in holes)
		[hole recursivelyNestPaths];
	
	[self fixHoleWindings];
}

- (void) addPathsToSkeletizer: (PolygonSkeletizer*) sk
{
	[sk addClosedPolygonWithVertices: outline.vertices count: outline.vertexCount];
	for (SlicedOutline* hole in holes)
		[hole addPathsToSkeletizer: sk];

}

- (void) generateSkeletonWithMergeThreshold: (double) mergeThreshold
{
	skeleton = [[PolygonSkeletizer alloc] init];
	skeleton.mergeThreshold = mergeThreshold;
	
	[self addPathsToSkeletizer: skeleton];
	
	[skeleton generateSkeleton];
}


- (id) description
{
	NSMutableArray* descs = [NSMutableArray array];
	
	for (SlicedOutline* hole in holes)
		[descs addObject: hole];
	
	return [NSString stringWithFormat: @"Holes (%@): %@", (outline.isCCW ? @"CCW" : @"---"), descs];
}



@end

@implementation SlicedLineSegment
{
	vector_t* vertices;
	size_t vertexCount;
}

@synthesize vertexCount, vertices, isClosed, isSelfIntersecting, isCCW, isConvex;

- (void) expandVertexCount: (size_t) count
{
	size_t newCount = MAX(vertexCount, count);
	vertices = realloc(vertices, sizeof(*vertices)*newCount);
	vertexCount = newCount;
}

- (void) setBegin:(vector_t) v
{
	[self expandVertexCount: 1];
	
	vertices[0] = v;
}

- (void) setEnd:(vector_t)v
{
	if (vertexCount < 2)
		[self expandVertexCount: 2];
	
	vertices[vertexCount-1] = v;
}

- (vector_t) begin
{
	assert(vertexCount > 0);
	return vertices[0];
}

- (vector_t) end
{
	assert(vertexCount > 1);
	return vertices[vertexCount-1];
}

- (void) insertVertexAtBeginning: (vector_t) v
{
	[self expandVertexCount: vertexCount+1];
	memmove(vertices+1,vertices, sizeof(*vertices)*(vertexCount-1));
	vertices[0] = v;
}
- (void) insertVertexAtEnd: (vector_t) v
{
	[self expandVertexCount: vertexCount+1];
	vertices[vertexCount-1] = v;
}

- (SlicedLineSegment*) joinSegment: (SlicedLineSegment*) seg atEnd: (BOOL) atEnd reverse: (BOOL) reverse
{
	SlicedLineSegment* newSegment = [[SlicedLineSegment alloc]  init];
	[newSegment expandVertexCount: vertexCount + seg.vertexCount - 1];
	
	size_t vi = 0;
	
	if (atEnd)
		for (size_t i = 0; i < vertexCount; ++i)
			newSegment->vertices[vi++] = vertices[i];
	else
		for (size_t i = vertexCount; i > 0; --i)
			newSegment->vertices[vi++] = vertices[i-1];
	
	if (reverse)
		for (size_t i = seg->vertexCount-1; i > 0; --i)
			newSegment->vertices[vi++] = seg->vertices[i-1];
	else
		for (size_t i = 1; i < seg->vertexCount; ++i)
			newSegment->vertices[vi++] = seg->vertices[i];
	
	vector_t v0 = newSegment->vertices[vertexCount-1];
	vector_t v1 = newSegment->vertices[vertexCount];
	assert(!v3Equal(v0, v1));

	return newSegment;
}

- (BOOL) closePolygonByMergingEndpoints: (double) threshold;
{
	if (vertexCount < 4)
		return NO;
	
	vector_t delta = v3Sub(self.begin, self.end);
	double dd = vDot(delta, delta);
	
	if (dd < threshold*threshold)
	{
		vector_t c = v3MulScalar(v3Add(self.begin, self.end), 0.5);
		self.begin = c;
		vertexCount--;
		isClosed = YES;
		return YES;
	}
	else
		return NO;
}


- (BOOL) checkSelfIntersection
{
	long count = vertexCount + isClosed-1;
	for (long i = 0; i < count; ++i)
	{
		vector_t a0 = vertices[i];
		vector_t b0 = vertices[(i+1)%vertexCount];
		for (long j = i+2; j < count; ++j)
		{
			vector_t a1 = vertices[j];
			vector_t b1 = vertices[(j+1)%vertexCount];
			if (xLineSegments2D(a0, b0, a1, b1))
				return YES;
			
			
		}
	}
	return NO;
}

- (void) analyzeSegment
{
	long signCounter = 0;
	vector_t crossSum = vZero();
	
	isSelfIntersecting = [self checkSelfIntersection];
	
	if (isSelfIntersecting || !isClosed)
		return;
	
	for (long i = 0; i < vertexCount; ++i)
	{
		vector_t a = vertices[i];
		vector_t b = vertices[(i+1)%vertexCount];
		vector_t cross = vCross(a, b);
		
		crossSum = v3Add(crossSum, cross);
		signCounter += (cross.farr[2] > 0.0 ? 1 : (cross.farr[2] < 0.0 ? -1 : 0));
	}
	
	if (crossSum.farr[2] > 0.0)
		isCCW = YES;
	else
		isCCW = NO;
	
	if (ABS(signCounter) == vertexCount)
		isConvex = YES;
	
}

- (vector_t) centroid
{
	vector_t c = vZero();
	for (long i = 0; i < vertexCount; ++i)
		c = v3Add(c, vertices[i]);
	return v3MulScalar(c, 1.0/vertexCount);
}

- (range3d_t) bounds
{
	range3d_t r = rInfRange();
	for (long i = 0; i < vertexCount; ++i)
	{
		r.minv = vMin(r.minv, vertices[i]);
		r.maxv = vMax(r.maxv, vertices[i]);
	}
	return r;
}

- (double) area2
{
	assert(isClosed);
	
	vector_t crossSum = vZero();
		
	for (long i = 0; i < vertexCount; ++i)
	{
		vector_t a = vertices[i];
		vector_t b = vertices[(i+1)%vertexCount];
		vector_t cross = vCross(a, b);
		
		crossSum = v3Add(crossSum, cross);
	}
	return 0.5*crossSum.farr[2];
}

- (double) area
{
	assert(isClosed);
	
	vector_t crossSum = vZero();
	
	double area = 0.0;
	
	for (long i = 0; i < vertexCount; ++i)
	{
		vector_t a = vertices[i];
		vector_t b = vertices[(i+1)%vertexCount];
		
		area += (b.farr[0] + a.farr[0])*(b.farr[1] - a.farr[1]);
		
	}
	return 0.5*area;
}


- (BOOL) containsPath: (SlicedLineSegment*) segment
{
	assert(isCCW && segment.isCCW);
	assert(isClosed);
	
	vector_t sc = segment.begin;
	range3d_t bounds = self.bounds;
	
//	if (!rRangeContainsPointXYInclusiveMinExclusiveMax(bounds, sc))
//		return NO;
	
	
	vector_t ray = vCreateDir(bounds.maxv.farr[0]+1.0, 1.0, 0.0);
	
	long windingCounter = 0;
	
	for (long i = 0; i < vertexCount; ++i)
	{
		vector_t d = v3Sub(vertices[(i+1) % vertexCount], vertices[i]);
		vector_t t = xRays2D(vertices[i], d, sc, ray);
		if ((t.farr[0] >= 0.0) && (t.farr[1] >= 0.0) && (t.farr[0] < 1.0) && (t.farr[1] < 1.0))
		{
			double f = vCross(ray, d).farr[2];
			assert(f != 0.0);
			windingCounter += (f > 0.0 ? 1 : -1);
		}
	}
	assert(ABS(windingCounter) < 2);
	if (windingCounter > 0)
		return YES;
	else
		return NO;
	
}

- (void) reverse
{
	for (long i = 0; i < vertexCount/2; ++i)
	{
		vector_t a = vertices[i];
		vector_t b = vertices[vertexCount-i-1];
		vertices[i] = b;
		vertices[vertexCount-i-1] = a;
	}
}

- (void) optimizeToThreshold: (double) threshold
{
	BOOL wasCCW = isCCW;
	BOOL foundOne = YES;
	while (foundOne)
	{
		size_t smallestIndex = NSNotFound;
		double smallestLengthSqr = threshold*threshold;
		foundOne = NO;
		for (size_t i = 0; i < vertexCount; ++i)
		{
			vector_t a = vertices[i];
			vector_t b = vertices[(i+1) % vertexCount];
			vector_t d = v3Sub(b, a);
			double l = vDot(d, d);
			if (l < smallestLengthSqr)
			{
				foundOne = YES;
				smallestLengthSqr = l;
				smallestIndex = i;
			}
		}
		if (foundOne)
		{
			size_t ia0 = (vertexCount+smallestIndex-1) % vertexCount;
			size_t ia1 = smallestIndex;
			size_t ib0 = (smallestIndex+1) % vertexCount;
			size_t ib1 = (smallestIndex+2) % vertexCount;
			vector_t a0 = vertices[ia0];
			vector_t a1 = vertices[ia1];
			vector_t b0 = vertices[ib0];
			vector_t b1 = vertices[ib1];
			vector_t c = v3MulScalar(v3Add(a1, b0), 0.5);
			
			if ((ia0 != ia1) && (ia0 != ib0) && (ia0 != ib1) && (ia1 != ib0) && (ia1 != ib1) && (ib1 != ib0)) // if they're all unique, we can extrapolate
			{
				vector_t tx = xRays2D(a0, v3Sub(a1, a0), b1, v3Sub(b0, b1));
				
				assert(isnormal(tx.farr[0]));
				
				c = v3Add(a0, v3MulScalar(v3Sub(a1, a0), tx.farr[0]));
			}
			
			
			vertices[ib0] = c;
			memmove(vertices + smallestIndex, vertices + smallestIndex + 1, sizeof(*vertices)*(vertexCount-smallestIndex-1));
			vertexCount--;
		}
	}
	
	[self analyzeSegment];
	assert(wasCCW == isCCW);
}

- (void) optimizeColinears: (double) threshold
{
//	BOOL wasCCW = self.isCCW;
	BOOL foundOne = YES;
	while (foundOne)
	{
		size_t smallestIndex = NSNotFound;
		double smallestArea = threshold;
		foundOne = NO;
		for (size_t i = 0; i < vertexCount; ++i)
		{
			vector_t p = vertices[(vertexCount+i-1) % vertexCount];
			vector_t c = vertices[i];
			vector_t n = vertices[(i+1) % vertexCount];
			vector_t e0 = v3Sub(c, p);
			vector_t e1 = v3Sub(n, c);
			double a = fabs(vCross(e0, e1).farr[2]);
			if (a < smallestArea)
			{
				foundOne = YES;
				smallestArea = a;
				smallestIndex = i;
			}
		}
		if (foundOne)
		{
			size_t ia = smallestIndex;
			memmove(vertices + ia, vertices + ia + 1, sizeof(*vertices)*(vertexCount-ia-1));
			vertexCount--;
		}
	}
	
	[self analyzeSegment];
//	assert(wasCCW == isCCW);
}


static inline vector_t bisectorVelocity(vector_t v0, vector_t v1, vector_t e0, vector_t e1)
{
	double lv0 = vLength(v0);
	double lv1 = vLength(v1);
	double vx = vCross(v0, v1).farr[2]/(lv0*lv1);
	
	vector_t s = vCreateDir(0.0, 0.0, 0.0);
	
	
	if (fabs(vx) < 1.0*sqrt(FLT_EPSILON))// nearly parallel, threshold is a guess
	{
		s = v3MulScalar(v3Add(v0, v1), 0.5);
		//NSLog(@"nearly parallel %g, %g / %g, %g", v0.x, v0.y, v1.x, v1.y);
	}
	else
	{
		s = v3Add(vReverseProject(v0, e1), vReverseProject(v1, e0));
	}
	
	return s;
	
}

- (NSArray*) splitAtSelfIntersectionWithThreshold: (double) mergeThreshold
{
	if (!isClosed)
		return  nil;
	
	
	long count = vertexCount;
	for (long i = 0; i < count; ++i)
	{
		vector_t a0 = vertices[i];
		vector_t b0 = vertices[(i+1)%vertexCount];
		for (long j = i+2; j < count; ++j)
		{
			vector_t a1 = vertices[j];
			vector_t b1 = vertices[(j+1)%vertexCount];
			if (xLineSegments2D(a0, b0, a1, b1))
			{
				
			};
			
			
		}
	}
	assert(0);
}

- (NSArray*) offsetOutline: (double) offset withThreshold: (double) mergeThreshold
{
	if (!isClosed)
		return nil;
	
	vector_t* newVertices = calloc(sizeof(*newVertices), vertexCount);
	
	for (size_t i = 0; i < vertexCount; ++i)
	{
		vector_t a = vertices[(vertexCount + i - 1) % vertexCount];
		vector_t b = vertices[i];
		vector_t c = vertices[(i + 1) % vertexCount];
		
		vector_t e0 = v3Sub(b, a);
		vector_t e1 = v3Sub(c, b);
		
		vector_t n0 = vSetLength(vCreateDir(-e0.farr[1], e0.farr[0], 0.0), offset);
		vector_t n1 = vSetLength(vCreateDir(-e0.farr[1], e0.farr[0], 0.0), offset);
		
		vector_t r = bisectorVelocity(n0, n1, e0, e1);
		
		newVertices[i] = v3Add(b, r);
	}
	
	
	SlicedLineSegment* offsetLine = [[SlicedLineSegment alloc] init];
	[offsetLine addVertices: newVertices count: vertexCount];
	[offsetLine analyzeSegment];
	
	free(newVertices);
	
	return [offsetLine splitAtSelfIntersectionWithThreshold: mergeThreshold];
}

- (id) description
{
	NSMutableArray* descs = [NSMutableArray array];
	
	for (size_t i = 0; i < vertexCount; ++i)
		[descs addObject: [NSString stringWithFormat: @"%.4f %.4f %.4f", vertices[i].farr[0],vertices[i].farr[1],vertices[i].farr[2]]];
	
	return [NSString stringWithFormat: @"Vertices: %@", descs];
}

@end
