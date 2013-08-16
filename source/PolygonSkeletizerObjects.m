//
//  PolygonSkeletizerObjects.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 29.03.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "PolygonSkeletizerObjects.h"
#import "PolygonSkeletizer.h"
#import "FoundationExtensions.h"
#import "PriorityQueue.h"
#import "MPVector2D.h"
#import "MPInteger.h"

#import "VectorMath_fixp.h"

@implementation PSEvent
{
	NSUInteger hashCache;
}

@synthesize timeSqr, creationTimeSqr, mpLocation;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	[self doesNotRecognizeSelector: _cmd];
	
	return self;
}

- (id) initWithLocation:(MPVector2D*)loc time:(MPDecimal *)t creationTime:(MPDecimal *)ct
{
	if (!(self = [super init]))
		return nil;
	
	
	
	assert(!t || ([t compare: [MPDecimal largerThan32Sqr]] < 0));

	mpLocation = loc;
	timeSqr = t;
	creationTimeSqr = ct;
	
	return self;
}

- (void) setTimeSqr:(MPDecimal *)t
{
	assert([t compare: [MPDecimal largerThan32Sqr]] < 0);
	timeSqr = t;
}


- (BOOL) isEqual: (PSEvent*) object
{
	if ([self class] != [object class])
		return NO;
	if (self.creationTimeSqr != object.creationTimeSqr)
		return NO;
	if (self.timeSqr != object.timeSqr)
		return NO;
	if (!v3iEqual(self.location, object.location))
		return NO;
	
	
	return YES;
}

- (vector_t) floatLocation
{
	return (self.mpLocation.toFloatVector);
}

- (v3i_t) location
{
	return [self.mpLocation toVectorWithShift: 16];
}

- (NSString*) hashString
{
	NSString* str = [NSString stringWithFormat: @"%f %f %@ %d %d", self.creationTimeSqr.sqrt.toDouble, timeSqr.sqrt.toDouble, [self class], self.location.x, self.location.y];
	return str;
}

- (NSUInteger) hash
{
	if (!hashCache)
	{
		NSString* str = [self hashString];
		hashCache = [str hash];
	}
	return hashCache;
}

- (NSString *)description
{
	vector_t loc = self.floatLocation;
	return [NSString stringWithFormat: @"%p @%f (%@) (%f, %f)", self, timeSqr.sqrt.toDouble, [self class], loc.farr[0], loc.farr[1]];
}

- (NSArray*) spokes
{
	[self doesNotRecognizeSelector: _cmd];
	return nil;
}


- (NSComparisonResult) compare:(PSEvent *)event
{
	MPDecimal* t0 = self.timeSqr;
	MPDecimal* t1 = event.timeSqr;
	assert(t0);
	assert(t1);
	NSComparisonResult cmp = [t0 compare: t1];
	return cmp;
}

- (BOOL) isIndependent
{
	[self doesNotRecognizeSelector: _cmd];
	return NO;
}
@end


@implementation PSCollapseEvent
{
	NSArray* spokes;
}

@synthesize  spokes, collapsingWaveFront;

- (id) initWithLocation: (MPVector2D*)loc time:(MPDecimal *)t creationTime:(MPDecimal *)ct waveFront:(PSWaveFront *)waveFront
{
	if (!(self = [super initWithLocation: loc time: t creationTime: ct]))
		return nil;
	
	collapsingWaveFront = waveFront;
	
	spokes = @[waveFront.leftSpoke, waveFront.rightSpoke];
	
	return self;
}

- (BOOL) isEqual: (PSCollapseEvent*) object
{
	if (![super isEqual: object])
		return NO;
	if (self.collapsingWaveFront != object.collapsingWaveFront)
		return NO;
	
	
	return YES;
}

- (NSString*) hashString
{
	NSString* str = [NSString stringWithFormat: @"%@ %d %d", [super hashString], self.collapsingWaveFront.edge.edge.x, self.collapsingWaveFront.edge.edge.y];
	return str;
}

- (NSComparisonResult) compareToSplit: (PSSplitEvent *)event
{
	NSComparisonResult cmp = [super compare: event];

//	if ((cmp == 0) && ([self.spokes containsObject: event.motorcycleSpoke]))
//		return NSOrderedAscending; // split comes after collapse

	return cmp;
}

- (NSComparisonResult) compareToSwap: (PSSwapEvent *)event
{
	NSComparisonResult cmp = [super compare: event];
	
	if (cmp == 0)
		return NSOrderedAscending; // swap comes after collapse
	
	return cmp;
}

- (NSComparisonResult) compareToEmit: (PSEmitEvent *)event
{
	NSComparisonResult cmp = [super compare: event];
	
	if (cmp == 0)
		return NSOrderedAscending; // emit comes after collapse
	
	return cmp;
}


- (NSArray*) spokes
{
	return @[collapsingWaveFront.leftSpoke, collapsingWaveFront.rightSpoke];
}

- (NSComparisonResult) compare:(PSCollapseEvent *)event
{
	/*
	if ([event isKindOfClass: [PSSplitEvent class]])
		return [self compareToSplit: (id)event];
	else if ([event isKindOfClass: [PSSwapEvent class]])
		return [self compareToSwap: (id)event];
	else if ([event isKindOfClass: [PSEmitEvent class]])
		return [self compareToEmit: (id)event];
	*/
	
	
	NSComparisonResult cmp = [super compare: event];
	if (![event isKindOfClass: [PSCollapseEvent class]] || (self.collapsingWaveFront == event.collapsingWaveFront))
		return cmp;
	
	/*
	
	PSSpoke* spoke = nil;
	if (self.collapsingWaveFront.leftSpoke == event.collapsingWaveFront.rightSpoke)
		spoke = self.collapsingWaveFront.leftSpoke;
	else if (self.collapsingWaveFront.rightSpoke == event.collapsingWaveFront.leftSpoke)
		spoke = self.collapsingWaveFront.rightSpoke;

	// FIXME: this case needs a better discriminating condition
	// only if the spoke has a high velocity factor?
	
	MPVector2D* a = spoke.leftWaveFront.edge.mpEdge;
	MPVector2D* b = spoke.rightWaveFront.edge.mpEdge.negate;
	
		
	double angle = [a angleTo: b];
	
	if (spoke && !v3iEqual(self.location, event.location) && (fabs(angle) < 1e-3))
	{
		MPVector2D* rs = [self.mpLocation sub: spoke.sourceVertex.mpPosition];
		MPVector2D* re = [event.mpLocation sub: spoke.sourceVertex.mpPosition];
		
		
		
		MPDecimal* dsSqr = [rs dot: rs];
		MPDecimal* deSqr = [re dot: re];
		
		NSComparisonResult cmpd = [dsSqr compare: deSqr];
		
		return cmpd;
	}
*/
	
	return cmp;
}

