//
//  PolygonSkeletizerObjects.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 29.03.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"

@class PSEdge, PSSourceEdge, PSSpoke, PSAntiSpoke, PSMotorcycle, PSWaveFront, PSCollapseEvent, PSSplitEvent, PSMergeEvent, PSReverseMergeEvent, PSReverseBranchEvent, PSEvent, PSBranchEvent;

@interface PSVertex : NSObject
@property(nonatomic) vector_t position;
@property(nonatomic) double time;
@property(nonatomic) PSSourceEdge* leftEdge;
@property(nonatomic) PSSourceEdge* rightEdge;
@property(nonatomic, readonly) NSArray* incomingMotorcycles;
@property(nonatomic, readonly) NSArray* outgoingMotorcycles;
@property(nonatomic, readonly) NSArray* outgoingSpokes;

- (PSSpoke*) nextSpokeClockwiseFrom: (vector_t) startDir to: (vector_t) endDir;

- (void) addMotorcycle: (PSMotorcycle*) cycle;
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
@end

@interface PSMergeVertex : PSVertex
// returns the incoming motorcycles that were merged, starting CCW from the outgoing motorcycle, in CCW order
- (NSArray*) mergedMotorcyclesCCW;
@property(nonatomic, weak) PSReverseMergeEvent* reverseEvent;
@property(nonatomic, weak) PSMergeEvent* forwardEvent;
@end


@interface PSEdge : NSObject
@property(nonatomic, weak) PSVertex* leftVertex, *rightVertex;
@property(nonatomic) vector_t normal, edge;
@end

@interface PSSourceEdge : PSEdge
@end

@interface PSSpoke : NSObject
@property(nonatomic, weak) PSVertex *sourceVertex, *terminalVertex;
@property(nonatomic) double start;
@property(nonatomic, weak) PSWaveFront* leftWaveFront;
@property(nonatomic, weak) PSWaveFront* rightWaveFront;
@property(nonatomic, readonly) BOOL convex;

- (vector_t) positionAtTime: (double) t;

@end

@interface PSSimpleSpoke : PSSpoke
@property(nonatomic) vector_t velocity;

@end

@interface PSFastSpoke : PSSpoke
@property(nonatomic) vector_t direction;

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
@property(nonatomic, strong) NSArray* crashVertices; // FIXME: results in cyclic references (weak NSPointerArray under ARC not available pre-10.8
@property(nonatomic, weak) PSVertex* sourceVertex;
@property(nonatomic, weak) PSVertex* terminalVertex;
@property(nonatomic, weak) id terminator;
@property(nonatomic) double terminationTime;
@property(nonatomic) vector_t velocity;
@property(nonatomic, weak) PSSourceEdge *leftEdge, *rightEdge;
@property(nonatomic, weak) PSMotorcycle *leftNeighbour, *rightNeighbour;
@property(nonatomic, weak) PSMotorcycle *leftParent, *rightParent;

@property(nonatomic) vector_t	reverseWaveVelocity;
@property(nonatomic) double		reverseHitTime;

@property(nonatomic, weak) PSAntiSpoke* antiSpoke;
@property(nonatomic, weak) PSMotorcycleSpoke* spoke;


@end



@interface PSWaveFront: NSObject

@property(nonatomic, strong) PSSpoke* leftSpoke;
@property(nonatomic, strong) PSSpoke* rightSpoke;
@property(nonatomic, weak) PSCollapseEvent* collapseEvent;
@property(nonatomic) vector_t direction;

@end


@interface PSEvent : NSObject

@property(nonatomic) double creationTime;
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
@property(nonatomic,weak) PSMotorcycleSpoke* rootSpoke;

@end

@interface PSMergeEvent : PSEvent

@property(nonatomic,weak) PSMergeVertex* mergeVertex;

@end

@interface PSEmitEvent : PSEvent

@end

@interface PSReverseMergeEvent : PSEvent
@property(nonatomic,weak) PSAntiSpoke* rootSpoke;
@end

@interface PSReverseBranchEvent : PSEvent
@property(nonatomic,weak) PSAntiSpoke* rootSpoke;
@property(nonatomic,weak) PSCrashVertex* branchVertex;
@end

