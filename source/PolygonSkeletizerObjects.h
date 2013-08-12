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

@class PSEdge, PSSourceEdge, PSSpoke, PSAntiSpoke, PSMotorcycle, PSWaveFront, PSCollapseEvent, PSSplitEvent, PSMergeEvent, PSReverseMergeEvent, PSReverseBranchEvent, PSEvent, PSBranchEvent, PriorityQueue, MPVector2D, PSMotorcycleCrash, MPDecimal;

@interface PSVertex : NSObject
@property(nonatomic, strong) MPDecimal* time;
@property(nonatomic, strong) PSSourceEdge* leftEdge;
@property(nonatomic, strong) PSSourceEdge* rightEdge;
- (MPVector2D*) mpPosition;
@property(nonatomic, readonly) NSArray* incomingMotorcycles;
@property(nonatomic, readonly) NSArray* outgoingMotorcycles;
@property(nonatomic, readonly) NSArray* outgoingSpokes;

//- (PSSpoke*) nextSpokeClockwiseFrom: (v3i_t) startDir to: (v3i_t) endDir;

- (MPVector2D*) intersectEdges;

- (void) addMotorcycle: (PSMotorcycle*) cycle;
- (void) removeMotorcycle: (PSMotorcycle*) cycle;
- (void) addSpoke: (PSSpoke*) spoke;
- (void) removeSpoke: (PSSpoke*) spoke;
@end

@interface PSVirtualVertex : PSVertex
@property(nonatomic, strong, readonly) MPVector2D* mpPosition;

@end

@interface PSRealVertex : PSVertex

+ (instancetype) vertexAtPosition: (v3i_t) pos;

@property(nonatomic) v3i_t position;
@end

@interface PSSourceVertex : PSRealVertex
@end

@interface PSCrashVertex : PSRealVertex
@property(nonatomic, weak) PSReverseBranchEvent* reverseEvent;
@property(nonatomic, weak) PSBranchEvent* forwardEvent;
- (NSArray*) incomingMotorcyclesCCW;
- (NSArray*) multiBranchMotorcyclesCCW;
@end


@interface PSEdge : NSObject
@property(nonatomic, weak) PSSourceVertex* leftVertex, *rightVertex;
@property(nonatomic, strong) NSArray* waveFronts;
@property(nonatomic) v3i_t edge;
- (MPVector2D*) mpEdge;

@property(nonatomic, readonly) NSArray* splittingMotorcycles;

- (void) addSplittingMotorcycle:(PSMotorcycle *)object;

- (BOOL) mpVertexInPositiveHalfPlane: (MPVector2D*) mpv;

- (MPDecimal*) timeSqrToLocation: (MPVector2D*) X;

@end

@interface PSSourceEdge : PSEdge
@end

@interface PSSpoke : NSObject
@property(nonatomic, weak) PSVertex *sourceVertex;
@property(nonatomic, weak) PSRealVertex *terminalVertex;
@property(nonatomic, weak) PSSourceEdge *leftEdge, *rightEdge;
@property(nonatomic) v3i_t startLocation, endLocation;
@property(nonatomic, weak) PSWaveFront* leftWaveFront;
@property(nonatomic, weak) PSWaveFront* rightWaveFront;
@property(nonatomic, readonly) BOOL convex;
@property(nonatomic, strong, readonly) NSMutableArray* retiredWaveFronts;

- (MPVector2D*) mpVelocity;
- (MPVector2D*) mpNumerator;
- (MPVector2D*) mpDirection;
- (MPDecimal*) mpDenominator;

@property(nonatomic, strong) MPDecimal* terminationTimeSqr;
@property(nonatomic, strong) MPDecimal* startTimeSqr;

- (MPDecimal*) timeSqrToLocation: (MPVector2D*) X;

@property(nonatomic, readonly) vector_t floatVelocity;

- (BOOL) isVertexCCWFromSpoke: (MPVector2D*) mpv;
- (BOOL) isVertexCWFromSpoke: (MPVector2D*) mpv;
- (BOOL) isSpokeCCW: (PSSpoke *) spoke;

@property(nonatomic, weak) PSEvent* upcomingEvent;

- (v3i_t) positionAtTime: (MPDecimal*) t;

@end

@interface PSSimpleSpoke : PSSpoke
//@property(nonatomic) v3i_t velocity;

@end

@interface PSDegenerateSpoke : PSSpoke
//@property(nonatomic) v3i_t velocity;

@end


@interface PSMotorcycleSpoke : PSSimpleSpoke
@property(nonatomic, weak) PSMotorcycle		*motorcycle;
@property(nonatomic, weak) PSWaveFront		*opposingWaveFront;
@property(nonatomic, weak) PSEvent			*upcomingEvent;
@property(nonatomic, strong) NSArray* remainingBranchVertices;
@end

@interface PSMotorcycle : NSObject

@property(nonatomic, weak) PSSourceVertex* sourceVertex;
@property(nonatomic, weak) PSRealVertex* terminalVertex;
@property(nonatomic, weak) id terminator;
@property(nonatomic) MPDecimal* terminationTime;