- (BOOL) isIndependent
{
//	if (self.collapsingWaveFront.opposingSpokes.count)
//		return NO;
	
	// checking for degenerates makes it worse
	//BOOL hasDegenerateSpoke = [self.collapsingWaveFront.leftSpoke isKindOfClass: [PSDegenerateSpoke class]] || [self.collapsingWaveFront.rightSpoke isKindOfClass: [PSDegenerateSpoke class]];
	//if (!hasDegenerateSpoke)

	{
		for (PSMotorcycleSpoke* mspoke in self.collapsingWaveFront.opposingSpokes)
		{
			// FIXME: how to determine when the collapse is independent?
			// due to indirect motorcycle crashes, collapse might be valid even if opposing spokes exist
			
			BOOL neighboursOk = (mspoke.leftWaveFront != mspoke.opposingWaveFront) && (mspoke.rightWaveFront!= mspoke.opposingWaveFront);

			if (!neighboursOk)
				continue;
			
			
			// proposed test: if motorcycle terminates "inside" triangle formed by the two opposing spokes, don't collapse
			// problem: when spoke is nearly parallel to wavefront, "inside" test is inaccurate
			
			// proposed test #2: test if split location is closer than collapse
						
			MPVector2D* X = mspoke.splitLocation;
			
			if (X)
			{
				MPDecimal* tLX = [self.collapsingWaveFront.leftSpoke.sourceVertex timeSqrToLocation: X];
				MPDecimal* tLE = [self.collapsingWaveFront.leftSpoke.sourceVertex timeSqrToLocation: self.mpLocation];
				MPDecimal* tRX = [self.collapsingWaveFront.rightSpoke.sourceVertex timeSqrToLocation: X];
				MPDecimal* tRE = [self.collapsingWaveFront.rightSpoke.sourceVertex timeSqrToLocation: self.mpLocation];
				
				BOOL closerLeft = [tLX compare: tLE] == NSOrderedAscending;
				BOOL closerRight = [tRX compare: tRE] == NSOrderedAscending;
				
				BOOL inside = ![self.collapsingWaveFront.leftSpoke isVertexCCWFromSpoke: X] && ![self.collapsingWaveFront.rightSpoke isVertexCWFromSpoke: X];
				
				if (inside || closerRight || closerLeft)
					return NO;
			}
		}
	}
	
	PSEvent* leftCollapse = self.collapsingWaveFront.leftSpoke.leftWaveFront.collapseEvent;
	PSEvent* rightCollapse = self.collapsingWaveFront.rightSpoke.rightWaveFront.collapseEvent;
	
	
	MPVector2D* X0 = self.mpLocation;
	
	if (leftCollapse)
	{
		MPVector2D* XL = leftCollapse.mpLocation;
		
		MPDecimal* D0 = [self.collapsingWaveFront.leftSpoke.sourceVertex timeSqrToLocation: X0];
		MPDecimal* DL = [self.collapsingWaveFront.leftSpoke.sourceVertex timeSqrToLocation: XL];
		
		if ([D0 compare: DL] == NSOrderedDescending)
			return NO;
	}
	
	if (rightCollapse)
	{
		MPVector2D* XR = rightCollapse.mpLocation;
		
		MPDecimal* D0 = [self.collapsingWaveFront.rightSpoke.sourceVertex timeSqrToLocation: X0];
		MPDecimal* DR = [self.collapsingWaveFront.rightSpoke.sourceVertex timeSqrToLocation: XR];
		
		if ([D0 compare: DR] == NSOrderedDescending)
			return NO;
	}

	return YES;
}

@end



@implementation PSSplitEvent

@synthesize motorcycleSpoke;

- (id) initWithLocation: (MPVector2D*) loc time: (MPDecimal*) t creationTime: (MPDecimal*) ct motorcycleSpoke: (PSMotorcycleSpoke*) spoke;
{
	if (!(self = [super initWithLocation: loc time: t creationTime: ct]))
		return nil;
	
	motorcycleSpoke = spoke;
	
	return self;

}

- (NSArray*) spokes
{
	if (motorcycleSpoke.opposingWaveFront)
		return @[motorcycleSpoke, motorcycleSpoke.opposingWaveFront.leftSpoke, motorcycleSpoke.opposingWaveFront.rightSpoke];
	else
		return @[motorcycleSpoke];
}

- (NSComparisonResult) compareToCollapse:(PSCollapseEvent *)event
{
	NSComparisonResult cmp = [super compare: event];
	if ((cmp == 0) && ([event.spokes containsObject: motorcycleSpoke]))
		return NSOrderedDescending; // split comes after collapse

	return cmp;
}
- (NSComparisonResult) compareToSwap: (PSSwapEvent *)event
{
	NSComparisonResult cmp = [super compare: event];
	if (cmp == 0)
		return NSOrderedAscending; // swap comes after split
	
	return cmp;
}
- (NSComparisonResult) compareToEmit: (PSEmitEvent *)event
{
	NSComparisonResult cmp = [super compare: event];
	if (cmp == 0)
		return NSOrderedAscending; // emit comes after split
	
	return cmp;
}

- (NSComparisonResult) compare: (PSSplitEvent *)event
{
	/*
	if ([event isKindOfClass: [PSCollapseEvent class]])
		return [self compareToCollapse: (id)event];
	else if ([event isKindOfClass: [PSSwapEvent class]])
		return [self compareToSwap: (id)event];
	else if ([event isKindOfClass: [PSEmitEvent class]])
		return [self compareToEmit: (id)event];
	*/
	
	NSComparisonResult cmp = [super compare: event];
	return cmp;
}

