//
//  PolygonSkeletizerObjects.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 29.03.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "PolygonSkeletizerObjects.h"
#import "FoundationExtensions.h"
#import "PriorityQueue.h"
#import "MPVector2D.h"
#import "MPInteger.h"

@implementation PSEvent
{
	NSUInteger hashCache;
}

@synthesize time, creationTime, location;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	creationTime = NAN;
	time = NAN;
	location = v3iCreate(0,0,0,-1);
	
	return self;
}

- (BOOL) isEqual: (PSEvent*) object
{
	if ([self class] != [object class])
		return NO;
	if (self.creationTime != object.creationTime)
		return NO;
	if (self.time != object.time)
		return NO;
	if (!v3iEqual(self.location, object.location))
		return NO;
	
	
	return YES;
}

- (NSString*) hashString
{
	NSString* str = [NSString stringWithFormat: @"%f %f %@ %d %d", self.creationTime, time, [self class], location.x, location.y];
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
	return [NSString stringWithFormat: @"%p @%f (%@)", self, time, [self class]];
}

@end


@implementation PSBranchEvent

- (BOOL) isEqual: (PSBranchEvent*) object
{
	if (![super isEqual: object])
		return NO;
	if (self.branchVertex != object.branchVertex)
		return NO;
	if (self.rootSpoke != object.rootSpoke)
		return NO;
	
	
	return YES;
}

- (NSString*) hashString
{
	NSString* str = [NSString stringWithFormat: @"%@ %d %d", [super hashString], self.branchVertex.position.x, self.branchVertex.position.y];
	return str;
}

@end

@implementation PSCollapseEvent

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
	NSString* str = [NSString stringWithFormat: @"%@ %d %d", [super hashString], self.collapsingWaveFront.direction.x, self.collapsingWaveFront.direction.y];
	return str;
}
@end

@implementation PSSplitEvent

- (BOOL) isEqual: (PSSplitEvent*) object
{
	if (![super isEqual: object])
		return NO;
	if (self.antiSpoke != object.antiSpoke)
		return NO;
	
	
	return YES;
}

- (NSString*) hashString
{
	NSString* str = [NSString stringWithFormat: @"%@ %f %f", [super hashString], self.antiSpoke.floatVelocity.farr[0], self.antiSpoke.floatVelocity.farr[1]];
	return str;
}
@end

@implementation PSEmitEvent
@end

@implementation PSReverseBranchEvent

- (BOOL) isEqual: (PSReverseBranchEvent*) object
{
	if (![super isEqual: object])
		return NO;
	if (self.branchVertex != object.branchVertex)
		return NO;
	if (self.rootSpoke != object.rootSpoke)
		return NO;
	
	
	return YES;
}

- (NSString*) hashString
{
	
	NSString* str = [NSString stringWithFormat: @"%@ %d %d %d", [super hashString], self.branchVertex.position.x, self.branchVertex.position.y, self.branchVertex.position.shift];
	return str;
}
@end

static double _maxBoundsDimension(NSArray* vertices)
{
	v3i_t minv = v3iCreate(INT32_MAX, INT32_MAX, INT32_MAX, 0);
	v3i_t maxv = v3iCreate(INT32_MIN, INT32_MIN, INT32_MIN, 0);
	
	for (PSVertex* vertex in vertices)
	{
		minv.shift = vertex.position.shift;
		maxv.shift = vertex.position.shift;
		minv = v3iMin(minv, vertex.position);
		maxv = v3iMax(maxv, vertex.position);
	}
	
	v3i_t r = v3iSub(maxv, minv);
	return vLength(v3iToFloat(r));
}

@implementation PSEdge



@end

@implementation PSMotorcycle

@synthesize crashVertices, terminationTime, crashQueue;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	crashVertices = @[];
	terminationTime = (vmlongerfix_t){INT128_MAX,0};
	
	crashQueue = [[PriorityQueue alloc] initWithCompareBlock: ^NSComparisonResult(PSMotorcycleCrash* obj0, PSMotorcycleCrash* obj1) {
		vmlongerfix_t t0 = obj0.crashTimeSqr;
		vmlongerfix_t t1 = obj1.crashTimeSqr;
		assert(t0.shift == t1.shift);
		
		return i128compare(t0.x, t1.x);
	}];

	return self;
}

