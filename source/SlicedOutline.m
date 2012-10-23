//
//  SlicedOutline.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 23.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import "SlicedOutline.h"

@implementation SlicedOutline

@synthesize outline, holes;

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

static inline long xLineSegments2D(vector_t p0, vector_t p1, vector_t p2, vector_t p3)
{
	vmfloat_t d = vCross(v3Sub(p1,p0), v3Sub(p3,p2)).farr[2];
	
	if (d == 0.0)
		return 0;
	
	vmfloat_t a = vCross(v3Sub(p2,p0), v3Sub(p3,p2)).farr[2];
	vmfloat_t b = vCross(v3Sub(p2,p0), v3Sub(p1,p0)).farr[2];
	
	vmfloat_t ta = a/d;
	vmfloat_t tb = b/d;
	
	return ((ta >= 0.0) && (ta < 1.0) && (tb >= 0.0) && (tb < 1.0));
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
	
	if (ABS(signCounter) == vertexCount)
		isConvex = YES;
	
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

- (id) description
{
	NSMutableArray* descs = [NSMutableArray array];
	
	for (size_t i = 0; i < vertexCount; ++i)
		[descs addObject: [NSString stringWithFormat: @"%.4f %.4f %.4f", vertices[i].farr[0],vertices[i].farr[1],vertices[i].farr[2]]];
	
	return [NSString stringWithFormat: @"Vertices: %@", descs];
}

@end