- (BOOL) isIndependent
{
	PSEvent* leftCollapse = self.motorcycleSpoke.leftWaveFront.collapseEvent;
	PSEvent* rightCollapse = self.motorcycleSpoke.rightWaveFront.collapseEvent;
	
	
	MPVector2D* X0 = self.mpLocation;
	MPVector2D* source = self.motorcycleSpoke.sourceVertex.mpPosition;
	MPVector2D* R0 = [X0 sub: source];
	
	if (leftCollapse)
	{
		
		MPVector2D* XL = leftCollapse.mpLocation;
		
		MPVector2D* RL = [XL sub: source];
		
		MPDecimal* D0 = [R0 dot: R0];
		MPDecimal* DL = [RL dot: RL];
		
		if ([D0 compare: DL] == NSOrderedDescending)
			return NO;
	}
	
	if (rightCollapse)
	{
		MPVector2D* XR = rightCollapse.mpLocation;
		
		MPVector2D* RR = [XR sub: source];
		
		MPDecimal* D0 = [R0 dot: R0];
		MPDecimal* DR = [RR dot: RR];
		
		if ([D0 compare: DR] == NSOrderedDescending)
			return NO;
	}

	return YES;
}

@end


@implementation PSSwapEvent

@synthesize motorcycleSpoke, pivotSpoke;

- (id) initWithLocation: (MPVector2D*) loc time:(MPDecimal *)t creationTime:(MPDecimal *)ct motorcycleSpoke:(PSMotorcycleSpoke *)spoke pivotSpoke:(PSSpoke *)pivot
{
	if (!(self = [super initWithLocation: loc time: t creationTime: ct]))
		return nil;
	
	motorcycleSpoke = spoke;
	pivotSpoke = pivot;
	
	return self;
}

- (NSArray*) spokes
{
	return @[motorcycleSpoke, pivotSpoke];
}

- (NSComparisonResult) compareToCollapse: (PSCollapseEvent *)event
{
	NSComparisonResult cmp = [super compare: event];
	if (cmp == 0)
		return NSOrderedDescending; // swap comes after collapse
	
	return cmp;
}
- (NSComparisonResult) compareToSplit: (PSSplitEvent *)event
{
	NSComparisonResult cmp = [super compare: event];
	if (cmp == 0)
		return NSOrderedDescending; // swap comes after split
	
	return cmp;
}
- (NSComparisonResult) compareToEmit: (PSEmitEvent *)event
{
	NSComparisonResult cmp = [super compare: event];
	if (cmp == 0)
		return NSOrderedAscending; // emit comes after swap
	
	return cmp;
}

- (NSComparisonResult) compare: (PSSplitEvent *)event
{
	/*
	if ([event isKindOfClass: [PSCollapseEvent class]])
		return [self compareToCollapse: (id)event];
	else if ([event isKindOfClass: [PSSplitEvent class]])
		return [self compareToSplit: (id)event];
	else if ([event isKindOfClass: [PSEmitEvent class]])
		return [self compareToEmit: (id)event];
	*/
	
	NSComparisonResult cmp = [super compare: event];
	return cmp;
}


- (BOOL) isIndependent
{
	/*
	PSEvent* leftCollapse = self.motorcycleSpoke.leftWaveFront.collapseEvent;
	PSEvent* rightCollapse = self.motorcycleSpoke.rightWaveFront.collapseEvent;
	
	
	MPVector2D* X0 = self.mpLocation;
	MPVector2D* source = self.motorcycleSpoke.sourceVertex.mpPosition;
	MPVector2D* R0 = [X0 sub: source];
	
	if (leftCollapse)
	{
		
		MPVector2D* XL = leftCollapse.mpLocation;
		
		MPVector2D* RL = [XL sub: source];
		
		MPDecimal* D0 = [R0 dot: R0];
		MPDecimal* DL = [RL dot: RL];
		
		if ([D0 compare: DL] == NSOrderedDescending)
			return NO;
	}
	
	if (rightCollapse)
	{
		MPVector2D* XR = rightCollapse.mpLocation;
		
		MPVector2D* RR = [XR sub: source];
		
		MPDecimal* D0 = [R0 dot: R0];
		MPDecimal* DR = [RR dot: RR];
		
		if ([D0 compare: DR] == NSOrderedDescending)
			return NO;
	}
	*/
	return YES;
}

@end


@implementation PSEmitEvent

// emit event is always last
- (NSComparisonResult) compare: (PSEmitEvent *)event
{
	if ([event isKindOfClass: [PSEmitEvent class]])
		return [super compare: event];
	
	
	NSComparisonResult cmp = [super compare: event];
	
	if (cmp == 0)
		return NSOrderedDescending;
		
	return cmp;
}
- (NSArray*) spokes
{
	return @[];
}

- (BOOL) isIndependent
{
	return YES;
}

@end

/*
static double _maxBoundsDimension(NSArray* vertices)
{
	v3i_t minv = v3iCreate(INT32_MAX, INT32_MAX, INT32_MAX, 0);
	v3i_t maxv = v3iCreate(INT32_MIN, INT32_MIN, INT32_MIN, 0);
	
	for (PSRealVertex* vertex in vertices)
	{
		minv.shift = vertex.position.shift;
		maxv.shift = vertex.position.shift;
		minv = v3iMin(minv, vertex.position);
		maxv = v3iMax(maxv, vertex.position);
	}
	
	v3i_t r = v3iSub(maxv, minv);
	return vLength(v3iToFloat(r));
}
*/

@implementation PSEdge

@synthesize splittingMotorcycles;

- (void) addSplittingMotorcycle:(PSMotorcycle *)object
{
	if (!splittingMotorcycles)
		splittingMotorcycles = @[object];
	else
		splittingMotorcycles = [splittingMotorcycles arrayByAddingObject: object];
}

- (BOOL) mpVertexInPositiveHalfPlane: (MPVector2D*) mpv;
{
	MPVector2D* E = [MPVector2D vectorWith3i: self.edge];
	MPVector2D* A = [MPVector2D vectorWith3i: self.leftVertex.position];
	
	MPDecimal* cross = [E cross: [mpv sub: A]];
	
	return cross.isPositive;
}

static MPVector2D* _mpLinePointDistanceNum(MPVector2D* A, MPVector2D* B, MPVector2D* P)
{
	MPVector2D* AP = [P sub: A];
	MPVector2D* AB = [B sub: A];
	
	MPDecimal* ABAB = [AB dot: AB];
	MPDecimal* ABAP = [AB dot: AP];
	
	MPVector2D* DN = [[AP scale: ABAB] sub: [AB scale: ABAP]];
	
	return DN;
}


