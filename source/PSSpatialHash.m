//
//  PSSpatialHash.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 18.06.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "PSSpatialHash.h"

#import "VectorMath_fixp.h"
#import "PolygonSkeletizerObjects.h"
#import "MPVector2D.h"
#import "MPInteger.h"
#import "PriorityQueue.h"

#define HASHX 73856093
#define HASHY 19349663
#define HASHZ 83492791


@interface PSSpatialHashCell : NSObject

@property(nonatomic, strong) NSMutableSet* edgeSegments;
@property(nonatomic) size_t index;

@end

@implementation PSSpatialHash
{
	NSArray* hashCells;
	vmintfix_t gridSize;
}

- (id) init
{
	[self doesNotRecognizeSelector: _cmd];

	if (!(self = [super init]))
		return nil;
	
	
	
	return self;
}

- (id) initWithGridSize: (vmintfix_t) size numCells: (size_t) ncells
{
	if (!(self = [super init]))
		return nil;
	
	gridSize = size;
	
	NSMutableArray* ary = [NSMutableArray array];
	
	for (size_t i = 0; i < ncells; ++i)
	{
		PSSpatialHashCell* cell = [[PSSpatialHashCell alloc] init];
		cell.index = i;
		
		[ary addObject: cell];
	}
	
	hashCells = ary;
	
	
	return self;
}

static size_t _hashXY(unsigned long x, unsigned long y, size_t ncells)
{
	return ((x*HASHX) ^ (y*HASHY)) % ncells;
}

- (void) addSegment: (PSEdge*) edge toCell: (v3i_t) cellLoc
{
	size_t cellIndex = _hashXY(cellLoc.x, cellLoc.y, hashCells.count);
	
	PSSpatialHashCell* cell = hashCells[cellIndex];
	
	[cell.edgeSegments addObject: edge];
	
}

- (void) addEdgeSegments: (NSArray*) segments
{
	for (PSEdge* edge in segments)
	{
		v3i_t startLoc = edge.leftVertex.position;
		v3i_t endLoc = edge.rightVertex.position;
		v3i_t r = v3iSub(endLoc, startLoc);
		
		int signx = i32compare(r.x, 0);
		int signy = i32compare(r.y, 0);
		
		int posx = startLoc.x / gridSize.x;
		int posy = startLoc.y / gridSize.x;
		int endx = endLoc.x / gridSize.x;
		int endy = endLoc.y / gridSize.x;
		
		int deltax = startLoc.x - posx*gridSize.x;
		int deltay = startLoc.y - posy*gridSize.x;

		if (signx > 0)
			deltax = gridSize.x - deltax;
		if (signy > 0)
			deltay = gridSize.x - deltay;
		
		/*
		if (deltax == gridSize.x)
		{
			deltax = 0;
			posx -= signx;
		}
		if (deltay == gridSize.x)
		{
			deltay = 0;
			posy -= signy;
		}
		*/
		
		assert(deltax >= 0);
		assert(deltay >= 0);
		assert(deltax <= gridSize.x);
		assert(deltay <= gridSize.x);

		long txry = deltax*labs(r.y);
		long tyrx = deltay*labs(r.x);
		
		//printf("from: %d, %d\n", posx, posy);
		//printf("  to: %d, %d\n", endx, endy);
		
		[self addSegment: edge toCell: v3iCreate(posx, posy, 0, 0)];
		
		while ((posx != endx) || (posy != endy))
		{
			
			
			if (txry < tyrx)
			{
				txry += labs(r.y)*gridSize.x;
				posx += signx;
			}
			else
			{
				tyrx += labs(r.x)*gridSize.x;
				posy += signy;
			}
			
			//printf(" pos: %d, %d\n", posx, posy);
			[self addSegment: edge toCell: v3iCreate(posx, posy, 0, 0)];
			
		}
		
		
	}
	
}


