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
@property(nonatomic, strong) NSMutableSet* motorcycles;
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

- (void) addMotorcycle: (PSMotorcycle*) cycle toCell: (v3i_t) cellLoc
{
	size_t cellIndex = _hashXY(cellLoc.x, cellLoc.y, hashCells.count);
	
	PSSpatialHashCell* cell = hashCells[cellIndex];
	
	[cell.motorcycles addObject: cycle];
	
}

- (void) addMotorcycles: (NSArray*) motorcycles;
{
	@autoreleasepool {
		for (PSMotorcycle* cycle in motorcycles)
		{
			v3i_t startLoc = cycle.sourceVertex.position;
			v3i_t endLoc = [cycle.limitingEdgeCrashLocation toVectorWithShift: 16];
			// FIXME: r should be the exact bisector velocity? needs to be investigated
			v3i_t r = v3iSub(endLoc, startLoc);
			
			int signx = i32compare(r.x, 0);
			int signy = i32compare(r.y, 0);
			
			int posx = _divToFloor(startLoc.x, gridSize.x);
			int posy = _divToFloor(startLoc.y, gridSize.x);
			int endx = _divToFloor(endLoc.x, gridSize.x);
			int endy = _divToFloor(endLoc.y, gridSize.x);
			
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
			
			[self addMotorcycle: cycle toCell: v3iCreate(posx, posy, 0, 0)];
			
			while ((posx != endx) || (posy != endy))
			{
				assert((signx <= 0) || (posx <= endx));
				assert((signx >= 0) || (posx >= endx));
				assert((signy <= 0) || (posy <= endy));
				assert((signy >= 0) || (posy >= endy));
				
				if (txry < tyrx)
				{
					posx += signx;
					assert((signx <= 0) || (posx <= endx));
					assert((signx >= 0) || (posx >= endx));
					txry += labs(r.y)*gridSize.x;
				}
				else
				{
					posy += signy;
					assert((signy <= 0) || (posy <= endy));
					assert((signy >= 0) || (posy >= endy));
					tyrx += labs(r.x)*gridSize.x;
				}
				
				//printf(" pos: %d, %d\n", posx, posy);
				[self addMotorcycle: cycle toCell: v3iCreate(posx, posy, 0, 0)];
				
			}
			
		}
	}
}