- (MPDecimal*) timeSqrToLocation: (MPVector2D*) X;
{
	assert(X);
	MPVector2D* A = [MPVector2D vectorWith3i: self.leftVertex.position];
	MPVector2D* B = [MPVector2D vectorWith3i: self.rightVertex.position];
	MPVector2D* AB = [B sub: A];
	
	{
		MPVector2D* AX = [X sub: A];
	
		MPDecimal* cross = [AB cross: AX];
	
		if (!(cross.isPositive || cross.isZero)) // assert that X is in the right half plane
			return [MPDecimal largerThan32Sqr];
	}
	
	MPDecimal* ABAB = [AB dot: AB];
	
	MPVector2D* DAB = _mpLinePointDistanceNum(A, B, X);
	
	
	MPDecimal* tSqr = [[DAB dot: DAB] div: [ABAB mul: ABAB]];
	
	assert([tSqr compare: [MPDecimal largerThan32Sqr]] < 0);

	return tSqr;
}

- (MPVector2D*) mpEdge
{
	return [MPVector2D vectorWith3i: self.edge];
}

@end

@implementation PSMotorcycle
{
	MPVector2D* cachedNumerator;
}

@synthesize crashVertices, terminationTime, crashQueue, terminalVertex;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	crashVertices = @[];
	terminationTime = nil;
	
	crashQueue = [[PriorityQueue alloc] initWithCompareBlock: ^NSComparisonResult(PSMotorcycleCrash* obj0, PSMotorcycleCrash* obj1) {
		MPDecimal* t0 = obj0.crashTimeSqr;
		MPDecimal* t1 = obj1.crashTimeSqr;
		
		return [t0 compare: t1];
	}];

	return self;
}

- (double) angleToLocation: (MPVector2D *) loc
{
	MPVector2D* vel = self.mpVelocity;
	MPVector2D* delta = [loc sub: self.sourceVertex.mpPosition];
	
	MPDecimal* cross = [[vel cross: delta] div: [vel.length mul: delta.length]];
	
	double da = cross.toDouble;

	return da;
}
- (void) setTerminalVertex:(PSRealVertex *)vertex
{	
	double da = [self angleToLocation: vertex.mpPosition];
	
	assert(fabs(da) < 100.0*FLT_EPSILON);
	
	
	terminalVertex = vertex;
}

- (MPVector2D*) mpNumerator
{
	
	if (cachedNumerator)
		return cachedNumerator;
	
	MPVector2D* E_AB = [MPVector2D vectorWith3i: self.leftEdge.edge];
	MPVector2D* E_BC = [MPVector2D vectorWith3i: self.rightEdge.edge];
		
	MPDecimal* l_E_AB = [E_AB length];
	MPDecimal* l_E_BC = [E_BC length];
	
	MPVector2D* RU = [[E_BC scale: l_E_AB] sub: [E_AB scale: l_E_BC]];
		
	cachedNumerator = RU;
	
	return RU;
}

- (MPVector2D*) mpDirection
{
	MPVector2D* E_AB = [MPVector2D vectorWith3i: self.leftEdge.edge];
	MPVector2D* E_BC = [MPVector2D vectorWith3i: self.rightEdge.edge];
	
	MPDecimal* E_ABxBC = [E_AB cross: E_BC];
	
	
	MPVector2D* RU = self.mpNumerator;
	
	if (E_ABxBC.isNegative)
		RU = RU.negate;
	

	assert(!isinf(RU.x.toDouble));
	assert(!isinf(RU.y.toDouble));
	
	
	
	return RU;
}
- (MPVector2D*) mpVelocity
{
	MPVector2D* E_AB = [MPVector2D vectorWith3i: self.leftEdge.edge];
	MPVector2D* E_BC = [MPVector2D vectorWith3i: self.rightEdge.edge];
	
	MPDecimal* E_ABxBC = [E_AB cross: E_BC];
		
	MPVector2D* RU = self.mpNumerator;
	
	MPVector2D* R = [RU scaleNum: [MPDecimal one] den: E_ABxBC];
	
	assert(!isinf(R.x.toDouble));
	assert(!isinf(R.y.toDouble));
	
	
	
	return R;
}

- (vector_t) floatVelocity
{
	MPVector2D* mpv = self.mpVelocity;
	vector_t v = vCreateDir(mpv.x.toDouble, mpv.y.toDouble, 0.0);
	
	return v;
}

- (NSString *)description
{
	vector_t v = (self.floatVelocity);
	return [NSString stringWithFormat: @"%p (%.3f, %.3f)", self, v.farr[0], v.farr[1]];
}

- (PSRealVertex*) getVertexOnMotorcycleAtLocation: (v3i_t) x
{
	if (self.sourceVertex && v3iEqual(self.sourceVertex.position, x))
		return self.sourceVertex;
	if (self.terminalVertex && v3iEqual(self.terminalVertex.position, x))
		return self.terminalVertex;
	for (PSRealVertex* vertex in self.crashVertices)
		if (v3iEqual(vertex.position, x))
			return vertex;
	
	return nil;
}

static MPVector2D* _crashLocationME(v3i_t _B, v3i_t _E_AB, v3i_t _E_BC, v3i_t _U, v3i_t _V, MPVector2D* E_ABC)
{
	MPVector2D* B = [MPVector2D vectorWith3i: _B];
	MPVector2D* U = [MPVector2D vectorWith3i: _U];
	MPVector2D* V = [MPVector2D vectorWith3i: _V];
	
	
	MPVector2D* S = [V sub: U];
	
	/*
	MPVector2D* E_AB = [MPVector2D vectorWith3i: _E_AB];
	MPVector2D* E_BC = [MPVector2D vectorWith3i: _E_BC];
	MPDecimal* E_ABxBC = [E_AB cross: E_BC];
	 MPDecimal* l_E_AB = E_AB.length;
	 MPDecimal* l_E_BC = E_BC.length;
	 
	 MPVector2D* E_ABC = [[E_BC scale: l_E_AB] sub: [E_AB scale: l_E_BC]];
	 */
	MPDecimal* denum = [E_ABC cross: S];
	
	
	if (denum.isZero)
	{
		return nil;
	}
	
	MPVector2D* RQS = [E_ABC scale: [V cross: S]];
	MPVector2D* SPR = [S scale: [B cross: E_ABC]];
	
	MPVector2D* X = [[RQS sub: SPR] scaleNum: [MPDecimal one] den: denum];
	
	
	
	if (X.minIntegerBits < 16)
	{
		return X;
	}
	
	return nil;
	
}

