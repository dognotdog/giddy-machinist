//
//  FixPolygon.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 26.06.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "FixPolygon.h"

#import "MPInteger.h"
#import "MPVector2D.h"
#import "gfx.h"
#import "ModelObject.h"



@import AppKit;

#import "FoundationExtensions.h"


@interface PolygonIntersection : NSObject

@property(nonatomic) MPVector2D* mpLocation;
@property(nonatomic) v3i_t	location;
@property(nonatomic) size_t	indexI, indexJ;
@property(nonatomic) long	dirI, dirJ;

@property(nonatomic, weak) PolygonIntersection* nextI;
@property(nonatomic, weak) PolygonIntersection* nextJ;

@end



@interface FixPolygonRecursive : NSObject

@property(nonatomic, strong) FixPolygonSegment* segment;
@property(nonatomic, strong) NSArray* children;

+ (NSArray*) recursivelySortSegments: (NSArray*) segments;

- (void) recursivelySortSegments;

- (void) recursivelyAdjustWindigs: (BOOL) startCCW;
//- (void) recursivelyAdjustLevels: (BOOL) startCCW;

- (NSArray*) allSegments;

@end



@implementation PolygonIntersection

- (NSString *)description
{
	vector_t x = v3iToFloat(self.location);
	return [NSString stringWithFormat: @"%p @ (%f, %f) diri: %ld dirj: %ld", self, x.farr[0], x.farr[1], self.dirI, self.dirJ];
}

@end

@implementation FixPolygonRecursive

+ (NSArray*) recursivelySortSegments: (NSArray*) segments
{
	NSArray* inputList = [segments map:^id(FixPolygonSegment* obj) {
		FixPolygonRecursive* poly = [[FixPolygonRecursive alloc] init];
		
		if (obj.isClosed)
		{
			FixPolygonClosedSegment* cseg = (id) obj;
			if (!cseg.isCCW)
				[cseg reverse];
			assert(cseg.isCCW);
		}
		
		poly.segment = obj;
		poly.children = @[];
		return poly;
	}];
	
	NSMutableArray* unsortedPolys = inputList.mutableCopy;
	NSMutableArray* rootPolys = [[NSMutableArray alloc] init];
	
	while (unsortedPolys.count)
	{
		FixPolygonRecursive* poly = [unsortedPolys lastObject];
		[unsortedPolys removeLastObject];
		for (FixPolygonRecursive* poly2 in unsortedPolys.copy)
		{
			if (poly2.segment.isClosed)
			{
				FixPolygonClosedSegment* cseg = (id)poly2.segment;
			
				if ([cseg containsPath: poly.segment])
				{
					poly2.children = [poly2.children arrayByAddingObject: poly];
					poly = nil;
					break;
				}
			}
		}
		if (poly)
			[rootPolys addObject: poly];
		
	}
	
	for (FixPolygonRecursive* poly in rootPolys)
		[poly recursivelySortSegments];
	
	return rootPolys;
	
}

- (void) recursivelySortSegments
{
	NSMutableArray* unsortedPolys = self.children.mutableCopy;
	NSMutableArray* rootPolys = [[NSMutableArray alloc] init];
	
	while (unsortedPolys.count)
	{
		FixPolygonRecursive* poly = [unsortedPolys lastObject];
		[unsortedPolys removeLastObject];
		for (FixPolygonRecursive* poly2 in unsortedPolys.copy)
		{
			if (poly2.segment.isClosed)
			{
				FixPolygonClosedSegment* cseg = (id)poly2.segment;
				
				if ([cseg containsPath: poly.segment])
				{
					poly2.children = [poly2.children arrayByAddingObject: poly];
					poly = nil;
					break;
				}
			}
		}
		if (poly)
			[rootPolys addObject: poly];
		
	}
	
	for (FixPolygonRecursive* poly in rootPolys)
		[poly recursivelySortSegments];

	self.children = rootPolys;
}

