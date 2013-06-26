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
#import "FoundationExtensions.h"

@interface SOIntersection : NSObject

@property(nonatomic) MPVector2D* mpLocation;
@property(nonatomic) v3i_t	location;
@property(nonatomic) size_t	indexI, indexJ;
@property(nonatomic) long	dirI, dirJ;

@property(nonatomic, weak) SOIntersection* nextI;
@property(nonatomic, weak) SOIntersection* nextJ;

@end

@implementation SOIntersection

- (NSString *)description
{
	vector_t x = v3iToFloat(self.location);
	return [NSString stringWithFormat: @"%p @ (%f, %f) diri: %ld dirj: %ld", self, x.farr[0], x.farr[1], self.dirI, self.dirJ];
}

@end



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

/*
 beginning this op, we assume that all holes are wholly contained in self, without intersections, and that the holes and their children are also non-intersecting respective to each other.
 
 
 */
- (NSArray*) booleanIntersectOutline: (SlicedOutline*) other
{
	NSArray* childResults = [holes map: ^id(SlicedOutline* obj) {
		return [obj booleanIntersectOutline: other];
	}];
	
	NSArray* ownSegments = [outline booleanIntersectSegment: other.outline];
	
	NSArray* ownResults = [ownSegments map: ^id(SlicedLineSegment* obj) {
		SlicedOutline* resultOutline = [[SlicedOutline alloc] init];
		resultOutline.outline = obj;
		
		return resultOutline;

	}];
	
	for (SlicedOutline* resultOutline in ownResults)
	{
		SlicedLineSegment* outlineSegment = resultOutline.outline;
		
		for (NSArray* childOutlines in childResults)
			for (SlicedOutline* childOutline in childOutlines)
			{
				if ([outlineSegment containsPath: childOutline.outline])
				{
					assert(outlineSegment.isCCW != childOutline.outline.isCCW);
					resultOutline.holes = [resultOutline.holes arrayByAddingObject: childOutline];
				}
					
			}
	}
	
	
	
	return ownResults;
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
	[self expandVertexCount: vertexCount+count];
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

- (BOOL) closePolygonWithoutMergingEndpoints
{
	if (vertexCount < 3)
		return NO;
	isClosed = YES;
	
	return isClosed;
}

static long _locationOnEdge_boxTest(v3i_t A, v3i_t B, v3i_t x)
{
	r3i_t r = riCreateFromVectors(A,B);
	
	return riContainsVector2D(r, x);
}


static long _mpLocationOnEdge_boxTest(v3i_t a, v3i_t b, MPVector2D* X)
{
	MPVector2D* A = [MPVector2D vectorWith3i: a];
	MPVector2D* B = [MPVector2D vectorWith3i: b];
	MPVector2D* minv = [A min: B];
	MPVector2D* maxv = [A max: B];
	
	
	return ([minv.x compare: X.x] <= 0) && ([minv.y compare: X.y] <= 0) && ([maxv.x compare: X.x] >= 0) && ([maxv.y compare: X.y] >= 0);
}


static MPVector2D* _checkIntersection(v3i_t p0, v3i_t p1, v3i_t q0, v3i_t q1)
{
	v3i_t r = v3iSub(p1, p0);
	v3i_t s = v3iSub(q1, q0);
	
	vmlongfix_t rxs = v3iCross2D(r, s);
	
	if (!rxs.x)
		return nil;
	
	MPVector2D* rqs = [[MPVector2D vectorWith3i: r] scale: [[MPVector2D vectorWith3i: q0] cross: [MPVector2D vectorWith3i: s]]];
	MPVector2D* spr = [[MPVector2D vectorWith3i: s] scale: [[MPVector2D vectorWith3i: p0] cross: [MPVector2D vectorWith3i: r]]];
	
	MPVector2D* num = [rqs sub: spr];
	MPDecimal* den = [MPDecimal decimalWithInt64: rxs.x shift: rxs.shift];
	
	MPVector2D* X = [num scaleNum: [MPDecimal one] den: den];
	
	if (X.minIntegerBits > 15)
		return nil;
	
	//v3i_t x = [X toVectorWithShift: p0.shift];
	
	
	if (!_mpLocationOnEdge_boxTest(p0, p1, X) || !_mpLocationOnEdge_boxTest(q0, q1, X))
		return nil;
	
	return X;
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
				if (_checkIntersection(a0, b0, a1, b1) && !v3iEqual(a0, b1) && !v3iEqual(a1, b0))
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

/*! Checks via ray casting if a single vertex of self is contained in segment.
 
 */
- (BOOL) containsPath: (SlicedLineSegment*) segment
{
	//assert(isCCW && segment.isCCW); // FIXME: assertion no longer necessary?
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
		
		MPVector2D* X = _checkIntersection(p0, p1, sc, se);
		
		if (!X)
			continue;
		
		v3i_t x = [X toVectorWithShift: 16];


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
	if (windingCounter != 0)
		return self.isCCW ? windingCounter > 0 : windingCounter < 0;
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

static SOIntersection* _findNextIntersection(v3i_t* verticesi, size_t istart, size_t iend, size_t counti, v3i_t* verticesj, size_t jstart, size_t jend, size_t countj)
{
	for (size_t i = istart; i < iend; ++i)
	{
		v3i_t pi0 = verticesi[i % counti];
		v3i_t pi1 = verticesi[(i+1) % counti];
		r3i_t ri = riCreateFromVectors(pi0, pi1);
		for (size_t j = jstart; j < jend; ++j)
		{
			v3i_t pj0 = verticesj[j % countj];
			v3i_t pj1 = verticesj[(j+1) % countj];
			r3i_t rj = riCreateFromVectors(pj0, pj1);
			
			if (!riCheckIntersection2D(ri, rj))
				continue;
			
			MPVector2D* X = _checkIntersection(pi0, pi1, pj0, pj1);
			if (X)
			{
				v3i_t x = [X toVectorWithShift: 16];
				
				if (v3iEqual(pi0, x) || v3iEqual(pj0, x)) // TODO: strategy for rejection correct?
					continue;
				
				v3i_t ei = v3iSub(pi1, pi0);
				v3i_t ej = v3iSub(pj1, pj0);
				
				vmlongfix_t crossi0 = v3iCross2D(ei, v3iSub(pj0, pi0));
				vmlongfix_t crossj0 = v3iCross2D(ej, v3iSub(pi0, pj0));
				vmlongfix_t crossi1 = v3iCross2D(ei, v3iSub(pj1, pi0));
				vmlongfix_t crossj1 = v3iCross2D(ej, v3iSub(pi1, pj0));
				
				NSComparisonResult diri = lcompare(crossi1.x, crossi0.x);
				NSComparisonResult dirj = lcompare(crossj1.x, crossj0.x);
				
				SOIntersection* intersection = [[SOIntersection alloc] init];
				intersection.location = x;
				intersection.mpLocation = X;
				intersection.indexI = i % counti;
				intersection.indexJ = j % countj;
				intersection.dirI = diri;
				intersection.dirJ = dirj;
				
				return intersection;
				
			}
			
		}
		
	}
	return nil;

}


- (NSArray*) booleanIntersectSegment: (SlicedLineSegment*) other
{
	assert(self.isClosed && other.isClosed);
	assert(!self.isSelfIntersecting && !other.isSelfIntersecting);
//	assert(self.isCCW); // we make a few assumptions about self being ccw later on
	
	BOOL containsOther = [self containsPath: other];
	BOOL containsSelf = [other containsPath: self];
	
	{
		SOIntersection* firstIntersection = _findNextIntersection(self.vertices, 0, self.vertexCount, self.vertexCount, other.vertices, 0, other.vertexCount, other.vertexCount);
		
		if (containsOther && !firstIntersection) // this means self fully contains the other path
		{
			return @[ other ];
		}
		else if (containsSelf && !firstIntersection) // the other path fully contains self
		{
			return @[ self ];
		}
		else if (!firstIntersection)
		{
			// empty set
			return @[];
		}
	}
	
	// we would a first intersection, now we have to traverse the paths to find the loops
	// at an intersection, we decide as follows:
	// - when both paths enter the other, the CW path is the outline (can only happen on CCW/CW intersect
	// - when one enters the other, take the one entering
	
	NSMutableArray* intersections = [NSMutableArray array];
	
	for (size_t i = 0; i < self.vertexCount; ++i)
	{
		NSMutableArray* segmentIntersections = [NSMutableArray array];
		
		
		SOIntersection* ix = nil;
		size_t jstart = 0;
		size_t jend = other.vertexCount;
		
		while ((ix = _findNextIntersection(self.vertices, i, i+1, self.vertexCount, other.vertices, jstart, jend, other.vertexCount)))
		{
			[segmentIntersections addObject: ix];
			
			jstart = ix.indexJ+1;
		}
		
		[segmentIntersections sortWithOptions: NSSortStable usingComparator: ^NSComparisonResult(SOIntersection* X0, SOIntersection* X1) {
			
			v3i_t p0 = self.vertices[X0.indexI];
			v3i_t p1 = self.vertices[X1.indexI];
			
			MPVector2D* P0 = [MPVector2D vectorWith3i: p0];
			MPVector2D* P1 = [MPVector2D vectorWith3i: p1];
			
			MPVector2D* R0 = [X0.mpLocation sub: P0];
			MPVector2D* R1 = [X0.mpLocation sub: P1];
			
			MPDecimal* dot0 = [R0 dot: R0];
			MPDecimal* dot1 = [R1 dot: R1];
			
			return [dot0 compare: dot1];
			
		}];
			
		[intersections addObjectsFromArray: segmentIntersections];
	}
	
	// at this point, we have all intersections of self, in sorted order as traversing self.
	
	// next up sort in order of J
	NSArray* intersectionsOnJ = [intersections sortedArrayWithOptions: NSSortStable usingComparator: ^NSComparisonResult(SOIntersection* X0, SOIntersection* X1) {
		
		v3i_t p0 = other.vertices[X0.indexJ];
		v3i_t p1 = other.vertices[X1.indexJ];
		
		MPVector2D* P0 = [MPVector2D vectorWith3i: p0];
		MPVector2D* P1 = [MPVector2D vectorWith3i: p1];
		
		MPVector2D* R0 = [X0.mpLocation sub: P0];
		MPVector2D* R1 = [X0.mpLocation sub: P1];
		
		MPDecimal* dot0 = [R0 dot: R0];
		MPDecimal* dot1 = [R1 dot: R1];
		
		return [dot0 compare: dot1];
		
	}];
	
	// populate linked lists
	[intersections enumerateObjectsUsingBlock:^(SOIntersection* obj, NSUInteger idx, BOOL *stop) {
		obj.nextI = [intersections objectAtIndex: (idx+1) % intersections.count];
	}];
	[intersectionsOnJ enumerateObjectsUsingBlock:^(SOIntersection* obj, NSUInteger idx, BOOL *stop) {
		obj.nextJ = [intersectionsOnJ objectAtIndex: (idx+1) % intersectionsOnJ.count];
	}];

	
	
	// now we have two lists of indices, for traversing self and other
	
	SOIntersection* loopStartIntersection = nil;
	SOIntersection* currentIntersection = nil;

	NSMutableArray* loops = [NSMutableArray array];
	__block SlicedLineSegment* currentSegment = nil;

	void (^emitBlock)(SOIntersection*, SOIntersection*, BOOL) = ^(SOIntersection* currentX, SOIntersection* nextX, BOOL followI){
		if (!currentSegment)
		{
			currentSegment = [[SlicedLineSegment alloc] init];
			[loops addObject: currentSegment];
		}
		
		
		[currentSegment insertVertexAtEnd: currentX.location];
		
		v3i_t* vs = followI ? self.vertices : other.vertices;
		
		size_t start = followI ? currentX.indexI+1 : currentX.indexJ+1;
		size_t end = followI ? nextX.indexI : nextX.indexJ;
		
		if (end < start)
			end += followI ? self.vertexCount : other.vertexCount;
		
		for (size_t i = start; i < end; ++i)
		{
			// add one by one because of "looping" overflow
			[currentSegment insertVertexAtEnd: vs[i]];
		}
		
		
		
		if (nextX == loopStartIntersection)
			currentSegment = nil;
	};
	

	
	NSMutableSet* unconsumedIntersections = [NSMutableSet setWithArray: intersections];
	
	
	
	while (unconsumedIntersections.count)
	{
		BOOL emitPath = NO;
		BOOL followI = NO;

		if (!currentIntersection)
		{
			currentIntersection = [unconsumedIntersections anyObject];
		}
		
		if ((currentIntersection.dirI > 0) && (currentIntersection.dirJ > 0))
		{ // entering both, means we're going into a hole
			//assert(!other.isCCW);
			
			followI = !self.isCCW;
			emitPath = YES;
		}
		else if ((currentIntersection.dirI < 0) && (currentIntersection.dirJ < 0))
		{ // exiting both, take the outline
			//assert(!other.isCCW);
			
			followI = self.isCCW;
			emitPath = YES;
			
		}
		else if ((currentIntersection.dirI < 0) && (currentIntersection.dirJ > 0))
		{ // entering other
			//assert(other.isCCW);
			
			followI = NO;
			emitPath = YES;
		}
		else if ((currentIntersection.dirI > 0) && (currentIntersection.dirJ < 0))
		{ // entering self
			//assert(other.isCCW);
			
			followI = YES;
			emitPath = YES;
		}
		else
			assert(0); // should never happen
		
		SOIntersection* nextIntersection = nil;
		if (followI)
			nextIntersection = currentIntersection.nextI;
		else
			nextIntersection = currentIntersection.nextJ;
		
		
		if (emitPath && !loopStartIntersection)
		{
			loopStartIntersection = currentIntersection;
		}
		
		if (emitPath)
			emitBlock(currentIntersection, nextIntersection, followI);
		

		[unconsumedIntersections removeObject: currentIntersection];

		if (emitPath && (loopStartIntersection != nextIntersection))
			currentIntersection = nextIntersection;
		else
		{
			currentIntersection = nil;
			loopStartIntersection = nil;
		}
		
	}
	
	return loops;
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

- (NSBezierPath*) bezierPath
{
	NSBezierPath* path = [NSBezierPath bezierPath];
	for (size_t i = 0; i < vertexCount; ++i)
	{
		v3i_t vertex = vertices[i];
		if (!i)
			[path moveToPoint: v3iToCGPoint(vertex)];
		else
			[path lineToPoint: v3iToCGPoint(vertex)];
	}
	if (self.isClosed)
		[path closePath];

	return path;
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