static long _locationOnEdge_boxTest(v3i_t A, v3i_t B, v3i_t x)
{
	r3i_t r = riCreateFromVectors(A,B);
	
	return riContainsVector2D(r, x);
}


- (MPVector2D*) crashIntoEdge: (PSEdge*) edge
{
	if ((edge.leftVertex == self.sourceVertex) || (edge.rightVertex == self.sourceVertex))
		return nil;
	
	
	MPVector2D* X = _crashLocationME(self.sourceVertex.position, self.leftEdge.edge, self.rightEdge.edge, edge.leftVertex.position, edge.rightVertex.position, self.mpNumerator);

	if (!X)
		return nil;
	
	if (!_locationOnEdge_boxTest(edge.leftVertex.position, edge.rightVertex.position, [X toVectorWithShift: 16]))
		return nil;
	
	if (!([self.leftEdge mpVertexInPositiveHalfPlane: X] && [self.rightEdge mpVertexInPositiveHalfPlane: X]))
		return nil;

	{
		// match test, intersection points must equal for reversed edge
		MPVector2D* XR = _crashLocationME(self.sourceVertex.position, self.leftEdge.edge, self.rightEdge.edge, edge.rightVertex.position, edge.leftVertex.position, self.mpNumerator);
		
		v3i_t xi = [X toVectorWithShift: 16];
		v3i_t xr = [XR toVectorWithShift: 16];
		assert(v3iEqual(xi, xr));
	}

	
	return X;
}

@end


@implementation PSSourceEdge


@end

@implementation PSVertex
{
}

@synthesize leftEdge, rightEdge, incomingMotorcycles, outgoingMotorcycles, outgoingSpokes;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	incomingMotorcycles = [NSArray array];
	outgoingMotorcycles = [NSArray array];
	outgoingSpokes = [NSArray array];
	
	return self;
}

- (MPVector2D*) mpPosition
{
	[self doesNotRecognizeSelector: _cmd];
	return nil;
}


- (MPVector2D*) intersectEdges
{
	MPVector2D* P = leftEdge.leftVertex.mpPosition;
	MPVector2D* Q = rightEdge.leftVertex.mpPosition;
	MPVector2D* R = [leftEdge.rightVertex.mpPosition sub: P];
	MPVector2D* S = [rightEdge.rightVertex.mpPosition sub: Q];
	
	MPVector2D* num = [[R scale: [Q cross: S]] sub: [S scale: [P cross: R]]];
	MPDecimal*	den = [R cross: S];
	
	if (den.isZero)
		return nil;
	
	
	return [num scaleNum: [[MPDecimal alloc] initWithInt64: 1 shift: 0] den: den];
	
}

- (void) addMotorcycle:(PSMotorcycle *)cycle
{
	assert(!((cycle.sourceVertex == self) && (cycle.terminalVertex == self)));
	if (cycle.sourceVertex == self)
	{
		outgoingMotorcycles = [outgoingMotorcycles arrayByAddingObject: cycle];
	}
	else if (cycle.terminalVertex == self)
	{
		incomingMotorcycles = [incomingMotorcycles arrayByAddingObject: cycle];
	}
	else
	{
		outgoingMotorcycles = [outgoingMotorcycles arrayByAddingObject: cycle];
		incomingMotorcycles = [incomingMotorcycles arrayByAddingObject: cycle];
	}
}

- (void) addSpoke:(PSSpoke *)spoke
{
	outgoingSpokes = [outgoingSpokes arrayByAddingObject: spoke];
}

- (void) removeSpoke:(PSSpoke *)spoke
{
	outgoingSpokes = [outgoingSpokes arrayByRemovingObject: spoke];
}

- (void) removeMotorcycle: (PSMotorcycle *)cycle
{
	outgoingMotorcycles = [outgoingMotorcycles arrayByRemovingObject: cycle];
	incomingMotorcycles = [incomingMotorcycles arrayByRemovingObject: cycle];
}

- (MPDecimal*) timeSqrToLocation: (MPVector2D*) X
{
	MPVector2D* D = [X sub: self.mpPosition];
	
	return [D dot: D];
}


#if 0
static double _angle2d(v3i_t from, v3i_t to)
{
	vmlongfix_t x = v3iDot(from, to);
	vmlongfix_t y = v3iCross2D(from, to);
	double angle = atan2(y.x, x.x);
	return angle;
}

static double _angle2d_ccw(v3i_t from, v3i_t to)
{
	double angle = _angle2d(from, to);
	if (angle < 0.0)
		angle = 2.0*M_PI - angle;
	return angle;
}

static double _angle2d_cw(v3i_t from, v3i_t to)
{
	double angle = -_angle2d(from, to);
	if (angle < 0.0)
		angle = 2.0*M_PI - angle;
	return angle;
}

- (PSSpoke*) nextSpokeClockwiseFrom: (v3i_t) startDir to: (v3i_t) endDir
{
	double alphaMin = 2.0*M_PI;
	id outSpoke = nil;
	
	assert(0);
	/*
	for (PSSimpleSpoke* spoke in outgoingSpokes)
	{
		v3i_t dir = spoke.floatVelocity;
		
		double angleStart = _angle2d_cw(startDir, dir);
		double angleEnd = _angle2d_cw(dir, endDir);
		
		if (angleEnd < 0.0)
			continue;
		
		if (angleStart <= 0.0)
			continue;
		
		if (angleStart < alphaMin)
		{
			outSpoke = spoke;
			alphaMin = angleStart;
		}
		
	}
	*/
	
	return outSpoke;
}
#endif


- (NSString *)description
{
	return [NSString stringWithFormat: @"%p (%@) @%f (%f, %f)", self, [self class], self.time.toDouble, self.mpPosition.x.toDouble, self.mpPosition.y.toDouble];
}


@end

@implementation  PSRealVertex

@synthesize position;

- (MPVector2D*) mpPosition
{
	return [MPVector2D vectorWith3i: position];
}

+ (instancetype) vertexAtPosition: (v3i_t) pos
{
	PSRealVertex* vertex = [[PSRealVertex alloc] init];
	vertex.position = pos;
	return vertex;
}

@end


@implementation PSVirtualVertex

