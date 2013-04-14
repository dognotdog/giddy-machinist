//
//  Slicer.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 22.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import "Slicer.h"

#import "gfx.h"
#import "FoundationExtensions.h"
#import "SlicedOutline.h"
#import "PolygonSkeletizer.h"

static void _sliceZLayer(OctreeNode* node, vector_t* vertices, double zh, NSMutableArray* outSegments)
{
	vector_t pop = vCreate(0.0, 0.0, zh, 1.0);
	for (size_t i = 0; i < node->numTriangles; ++i)
	{
		SlicedLineSegment* segment = nil;
		for (size_t j = 0; j < 3; ++j)
		{
			MeshTriangle* tri = node->triangles[i];
			vector_t a = vertices[tri->vertices[j]];
			vector_t b = vertices[tri->vertices[(j+1)%3]];
			vector_t ray = v3Sub(b, a);
			double t = IntersectLinePlane(a, ray, pop, vCreateDir(0.0, 0.0, 1.0));
			
			if ((t >= 0.0) & (t < 1.0))
			{
				vector_t x = v3Add(a, v3MulScalar(ray, t));
				x.farr[2] = zh; // set Z height explicitly to prevent floating point rounding error
				if (!segment)
				{
					segment = [[SlicedLineSegment alloc] init];
					segment.begin = x;
				}
				else
				{
					segment.end = x;
					[outSegments addObject: segment];
					break;
				}
			}
		}
	}

	for (size_t i = 0; i < node->numChildren; ++i)
	{
		OctreeNode* child = node->children[i];
		
		if ((child->outerBounds.minv.farr[2] <= zh) && (child->outerBounds.maxv.farr[2] > zh))
			_sliceZLayer(child, vertices, zh, outSegments);
	}
}

@implementation Slicer

@synthesize mergeThreshold;

- (id) init
{
	if (!(self = [super init]))
		return nil;

	mergeThreshold = 0.01;
	
	return self;
}

- (void) asyncSliceModel: (GfxMesh*) model intoLayers: (NSArray*) layers layersWithCallbackOnQueue: (dispatch_queue_t) queue block: (void (^)(id)) callback;
{
//	dispatch_queue_t workQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_queue_t workQueue = dispatch_queue_create("com.elmonkey.giddy-machinist.slicing", 0);
	
	MeshOctree* octree = [[MeshOctree alloc] init];
	[model addTrianglesToOctree: octree];
	MeshOctree_generateTree(octree);

	for (NSNumber* layerZ in layers)
	{
		double height = [layerZ doubleValue];
		
		dispatch_async(workQueue, ^{
			@autoreleasepool {
				
				NSMutableArray* segments = [NSMutableArray array];
				
				_sliceZLayer(octree->baseNode, octree->vertices, height, segments);
				
				SlicedLayer* layer = [self connectSegments: segments];
				layer.layerZ = height;
				layer = [self nestPaths: layer];
				
				
				dispatch_async(queue, ^{
					@autoreleasepool {
						callback(layer);
					}
				});
			}
		});
		
		
		
	}

}

- (NSArray*) sliceModel: (GfxMesh*) model intoLayers: (NSArray*) layers
{
	MeshOctree* octree = [[MeshOctree alloc] init];
	[model addTrianglesToOctree: octree];
	MeshOctree_generateTree(octree);
	NSMutableArray* segmentedLayers = [[NSMutableArray alloc] initWithCapacity: [layers count]];
	
	for (NSNumber* layerZ in layers)
	{
		double height = [layerZ doubleValue];
		NSMutableArray* segments = [NSMutableArray array];
		
		_sliceZLayer(octree->baseNode, octree->vertices, height, segments);
		
		[segmentedLayers addObject: segments];
	}
	
	NSArray* workingLayers = [self connectAllSegments: segmentedLayers];
	
	workingLayers = [workingLayers map:^id(id obj) {
		return [self nestPaths: obj];
	}];
	
//	NSLog([workingLayers description]);
	
	return workingLayers;
}

