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
	
	NSArray* workingLayers = [self connectSegments: segmentedLayers];
	
	workingLayers = [workingLayers map:^id(id obj) {
		return [self nestPaths: obj];
	}];
	
	return workingLayers;
}

- (SlicedLayer*) nestPaths: (SlicedLayer* ) inLayer
{
	for (SlicedLineSegment* path in inLayer.outlinePaths)
	{
	}
	
	
	
	for (SlicedLineSegment* path in inLayer.outlinePaths)
	{
		
	}
	
	
	return inLayer;

}

- (NSArray*) connectSegments: (NSArray* ) inLayers
{

	NSArray* outLayers = [inLayers map: ^id(NSArray* segments)
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
			size_t foundIndex = NSNotFound, foundCombo;
			
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
				
			if (foundDistanceSqr < mergeThreshold*mergeThreshold)
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
					[closedPaths addObject: referenceSegment];
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
			[segment analyzeSegment];
			[segment analyzeSegment];
			if (!segment.isCCW)
			{
				[segment reverse];
				[segment analyzeSegment];
			}
			SlicedOutline* outline = [[SlicedOutline alloc] init];
			outline.outline = segment;
			return outline;
		}];
		
		layer.openPaths = openPaths;

		return layer;
	}];
	
	
	return outLayers;
}


@end




@implementation SlicedLayer

@synthesize outlinePaths, openPaths;

@end

