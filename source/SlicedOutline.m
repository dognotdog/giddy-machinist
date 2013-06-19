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
#import "MPInteger.h"
#import "MPVector2D.h"

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
	v3i_t* vertices;
	size_t vertexCount;
}

@synthesize vertexCount, vertices, isClosed, isSelfIntersecting, isCCW, isConvex;

- (void) expandVertexCount: (size_t) count
{
	size_t newCount = MAX(vertexCount, count);
	vertices = realloc(vertices, sizeof(*vertices)*newCount);
	vertexCount = newCount;
}

- (void) setBegin: (v3i_t) v
{
	[self expandVertexCount: 1];
	
	vertices[0] = v;
}

- (void) setEnd: (v3i_t)v
{
	if (vertexCount < 2)
		[self expandVertexCount: 2];
	
	vertices[vertexCount-1] = v;
}

- (void) addVertices: (v3i_t*) v count: (size_t) count;
{
	[self expandVertexCount: vertexCount+2];
	for (size_t i = 0; i < count; ++i)
		vertices[vertexCount-count+i] = v[i];
}
- (v3i_t) begin
{
	assert(vertexCount > 0);
	return vertices[0];
}

- (v3i_t) end
{
	assert(vertexCount > 1);
	return vertices[vertexCount-1];
}

- (void) insertVertexAtBeginning: (v3i_t) v
{
	[self expandVertexCount: vertexCount+1];
	memmove(vertices+1,vertices, sizeof(*vertices)*(vertexCount-1));
	vertices[0] = v;
}
- (void) insertVertexAtEnd: (v3i_t) v
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
	{
		for (size_t i = 0; i < vertexCount; ++i)
			newSegment->vertices[vi++] = vertices[i];
	}
	else
	{
		for (size_t i = vertexCount; i > 0; --i)
			newSegment->vertices[vi++] = vertices[i-1];
	}
	
	if (reverse)
	{
		// need to deduplicate reversed segments
		
		size_t vcount = seg->vertexCount;
		for (size_t i = 0; i < MIN(vertexCount, seg->vertexCount); ++i)
		{
			v3i_t v0 = newSegment->vertices[vertexCount-1-i];
			v3i_t v1 = seg->vertices[seg->vertexCount-1-i];
			if (v3iEqual(v0, v1))
				vcount--;
			else
				break;
		}
		
		for (size_t i = vcount; i > 0; --i)
			newSegment->vertices[vi++] = seg->vertices[i-1];
	}
	else
	{
		size_t vcount = 0;
		for (size_t i = 0; i < MIN(vertexCount, seg->vertexCount); ++i)
		{
			v3i_t v0 = newSegment->vertices[vertexCount-1-i];
			v3i_t v1 = seg->vertices[i];
			if (v3iEqual(v0, v1))
				vcount++;
			else
				break;
		}

		for (size_t i = vcount; i < seg->vertexCount; ++i)
			newSegment->vertices[vi++] = seg->vertices[i];
	}
	newSegment->vertexCount = vi;
	
	if (newSegment->vertexCount > vertexCount)
	{
		v3i_t v0 = newSegment->vertices[vertexCount-1];
		v3i_t v1 = newSegment->vertices[vertexCount];
		assert(!v3iEqual(v0, v1));
	}
	return newSegment;
}

- (BOOL) closePolygonByMergingEndpoints
{
	if (vertexCount < 4)
		return NO;
		
	if (v3iEqual(self.begin, self.end))
	{
		vertexCount--;
		isClosed = YES;
		return YES;
	}
	else
		return NO;
}

static long _locationOnEdge_boxTest(v3i_t A, v3i_t B, v3i_t x)
{
	r3i_t r = riCreateFromVectors(A,B);
	
	return riContainsVector2D(r, x);
}



static long _checkIntersection(v3i_t p0, v3i_t p1, v3i_t q0, v3i_t q1, v3i_t* xptr)
{
	v3i_t r = v3iSub(p1, p0);
	v3i_t s = v3iSub(q1, q0);
	
	vmlongfix_t rxs = v3iCross2D(r, s);
	
	if (!rxs.x)
		return 0;
	
	MPVector2D* rqs = [[MPVector2D vectorWith3i: r] scale: [[MPVector2D vectorWith3i: q0] cross: [MPVector2D vectorWith3i: s]]];
	MPVector2D* spr = [[MPVector2D vectorWith3i: s] scale: [[MPVector2D vectorWith3i: p0] cross: [MPVector2D vectorWith3i: r]]];
	
	MPVector2D* num = [rqs sub: spr];
	MPDecimal* den = [MPDecimal decimalWithInt64: rxs.x shift: rxs.shift];
	
	MPVector2D* X = [num scaleNum: [MPDecimal one] den: den];
	
	if ((X.x.integerBits > 15) || (X.y.integerBits > 15))
		return 0;
	
	v3i_t x = [X toVectorWithShift: p0.shift];
	
	if (xptr)
		*xptr = x;
	
	return _locationOnEdge_boxTest(p0, p1, x) && _locationOnEdge_boxTest(q0, q1, x);
}