- (SlicedLayer*) nestPaths: (SlicedLayer* ) inLayer
{
	NSMutableArray* inPaths = [inLayer.outlinePaths mutableCopy];
	NSMutableArray* outerPaths = [NSMutableArray array];
	while ([inPaths count])
	{
		SlicedOutline* outline = [inPaths lastObject];
		[inPaths removeLastObject];
		BOOL outerPath = YES;
		for (SlicedOutline* outline2 in inPaths)
		{			
			if ([outline2.outline containsPath: outline.outline])
			{
				outerPath = NO;
				
				outline2.holes = [outline2.holes arrayByAddingObject: outline];
				
				break;
			}
			else if ([outline.outline containsPath: outline2.outline])
			{
				[inPaths insertObject: outline atIndex: 0];
				outerPath = NO;
				break;
			}

		}
		
		if (outerPath)
			[outerPaths addObject: outline];
	}
	
	for (SlicedOutline* outline in outerPaths)
	{
		[outline recursivelyNestPaths];
		[outline generateSkeletonWithMergeThreshold: 0.5*mergeThreshold];
	}
	
	inLayer.outlinePaths = outerPaths;
	
	return inLayer;

}

- (SlicedLayer*) connectSegments: (NSArray* ) segments
{
	SlicedLayer* layer = [[SlicedLayer alloc] init];
	
	if (![segments count])
		return layer;
	
	NSMutableArray* openPaths = [NSMutableArray array];
	
	NSMutableArray* closedPaths = [NSMutableArray array];
	
	NSMutableArray* unprocessedSegments = [segments mutableCopy];
	
	while ([unprocessedSegments count])
	{
		BOOL foundMerge = NO;
		SlicedLineSegment* referenceSegment = [unprocessedSegments lastObject];
		[unprocessedSegments removeLastObject];
		
		
		double foundDistanceSqr = INFINITY;
		size_t foundIndex = NSNotFound, foundCombo = NSNotFound;
		
		BOOL atEnd[4] = {NO, NO, YES, YES};
		BOOL reverse[4] = {NO, YES, NO, YES};
		
		size_t si = 0;
		for (SlicedLineSegment* segment in unprocessedSegments)
		{
			vector_t delta[4] = {
				v3Sub(referenceSegment.begin, segment.begin),
				v3Sub(referenceSegment.begin, segment.end),
				v3Sub(referenceSegment.end, segment.begin),
				v3Sub(referenceSegment.end, segment.end),
			};
			
			double distance[4];
			
			for (size_t i = 0; i < 4; ++i)
			{
				distance[i] = vDot(delta[i], delta[i]);
				if (distance[i] < foundDistanceSqr)
				{
					foundDistanceSqr = distance[i];
					foundIndex = si;
					foundCombo = i;
				}
			}
			++si;
		}
		
		if ((foundDistanceSqr) < mergeThreshold*mergeThreshold)
		{
			foundMerge = YES;
			
			//NSLog(@"merging: %@, %@", referenceSegment, [unprocessedSegments objectAtIndex: foundIndex]);
			
			referenceSegment = [referenceSegment joinSegment: [unprocessedSegments objectAtIndex: foundIndex] atEnd: atEnd[foundCombo] reverse: reverse[foundCombo]];
			[unprocessedSegments removeObjectAtIndex: foundIndex];
		}
		
		
		
		if (foundMerge)
		{
			if ([referenceSegment closePolygonByMergingEndpoints: mergeThreshold])
			{
				double area = [referenceSegment area];
				if (fabs(area) > mergeThreshold*mergeThreshold) // discard triangle if its too bloody small
					[closedPaths addObject: referenceSegment];
				//else
				//	NSLog(@"discarding polygon %f: %@", area, referenceSegment);
			}
			else
			{
				[unprocessedSegments addObject: referenceSegment];
			}
		}
		else
			[openPaths addObject: referenceSegment];
		
		
		
	}
	
	//		assert(![openPaths count]);
	
	//		NSLog(@"Layer generated with %zd, %zd paths", [closedPaths count], [openPaths count]);
	
	layer.outlinePaths = [closedPaths map:^id(SlicedLineSegment* segment) {
		assert(segment.vertexCount);

		[segment optimizeColinears: mergeThreshold];
		[segment optimizeToThreshold: mergeThreshold];

		[segment analyzeSegment];

		if (!segment.isCCW)
		{
			[segment reverse];
			[segment analyzeSegment];
			assert(segment.isCCW);
		}

		[segment analyzeSegment];
		assert(segment.isCCW);
		
		SlicedOutline* outline = [[SlicedOutline alloc] init];
		outline.outline = segment;
		return outline;
	}];
	
	layer.outlinePaths = [layer.outlinePaths select: ^BOOL(SlicedOutline* obj) {
		return 0 != obj.outline.vertexCount;
	}];
	
	layer.openPaths = openPaths;
	
	return layer;
}


