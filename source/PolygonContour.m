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

- (void) generateToolpathWithOffset: (double) floatOffset
{
	r3i_t polyBounds = self.polygon.bounds;
	
	vmintfix_t offset = iFixCreateFromFloat(2.0*floatOffset, 16);
	
	r3i_t extendedBounds = polyBounds;
	extendedBounds.min.x -= 2*offset.x+2;
	extendedBounds.min.y -= 2*offset.x+2;
	extendedBounds.max.x += 2*offset.x+2;
	extendedBounds.max.y += 2*offset.x+2;

	FixPolygonClosedSegment* boundary = [[FixPolygonClosedSegment alloc] init];
	
	[boundary insertVertexAtEnd: extendedBounds.min];
	[boundary insertVertexAtEnd: v3iCreate(extendedBounds.max.x, extendedBounds.min.y, extendedBounds.min.z, extendedBounds.min.shift)];
	[boundary insertVertexAtEnd: extendedBounds.max];
	[boundary insertVertexAtEnd: v3iCreate(extendedBounds.min.x, extendedBounds.max.y, extendedBounds.min.z, extendedBounds.min.shift)];
	
	r3i_t clipBounds = polyBounds;
	clipBounds.min.x -= offset.x+1;
	clipBounds.min.y -= offset.x+1;
	clipBounds.max.x += offset.x+1;
	clipBounds.max.y += offset.x+1;
	
	FixPolygonClosedSegment* clippingSegment = [[FixPolygonClosedSegment alloc] init];
	[clippingSegment insertVertexAtEnd: clipBounds.min];
	[clippingSegment insertVertexAtEnd: v3iCreate(clipBounds.max.x, clipBounds.min.y, clipBounds.min.z, clipBounds.min.shift)];
	[clippingSegment insertVertexAtEnd: clipBounds.max];
	[clippingSegment insertVertexAtEnd: v3iCreate(clipBounds.min.x, clipBounds.max.y, clipBounds.min.z, clipBounds.min.shift)];
	
	[clippingSegment analyzeSegment];
	
	PolygonSkeletizer* skeletizer = [[PolygonSkeletizer alloc] init];
	
	skeletizer.extensionLimit = 2.0*floatOffset;
	
	skeletizer.emissionTimes = @[[NSNumber numberWithDouble: floatOffset]];
	
	FixPolygon* poly = self.polygon.copy;
	
	poly.segments = [poly.segments arrayByAddingObject: boundary];
	
	[poly reviseWinding];
	
	for (FixPolygonSegment* obj in poly.segments)
		if (obj.vertexCount > 1)
			[skeletizer addClosedPolygonWithVertices: obj.vertices count: obj.vertexCount];
	
	skeletizer.emitCallback = ^(PolygonSkeletizer* skeletizer, PSWaveFrontSnapshot* snapshot)
	{
		FixPolygon* toolpath = snapshot.waveFrontPolygon;
		self.toolpath = toolpath;
	};
	
	[skeletizer generateSkeleton];
	
	
	self.toolpath.segments = [self.toolpath.segments select: ^BOOL(FixPolygonSegment* obj) {
		
		return [clippingSegment containsPath: obj];
		
	}];
	 

}

@end