static int _divToFloor(int a, int b)
{
	int d = abs(a)/abs(b);
	
	long ab = a*(long)b;
	
	if (ab < 0)
	{
		if (d*abs(b) != abs(a))
			d = -d-1;
		else
			d = -d;
	}
		
	return d;
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
		
		int posx = _divToFloor(startLoc.x, gridSize.x);
		int posy = _divToFloor(startLoc.y, gridSize.x);
		int endx = _divToFloor(endLoc.x, gridSize.x);
		int endy = _divToFloor(endLoc.y, gridSize.x);
		
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
			
			
			
			if (X && [[edge.mpEdge.rotateCCW dot: cycle.mpDirection] isNegative])
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

					assert([[edge.mpEdge.rotateCCW dot: cycle.mpDirection] isNegative]);
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

					assert([[edge.mpEdge.rotateCCW dot: cycle.mpDirection] isNegative]);
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
					
					assert([[edge.mpEdge.rotateCCW dot: cycle.mpDirection] isNegative]);

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

static MPVector2D* _crashLocationMM(PSMotorcycle* ma, PSMotorcycle* mb)
{
	MPVector2D* B = [MPVector2D vectorWith3i: ma.sourceVertex.position];
	MPVector2D* V = [MPVector2D vectorWith3i: mb.sourceVertex.position];
	
	MPVector2D* E_AB = [MPVector2D vectorWith3i: ma.leftEdge.edge];
	MPVector2D* E_BC = [MPVector2D vectorWith3i: ma.rightEdge.edge];
	MPVector2D* E_UV = [MPVector2D vectorWith3i: mb.leftEdge.edge];
	MPVector2D* E_VW = [MPVector2D vectorWith3i: mb.rightEdge.edge];
	
	MPDecimal* E_ABxBC = [E_AB cross: E_BC];
	MPDecimal* E_UVxVW = [E_UV cross: E_VW];
	
	MPDecimal* E_ABdBC = [E_AB dot: E_BC];
	MPDecimal* E_UVdVW = [E_UV dot: E_VW];
	
	/*
	 MPDecimal* l_E_AB = [E_AB length];
	 MPDecimal* l_E_BC = [E_BC length];
	 MPDecimal* l_E_UV = [E_UV length];
	 MPDecimal* l_E_VW = [E_VW length];
	 */
	MPVector2D* E_ABC = ma.mpNumerator;
	MPVector2D* E_UVW = mb.mpNumerator;
	
	if (E_ABxBC.isZero)
	{
		if (E_ABdBC.isPositive)
		{
			MPVector2D* E = [E_BC sub: E_AB];
			E_ABC.x = E.y.negate;
			E_ABC.y = E.x;
			
		}
		else
		{
			E_ABC = [E_AB sub: E_BC];
			
		}
	}
	
	if (E_UVxVW.isZero)
	{
		if (E_UVdVW.isPositive)
		{
			MPVector2D* E = [E_VW add: E_UV];
			E_UVW.x = E.y.negate;
			E_UVW.y = E.x;
		}
		else
		{
			E_UVW = [E_VW sub: E_UV];
			
		}
	}
	
	MPDecimal* denum = [E_ABC cross: E_UVW];
	
	
	if (!denum.isZero)
	{
		MPVector2D* RQS = [E_ABC scale: [V cross: E_UVW]];
		MPVector2D* SPR = [E_UVW scale: [B cross: E_ABC]];
		MPVector2D* XD = [RQS sub: SPR];
		
		MPVector2D* X = [XD scaleNum: [MPDecimal one] den: denum];
		
		if (X.minIntegerBits < 16)
		{
			//double angle = [ma.mpDirection angleTo: mb.mpDirection.negate];
			//assert(fabs(angle) > 1e-3);
			
			return X;
		}
	}
	else
	{
		/* do not return anything in this case
		 MPDecimal* dot = [E_ABC dot: E_UVW];
		 if (dot.isPositive)
		 return nil;
		 else
		 return [[B add: V] scale: [MPDecimal oneHalf]];
		 */
	}
	
	
	return nil;
}

- (id) crashMotorcycleIntoMotorcycles: (PSMotorcycle*) cycle0;
{
	NSMutableSet* visitedCells = [[NSMutableSet alloc] init];
	PriorityQueue* crashes = [[PriorityQueue alloc] initWithCompareBlock: ^NSComparisonResult(PSMotorcycleCrash* obj0, PSMotorcycleCrash* obj1) {
		
		MPDecimal* t0 = obj0.crashTimeSqr;
		MPDecimal* t1 = obj1.crashTimeSqr;
		
		return [t0 compare: t1];
	}];
	
	
	MPDecimal* grid = [MPDecimal decimalWithInt64: gridSize.x shift: gridSize.shift];
	
	MPVector2D* startLoc = cycle0.sourceVertex.mpPosition;
	MPVector2D* endLoc = cycle0.limitingEdgeCrashLocation;
	
	
	MPVector2D* r = cycle0.mpDirection;
	
	long stepx = [r.x compareToZero];
	long stepy = [r.y compareToZero];
	
	MPVector2D* pos = [startLoc divToFloor: grid];
	MPVector2D* end = [endLoc divToFloor: grid];
	
	v3i_t starti = [pos toVectorWithShift: 0];
	v3i_t endi = [end toVectorWithShift: 0];
	
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
		
		for (PSMotorcycle* cycle1 in cell.motorcycles)
		{
			if (cycle1 == cycle0)
				continue;
			
			MPVector2D* X = _crashLocationMM(cycle0, cycle1);

			if (X)
				if(![cycle0.leftEdge mpVertexInPositiveHalfPlane: X] || ![cycle0.rightEdge mpVertexInPositiveHalfPlane: X] || ![cycle1.leftEdge mpVertexInPositiveHalfPlane: X] || ![cycle1.rightEdge mpVertexInPositiveHalfPlane: X])
				X = nil;
			
			
			
			v3i_t xloc = [X toVectorWithShift: 16];
			
			if (X)
			{
				//assert(fabs([cycle0 angleToLocation: X]) < 100.0*FLT_EPSILON);
				//assert(fabs([cycle1 angleToLocation: X]) < 100.0*FLT_EPSILON);
				
				MPDecimal* ta0 = [cycle0.leftEdge timeSqrToLocation: X];
				MPDecimal* ta1 = [cycle0.rightEdge timeSqrToLocation: X];
				MPDecimal* tb0 = [cycle1.leftEdge timeSqrToLocation: X];
				MPDecimal* tb1 = [cycle1.rightEdge timeSqrToLocation: X];
				
				MPDecimal* ta = [ta0 max: ta1];
				MPDecimal* tb = [tb0 max: tb1];
				MPDecimal* hitTime = [ta max: tb];
				id survivor = nil;
				id crasher = nil;
				MPDecimal* ts = nil, *tc = nil;
				
				NSComparisonResult cmpab = [ta compare: tb];
				
				if (cmpab == 0)
				{
					MPVector2D* P = cycle0.sourceVertex.mpPosition;
					MPVector2D* Q = cycle1.sourceVertex.mpPosition;
					
					cmpab = [P.x compare: Q.x];
					
					if (cmpab == 0)
						cmpab = [P.y compare: Q.y];
				}
				
				if (cmpab < 0)
				{
					ts = ta;
					tc = tb;
					survivor = cycle0;
					crasher = cycle1;
				}
				else if (cmpab > 0)
				{
					ts = tb;
					tc = ta;
					survivor = cycle1;
					crasher = cycle0;
				}
				else
					assert(0);
				
				if (cycle0 != crasher)
					continue;
				
				PSMotorcycleMotorcycleCrash* crash = [[PSMotorcycleMotorcycleCrash alloc] init];
				
				crash.cycle0 = crasher;
				crash.cycle1 = survivor;
				crash.crashTimeSqr = hitTime;
				crash.time0Sqr = tc;
				crash.time1Sqr = ts;
				crash.location = xloc;
								
				[crashes addObject: crash];
				[crash.cycle0.crashQueue addObject: crash];
				
				
			}
		}
			
	};
	
	
	v3i_t posi = starti;
	visitCellBlock(posi);
	
	
	while (!v3iEqual(posi, endi))
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
	}

	return crashes;
}

@end

@implementation PSSpatialHashCell

@synthesize edgeSegments, motorcycles;

- (id) init
{	
	if (!(self = [super init]))
		return nil;
	
	edgeSegments = [NSMutableSet set];
	motorcycles = [NSMutableSet set];
	
	return self;
}

@end
