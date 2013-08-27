//
//  PolygonSkeletizer.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 23.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath_fixp.h"

@class GfxMesh, PolygonSkeletizer, PSWaveFrontSnapshot, PSMotorcycle, PSEdge, PSVertex, MPDecimal, MPVector2D, PSSpoke;


MPVector2D* PSIntersectSpokes(PSSpoke* spoke0, PSSpoke* spoke1);



typedef void (^SkeletizerEventCallback)(PolygonSkeletizer* skeletizer, id event);
typedef void (^SkeletizerEmitCallback)(PolygonSkeletizer* skeletizer, PSWaveFrontSnapshot* snapshot);


@interface PolygonSkeletizer : NSObject

@property(nonatomic) BOOL debugLoggingEnabled;

@property(nonatomic) double extensionLimit;
@property(nonatomic) double mergeThreshold;
@property(nonatomic,strong) NSArray* emissionTimes;
@property(nonatomic,strong, readonly) NSArray* doneSteps;

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


@interface PolySkelPhase : NSObject

@property(nonatomic, strong) id (^nextHandler)(id);

@property(nonatomic, strong) NSArray* outlinePaths;
@property(nonatomic, strong) NSArray* motorcyclePaths;
@property(nonatomic, strong) NSArray* activeSpokePaths;
@property(nonatomic, strong) NSArray* terminatedSpokePaths;
@property(nonatomic, strong) NSArray* waveFrontPaths;

@property(nonatomic, strong) NSMutableArray* eventLog;

@property(nonatomic, strong) MPDecimal* timeSqr;
@property(nonatomic, strong) MPVector2D* location;

@property(nonatomic) BOOL isFinished;

@end