- (void) recursivelyAdjustWindigs: (BOOL) startCCW
{
	if (self.segment.isClosed)
	{
		FixPolygonClosedSegment* cseg = (id) self.segment;
		if (cseg.isCCW != startCCW)
		{
			[cseg reverse];
		}
	}
	
	for (FixPolygonRecursive* child in self.children)
		[child recursivelyAdjustWindigs: !startCCW];
}

- (NSArray*) allSegments
{
	NSMutableArray* all = [NSMutableArray array];
	
	for (FixPolygonRecursive* child in self.children)
	{
		[all addObjectsFromArray: [child allSegments]];
	}
	
	[all addObject: self.segment];
	return all;
}

@end


@interface FixPolygon () <ModelObjectNavigation>
{
	NSString* navLabel;
}
@property(nonatomic, strong) NSString* navLabel;

@end


@implementation FixPolygon
{
	id gfxMeshCache;
}

@synthesize openStartColor, openEndColor, ccwStartColor, ccwEndColor, cwStartColor, cwEndColor, opacity;
@synthesize segments;
@synthesize document;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	openStartColor = vCreate(1.0, 0.0, 0.0, 1.0);
	openEndColor = vCreate(1.0, 0.5, 0.0, 1.0);
	ccwStartColor = vCreate(0.0, 1.0, 0.0, 1.0);
	ccwEndColor = vCreate(1.0, 1.0, 0.0, 1.0);
	cwStartColor = vCreate(0.0, 0.5, 1.0, 1.0);
	cwEndColor = vCreate(0.5, 0.0, 1.0, 1.0);
	opacity = 0.5;
	
	return self;
}

- (instancetype) copyWithZone:(NSZone *)zone
{
	FixPolygon* poly = [[FixPolygon alloc] init];
	
	poly.segments = [self.segments map:^id(id obj) {
		return  [obj copyWithZone: zone];
	}];
	
	return poly;
}

- (void) reviseWinding
{
	NSArray* polys = [FixPolygonRecursive recursivelySortSegments: self.segments];
	NSMutableArray* allSegments = [[NSMutableArray alloc] init];
	
	for (FixPolygonRecursive* poly in polys)
	{
		[poly recursivelyAdjustWindigs: YES];
		[allSegments addObjectsFromArray: poly.allSegments];
	}
	
	self.segments = allSegments;
	
}


+ (FixPolygon*) polygonFromBezierPath: (NSBezierPath*) bpath withTransform: (NSAffineTransform*) transform flatness: (CGFloat) flatness
{
	bpath = [bpath copy]; // copy path because we don't want to alter the original
	if (transform)
		[bpath transformUsingAffineTransform: transform];
	
	CGFloat oldFlatness = [NSBezierPath defaultFlatness];
	
	[NSBezierPath setDefaultFlatness: flatness];
	[bpath setFlatness: flatness];
	NSBezierPath* flatPath = [bpath bezierPathByFlatteningPath];
	
	[NSBezierPath setDefaultFlatness: oldFlatness];

	NSInteger count = flatPath.elementCount;
	
	FixPolygonOpenSegment* currentSegment = nil;
	
	NSMutableArray* segments = [[NSMutableArray alloc] init];
	
	id (^attemptClose)(id) = ^id(FixPolygonOpenSegment* segment){

		if (!segment.isClosed)
		{
			FixPolygonClosedSegment* csegment = [segment closePolygonByMergingEndpoints];
			[csegment analyzeSegment];
			
			
			if (csegment)
			{
				return csegment;
			}
		}
		return segment;
	};
	
	for (NSInteger i = 0; i < count; ++i)
	{
		NSPoint pa[3];
		NSBezierPathElement element = [flatPath elementAtIndex: i associatedPoints: pa];
		
		switch (element) {
			case NSMoveToBezierPathElement:
			{
				if (currentSegment)
				{
					[segments addObject: attemptClose(currentSegment)];
				}
				currentSegment = [[FixPolygonOpenSegment alloc] init];
				v3i_t v = v3iCreateFromFloat(pa[0].x, pa[0].y, 0.0, 16);
				[currentSegment insertVertexAtEnd: v];
				break;
			}
			case NSLineToBezierPathElement:
			{
				v3i_t v = v3iCreateFromFloat(pa[0].x, pa[0].y, 0.0, 16);
				[currentSegment insertVertexAtEnd: v];
				break;
			}
			case NSClosePathBezierPathElement:
			{
				FixPolygonClosedSegment* cseg = [currentSegment closePolygonWithoutMergingEndpoints];

				if (cseg)
					[segments addObject: cseg];
				currentSegment = nil;
				break;
			}
			default:
				assert(0); // unsupported path element
				break;
		}
		
	}
	
	if (currentSegment)
	{
		[currentSegment cleanupDoubleVertices];
		[segments addObject: attemptClose(currentSegment)];
	}
	
	FixPolygon* polygon = [[FixPolygon alloc] init];
	polygon.segments = segments;
	
	[polygon reviseWinding];
	
	return polygon;
}

