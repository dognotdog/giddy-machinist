//
//  PolygonSkeletizer.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 23.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"

@class GfxMesh;

@interface PolygonSkeletizer : NSObject

@property(nonatomic) double extensionLimit;
@property(nonatomic) double mergeThreshold;

- (void) addClosedPolygonWithVertices: (vector_t*) vv count: (size_t) vcount;
- (void) generateSkeleton;

- (GfxMesh*) skeletonMesh;

@end