- (BOOL) checkSelfIntersection
{
	long count = vertexCount + isClosed-1;
	for (long i = 0; i < count; ++i)
	{
		v3i_t a0 = vertices[i];
		v3i_t b0 = vertices[(i+1)%vertexCount];
		
		r3i_t r0 = riCreateFromVectors(a0, b0);
		
		for (long j = i+2; j < count; ++j)
		{
			v3i_t a1 = vertices[j];
			v3i_t b1 = vertices[(j+1)%vertexCount];

			r3i_t r1 = riCreateFromVectors(a1, b1);
			
			if (riCheckIntersection2D(r0, r1))
				if (_checkIntersection(a0, b0, a1, b1, NULL) && !v3iEqual(a0, b1) && !v3iEqual(a1, b0))
					return YES;
			
			
		}
	}
	return NO;
}

- (void) analyzeSegment
{
	long signCounter = 0;
	
	isSelfIntersecting = [self checkSelfIntersection];
	
	if (isSelfIntersecting || !isClosed)
		return;
	
	MPDecimal* area = [MPDecimal decimalWithInt64: 0 shift: 0];

	for (long i = 0; i < vertexCount; ++i)
	{
		v3i_t a = vertices[i];
		v3i_t b = vertices[(i+1)%vertexCount];
		vmlongfix_t cross = v3iCross2D(a, b);
		area = [area add: [MPDecimal decimalWithInt64: cross.x shift: cross.shift]];
		
		signCounter += (cross.x > 0 ? 1 : (cross.x < 0 ? -1 : 0));
	}
	
	isCCW = area.isPositive && !area.isZero;

	
	if (ABS(signCounter) == vertexCount)
		isConvex = YES;
	
}

/*
- (vector_t) centroid
{
	vector_t c = vZero();
	for (long i = 0; i < vertexCount; ++i)
		c = v3Add(c, vertices[i]);
	return v3MulScalar(c, 1.0/vertexCount);
}
*/
- (r3i_t) bounds
{
	r3i_t r = {v3iCreate(INT32_MAX, INT32_MAX, INT32_MAX, 0), v3iCreate(INT32_MIN, INT32_MIN, INT32_MIN, 0)};
	for (long i = 0; i < vertexCount; ++i)
	{
		r.min.shift = vertices[i].shift;
		r.max.shift = vertices[i].shift;
		r.min = v3iMin(r.min, vertices[i]);
		r.max = v3iMax(r.max, vertices[i]);
	}
	return r;
}

- (double) area
{
	assert(isClosed);
	
	MPDecimal* crossSum = [MPDecimal decimalWithInt64: 0 shift: 0];
		
	for (long i = 0; i < vertexCount; ++i)
	{
		v3i_t a = vertices[i];
		v3i_t b = vertices[(i+1)%vertexCount];
		vmlongfix_t cross = v3iCross2D(a, b);
		
		crossSum = [crossSum add: [MPDecimal decimalWithInt64: cross.x shift: cross.shift]];
	}
	return [crossSum mul: [MPDecimal decimalWithInt64: 1 shift: 1]].toDouble;
}

- (double) area2
{
	assert(isClosed);
	
//	vector_t crossSum = vZero();
	
	int64_t area = 0.0;
	
	for (long i = 0; i < vertexCount; ++i)
	{
		v3i_t a = vertices[i];
		v3i_t b = vertices[(i+1)%vertexCount];
		
		area += (b.x + a.x)*(b.y - a.y); // b.x*b.y + a.x*a.y - a.x*b.y - a.y*b.x
		
	}
	return area/2;
}


- (BOOL) containsPath: (SlicedLineSegment*) segment
{
	assert(isCCW && segment.isCCW);
	assert(isClosed);
	
	v3i_t sc = segment.begin;
	r3i_t bounds = self.bounds;
	
//	if (!rRangeContainsPointXYInclusiveMinExclusiveMax(bounds, sc))
//		return NO;
	
	
	// ray is going along X
	v3i_t ray = v3iCreate(bounds.max.x+1, 0, 0, bounds.max.shift);
	v3i_t se = v3iAdd(sc, ray);
	
	r3i_t rr = riCreateFromVectors(sc, se);

	long windingCounter = 0;
	
	for (long i = 0; i < vertexCount; ++i)
	{
		v3i_t p0 = vertices[i];
		v3i_t p1 = vertices[(i+1) % vertexCount];
		
		r3i_t rp = riCreateFromVectors(p0, p1);
		
		if (!riCheckIntersection2D(rr, rp))
			continue;
		
		v3i_t x = v3iCreate(0, 0, 0, 0);
		
		if (!_checkIntersection(p0, p1, sc, se, &x))
			continue;


		v3i_t e = v3iSub(p1, p0);

		// as the test ray propagates in +X
		// for edges going +Y, [0,den) is valid
		// for edges going -Y, (0, den] is valid
		
		BOOL goingY = e.y > 0;
		
		if (goingY && v3iEqual(p0, x))
			continue;
		else if (!goingY && v3iEqual(p1, x))
			continue;

		v3i_t d = v3iSub(sc, p0);
		assert(e.z == 0);
		v3i_t n = {-e.y, e.x, e.z, e.shift};
		vmlong_t f = v3iDot(n, d).x;
		assert(f != 0);
		windingCounter += (f > 0 ? 1 : -1);
	}
	assert(ABS(windingCounter) < 2);
	if (windingCounter > 0)
		return YES;
	else
		return NO;
	
}

