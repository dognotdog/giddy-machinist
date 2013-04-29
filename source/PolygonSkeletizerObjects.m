//
//  PolygonSkeletizerObjects.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 29.03.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "PolygonSkeletizerObjects.h"
#import "FoundationExtensions.h"

@implementation PSEvent

@synthesize time, creationTime, location;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	creationTime = NAN;
	time = NAN;
	location = vCreate(NAN, NAN, NAN, NAN);
	
	return self;
}

- (NSString *)description
{
	return [NSString stringWithFormat: @"%p @%f (%@)", self, time, [self class]];
}

@end


@implementation PSBranchEvent
@end

@implementation PSMergeEvent
@end

@implementation PSCollapseEvent
@end

@implementation PSSplitEvent
@end

@implementation PSEmitEvent
@end

@implementation PSReverseMergeEvent
@end

@implementation PSReverseBranchEvent
@end

static double _maxBoundsDimension(NSArray* vertices)
{
	vector_t minv = vCreatePos(INFINITY, INFINITY, INFINITY);
	vector_t maxv = vCreatePos(-INFINITY, -INFINITY, -INFINITY);
	
	for (PSVertex* vertex in vertices)
	{
		minv = vMin(minv, vertex.position);
		maxv = vMax(maxv, vertex.position);
	}
	
	vector_t r = v3Sub(maxv, minv);
	return vLength(r);
}

@implementation PSEdge



@end

@implementation PSMotorcycle

@synthesize crashVertices, terminationTime;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	crashVertices = @[];
	terminationTime = INFINITY;
	
	
	return self;
}

- (NSString *)description
{
	return [NSString stringWithFormat: @"%p (%.3f, %.3f)", self, self.velocity.farr[0], self.velocity.farr[1]];
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


static double _angle2d(vector_t from, vector_t to)
{
	double x = vDot(from, to);
	double y = vCross(from, to).farr[2];
	double angle = atan2(y, x);
	return angle;
}

static double _angle2d_ccw(vector_t from, vector_t to)
{
	double angle = _angle2d(from, to);
	if (angle < 0.0)
		angle = 2.0*M_PI - angle;
	return angle;
}

static double _angle2d_cw(vector_t from, vector_t to)
{
	double angle = -_angle2d(from, to);
	if (angle < 0.0)
		angle = 2.0*M_PI - angle;
	return angle;
}

- (PSSpoke*) nextSpokeClockwiseFrom: (vector_t) startDir to: (vector_t) endDir
{
	double alphaMin = 2.0*M_PI;
	id outSpoke = nil;
	
	for (PSSimpleSpoke* spoke in outgoingSpokes)
	{
		vector_t dir = spoke.velocity;
		
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
	
	
	return outSpoke;
}

- (NSString *)description
{
	return [NSString stringWithFormat: @"%p (%@) @%f (%f, %f)", self, [self class], self.time, self.position.farr[0], self.position.farr[1]];
}


@end

@implementation PSSourceVertex

@end

@implementation PSCrashVertex

- (NSArray*) incomingMotorcyclesCCW
{
	PSMotorcycle* outCycle = [self.outgoingMotorcycles objectAtIndex: 0];
	NSArray* angles = [self.incomingMotorcycles map: ^id (PSMotorcycle* obj) {
		
		vector_t a = outCycle.velocity;
		vector_t b = vNegate(obj.velocity);
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
		
		vector_t a = outCycle.velocity;
		vector_t b = vNegate(obj.velocity);
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

- (vector_t) positionAtTime: (double) t
{
	[self doesNotRecognizeSelector: _cmd];
	return vZero();
}

@end

@implementation PSSimpleSpoke

- (vector_t) positionAtTime: (double) t
{
	return v3Add(self.sourceVertex.position, v3MulScalar(self.velocity, t - self.start));
}

- (void) setVelocity:(vector_t)velocity
{
	assert(!vIsInf(velocity) && !vIsNAN(velocity));
	_velocity = velocity;
}

- (NSString *)description
{
	return [NSString stringWithFormat: @"%p (%@) @%f: (%f, %f)", self, [self class], self.start, self.velocity.farr[0], self.velocity.farr[1]];
}

- (BOOL) convex
{
	return YES;
}

@end


@implementation PSFastSpoke

- (vector_t) positionAtTime: (double) t
{
	return (self.sourceVertex.position);
}

- (NSString *)description
{
	return [NSString stringWithFormat: @"%p (%@) @%f: (%f, %f)", self, [self class], self.start, self.direction.farr[0], self.direction.farr[1]];
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

@synthesize retiredLeftSpokes, retiredRightSpokes, leftSpoke, rightSpoke;

- (void) setLeftSpoke:(PSSpoke *)spoke
{
	if (!retiredLeftSpokes)
		retiredLeftSpokes = @[];
	
	if (leftSpoke)
		retiredLeftSpokes = [retiredLeftSpokes arrayByAddingObject: leftSpoke];
	
	leftSpoke = spoke;
}

- (void) setRightSpoke:(PSSpoke *)spoke
{
	if (!retiredRightSpokes)
		retiredRightSpokes = @[];
	
	if (rightSpoke)
		retiredRightSpokes = [retiredRightSpokes arrayByAddingObject: rightSpoke];
	
	rightSpoke = spoke;
}


- (NSString *)description
{
	return [NSString stringWithFormat: @"%p (%@): (%f, %f)", self, [self class], self.direction.farr[0], self.direction.farr[1]];
}

@end