- (MPVector2D*) mpVelocity
{
	MPVector2D* E_AB = [MPVector2D vectorWith3i: self.leftEdge.edge];
	MPVector2D* E_BC = [MPVector2D vectorWith3i: self.rightEdge.edge];
	
	MPDecimal* E_ABxBC = [E_AB cross: E_BC];
	
	MPDecimal* l_E_AB = [E_AB length];
	MPDecimal* l_E_BC = [E_BC length];
	
	MPVector2D* RU = [[E_BC scale: l_E_AB] sub: [E_AB scale: l_E_BC]];
	
	MPVector2D* R = [RU scaleNum: [[MPDecimal alloc] initWithInt64: 1 shift: 0] den: E_ABxBC];

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

- (PSVertex*) getVertexOnMotorcycleAtLocation: (v3i_t) x
{
	if (self.sourceVertex && v3iEqual(self.sourceVertex.position, x))
		return self.sourceVertex;
	if (self.terminalVertex && v3iEqual(self.terminalVertex.position, x))
		return self.terminalVertex;
	for (PSVertex* vertex in self.crashVertices)
		if (v3iEqual(vertex.position, x))
			return vertex;
	
	return nil;
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

- (NSString *)description
{
	return [NSString stringWithFormat: @"%p (%@) @%f (%d, %d)", self, [self class], self.time, self.position.x, self.position.y];
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

@implementation PSMergeVertex

- (NSArray*) mergedMotorcyclesCCW
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

@implementation PSSplitVertex

@end

@implementation	PSSpoke

@synthesize retiredWaveFronts, terminationTime, start;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	terminationTime = INFINITY;
	start = INFINITY;
	
	retiredWaveFronts = [[NSMutableArray alloc] init];
	
	return self;
}

- (v3i_t) positionAtTime: (double) t
{
	[self doesNotRecognizeSelector: _cmd];
	return v3iCreate(0, 0, 0, 0);
}

@end

@implementation PSSimpleSpoke

- (v3i_t) positionAtTime: (double) t
{
	assert(0);
	return v3iCreate(0, 0, 0, 0);
//	return v3Add(self.sourceVertex.position, v3MulScalar(self.velocity, t - self.start));
}

/*
- (void) setVelocity:(vector_t)velocity
{
	assert(!vIsInf(velocity) && !vIsNAN(velocity));
	_velocity = velocity;
}
*/

- (NSString *)description
{
	return [NSString stringWithFormat: @"%p (%@) @%f: (%f, %f)", self, [self class], self.start, self.floatVelocity.farr[0], self.floatVelocity.farr[1]];
}

- (BOOL) convex
{
	return YES;
}

@end


@implementation PSFastSpoke

/*
- (vector_t) positionAtTime: (double) t
{
	return (self.sourceVertex.position);
}
*/
- (NSString *)description
{
	return [NSString stringWithFormat: @"%p (%@) @%f: (%d, %d)", self, [self class], self.start, self.direction.x, self.direction.y];
}

- (BOOL) convex
{
	return YES;
}


@end

@implementation PSAntiSpoke

- (BOOL) convex
{
	return NO;
}


@end

@implementation PSMotorcycleSpoke

- (BOOL) convex
{
	return NO;
}


@end


@implementation PSWaveFront
{
	NSUInteger hashCache;
}

@synthesize retiredLeftSpokes, retiredRightSpokes, leftSpoke, rightSpoke, terminationTime;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	terminationTime = INFINITY;
	
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
	assert(oldSpoke.start == newSpoke.start);
	assert(oldSpoke.terminationTime == newSpoke.terminationTime);
	
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

- (void) setLeftSpoke:(PSSpoke *)spoke
{
	if (spoke == leftSpoke)
		return;
	
	if (!retiredLeftSpokes)
		retiredLeftSpokes = @[];
	
	if (spoke)
	{
		assert(![retiredLeftSpokes containsObject: spoke]);
		assert(spoke.terminationTime >= spoke.start);
	}
	
	if (leftSpoke && spoke)
	{
		assert(leftSpoke.terminalVertex == spoke.sourceVertex);
		assert(leftSpoke.terminationTime <= spoke.start);
		assert(leftSpoke.terminationTime != INFINITY);
		assert(spoke.start != INFINITY);
	}
	
	if (leftSpoke)
	{

		if (retiredLeftSpokes.count && leftSpoke)
		{
			if ([retiredLeftSpokes lastObject] != leftSpoke)
				assert([[retiredLeftSpokes lastObject] terminalVertex] == leftSpoke.sourceVertex);
		}
	
	}
	
	// hack against other error: ![retiredLeftSpokes containsObject: leftSpoke]
	//if (leftSpoke && ![retiredLeftSpokes containsObject: leftSpoke])
	if (leftSpoke)
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
	
	if (rightSpoke)
	{
		assert(![retiredRightSpokes containsObject: rightSpoke]);
		retiredRightSpokes = [retiredRightSpokes arrayByAddingObject: rightSpoke];
		[rightSpoke.retiredWaveFronts addObject: self];
	}
	
	rightSpoke = spoke;
}

- (BOOL) isEqual: (PSWaveFront*) object
{
	if ([self class] != [object class])
		return NO;
	if (self.startTime != object.startTime)
		return NO;
	if (self.terminationTime != object.terminationTime)
		return NO;
	if (self.leftSpoke != object.leftSpoke)
		return NO;
	if (self.rightSpoke != object.rightSpoke)
		return NO;
	if (!v3iEqual(self.direction, object.direction))
		return NO;
	
	
	return YES;
}

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
	return [NSString stringWithFormat: @"%p (%@): (%d, %d)", self, [self class], self.direction.x, self.direction.y];
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

