//
//  PolygonContour.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 24.08.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "PolygonContour.h"

#import "FixPolygon.h"
#import "PolygonSkeletizer.h"
#import "PSWaveFrontSnapshot.h"

#import "FoundationExtensions.h"

@implementation PolygonContour


- (NSArray*) gfxMeshes
{
	NSMutableArray* meshes = [NSMutableArray array];
	if (self.polygon.gfxMesh)
		[meshes addObject: self.polygon.gfxMesh];
	if (self.toolpath.gfxMesh)
		[meshes addObject: self.toolpath.gfxMesh];
	return meshes;
}

- (void) generateToolpathWithOffset: (double) floatOffset cancellationCheck: (BOOL(^)(void)) checkBlock
{
	r3i_t polyBounds = self.polygon.bounds;
	
	if (floatOffset == 0.0)
	{
		self.toolpath = self.polygon.copy;
		//[self.toolpath nestPolygonWithOptions: PolygonNestingOptionSortY];
		return;
	}
	else
	{
		[self.polygon nestPolygonWithOptions: PolygonNestingOptionSortY];
	}
	
	BOOL insertExtendedBounds = (floatOffset > 0.0);

	
	vmintfix_t offset = iFixCreateFromFloat(2.0*floatOffset, 16);
	
	r3i_t extendedBounds = polyBounds;
	extendedBounds.min.x -= 2*offset.x+10;
	extendedBounds.min.y -= 2*offset.x+10;
	extendedBounds.max.x += 2*offset.x+10;
	extendedBounds.max.y += 2*offset.x+10;

	FixPolygonClosedSegment* boundary = [[FixPolygonClosedSegment alloc] init];
	
	[boundary insertVertexAtEnd: extendedBounds.min];
	[boundary insertVertexAtEnd: v3iCreate(extendedBounds.max.x, extendedBounds.min.y, extendedBounds.min.z, extendedBounds.min.shift)];
	[boundary insertVertexAtEnd: extendedBounds.max];
	[boundary insertVertexAtEnd: v3iCreate(extendedBounds.min.x, extendedBounds.max.y, extendedBounds.min.z, extendedBounds.min.shift)];
	
	r3i_t clipBounds = polyBounds;
	clipBounds.min.x -= offset.x+2;
	clipBounds.min.y -= offset.x+2;
	clipBounds.max.x += offset.x+2;
	clipBounds.max.y += offset.x+2;
	
	FixPolygonClosedSegment* clippingSegment = [[FixPolygonClosedSegment alloc] init];
	[clippingSegment insertVertexAtEnd: clipBounds.min];
	[clippingSegment insertVertexAtEnd: v3iCreate(clipBounds.max.x, clipBounds.min.y, clipBounds.min.z, clipBounds.min.shift)];
	[clippingSegment insertVertexAtEnd: clipBounds.max];
	[clippingSegment insertVertexAtEnd: v3iCreate(clipBounds.min.x, clipBounds.max.y, clipBounds.min.z, clipBounds.min.shift)];
	
	[clippingSegment analyzeSegment];
	
	PolygonSkeletizer* skeletizer = [[PolygonSkeletizer alloc] init];
	
	skeletizer.extensionLimit = 1.1*floatOffset;
	
	skeletizer.emissionTimes = @[[NSNumber numberWithDouble: floatOffset]];
	
	FixPolygon* poly = self.polygon.copy;
	
	
	if (insertExtendedBounds)
	{
		[poly.segments enumerateObjectsUsingBlock:^(FixPolygonClosedSegment* obj, NSUInteger idx, BOOL *stop) {
			if (obj.isClosed)
				[obj reverse];
		}];

		poly.segments = [poly.segments arrayByAddingObject: boundary];
	}
	for (FixPolygonSegment* obj in poly.segments)
		if (obj.vertexCount > 1)
			[skeletizer addClosedPolygonWithVertices: obj.vertices count: obj.vertexCount];
	
	skeletizer.emitCallback = ^(PolygonSkeletizer* skeletizer, PSWaveFrontSnapshot* snapshot)
	{
		FixPolygon* toolpath = snapshot.waveFrontPolygon;
		self.toolpath = toolpath;
	};
	
	[skeletizer generateSkeletonWithCancellationCheck:^BOOL{
		return NO;
	}];
	
	
	if (insertExtendedBounds)
	{
		self.toolpath.segments = [self.toolpath.segments select: ^BOOL(FixPolygonSegment* obj) {
			
			return [clippingSegment containsPath: obj];
			
		}];
	}

}

@end