- (void) setMpPosition:(MPVector2D *)mpPosition
{
	[self doesNotRecognizeSelector: _cmd];
}

- (MPVector2D*) mpPosition
{
	MPVector2D* X = [self intersectEdges];
	if (!X)
		X = [[self.leftEdge.rightVertex.mpPosition add: self.rightEdge.leftVertex.mpPosition] scale: [[MPDecimal alloc] initWithInt64: 1 shift: 1]];
	assert(X);
	return X;
}

@end


@implementation PSSourceVertex

@end

@implementation PSCrashVertex

- (NSArray*) multiBranchMotorcyclesCCW
{
	PSMotorcycle* outCycle = [self.outgoingMotorcycles objectAtIndex: 0];
	NSArray* angles = [self.incomingMotorcycles map: ^id (PSMotorcycle* obj) {
		
		vector_t a = vNegate(outCycle.floatVelocity);
		vector_t b = vNegate(obj.floatVelocity);
		double angle = vAngleBetweenVectors2D(a, b);
		if (angle < 0.0)
			angle += 2.0*M_PI;
		if (outCycle == obj)
			return @M_PI; // FIXME: 0.0 or M_PI?
		return [NSNumber numberWithDouble: angle];
	}];
	
	NSDictionary* dict = [NSDictionary dictionaryWithObjects: self.incomingMotorcycles forKeys: angles];
	
	angles = [angles sortedArrayUsingSelector: @selector(compare:)];
	
	
	return [dict objectsForKeys: angles notFoundMarker: [NSNull null]];

}

- (NSArray*) incomingMotorcyclesCCW
{
	PSMotorcycle* outCycle = [self.outgoingMotorcycles objectAtIndex: 0];
	NSArray* angles = [self.incomingMotorcycles map: ^id (PSMotorcycle* obj) {
		
		vector_t a = outCycle.floatVelocity;
		vector_t b = vNegate(obj.floatVelocity);
		double angle = vAngleBetweenVectors2D(a, b);
		if (angle < 0.0)
			angle += 2.0*M_PI;
		return [NSNumber numberWithDouble: angle];
	}];
	
	NSDictionary* dict = [NSDictionary dictionaryWithObjects: self.incomingMotorcycles forKeys: angles];
	
	angles = [angles sortedArrayUsingSelector: @selector(compare:)];
	
	
	return [dict objectsForKeys: angles notFoundMarker: [NSNull null]];
}


@end



@implementation	PSSpoke
{
	MPVector2D* cachedNumerator;
}

@synthesize retiredWaveFronts, terminationTimeSqr, startTimeSqr, endLocation;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	//endLocation = v3iCreate(INT32_MAX, INT32_MAX, INT32_MAX, 16);
	retiredWaveFronts = [[NSMutableArray alloc] init];
	
	return self;
}

- (v3i_t) positionAtTime: (MPDecimal*) t
{
	[self doesNotRecognizeSelector: _cmd];
	return v3iCreate(0, 0, 0, 0);
}

- (MPDecimal*) timeSqrToLocation: (MPVector2D*) X;
{
	assert(self.leftEdge && self.rightEdge);
	
	return [[self.leftEdge timeSqrToLocation: X] max: [self.rightEdge timeSqrToLocation: X]];
}

/*!
 @return returns spoke velocity, if possible
 */
- (MPVector2D*) mpVelocity
{
	MPDecimal* den = self.mpDenominator;
	if (den.isZero)
		return self.mpDirection;
	MPVector2D* R = [self.mpNumerator scaleNum: [MPDecimal one] den: den];
	
	
	assert(!isinf(R.x.toDouble));
	assert(!isinf(R.y.toDouble));
	
	
	
	return R;
}

- (MPDecimal*) mpDenominator
{
	assert(self.leftEdge);
	assert(self.rightEdge);
	MPVector2D* E_AB = [MPVector2D vectorWith3i: self.leftEdge.edge];
	MPVector2D* E_BC = [MPVector2D vectorWith3i: self.rightEdge.edge];
	
	MPDecimal* d = [E_AB cross: E_BC];
	MPDecimal* dot = [E_AB dot: E_BC];
	
	if (d.isZero && dot.isPositive) // the velocity is 1 when the two edges are parallel
	{
		MPVector2D* R = [E_AB add: E_BC];
				
		R = [R scale: [MPDecimal decimalWithInt64: 1 shift: 1]]; // divide by 2
		return R.length;
	}
	return d;
}

- (MPVector2D*) mpNumerator
{
	if (cachedNumerator)
		return cachedNumerator;

	assert(self.leftEdge);
	assert(self.rightEdge);
	assert(v3iLength2D(self.leftEdge.edge).x > 0);
	assert(v3iLength2D(self.rightEdge.edge).x > 0);
	MPVector2D* E_AB = [MPVector2D vectorWith3i: self.leftEdge.edge];
	MPVector2D* E_BC = [MPVector2D vectorWith3i: self.rightEdge.edge];
		
	MPDecimal* l_E_AB = [E_AB length];
	MPDecimal* l_E_BC = [E_BC length];
	
	MPVector2D* R = [[E_BC scale: l_E_AB] sub: [E_AB scale: l_E_BC]];
	
	MPDecimal* ABxBC = [E_AB cross: E_BC];
	MPDecimal* ABdBC = [E_AB dot: E_BC];
	
	// if the R is zero, segments are parallel and colinear
	if (ABxBC.isZero)
	{
		if (ABdBC.isPositive)
		{
			MPVector2D* RE = [E_AB add: E_BC];
		
			R.x = RE.y.negate;
			R.y = RE.x;
		
			R = [R scale: [MPDecimal oneHalf]]; // divide by 2
		}
		else // no denumerator for the anti-parallel case, but we still need a direction
		{
			R = [E_BC sub: E_AB]; // negate because we need to do AB-BC
			
			R = [R scale: [MPDecimal oneHalf]]; // divide by 2
		}
	}
	
	
	assert(!isinf(R.x.toDouble));
	assert(!isinf(R.y.toDouble));
	
	cachedNumerator = R;
	
	return R;
}

- (MPVector2D*) mpDirection
{
	MPVector2D* num = self.mpNumerator;
	MPDecimal* den = self.mpDenominator;
	
	if (den && den.isNegative)
		num = num.negate;
	
	return num;
}