- (NSArray*) connectAllSegments: (NSArray* ) inLayers
{

	NSArray* outLayers = [inLayers map: ^id(NSArray* segments)
	{
		return [self connectSegments: segments];
	}];
	
	
	return outLayers;
}


@end




@implementation SlicedLayer

@synthesize outlinePaths, openPaths;

- (GfxMesh*) layerMesh
{
	GfxMesh* layerMesh = [[GfxMesh alloc] init];
	
	size_t vertexCount = 0;
	
	for (SlicedOutline* path in outlinePaths)
	{
		NSArray* segments = [path allNestedPaths];
		for (SlicedLineSegment* segment in segments)
			vertexCount += ([segment vertexCount])*2;
	}
	for (SlicedLineSegment* line in openPaths)
		vertexCount += ([line vertexCount]-1)*2;
	
	if (!vertexCount)
		return layerMesh;
	
	vector_t* vertices = calloc(vertexCount, sizeof(*vertices));
	vector_t* colors = calloc(vertexCount, sizeof(*colors));
	uint32_t* indices = calloc(vertexCount, sizeof(*indices));
	
	for (size_t i = 0; i < vertexCount; ++i)
		indices[i] = i;
	for (size_t i = 0; i < vertexCount; ++i)
		colors[i] = vCreate(1.0, 1.0, 0.0, 1.0);
	
	size_t k = 0;
	
	for (SlicedOutline* outline in outlinePaths)
	{
		NSArray* segments = [outline allNestedPaths];
		for (SlicedLineSegment* segment in segments)
		{
			vector_t color = vCreate(0.0, 0.5+0.5*(segment.isCCW), segment.isSelfIntersecting, 1.0);
			for (size_t i = 0; i < segment.vertexCount; ++i)
			{
				double fa = (double)i/segment.vertexCount;
				double fb = (double)(i+1)/segment.vertexCount;
				
				colors[k] = (vCreate(fa, 1.0, 0.0, 1.0));
				vertices[k++] = segment.vertices[i];
				colors[k] = (vCreate(fb, 1.0, 0.0, 1.0));
				vertices[k++] = segment.vertices[(i+1)%segment.vertexCount];
			}
		}
	}
	for (SlicedLineSegment* segment in openPaths)
	{
		for (size_t i = 0; i+1 < segment.vertexCount; ++i)
		{
			colors[k] = vCreate(1.0, 0.0, 0.0, 1.0);
			vertices[k++] = segment.vertices[i];
			colors[k] = vCreate(1.0, 0.0, 0.0, 1.0);
			vertices[k++] = segment.vertices[i+1];
		}
	}
	
	assert(k==vertexCount);
	
	
	[layerMesh setVertices: vertices count: vertexCount copy: NO];
	[layerMesh setColors: colors count: vertexCount copy: NO];
	[layerMesh addDrawArrayIndices: indices count: vertexCount withMode: GL_LINES];
	
	free(indices);
	
	for (SlicedOutline* outline in outlinePaths)
	{
		NSArray* outlines = [outline.skeleton offsetMeshes];
		for (GfxMesh* mesh in outlines)
			[layerMesh appendMesh: mesh];
		[layerMesh appendMesh: [outline.skeleton skeletonMesh]];

	}
	
	return layerMesh;
}

- (id) description
{
	NSMutableArray* descs = [NSMutableArray array];
	
	for (SlicedOutline* path in outlinePaths)
		[descs addObject: path];
	
	return [NSString stringWithFormat: @"Outlines: %@", descs];
}


@end

