//
//  PolygonSkeletizer.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 23.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath_fixp.h"



@class GfxMesh, PolygonSkeletizer, PSWaveFrontSnapshot, PSMotorcycle, PSEdge, PSVertex, MPDecimal;


typedef void (^SkeletizerEventCallback)(PolygonSkeletizer* skeletizer, id event);
typedef void (^SkeletizerEmitCallback)(PolygonSkeletizer* skeletizer, PSWaveFrontSnapshot* snapshot);


@interface PolygonSkeletizer : NSObject

@property(nonatomic) double extensionLimit;
@property(nonatomic) double mergeThreshold;
@property(nonatomic,strong) NSArray* emissionTimes;

@property(nonatomic,strong) SkeletizerEventCallback eventCallback;
@property(nonatomic,strong) SkeletizerEmitCallback emitCallback;

- (void) addClosedPolygonWithVertices: (v3i_t*) vv count: (size_t) vcount;
- (void) generateSkeleton;

- (GfxMesh*) skeletonMesh;
- (NSArray*) offsetMeshes;
- (NSArray*) motorcycleDisplayPaths;
- (NSArray*) spokeDisplayPaths;
- (NSArray*) outlineDisplayPaths;

- (NSArray*) waveFrontOutlinesTerminatedAfter: (MPDecimal*) tBegin upTo: (MPDecimal*) tEnd;


@end


