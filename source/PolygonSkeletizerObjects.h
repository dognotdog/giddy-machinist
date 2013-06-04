//
//  PolygonSkeletizerObjects.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 29.03.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath_fixp.h"

// FIXME: for debugging purposes, remove all weak references and put strong ones in place
//#define weak strong

@class PSEdge, PSSourceEdge, PSSpoke, PSAntiSpoke, PSMotorcycle, PSWaveFront, PSCollapseEvent, PSSplitEvent, PSMergeEvent, PSReverseMergeEvent, PSReverseBranchEvent, PSEvent, PSBranchEvent, PriorityQueue, MPVector2D;

@interface PSVertex : NSObject
@property(nonatomic) v3i_t position;
@property(nonatomic) double time;
@property(nonatomic) PSSourceEdge* leftEdge;
@property(nonatomic) PSSourceEdge* rightEdge;
@property(nonatomic, readonly) NSArray* incomingMotorcycles;
@property(nonatomic, readonly) NSArray* outgoingMotorcycles;
@property(nonatomic, readonly) NSArray* outgoingSpokes;

- (PSSpoke*) nextSpokeClockwiseFrom: (v3i_t) startDir to: (v3i_t) endDir;

- (void) addMotorcycle: (PSMotorcycle*) cycle;
- (void) removeMotorcycle: (PSMotorcycle*) cycle;
- (void) addSpoke: (PSSpoke*) spoke;
- (void) removeSpoke: (PSSpoke*) spoke;
@end

@interface PSSplitVertex : PSVertex
@end

@interface PSSourceVertex : PSVertex
@end

@interface PSCrashVertex : PSVertex
@property(nonatomic, weak) PSReverseBranchEvent* reverseEvent;
@property(nonatomic, weak) PSBranchEvent* forwardEvent;
- (NSArray*) incomingMotorcyclesCCW;
- (NSArray*) multiBranchMotorcyclesCCW;
@end

@interface PSMergeVertex : PSVertex
// returns the incoming motorcycles that were merged, starting CCW from the outgoing motorcycle, in CCW order
- (NSArray*) mergedMotorcyclesCCW;
@property(nonatomic, weak) PSReverseMergeEvent* reverseEvent;
@property(nonatomic, weak) PSMergeEvent* forwardEvent;
@end


@interface PSEdge : NSObject
@property(nonatomic, weak) PSVertex* leftVertex, *rightVertex;
@property(nonatomic) v3i_t normal, edge;
@end

@interface PSSourceEdge : PSEdge
@end

@interface PSSpoke : NSObject
@property(nonatomic, weak) PSVertex *sourceVertex, *terminalVertex;
@property(nonatomic) double start, terminationTime;
@property(nonatomic, weak) PSWaveFront* leftWaveFront;
@property(nonatomic, weak) PSWaveFront* rightWaveFront;
@property(nonatomic, readonly) BOOL convex;
@property(nonatomic, strong, readonly) NSMutableArray* retiredWaveFronts;


@property(nonatomic, readonly) vector_t floatVelocity;


- (v3i_t) positionAtTime: (double) t;

@end

@interface PSSimpleSpoke : PSSpoke
//@property(nonatomic) v3i_t velocity;

@end

@interface PSFastSpoke : PSSpoke
@property(nonatomic) v3i_t direction;

@end

@interface PSMotorcycleSpoke : PSSimpleSpoke
@property(nonatomic, weak) PSMotorcycle		*motorcycle;
@property(nonatomic, weak) PSAntiSpoke		*antiSpoke;
@property(nonatomic, weak) PSEvent			*upcomingEvent;
@property(nonatomic, weak) PSCrashVertex	*passedCrashVertex;
@end

@interface PSAntiSpoke : PSSimpleSpoke
@property(nonatomic, weak) PSMotorcycle			*motorcycle;
@property(nonatomic, weak) PSMotorcycleSpoke	*motorcycleSpoke;
@property(nonatomic, weak) PSCrashVertex		*passedCrashVertex;

@end


@interface PSMotorcycle : NSObject

@property(nonatomic, weak) PSVertex* sourceVertex;
@property(nonatomic, weak) PSVertex* terminalVertex;
@property(nonatomic, weak) id terminator;
@property(nonatomic) vmlongerfix_t terminationTime;

@property(nonatomic, strong) PriorityQueue* crashQueue;

@property(nonatomic) vector_t floatVelocity;
@property(nonatomic, readonly) MPVector2D* mpVelocity;
@property(nonatomic, weak) PSSourceEdge *leftEdge, *rightEdge;
@property(nonatomic, weak) PSMotorcycle *leftNeighbour, *rightNeighbour;
@property(nonatomic, weak) PSMotorcycle *leftParent, *rightParent;

@property(nonatomic, strong) NSArray* crashVertices; // FIXME: results in cyclic references (weak NSPointerArray under ARC not available pre-10.8
@property(nonatomic) PSAntiSpoke* antiSpoke;
@property(nonatomic) PSMotorcycleSpoke* spoke;
@property(nonatomic) BOOL terminatedWithoutSplit;
@property(nonatomic) BOOL terminatedWithSplit;

- (PSVertex*) getVertexOnMotorcycleAtLocation: (v3i_t) x;

@end



@interface PSMotorcycleCrash : NSObject

@property(nonatomic) vmlongerfix_t	crashTimeSqr;
@property(nonatomic) vmlongerfix_t	time0Sqr;
@property(nonatomic) v3i_t			location;
@property(nonatomic, strong) PSMotorcycle* cycle0;

@end


@interface PSMotorcycleEdgeCrash : PSMotorcycleCrash

@property(nonatomic, strong) PSEdge* edge1;

@end


@interface PSMotorcycleVertexCrash : PSMotorcycleCrash

@property(nonatomic, strong) PSVertex* vertex;

@end


@interface PSMotorcycleMotorcycleCrash : PSMotorcycleCrash

@property(nonatomic) vmlongerfix_t	time1Sqr;
@property(nonatomic, strong) PSMotorcycle* cycle1;

@end



@interface PSWaveFront: NSObject

@property(nonatomic, strong) PSSpoke* leftSpoke;
@property(nonatomic, strong) PSSpoke* rightSpoke;
@property(nonatomic, weak) PSCollapseEvent* collapseEvent;
@property(nonatomic) v3i_t direction;

@property(nonatomic) double startTime, terminationTime;
@property(nonatomic, weak) PSWaveFront* successor;

@property(nonatomic, strong) NSArray* retiredLeftSpokes;
@property(nonatomic, strong) NSArray* retiredRightSpokes;

- (void) swapSpoke: (PSSpoke*) oldSpoke forSpoke: (PSSpoke*) newSpoke;

@end


@interface PSEvent : NSObject

@property(nonatomic) double creationTime;
@property(nonatomic) double time;
@property(nonatomic) v3i_t location;

@end

@interface PSCollapseEvent : PSEvent

@property(nonatomic,weak) PSWaveFront* collapsingWaveFront;

@end

@interface PSSplitEvent : PSEvent

@property(nonatomic,weak) PSAntiSpoke* antiSpoke;

@end

@interface PSBranchEvent : PSEvent

@property(nonatomic,weak) PSCrashVertex* branchVertex;
@property(nonatomic,weak) PSMotorcycleSpoke* rootSpoke;

@end

@interface PSEmitEvent : PSEvent

@end

@interface PSReverseBranchEvent : PSEvent
@property(nonatomic,weak) PSAntiSpoke* rootSpoke;
@property(nonatomic,weak) PSCrashVertex* branchVertex;
@end