- (MPVector2D*) mpSourcePosition
{
	assert(self.leftEdge);
	assert(self.rightEdge);

	if (self.leftEdge.rightVertex == self.rightEdge.leftVertex)
		return [MPVector2D vectorWith3i: self.leftEdge.rightVertex.position];
	
	return self.sourceVertex.mpPosition;
	
}


- (BOOL) isVertexCCWFromSpoke: (MPVector2D *)mpx
{
	MPVector2D* dir = self.mpDirection;
	
	MPVector2D* xdir = [mpx sub: self.mpSourcePosition];
	
	MPDecimal* cross = [dir cross: xdir];
	
	return cross.isPositive;
}

- (BOOL) isVertexCWFromSpoke: (MPVector2D *)mpx
{
	MPVector2D* dir = self.mpDirection;
	
	MPVector2D* xdir = [mpx sub: self.mpSourcePosition];
	
	MPDecimal* cross = [dir cross: xdir];
	
	return cross.isNegative;
}


- (BOOL) isSpokeCCW: (PSSpoke *) spoke
{
	MPVector2D* dir = self.mpDirection;
	
	MPVector2D* xdir = spoke.mpDirection;
	
	MPDecimal* cross = [dir cross: xdir];
	
	return cross.isPositive;
}


@end

@implementation PSSimpleSpoke

- (v3i_t) positionAtTime: (MPDecimal*) t
{
	MPVector2D* num = self.mpNumerator;
	
	MPDecimal* den = self.mpDenominator;
	
	if (den.isZero)
		return self.startLocation;
	
	assert(den);
	assert(!den.isZero);
	assert(self.sourceVertex.mpPosition);
	
	MPVector2D* v = [self.sourceVertex.mpPosition add: [num scaleNum: t den: den]];
	
	if (v.minIntegerBits > 15)
		return v3iCreate(0, 0, 0, 16); // FIXME: should not be necessary to check here!
	
	v3i_t x = [v toVectorWithShift: 16];
	
	return x;
	
	
	
}

/*
- (void) setVelocity:(vector_t)velocity
{
	assert(!vIsInf(velocity) && !vIsNAN(velocity));
	_velocity = velocity;
}
*/

- (vector_t) floatVelocity
{
	return self.mpVelocity.toFloatVector;
}


- (NSString *)description
{
	vector_t sl = v3iToFloat(self.startLocation);
	
	return [NSString stringWithFormat: @"%p (%@) @(%f, %f) : (%f, %f)", self, [self class], sl.farr[0], sl.farr[1], self.floatVelocity.farr[0], self.floatVelocity.farr[1]];
}

- (BOOL) convex
{
	return YES;
}

@end


@implementation PSMotorcycleSpoke

@synthesize opposingWaveFront;

- (BOOL) convex
{
	return NO;
}

- (void) setOpposingWaveFront: (PSWaveFront *)wf
{
	assert(!wf || ((wf != self.leftWaveFront) && (wf != self.rightWaveFront)));
	opposingWaveFront = wf;
}

static v3i_t _rotateEdgeToNormal(v3i_t E)
{
	return v3iCreate(-E.y, E.x, E.z, E.shift);
}

- (MPVector2D*) splitLocation
{
	PSWaveFront* waveFront = self.opposingWaveFront;
	assert(waveFront);
	assert(self.motorcycle.sourceVertex);
	assert(waveFront.edge);
	
	
	
	v3i_t we = waveFront.edge.edge;
	v3i_t wn = _rotateEdgeToNormal(we);
	
	assert(self.mpNumerator && !(self.mpNumerator.x.isZero && self.mpNumerator.y.isZero));
	MPDecimal* xx = [self.mpDirection dot: [MPVector2D vectorWith3i: wn]];
	
	
	if (xx.isPositive || xx.isZero)
	{
		return nil;
	}
	
	MPVector2D* D = self.mpNumerator;
	MPDecimal* d = self.mpDenominator;
	
	MPVector2D* E = waveFront.edge.mpEdge;
	MPDecimal* El = E.length;
	//	MPDecimal* EE = [E dot: E];
	//	MPVector2D* N = E.rotateCCW;
	
	MPVector2D* V = self.opposingWaveFront.edge.leftVertex.mpPosition;
	MPVector2D* B = self.sourceVertex.mpPosition;
	
	
	MPDecimal* nom = [[V sub: B] cross: E];
	MPDecimal* den = [[D cross: E] add: [d mul: El]];
	
	MPVector2D* uR = [D scaleNum: nom den: den];
	MPVector2D* X = [B add: uR];
	
	if (X.minIntegerBits > 15)
		return nil;
	
	assert([waveFront.edge mpVertexInPositiveHalfPlane: X]);
	
	return X;
}

@end

@implementation PSDegenerateSpoke

- (v3i_t) positionAtTime: (MPDecimal*) t
{
	return self.startLocation;
}

- (MPVector2D*) mpDirection
{
	return [MPVector2D vectorWith3i: v3iCreate(0, 0, 0, 16)];
}

- (MPVector2D*) mpVelocity
{
	return [MPVector2D vectorWith3i: v3iCreate(0, 0, 0, 16)];
}


- (BOOL) convex
{
	return NO;
}

- (NSString *)description
{
	vector_t sl = v3iToFloat(self.startLocation);
	
	return [NSString stringWithFormat: @"%p (%@) @(%f, %f)", self, [self class], sl.farr[0], sl.farr[1]];
}

@end




@implementation PSWaveFront
{
	NSUInteger hashCache;
}

@synthesize retiredLeftSpokes, retiredRightSpokes, leftSpoke, rightSpoke, terminationTimeSqr, opposingSpokes;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	opposingSpokes = @[];
	
	return self;
}