- (PSMotorcycleCrash*) crashMotorcycleIntoEdges: (PSMotorcycle*) cycle withLimit: (MPDecimal*) limit;
{
	NSMutableSet* visitedCells = [[NSMutableSet alloc] init];
	PriorityQueue* crashes = [[PriorityQueue alloc] initWithCompareBlock: ^NSComparisonResult(PSMotorcycleCrash* obj0, PSMotorcycleCrash* obj1) {

		MPDecimal* t0 = obj0.crashTimeSqr;
		MPDecimal* t1 = obj1.crashTimeSqr;
			
		return [t0 compare: t1];
	}];
	
	
	MPDecimal* grid = [MPDecimal decimalWithInt64: gridSize.x shift: gridSize.shift];
	
	MPVector2D* startLoc = cycle.sourceVertex.mpPosition;
	

	MPVector2D* r = cycle.mpDirection;
	
	long stepx = [r.x compareToZero];
	long stepy = [r.y compareToZero];
	
	MPVector2D* pos = [startLoc div: grid];
	
	v3i_t starti = [pos toVectorWithShift: 0];
	
	MPVector2D* delta = [startLoc sub: [pos scale: grid]];
	
	if (stepx > 0)
		delta.x = [grid sub: delta.x];
	if (stepy > 0)
		delta.y = [grid sub: delta.y];

	MPVector2D* tr = delta.copy;
	tr.x = [tr.x mul: r.y.abs];
	tr.y = [tr.y mul: r.x.abs];
	
	//NSMutableArray* cellLog = [NSMutableArray array];
	

	void (^visitCellBlock)(v3i_t) = ^(v3i_t cellLoc) {
		size_t cellIndex = _hashXY(cellLoc.x, cellLoc.y, hashCells.count);
		PSSpatialHashCell* cell = hashCells[cellIndex];
		
		//[cellLog addObject: [NSString stringWithFormat: @"%d, %d", cellLoc.x, cellLoc.y]];
		//[cellLog addObject: [NSString stringWithFormat: @"  %zd", cell.edgeSegments.count]];
		
		
		if ([visitedCells containsObject: cell])
			return;
		
		[visitedCells addObject: cell];
		
		for (PSEdge* edge in cell.edgeSegments)
		{
		
			MPVector2D* X = [cycle crashIntoEdge: edge];
			
			
			
			if (X)
			{
				v3i_t x = [X toVectorWithShift: 16];
				
				
				MPDecimal* ta0 = [cycle.leftEdge timeSqrToLocation: X];
				MPDecimal* ta1 = [cycle.rightEdge timeSqrToLocation: X];
				MPDecimal* ta = [ta0 max: ta1];
								
				v3i_t ax = v3iSub(x, edge.leftVertex.position);
				v3i_t bx = v3iSub(x, edge.rightVertex.position);
				
				BOOL hitStart = !ax.x && !ax.y;
				BOOL hitEnd = !bx.x && !bx.y;
				
				id crash = nil;
				
				if (hitStart)
				{
					PSMotorcycleVertexCrash* vc = [[PSMotorcycleVertexCrash alloc] init];
					vc.location = x;
					vc.cycle0 = cycle;
					vc.vertex = edge.leftVertex;
					vc.time0Sqr = ta;
					vc.crashTimeSqr = ta;
					crash = vc;
				}
				else if (hitEnd)
				{
					PSMotorcycleVertexCrash* vc = [[PSMotorcycleVertexCrash alloc] init];
					vc.location = x;
					vc.cycle0 = cycle;
					vc.vertex = edge.rightVertex;
					vc.time0Sqr = ta;
					vc.crashTimeSqr = ta;
					crash = vc;
				}
				else
				{
					PSMotorcycleEdgeCrash* ec = [[PSMotorcycleEdgeCrash alloc] init];
					ec.location = x;
					ec.cycle0 = cycle;
					ec.edge1 = edge;
					ec.time0Sqr = ta;
					ec.crashTimeSqr = ta;
					crash = ec;
				}
				
				if (crash)
				{
					[crashes addObject: crash];
				}
			}
		}
	};
	
	
	v3i_t posi = [pos toVectorWithShift: 0];
	visitCellBlock(posi);

	MPDecimal* gridLimit = [limit div: grid];
	
	int32_t lim = [gridLimit toInt32WithQ: 0]+1;
	
	v3i_t dcells = v3iSub(posi, starti);
	
	while (lmax(labs(dcells.x), labs(dcells.y)) < lim)
	{
		if ([tr.x compare: tr.y] < 0)
		{
			tr.x = [tr.x add: [r.y.abs mul: grid]];
			pos.x = [pos.x add: [MPDecimal decimalWithInt64: stepx shift: 0]];
		}
		else
		{
			tr.y = [tr.y add: [r.x.abs mul: grid]];
			pos.y = [pos.y add: [MPDecimal decimalWithInt64: stepy shift: 0]];
			
		}
		posi = [pos toVectorWithShift: 0];
		visitCellBlock(posi);

		dcells = v3iSub(posi, starti);
	}
	
	if (crashes.count)
		return crashes.firstObject;
	
	assert(0);
	
	return nil;	
}


@end

@implementation PSSpatialHashCell

@synthesize edgeSegments;

- (id) init
{	
	if (!(self = [super init]))
		return nil;
	
	edgeSegments = [NSMutableSet set];
	
	return self;
}

@end