- (void) setSegments: (NSArray *) array
{
	[self willChangeValueForKey: @"segments"];
	
	[array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		[obj setNavLabel: [NSString stringWithFormat: @"%lu (%lu)", idx, [obj vertexCount]]];
	}];
	
	
	segments = array;
	gfxMeshCache = nil;
	
	[self didChangeValueForKey: @"segments"];
}

- (GfxMesh*) gfxMesh
{
	if (gfxMeshCache)
		return gfxMeshCache;

	GfxMesh* gfxMesh = [[GfxMesh alloc] init];
	gfxMeshCache = gfxMesh;
	
	size_t vertexCount = 0;
	
	for (FixPolygonSegment* segment in self.segments)
	{
		if (segment.isClosed)
			vertexCount += (segment.vertexCount)*2;
		else if (segment.vertexCount)
			vertexCount += (segment.vertexCount-1)*2;
	}

	if (!vertexCount)
		return gfxMesh;
	
	vector_t* vertices = calloc(vertexCount, sizeof(*vertices));
	vector_t* colors = calloc(vertexCount, sizeof(*colors));
	uint32_t* indices = calloc(vertexCount, sizeof(*indices));
	
	for (size_t i = 0; i < vertexCount; ++i)
		indices[i] = i;
	for (size_t i = 0; i < vertexCount; ++i)
		colors[i] = vCreate(1.0, 1.0, 0.0, 1.0);
	
	size_t k = 0;
	
	for (FixPolygonSegment* segment in self.segments)
	{
		vector_t startColor = openStartColor;
		vector_t endColor = openEndColor;
		
		if (segment.isClosed)
		{
			if (((FixPolygonClosedSegment*)segment).isCCW)
			{
				startColor = ccwStartColor;
				endColor = ccwEndColor;
			}
			else
			{
				startColor = cwStartColor;
				endColor = cwEndColor;
			}
			//vector_t color = vCreate(0.0, 0.5+0.5*(segment.isCCW), segment.isSelfIntersecting, 1.0);
			for (size_t i = 0; i < segment.vertexCount; ++i)
			{
				double fa = (double)i/segment.vertexCount;
				double fb = (double)(i+1)/segment.vertexCount;
				
				vector_t colorA = vScaleRaw(vAddRaw(vScaleRaw(startColor, 1.0-fa), vScaleRaw(endColor, fa)), opacity);
				vector_t colorB = vScaleRaw(vAddRaw(vScaleRaw(startColor, 1.0-fb), vScaleRaw(endColor, fb)), opacity);
								
				colors[k] = colorA;
				vertices[k++] = v3iToFloat(segment.vertices[i]);
				colors[k] = colorB;
				vertices[k++] = v3iToFloat(segment.vertices[(i+1)%segment.vertexCount]);
			}
		}
		else
		{
			for (size_t i = 0; i+1 < segment.vertexCount; ++i)
			{
				double fa = (double)i/segment.vertexCount;
				double fb = (double)(i+1)/segment.vertexCount;
				
				vector_t colorA = vScaleRaw(vAddRaw(vScaleRaw(startColor, 1.0-fa), vScaleRaw(endColor, fa)), opacity);
				vector_t colorB = vScaleRaw(vAddRaw(vScaleRaw(startColor, 1.0-fb), vScaleRaw(endColor, fb)), opacity);

				colors[k] = colorA;
				vertices[k++] = v3iToFloat(segment.vertices[i]);
				colors[k] = colorB;
				vertices[k++] = v3iToFloat(segment.vertices[i+1]);
			}
		}
	}

	assert(k==vertexCount);
	
	
	[gfxMesh setVertices: vertices count: vertexCount copy: NO];
	[gfxMesh setColors: colors count: vertexCount copy: NO];
	[gfxMesh addDrawArrayIndices: indices count: vertexCount withMode: GL_LINES];
	
	free(indices);
	
	return gfxMesh;
}