@property(nonatomic, strong) PriorityQueue* crashQueue;

- (MPVector2D*) crashIntoEdge: (PSEdge*) edge;

@property(nonatomic, strong) MPVector2D* limitingEdgeCrashLocation;

@property(nonatomic) vector_t floatVelocity;

- (MPVector2D*) mpNumerator;
- (MPVector2D*) mpDirection;
- (MPVector2D*) mpVelocity;

@property(nonatomic, weak) PSSourceEdge *leftEdge, *rightEdge;
@property(nonatomic, weak) PSMotorcycle *leftNeighbour, *rightNeighbour;
@property(nonatomic, weak) PSMotorcycle *leftParent, *rightParent;

@property(nonatomic, strong) PSMotorcycleCrash *terminatingCrash;

@property(nonatomic, strong) NSArray* crashVertices; // FIXME: results in cyclic references (weak NSPointerArray under ARC not available pre-10.8
@property(nonatomic) PSMotorcycleSpoke* spoke;
@property(nonatomic) BOOL terminatedWithoutSplit;
@property(nonatomic) BOOL terminatedWithSplit;

- (PSRealVertex*) getVertexOnMotorcycleAtLocation: (v3i_t) x;
- (double) angleToLocation: (MPVector2D *) loc;

@end



@interface PSMotorcycleCrash : NSObject

@property(nonatomic) MPDecimal*	crashTimeSqr;
@property(nonatomic) MPDecimal*	time0Sqr;
@property(nonatomic) v3i_t			location;
@property(nonatomic, weak) PSMotorcycle* cycle0;

@end


@interface PSMotorcycleEdgeCrash : PSMotorcycleCrash

@property(nonatomic, weak) PSEdge* edge1;

@end


@interface PSMotorcycleVertexCrash : PSMotorcycleCrash

@property(nonatomic, weak) PSSourceVertex* vertex;

@end


@interface PSMotorcycleMotorcycleCrash : PSMotorcycleCrash

@property(nonatomic) MPDecimal*	time1Sqr;
@property(nonatomic, weak) PSMotorcycle* cycle1;

@end



@interface PSWaveFront: NSObject

@property(nonatomic, strong) PSSpoke* leftSpoke;
@property(nonatomic, strong) PSSpoke* rightSpoke;
@property(nonatomic, weak) PSSourceEdge* edge;
@property(nonatomic, weak) PSCollapseEvent* collapseEvent;

@property(nonatomic) v3i_t startLocation, endLocation;
@property(nonatomic, weak) PSWaveFront* successor;
@property(nonatomic, strong) NSArray* opposingSpokes;

@property(nonatomic, strong) NSArray* retiredLeftSpokes;
@property(nonatomic, strong) NSArray* retiredRightSpokes;

@property(nonatomic, strong) MPDecimal* terminationTimeSqr;

- (void) swapSpoke: (PSSpoke*) oldSpoke forSpoke: (PSSpoke*) newSpoke;
- (BOOL) isWeaklyConvexTo: (PSWaveFront*) wf;

- (MPVector2D*) computeCollapseLocation;

@end


@interface PSEvent : NSObject

- (id) initWithLocation: (MPVector2D*) loc time: (MPDecimal*) t creationTime: (MPDecimal*) ct;

@property(nonatomic, strong) MPDecimal* creationTimeSqr;
@property(nonatomic, strong) MPDecimal* timeSqr;
@property(nonatomic) MPVector2D* mpLocation;
@property(nonatomic, readonly) vector_t floatLocation;

@property(nonatomic, readonly) NSArray* spokes;

- (NSComparisonResult) compare: (PSEvent*) event;

- (BOOL) isIndependent;

- (v3i_t) location;

@end

@interface PSCollapseEvent : PSEvent

- (id) initWithLocation: (MPVector2D*) loc time: (MPDecimal*) t creationTime: (MPDecimal*) ct waveFront: (PSWaveFront*) waveFront;

@property(nonatomic,weak) PSWaveFront* collapsingWaveFront;

@end


@interface PSSplitEvent : PSEvent

- (id) initWithLocation: (MPVector2D*) loc time: (MPDecimal*) t creationTime: (MPDecimal*) ct motorcycleSpoke: (PSMotorcycleSpoke*) spoke;

@property(nonatomic,weak) PSMotorcycleSpoke* motorcycleSpoke;

@end

@interface PSSwapEvent : PSEvent

- (id) initWithLocation: (MPVector2D*) loc time: (MPDecimal*) t creationTime: (MPDecimal*) ct motorcycleSpoke: (PSMotorcycleSpoke*) spoke pivotSpoke: (PSSpoke*) pivot;

@property(nonatomic,weak) PSMotorcycleSpoke*	motorcycleSpoke;
@property(nonatomic,weak) PSSpoke*				pivotSpoke;

@end



@interface PSEmitEvent : PSEvent

@end