- (void) swapSpoke: (PSSpoke*) oldSpoke forSpoke: (PSSpoke*) newSpoke
{
	assert(!([retiredLeftSpokes containsObject: oldSpoke] && (leftSpoke == oldSpoke)));
	assert(!([retiredRightSpokes containsObject: oldSpoke] && (rightSpoke == oldSpoke)));
	assert(![retiredRightSpokes containsObject: newSpoke]);
	assert(![retiredLeftSpokes containsObject: newSpoke]);
	assert(leftSpoke != newSpoke);
	assert(rightSpoke != newSpoke);

	assert(oldSpoke.sourceVertex == newSpoke.sourceVertex);
	assert(oldSpoke.terminalVertex == newSpoke.terminalVertex);
	assert(v3iEqual(oldSpoke.startLocation, newSpoke.startLocation));
//	assert([oldSpoke.terminationTimeSqr compare: newSpoke.terminationTimeSqr] == 0);
	
	if (leftSpoke == oldSpoke)
		leftSpoke = newSpoke;
	if (rightSpoke == oldSpoke)
		rightSpoke = newSpoke;
	
	
	if ([retiredLeftSpokes containsObject: oldSpoke])
	{
		assert(![retiredLeftSpokes containsObject: newSpoke]);
		NSMutableArray* ary = [retiredLeftSpokes mutableCopy];
		[ary replaceObjectAtIndex: [ary indexOfObject: oldSpoke] withObject: newSpoke];
		retiredLeftSpokes = ary;
	}
	if ([retiredRightSpokes containsObject: oldSpoke])
	{
		assert(![retiredRightSpokes containsObject: newSpoke]);
		NSMutableArray* ary = [retiredRightSpokes mutableCopy];
		[ary replaceObjectAtIndex: [ary indexOfObject: oldSpoke] withObject: newSpoke];
		retiredRightSpokes = ary;
	}
}

- (void) setLeftSpoke: (PSSpoke *)spoke
{
	if (spoke == leftSpoke)
		return;
	
	if (!retiredLeftSpokes)
		retiredLeftSpokes = @[];
	
	
	// hack against other error: ![retiredLeftSpokes containsObject: leftSpoke]
	//if (leftSpoke && ![retiredLeftSpokes containsObject: leftSpoke])
	if (leftSpoke && leftSpoke.terminalVertex && !v3iEqual(leftSpoke.endLocation, leftSpoke.startLocation))
	{

		assert(![retiredLeftSpokes containsObject: leftSpoke]);
		retiredLeftSpokes = [retiredLeftSpokes arrayByAddingObject: leftSpoke];
		[leftSpoke.retiredWaveFronts addObject: self];
	}
	leftSpoke = spoke;
}

- (void) setRightSpoke:(PSSpoke *)spoke
{
	if (spoke == rightSpoke)
		return;
	
	if (!retiredRightSpokes)
		retiredRightSpokes = @[];
	
	if (rightSpoke && rightSpoke.terminalVertex && !v3iEqual(rightSpoke.endLocation, rightSpoke.startLocation))
	{
		assert(![retiredRightSpokes containsObject: rightSpoke]);
		retiredRightSpokes = [retiredRightSpokes arrayByAddingObject: rightSpoke];
		[rightSpoke.retiredWaveFronts addObject: self];
	}
	
	rightSpoke = spoke;
}

static long _waveFrontsWeaklyConvex(PSWaveFront* leftFront, PSWaveFront* rightFront)
{
	MPDecimal* cross = [leftFront.edge.mpEdge cross: rightFront.edge.mpEdge];
	
	return (cross.isPositive || cross.isZero);
}


- (BOOL) isWeaklyConvexTo:(PSWaveFront *)wf
{
	return _waveFrontsWeaklyConvex(self, wf);
}



- (MPVector2D*) computeCollapseLocation
{
//	PSSpoke* leftSpoke = self.leftSpoke;
//	PSSpoke* rightSpoke = self.rightSpoke;
	
	MPVector2D* X = nil;
	
	BOOL hasActiveMotorcycle = ([leftSpoke isKindOfClass: [PSMotorcycleSpoke class]] && [(PSMotorcycleSpoke*)leftSpoke opposingWaveFront]) || ([rightSpoke isKindOfClass: [PSMotorcycleSpoke class]] && [(PSMotorcycleSpoke*)rightSpoke opposingWaveFront]);
	BOOL leftDegenerate = [leftSpoke isKindOfClass: [PSDegenerateSpoke class]];
	BOOL rightDegenerate = [rightSpoke isKindOfClass: [PSDegenerateSpoke class]];
	BOOL hasDegenerate = leftDegenerate || rightDegenerate;
	
	
	if (leftDegenerate && !hasActiveMotorcycle)
	{
		X = [MPVector2D vectorWith3i: leftSpoke.startLocation];
	}
	
	if (!X && rightDegenerate && !hasActiveMotorcycle)
	{
		X = [MPVector2D vectorWith3i: rightSpoke.startLocation];
	}
	
	if (!X && !hasDegenerate)
		X = PSIntersectSpokes(leftSpoke, rightSpoke);
	
	if (!X)
	{
		
		// if we have a loop, we assume we're running two fast spokes into each other in a closing loop
		if ((leftSpoke.leftWaveFront == rightSpoke.rightWaveFront) && (rightSpoke.leftWaveFront == leftSpoke.rightWaveFront))
		{
			//assert(leftSpoke.mpDenominator.isZero && rightSpoke.mpDenominator.isZero);
			X = [[[MPVector2D vectorWith3i: leftSpoke.startLocation] add: [MPVector2D vectorWith3i: rightSpoke.startLocation]] scale: [MPDecimal oneHalf]];
		}
		
	}

	return X;
}




/*
- (BOOL) isEqual: (PSWaveFront*) object
{
	[self doesNotRecognizeSelector: _cmd];
	return NO;
}
*/
/*
- (NSString*) hashString
{
	NSString* str = [NSString stringWithFormat: @"%f %f %@ %f %f %f %f %f %f", self.startTime, self.terminationTime, [self class], self.direction.farr[0], self.direction.farr[1], self.leftSpoke.sourceVertex.position.farr[0], self.leftSpoke.sourceVertex.position.farr[1], self.rightSpoke.sourceVertex.position.farr[0], self.rightSpoke.sourceVertex.position.farr[1]];
	return str;
}


- (NSUInteger) hash
{
	if (!hashCache)
	{
		NSString* str = [self hashString];
		hashCache = [str hash];
	}
	return hashCache;
}
*/
- (NSString *)description
{
	vector_t e = v3iToFloat(self.edge.edge);
	return [NSString stringWithFormat: @"%p (%@): (%f, %f) o: %lu", self, [self class], -e.farr[1], e.farr[0], (unsigned long)opposingSpokes.count];
}

@end


@implementation PSMotorcycleCrash

@end

@implementation PSMotorcycleMotorcycleCrash

@end

@implementation PSMotorcycleEdgeCrash

@end

@implementation PSMotorcycleVertexCrash

@end