- (void) reverse
{
	long areaPositive = self.area > 0;
	for (long i = 0; i < vertexCount/2; ++i)
	{
		v3i_t a = vertices[i];
		v3i_t b = vertices[vertexCount-i-1];
		vertices[i] = b;
		vertices[vertexCount-i-1] = a;
	}
	long areaRev = self.area >= 0;
	
	assert(areaPositive != areaRev);
}

/*
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
*/
- (void) optimizeColinears: (vmlongfix_t) threshold
{
//	BOOL wasCCW = self.isCCW;
	BOOL foundOne = YES;
	while (foundOne)
	{
		size_t smallestIndex = NSNotFound;
		vmlongfix_t smallestArea = threshold;
		foundOne = NO;
		for (size_t i = 0; i < vertexCount; ++i)
		{
			v3i_t p = vertices[(vertexCount+i-1) % vertexCount];
			v3i_t c = vertices[i];
			v3i_t n = vertices[(i+1) % vertexCount];
			v3i_t e0 = v3iSub(c, p);
			v3i_t e1 = v3iSub(n, c);
			vmlongfix_t a = v3iCross2D(e0, e1);
			a.x = labs(a.x);
			assert(a.shift == smallestArea.shift);
			if (a.x < smallestArea.x)
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

/*!
 Returns closed polygons outlining the areas common to both input polygons. Both polygons must be closed and non self-intersecting. CCW polygons represent filled outlines, CW polygons are holes.
 */
- (NSArray*) booleanIntersectSegment: (SlicedLineSegment*) other
{
	assert(self.isClosed && other.isClosed);
	assert(!self.isSelfIntersecting && !other.isSelfIntersecting);
	
	
	// lets start by finding the intersecting primitive segments
	v3i_t* vertices0 = self.vertices;
	v3i_t* vertices1 = other.vertices;
	size_t count0 = self.vertexCount;
	size_t count1 = other.vertexCount;
	for (size_t i = 0; i < count0; ++i)
	{
		v3i_t pi0 = vertices0[i];
		v3i_t pi1 = vertices0[(i+1)%count0];
		for (size_t j = 0; j < count1; ++j)
		{
			v3i_t pj0 = vertices1[j];
			v3i_t pj1 = vertices1[(j+1)%count1];
			
		}
		
	}
	
	
}

/*
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
*/
extern vector_t bisectorVelocity(vector_t v0, vector_t v1, vector_t e0, vector_t e1);

/*
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
*/

static NSString* _verticesToSVGPolygon(v3i_t* vertices, size_t numVertices)
{
	
	NSString* polygonHeader = @"<polygon stroke=\"red\" points=\"";
	NSString* polygonFooter = @"\" />";
	
	NSMutableArray* strings = @[polygonHeader].mutableCopy;
	
	for (size_t i = 0; i < numVertices; ++i)
	{
		vector_t v = v3iToFloat(vertices[i]);
		[strings addObject: [NSString stringWithFormat: @"%f, %f ", v.farr[0], v.farr[1]]];
	}
	
	[strings addObjectsFromArray: @[polygonFooter]];
	
	return [strings componentsJoinedByString: @""];
	
}

static NSString* _verticesToSVG(v3i_t* vertices, size_t numVertices)
{
	NSString* svgHeader = @"<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\">";
	
	NSString* svgFooter = @"</svg>";
	
	NSMutableArray* strings = @[svgHeader].mutableCopy;
	
	[strings addObject: _verticesToSVGPolygon(vertices, numVertices)];
	
	
	[strings addObjectsFromArray: @[svgFooter]];
	
	return [strings componentsJoinedByString: @""];
	
}

- (NSString*) svgString
{
	return _verticesToSVG(vertices, vertexCount);
}


- (void) copySVG
{
	NSPasteboard* pb = [NSPasteboard generalPasteboard];
	[pb declareTypes: @[@"public.svg-image"] owner: nil];
	[pb setData: [_verticesToSVG(vertices, vertexCount) dataUsingEncoding: NSUTF8StringEncoding] forType: @"public.svg-image"];
}


- (id) description
{
	NSMutableArray* descs = [NSMutableArray array];
	
	for (size_t i = 0; i < vertexCount; ++i)
	{
		vector_t v = v3iToFloat(vertices[i]);
		[descs addObject: [NSString stringWithFormat: @"%.4f %.4f %.4f", v.farr[0], v.farr[1], v.farr[2]]];
	}
	return [NSString stringWithFormat: @"Vertices: %@", descs];
}

@end
