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

@end

@implementation	PSSpoke
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

