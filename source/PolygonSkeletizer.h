//
//  PolygonSkeletizer.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 23.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"



@class GfxMesh, PolygonSkeletizer;


typedef void (^SkeletizerEventCallback)(PolygonSkeletizer* skeletizer, id event);
typedef void (^SkeletizerEmitCallback)(PolygonSkeletizer* skeletizer, NSBezierPath* path);


@interface PolygonSkeletizer : NSObject

@property(nonatomic) double extensionLimit;
@property(nonatomic) double mergeThreshold;
@property(nonatomic,strong) SkeletizerEventCallback eventCallback;
@property(nonatomic,strong) SkeletizerEmitCallback emitCallback;

- (void) addClosedPolygonWithVertices: (vector_t*) vv count: (size_t) vcount;
- (void) generateSkeleton;

- (GfxMesh*) skeletonMesh;
- (NSArray*) offsetMeshes;
- (NSArray*) motorcycleDisplayPaths;
- (NSArray*) spokeDisplayPaths;
- (NSArray*) outlineDisplayPaths;

@end
