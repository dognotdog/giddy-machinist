//
//  PolygonSkeletizerObjects.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 29.03.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"

@class PSEdge, PSSourceEdge, PSSpoke, PSAntiSpoke, PSMotorcycle, PSWaveFront;

@interface PSVertex : NSObject
@property(nonatomic) vector_t position;
@property(nonatomic) double time;
@property(nonatomic, readonly) NSArray* edges;
@property(nonatomic, readonly) PSSourceEdge* prevEdge;
@property(nonatomic, readonly) PSSourceEdge* nextEdge;
@property(nonatomic, readonly) NSArray* incomingMotorcycles;
@property(nonatomic, readonly) NSArray* outgoingMotorcycles;
@property(nonatomic, readonly) NSArray* outgoingSpokes;

- (void) addEdge: (PSEdge*) edge;
- (void) removeEdge: (PSEdge*) edge;
- (PSSpoke*) nextSpokeClockwiseFrom: (vector_t) startDir to: (vector_t) endDir;

- (void) addMotorcycle: (PSMotorcycle*) cycle;
- (void) addSpoke: (PSSpoke*) spoke;

@end

@interface PSSplitVertex : PSVertex
@end

@interface PSCrashVertex : PSVertex
@end

@interface PSMergeVertex : PSVertex
@end


@interface PSEdge : NSObject
@property(nonatomic, weak) PSVertex* startVertex, *endVertex;
@property(nonatomic) vector_t normal, edge;
@end

@interface PSSourceEdge : PSEdge
@property(nonatomic, weak) PSSourceEdge *next, *prev;
@end

@interface PSSpoke : NSObject
@property(nonatomic, weak) PSVertex *sourceVertex, *terminalVertex;
@property(nonatomic) double start;
@property(nonatomic) vector_t velocity;
@property(nonatomic, weak) PSWaveFront* leftWaveFront;
@property(nonatomic, weak) PSWaveFront* rightWaveFront;
@end

@interface PSMotorcycleSpoke : PSSpoke
@property(nonatomic, weak) PSMotorcycle *motorcycle;
@property(nonatomic, weak) PSAntiSpoke	*antiSpoke;
@end

@interface PSAntiSpoke : PSSpoke
@property(nonatomic, weak) PSMotorcycle			*motorcycle;
@property(nonatomic, weak) PSMotorcycleSpoke	*motorcycleSpoke;
@end


@interface PSMotorcycle : NSObject
@property(nonatomic, weak) PSVertex* sourceVertex;
@property(nonatomic, weak) PSVertex* terminalVertex;
@property(nonatomic, weak) id terminator;
@property(nonatomic) vector_t velocity;
@property(nonatomic) vector_t leftNormal, rightNormal;
@property(nonatomic, weak) PSMotorcycle *leftNeighbour, *rightNeighbour;
@property(nonatomic) double start;

@property(nonatomic, weak) PSAntiSpoke* antiSpoke;
@property(nonatomic, weak) PSMotorcycleSpoke* spoke;


@end



@interface PSWaveFront: NSObject

@property(nonatomic, strong) PSSpoke* leftSpoke;
@property(nonatomic, strong) PSSpoke* rightSpoke;
@property(nonatomic) double collapseTime;

@end


@interface PSEvent : NSObject

@property(nonatomic) double time;
@property(nonatomic) vector_t location;

@end

@interface PSCollapseEvent : PSEvent

@property(nonatomic,weak) PSWaveFront* collapsingWaveFront;

@end

@interface PSSplitEvent : PSEvent

@property(nonatomic,weak) PSAntiSpoke* antiSpoke;

@end

@interface PSBranchEvent : PSEvent

@property(nonatomic,weak) PSCrashVertex* branchVertex;

@end

@interface PSMergeEvent : PSEvent

@property(nonatomic,weak) PSMergeVertex* mergeVertex;

@end

