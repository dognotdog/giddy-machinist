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

@synthesize time, location;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
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


@end


@implementation PSSourceEdge


@end

@implementation PSVertex
{
}

@synthesize edges, incomingMotorcycles, outgoingMotorcycles, outgoingSpokes;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	edges = [NSArray array];
	incomingMotorcycles = [NSArray array];
	outgoingMotorcycles = [NSArray array];
	outgoingSpokes = [NSArray array];
	
	return self;
}

- (void) addEdge:(PSEdge *)edge
{
	edges = [edges arrayByAddingObject: edge];
}

- (void) removeEdge:(PSEdge *)edge
{
	edges = [edges arrayByRemovingObject: edge];
	
}

- (PSSourceEdge*) prevEdge
{
	for (PSEdge* edge in edges)
		if ([edge isKindOfClass: [PSSourceEdge class]] && (self == edge.endVertex))
			return (PSSourceEdge*)edge;
	return nil;
}

- (PSSourceEdge*) nextEdge
{
	for (PSEdge* edge in edges)
		if ([edge isKindOfClass: [PSSourceEdge class]] && (self == edge.startVertex))
			return (PSSourceEdge*)edge;
	return nil;
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
		angle = M_PI - angle;
	return angle;
}

static double _angle2d_cw(vector_t from, vector_t to)
{
	double angle = -_angle2d(from, to);
	if (angle < 0.0)
		angle = M_PI - angle;
	return angle;
}

- (PSSpoke*) nextSpokeClockwiseFrom: (vector_t) startDir to: (vector_t) endDir
{
	double alphaMin = 2.0*M_PI;
	id outSpoke = nil;
	
	for (PSSpoke* spoke in outgoingSpokes)
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
	return [NSString stringWithFormat: @"%p @%f (%f, %f)", self, self.time, self.position.farr[0], self.position.farr[1]];
}


@end

@implementation	PSSpoke

- (void) setVelocity:(vector_t)velocity
{
	assert(!vIsInf(velocity) && !vIsNAN(velocity));
	_velocity = velocity;
}

- (NSString *)description
{
	return [NSString stringWithFormat: @"%p @%f: (%f, %f)", self, self.start, self.velocity.farr[0], self.velocity.farr[1]];
}

@end


@implementation PSAntiSpoke


@end

@implementation PSMotorcycleSpoke

@end

@implementation PSCrashVertex

@end

@implementation PSMergeVertex

@end

@implementation PSSplitVertex

@end

@implementation PSWaveFront

@end