- (r3i_t) bounds
{
	r3i_t bounds = {v3iCreate(INT32_MAX, INT32_MAX, INT32_MAX, 16), v3iCreate(INT32_MIN, INT32_MIN, INT32_MIN, 16)};
	for (FixPolygonSegment* seg in self.segments)
	{
		r3i_t pb = seg.bounds;
		bounds.min = v3iMin(pb.min, bounds.min);
		bounds.max = v3iMax(pb.max, bounds.max);
	}
	return bounds;
}


#pragma mark - Model Navigation

@synthesize navLabel, navSelection;

- (NSInteger) navChildCount
{
	return segments.count;
}

- (id) navChildAtIndex:(NSInteger)idx
{
	return [segments objectAtIndex: idx];
}

- (GfxNode*) gfx
{
	GfxNode* root = [[GfxNode alloc] init];

	if (self.navSelection)
		[root addChild: [ModelObject boundingBoxForIntegerRange: self.bounds margin: vCreatePos(1.0, 1.0, 1.0)]];
	
	
	[root addChild: [[GfxTransformNode alloc] initWithMatrix: mIdentity()]];
	GfxMesh* mesh = self.gfxMesh;
	
	[root addChild: mesh];
	
	return root;
}

@end


@interface FixPolygonSegment () <ModelObjectNavigation>

@property(nonatomic,strong) NSString* navLabel;

@end


@implementation FixPolygonSegment
{
@public
	size_t	vertexCount;
	v3i_t*	vertices;
}

@synthesize vertexCount, vertices;
@synthesize document;

- (id) init
{
	if (!(self = [super init]))
		return nil;
		
	return self;
}

- (instancetype) copyWithZone:(NSZone *)zone
{
	FixPolygonSegment* poly = [[[self class] alloc] init];
	
	[poly addVertices: vertices count: vertexCount];
		
	return poly;
}

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

- (r3i_t) bounds
{
	r3i_t r = {v3iCreate(INT32_MAX, INT32_MAX, INT32_MAX, 16), v3iCreate(INT32_MIN, INT32_MIN, INT32_MIN, 16)};
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
	MPDecimal* crossSum = [MPDecimal zero];
	
	for (long i = 0; i < vertexCount; ++i)
	{
		v3i_t a = vertices[i];
		v3i_t b = vertices[(i+1)%vertexCount];
		vmlongfix_t cross = v3iCross2D(a, b);
		
		crossSum = [crossSum add: [MPDecimal decimalWithInt64: cross.x shift: cross.shift]];
	}
	return [crossSum mul: [MPDecimal oneHalf]].toDouble;
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

- (BOOL) isClosed
{
	[self doesNotRecognizeSelector: _cmd];
	return NO;
}

- (void) cleanupDoubleVertices
{
	if (vertexCount < 2)
		return;
	
	size_t max = self.vertexCount;
	
	for (size_t i = 0; i+1 < max; ++i)
	{
		if (v3iEqual(vertices[i], vertices[i+1]))
		{
			memmove(vertices + i, vertices + i + 1, sizeof(*vertices)*(vertexCount-i-1));
			--vertexCount;
			--max;
			--i;
		}
	}
	
	if (self.isClosed)
		while (v3iEqual(self.begin, self.end))
			--vertexCount;
	
}

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



@implementation FixPolygonOpenSegment

- (BOOL) isClosed
{
	return NO;
}


- (FixPolygonOpenSegment*) joinSegment: (FixPolygonOpenSegment*) seg atEnd: (BOOL) atEnd reverse: (BOOL) reverse
{
	FixPolygonOpenSegment* newSegment = [[FixPolygonOpenSegment alloc]  init];
	[newSegment expandVertexCount: vertexCount + seg.vertexCount - 1];
	
	v3i_t* newVertices = newSegment.vertices;
	v3i_t* selfVertices = self.vertices;
	v3i_t* segVertices = seg.vertices;
	
	size_t segVertexCount = seg.vertexCount;
	
	size_t vi = 0;
	
	if (atEnd)
	{
		for (size_t i = 0; i < vertexCount; ++i)
			newVertices[vi++] = selfVertices[i];
	}
	else
	{
		for (size_t i = vertexCount; i > 0; --i)
			newVertices[vi++] = selfVertices[i-1];
	}
	
	if (reverse)
	{
		// need to deduplicate reversed segments
		
		size_t vcount = segVertexCount;
		for (size_t i = 0; i < MIN(vertexCount, segVertexCount); ++i)
		{
			v3i_t v0 = newVertices[vertexCount-1-i];
			v3i_t v1 = segVertices[segVertexCount-1-i];
			if (v3iEqual(v0, v1))
				vcount--;
			else
				break;
		}
		
		for (size_t i = vcount; i > 0; --i)
			newVertices[vi++] = segVertices[i-1];
	}
	else
	{
		size_t vcount = 0;
		for (size_t i = 0; i < MIN(vertexCount, segVertexCount); ++i)
		{
			v3i_t v0 = newVertices[vertexCount-1-i];
			v3i_t v1 = segVertices[i];
			if (v3iEqual(v0, v1))
				vcount++;
			else
				break;
		}
		
		for (size_t i = vcount; i < segVertexCount; ++i)
			newVertices[vi++] = segVertices[i];
	}
	newSegment->vertexCount = vi;
	
	if (newSegment->vertexCount > vertexCount)
	{
		v3i_t v0 = newVertices[vertexCount-1];
		v3i_t v1 = newVertices[vertexCount];
		assert(!v3iEqual(v0, v1));
	}
	return newSegment;
}

- (FixPolygonClosedSegment*) closePolygonByMergingEndpoints
{
	if (vertexCount < 4)
		return nil;
	
	if (v3iEqual(self.begin, self.end))
	{
		FixPolygonClosedSegment* seg = [[FixPolygonClosedSegment alloc] init];
		
		size_t newCount = vertexCount;
		
		while (newCount && v3iEqual(vertices[0], vertices[newCount-1]))
			newCount--;

		if (newCount < 3)
			return nil;
		
		[seg addVertices: vertices count: newCount];
		return seg;
	}
	else
		return nil;
}

- (FixPolygonClosedSegment*) closePolygonWithoutMergingEndpoints
{
	if (vertexCount < 3)
		return nil;
	
	FixPolygonClosedSegment* seg = [[FixPolygonClosedSegment alloc] init];

	size_t newCount = vertexCount;
	
	while (newCount && v3iEqual(vertices[0], vertices[newCount-1]))
		newCount--;
	
	if (newCount < 3)
		return nil;
	
	[seg addVertices: vertices count: newCount];

	return seg;
}



@end



@implementation FixPolygonClosedSegment
{
}
@synthesize isConvex;

- (instancetype) copyWithZone:(NSZone *)zone
{
	FixPolygonClosedSegment* poly = [super copyWithZone: zone];
	
	poly->isConvex = isConvex;
	
	return poly;
}



- (BOOL) isClosed
{
	return YES;
}


- (NSBezierPath*) bezierPath
{
	NSBezierPath* path = [super bezierPath];
	[path closePath];
	return path;
}

- (BOOL) isCCW
{
	MPDecimal* area = [MPDecimal zero];
	
	for (long i = 0; i < vertexCount; ++i)
	{
		v3i_t a = vertices[i];
		v3i_t b = vertices[(i+1)%vertexCount];
		vmlongfix_t cross = v3iCross2D(a, b);
		area = [area add: [MPDecimal decimalWithInt64: cross.x shift: cross.shift]];
		
	}
	
	BOOL isCCW = area.isPositive && !area.isZero;
	return isCCW;
}

- (void) analyzeSegment
{
	long signCounter = 0;
	
	//	isSelfIntersecting = [self checkSelfIntersection];
	
	
	MPDecimal* area = [MPDecimal zero];
	
	for (long i = 0; i < vertexCount; ++i)
	{
		v3i_t a = vertices[i];
		v3i_t b = vertices[(i+1)%vertexCount];
		vmlongfix_t cross = v3iCross2D(a, b);
		area = [area add: [MPDecimal decimalWithInt64: cross.x shift: cross.shift]];
		
		signCounter += (cross.x > 0 ? 1 : (cross.x < 0 ? -1 : 0));
	}
	
	//isCCW = area.isPositive && !area.isZero;
	
	
	if (ABS(signCounter) == vertexCount)
		isConvex = YES;
	
}

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
	long count = vertexCount;
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

/*! Checks via ray casting if a single vertex of self is contained in segment.
 
 */
- (BOOL) containsPath: (FixPolygonSegment*) segment
{
	//assert(isCCW && segment.isCCW); // FIXME: assertion no longer necessary?
	
	v3i_t sc = segment.begin;
	r3i_t bounds = self.bounds;
	
	if (vertexCount < 3)
		return NO;
	
	//	if (!rRangeContainsPointXYInclusiveMinExclusiveMax(bounds, sc))
	//		return NO;
	
	// ray is going along X
	v3i_t ray = v3iCreate(bounds.max.x, 0, 0, bounds.max.shift);
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
		
		//v3i_t x = [X toVectorWithShift: 16];
		
		MPVector2D* P0 = [MPVector2D vectorWith3i: p0];
		MPVector2D* P1 = [MPVector2D vectorWith3i: p1];
		
		
		v3i_t e = v3iSub(p1, p0);
		
		// as the test ray propagates in +X
		// for edges going +Y, [0,den) is valid
		// for edges going -Y, (0, den] is valid
		
		BOOL goingY = e.y > 0;
		
		if (goingY && [P0 isEqualToVector: X])
			continue;
		else if (!goingY && [P1 isEqualToVector: X])
			continue;
		
		v3i_t d = v3iSub(sc, p0);
		
		if (!d.x && !d.y)
			continue;
		
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


static PolygonIntersection* _findNextIntersection(v3i_t* verticesi, size_t istart, size_t iend, size_t counti, v3i_t* verticesj, size_t jstart, size_t jend, size_t countj)
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
				vmlongfix_t crossi1 = v3iCross2D(ei, v3iSub(pj1, pi0));
				vmlongfix_t crossj0 = v3iCross2D(ej, v3iSub(pi0, pj0));
				vmlongfix_t crossj1 = v3iCross2D(ej, v3iSub(pi1, pj0));
				
				NSComparisonResult dirj = lcompare(crossi1.x, crossi0.x);
				NSComparisonResult diri = lcompare(crossj1.x, crossj0.x);
				
				PolygonIntersection* intersection = [[PolygonIntersection alloc] init];
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



- (NSArray*) booleanIntersectSegment: (FixPolygonSegment*) other
{
	assert(self.isClosed && other.isClosed);
	//assert(!self.isSelfIntersecting && !other.isSelfIntersecting);
	//	assert(self.isCCW); // we make a few assumptions about self being ccw later on
	
	BOOL containsOther = [self containsPath: other];
	BOOL containsSelf = [other respondsToSelector: @selector(containsPath:)] ? [(id)other containsPath: self] : NO;
	
	{
		PolygonIntersection* firstIntersection = _findNextIntersection(self.vertices, 0, self.vertexCount, self.vertexCount, other.vertices, 0, other.vertexCount, other.vertexCount);
		
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
	
	// we found a first intersection, now we have to traverse the paths to find the loops
	// at an intersection, we decide as follows:
	// - when both paths enter the other, the CW path is the outline (can only happen on CCW/CW intersect
	// - when one enters the other, take the one entering
	
	NSMutableArray* intersections = [NSMutableArray array];
	
	for (size_t i = 0; i < self.vertexCount; ++i)
	{
		NSMutableArray* segmentIntersections = [NSMutableArray array];
		
		
		PolygonIntersection* ix = nil;
		size_t jstart = 0;
		size_t jend = other.vertexCount;
		
		while ((ix = _findNextIntersection(self.vertices, i, i+1, self.vertexCount, other.vertices, jstart, jend, other.vertexCount)))
		{
			[segmentIntersections addObject: ix];
			
			jstart = ix.indexJ+1;
		}
		
		
		// sort only this subset, as overall it's sorted already
		[segmentIntersections sortWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PolygonIntersection* X0, PolygonIntersection* X1) {
			
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
	NSArray* intersectionsOnJ = [intersections sortedArrayWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PolygonIntersection* X0, PolygonIntersection* X1) {
		
		NSComparisonResult cmp = lcompare(X0.indexJ, X1.indexJ);
		
		if (cmp != NSOrderedSame)
			return cmp;
		
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
	[intersections enumerateObjectsUsingBlock: ^(PolygonIntersection* obj, NSUInteger idx, BOOL *stop) {
		obj.nextI = [intersections objectAtIndex: (idx+1) % intersections.count];
	}];
	[intersectionsOnJ enumerateObjectsUsingBlock: ^(PolygonIntersection* obj, NSUInteger idx, BOOL *stop) {
		obj.nextJ = [intersectionsOnJ objectAtIndex: (idx+1) % intersectionsOnJ.count];
	}];
	
	
	
	// now we have two lists of indices, for traversing self and other
	
	PolygonIntersection* loopStartIntersection = nil;
	PolygonIntersection* currentIntersection = nil;
	
	NSMutableArray* loops = [NSMutableArray array];
	__block FixPolygonSegment* currentSegment = nil;
	
	void (^emitBlock)(PolygonIntersection*, PolygonIntersection*, BOOL) = ^(PolygonIntersection* currentX, PolygonIntersection* nextX, BOOL followI){
		if (!currentSegment)
		{
			currentSegment = [[[self class] alloc] init];
			[loops addObject: currentSegment];
		}
		
		
		[currentSegment insertVertexAtEnd: currentX.location];
		
		v3i_t* vs = followI ? self.vertices : other.vertices;
		size_t vc = followI ? self.vertexCount : other.vertexCount;

		size_t start = (followI ? currentX.indexI : currentX.indexJ)+1;
		size_t end = (followI ? nextX.indexI : nextX.indexJ)+1;
		
		if (end < start)
			end += vc;
		
		for (size_t i = start; i < end; ++i)
		{
			// add one by one because of "looping" overflow
			[currentSegment insertVertexAtEnd: vs[i % vc]];
		}
		
		
		
		if (nextX == loopStartIntersection)
		{
			currentSegment = nil;
		}
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
		{ // entering both, invalid
			//assert(!other.isCCW);
			assert(0); // Not a valid configuration
			
			followI = !self.isCCW;
			emitPath = NO;
		}
		else if ((currentIntersection.dirI < 0) && (currentIntersection.dirJ < 0))
		{ // exiting both, invalid
			//assert(!other.isCCW);
			assert(0); // Not a valid configuration

			followI = self.isCCW;
			emitPath = NO;
			
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
		
		PolygonIntersection* nextIntersection = nil;
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


@end


