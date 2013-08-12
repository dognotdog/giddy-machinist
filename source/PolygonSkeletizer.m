 //
//  PolygonSkeletizer.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 23.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import "PolygonSkeletizer.h"

#import "gfx.h"
#import "VectorMath.h"
#import "VectorMath_fixp.h"
#import "FoundationExtensions.h"
#import "PolygonSkeletizerObjects.h"
#import "PSSpatialHash.h"
#import "PSWaveFrontSnapshot.h"
#import "PriorityQueue.h"
#import "MPVector2D.h"
#import "MPInteger.h"

@implementation PolygonSkeletizer
{
	NSArray* vertices;
	NSArray* originalVertices;
	NSArray* edgeLoops;
	
	
	NSMutableArray* traceCrashVertices;
	NSMutableArray* interiorVertices;
	
	NSMutableArray* terminatedMotorcycles;
	NSMutableSet* terminatedSpokes;
	NSMutableArray* terminatedWaveFronts;
	
	NSMutableArray* outlineMeshes;
	
	PriorityQueue* motorcycleCrashes;
	//PriorityQueue* motorcycleEdgeCrashes;
	//NSMutableDictionary* motorcycleMotorcycleCrashes;
	
}

@synthesize extensionLimit, mergeThreshold, eventCallback, emitCallback, emissionTimes;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	extensionLimit = 500.0;
	mergeThreshold = 0.001;
	
	vertices = [NSArray array];
	originalVertices = [NSArray array];
	traceCrashVertices = [NSMutableArray array];
	interiorVertices = [NSMutableArray array];
	edgeLoops = [NSArray array];
	terminatedMotorcycles = [NSMutableArray array];
	terminatedSpokes = [NSMutableSet set];
	terminatedWaveFronts = [NSMutableArray array];
	
	outlineMeshes = [NSMutableArray array];
	
	motorcycleCrashes = [[PriorityQueue alloc] initWithCompareBlock:^NSComparisonResult(PSMotorcycleCrash* obj0, PSMotorcycleCrash* obj1) {
		MPDecimal* t0 = obj0.crashTimeSqr;
		MPDecimal* t1 = obj1.crashTimeSqr;
		
		return [t0 compare: t1];
	}];
	//motorcycleMotorcycleCrashes = [NSMutableDictionary dictionary];
	
	emissionTimes = @[@1.0, @2.0, @5.0, @10.0, @11.0, @12.0,@13.0,@14.0, @15.0, @16.0,@17.0,@18.0,@19.0, @20.0, @25.0, @30.0, @35.0, @40.0, @45.0, @50.0];

	return self;
}

- (void) dealloc
{
}



static inline v3i_t _edgeToNormal(v3i_t e)
{
	// does not set length to unity!!!
	return v3iCreate(-e.y, e.x, 0, e.shift);
}

static inline v3i_t _normalToEdge(v3i_t n)
{
	return v3iCreate(n.y, -n.x, 0, n.shift);
}


- (void) addClosedPolygonWithVertices: (v3i_t*) vv count: (size_t) vcount
{
	NSMutableArray* newVertices = [NSMutableArray arrayWithCapacity: vcount];
	NSMutableArray* newEdges = [NSMutableArray arrayWithCapacity: vcount];

	
	
	for (long i = 0; i < vcount; ++i)
	{
		PSSourceVertex* vertex = [[PSSourceVertex alloc] init];
		vertex.position = vv[i];
		[newVertices addObject: vertex];
	}
	for (long i = 0; i < vcount; ++i)
	{
		PSSourceEdge* edge = [[PSSourceEdge alloc] init];
		edge.leftVertex = [newVertices objectAtIndex: i];
		edge.rightVertex = [newVertices objectAtIndex: (i+1) % vcount];
		edge.leftVertex.rightEdge = edge;;
		edge.rightVertex.leftEdge = edge;
		v3i_t a = edge.leftVertex.position;
		v3i_t b = edge.rightVertex.position;
		v3i_t e = v3iSub(b, a);
		edge.edge = e;
		
	//	assert(vLength(e) >= mergeThreshold);
		
		[newEdges addObject: edge];
	}

	edgeLoops = [edgeLoops arrayByAddingObject: newEdges];
	vertices = [vertices arrayByAddingObjectsFromArray: newVertices];
	originalVertices = [originalVertices arrayByAddingObjectsFromArray: newVertices];

}

vector_t bisectorVelocity(vector_t v0, vector_t v1, vector_t e0, vector_t e1)
{
	assert(v0.farr[2] == 0.0);
	assert(v1.farr[2] == 0.0);
	assert(e0.farr[2] == 0.0);
	assert(e1.farr[2] == 0.0);
	double lv0 = vLength(v0);
	double lv1 = vLength(v1);
	double vx = vCross(v0, v1).farr[2]/(lv0*lv1);
	double vd = vDot(v0, v1)/(lv0*lv1);
	
	vector_t s = vCreateDir(0.0, 0.0, 0.0);
	
	
	if (fabs(vx) < 1.0*sqrt(FLT_EPSILON) && (vd > 0))// nearly parallel, threshold is a guess
	{
		s = v3MulScalar(v3Add(v0, v1), 0.5);
		//NSLog(@"nearly parallel %g, %g / %g, %g", v0.x, v0.y, v1.x, v1.y);
	}
	else if ((fabs(vx) < 1.0*(FLT_EPSILON)) && (vd < 0)) // anti-parallel case
	{
		//vector_t ee = v3MulScalar(v3Add(vNegate(e0), e1), 0.5);
		//double halfAngle = 0.5*atan2(vx, vd);
		s = v3Add(vReverseProject(v0, e1), vReverseProject(v1, e0));
		
	}
	else
	{
		s = v3Add(vReverseProject(v0, e1), vReverseProject(v1, e0));
	}
	
	return s;
	
}

/* unused
static v3l_t _intToLongVector(v3i_t a, long shift)
{
	assert(shift > 0);
	return (v3l_t){((vmlong_t)a.x) << shift, ((vmlong_t)a.y) << shift, ((vmlong_t)a.z) << shift, a.shift + shift};
}

static v3i_t _longToIntVector(v3l_t a, long rshift)
{
	vmlong_t x = a.x >> rshift;
	vmlong_t y = a.y >> rshift;
	vmlong_t z = a.z >> rshift;
	
	assert(x <= INT32_MAX);
	assert(x >= INT32_MIN);
	assert(y <= INT32_MAX);
	assert(y >= INT32_MIN);
	assert(z <= INT32_MAX);
	assert(z >= INT32_MIN);

	return (v3i_t){x, y, z, a.shift - rshift};
}
*/

static inline vmlongfix_t lfixdiv(vmlongfix_t a, vmlongfix_t b)
{
	vmlonger_t x = (vmlonger_t)a.x/b.x;
	return (vmlongfix_t){x, a.shift-b.shift};
}

static inline v3l_t v3lScaleFloor(v3l_t a, vmlongfix_t num, vmlongfix_t den)
{
	vmlonger_t xn = (vmlonger_t)a.x*num.x;
	vmlonger_t yn = (vmlonger_t)a.y*num.x;
	vmlonger_t zn = (vmlonger_t)a.z*num.x;
	
	vmlonger_t x = xn/den.x;
	vmlonger_t y = yn/den.x;
	vmlonger_t z = zn/den.x;
	
	assert(x <= INT64_MAX);
	assert(x >= INT64_MIN);
	assert(y <= INT64_MAX);
	assert(y >= INT64_MIN);
	assert(z <= INT64_MAX);
	assert(z >= INT64_MIN);
	
	return (v3l_t){x, y, z, a.shift + num.shift - den.shift};
}

static long _locationOnEdge_boxTest(v3i_t A, v3i_t B, v3i_t x)
{
	r3i_t r = riCreateFromVectors(A,B);
	
	return riContainsVector2D(r, x);
}

static long _locationOnRayHalfPlaneTest(v3i_t R, v3i_t X)
{
	return v3iDot(R, X).x > 0;
}

static v3i_t _rotateEdgeToNormal(v3i_t E)
{
	return v3iCreate(-E.y, E.x, E.z, E.shift);
}


static MPDecimal* _maxTimeSqrFromEdges(NSArray* edges, MPVector2D* X)
{
	MPDecimal* maxTime = [[MPDecimal alloc] initWithInt64: 0 shift: 0];
	for (PSEdge* edge in edges)
	{
		MPDecimal* tASqr = [edge timeSqrToLocation: X];
		
		maxTime = [maxTime max: tASqr];
	}
	
	return maxTime;
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

/*!
 checks for crashes between angular bisectors. conditionally ignores crashes with infinte velocity spokes
 */
static MPVector2D* _crashLocationBisectors(MPVector2D* B, MPVector2D* E_AB, MPVector2D* E_BC, MPVector2D* V, MPVector2D* E_UV, MPVector2D* E_VW, BOOL ignoreFastSpokes)
{
	assert(B);
	assert(E_AB);
	assert(E_BC);
	assert(V);
	assert(E_UV);
	assert(E_VW);
	
	MPDecimal* E_ABxBC = [E_AB cross: E_BC];
	MPDecimal* E_UVxVW = [E_UV cross: E_VW];
	MPDecimal* E_ABdBC = [E_AB dot: E_BC];
	MPDecimal* E_UVdVW = [E_UV dot: E_VW];

	BOOL fast0 = E_ABxBC.isZero;
	BOOL fast1 = E_UVxVW.isZero;
	
	if (ignoreFastSpokes && (fast0 || fast1)) // ignore intersects with fast spokes
	{
		return nil;
	}
	

	MPDecimal* l_E_AB = [E_AB length];
	MPDecimal* l_E_BC = [E_BC length];
	MPDecimal* l_E_UV = [E_UV length];
	MPDecimal* l_E_VW = [E_VW length];
	
	MPVector2D* E_ABC = [[E_BC scale: l_E_AB] sub: [E_AB scale: l_E_BC]];
	MPVector2D* E_UVW = [[E_VW scale: l_E_UV] sub: [E_UV scale: l_E_VW]];
	
	if (E_ABxBC.isZero)
	{
		if (E_ABdBC.isPositive)
		{
			MPVector2D* E = [E_BC add: E_AB];
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
	

	//MPVector2D* R = ma.mpVelocity;
	//MPVector2D* S = mb.mpVelocity;
	
	MPDecimal* denum = [E_ABC cross: E_UVW];
	
	
	if (!denum.isZero)
	{
		MPVector2D* RQS = [E_ABC scale: [V cross: E_UVW]];
		MPVector2D* SPR = [E_UVW scale: [B cross: E_ABC]];
		MPVector2D* XD = [RQS sub: SPR];
		
		MPVector2D* X = [XD scaleNum: [MPDecimal one] den: denum];
		
		return X;
	}
	else
	{
		// either the two spokes are parallel or anti-parallel.
		// if they're anti-parallel, they're defined to meet in the middle, but only under special circumstances that are outside the scope of this function.
		// if they're parallel, never meet
		MPDecimal* dot = [E_ABC dot: E_UVW];
		if (dot.isPositive)
			return nil;
		else
			return nil;
		//return [[B add: V] scale: [MPDecimal oneHalf]];
		[NSException raise: @"PolgyonSkeletizer.crashException" format: @"A bisector is invalid"];
	}
	return nil;
}

static PSSpoke* _disconnectRightWaveFront(PSSpoke* spoke)
{
	//PSSpoke* leftSpoke = spoke.leftWaveFront.leftSpoke;
	PSSpoke* rightSpoke = spoke.rightWaveFront.rightSpoke;
	
	spoke.endLocation = spoke.startLocation;
	spoke.leftWaveFront.rightSpoke = spoke.rightWaveFront.rightSpoke;
	spoke.rightWaveFront.rightSpoke.leftWaveFront = spoke.leftWaveFront;
	
	//leftSpoke.rightEdge = leftSpoke.rightWaveFront.edge;
	//rightSpoke.leftEdge = rightSpoke.leftWaveFront.edge;
	
	spoke.leftWaveFront = nil;
	spoke.rightWaveFront.rightSpoke = nil;
	spoke.rightWaveFront.leftSpoke = nil;
	
	return rightSpoke;
}

static PSSpoke* _disconnectLeftWaveFront(PSSpoke* spoke)
{
	PSSpoke* leftSpoke = spoke.leftWaveFront.leftSpoke;
	//PSSpoke* rightSpoke = spoke.rightWaveFront.rightSpoke;

	spoke.endLocation = spoke.startLocation;
	spoke.rightWaveFront.leftSpoke = spoke.leftWaveFront.leftSpoke;
	spoke.leftWaveFront.leftSpoke.rightWaveFront = spoke.rightWaveFront;
	
	//leftSpoke.rightEdge = leftSpoke.rightWaveFront.edge;
	//rightSpoke.leftEdge = rightSpoke.leftWaveFront.edge;
	
	spoke.rightWaveFront = nil;
	spoke.leftWaveFront.leftSpoke = nil;
	spoke.leftWaveFront.rightSpoke = nil;
	
	return leftSpoke;
}


- (void) crashMotorcycle: (PSMotorcycle*) cycle0 intoMotorcycles: (NSArray*) motorcycles withLimit: (double) motorLimit
{
	
	NSUInteger k = [motorcycles indexOfObject: cycle0];
	for (PSMotorcycle* cycle1 in [motorcycles subarrayWithRange: NSMakeRange(k+1, [motorcycles count] - k - 1)])
	{
		
		MPVector2D* X = _crashLocationMM(cycle0, cycle1);
		
		
		if (X && (![cycle0.leftEdge mpVertexInPositiveHalfPlane: X] || ![cycle0.rightEdge mpVertexInPositiveHalfPlane: X] || ![cycle1.leftEdge mpVertexInPositiveHalfPlane: X] || ![cycle1.rightEdge mpVertexInPositiveHalfPlane: X]))
			X = nil;
		
		
		
		v3i_t xloc = [X toVectorWithShift: 16];
		
		//xiLineSegments2DFrac(motorp, v3iAdd(motorp, motorv), cycle1.sourceVertex.position, v3iAdd(cycle1.sourceVertex.position, cycle1.velocity), &t0, &t1, &den);

				
		//vmlong_t ta = t0;
		//vmlong_t tb = t1;

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
						
			if ([ta compare: tb] < 0)
			{
				ts = ta;
				tc = tb;
				survivor = cycle0;
				crasher = cycle1;
			}
			else if ([ta compare: tb] > 0)
			{
				ts = tb;
				tc = ta;
				survivor = cycle1;
				crasher = cycle0;
			}
			else // same time
			{
				NSComparisonResult cmpx = [[cycle0.mpDirection cross: cycle1.mpDirection] compare: [MPDecimal zero]];
				if (cmpx > 0)
				{
					ts = tb;
					tc = ta;
					survivor = cycle1;
					crasher = cycle0;
				}
				else if (cmpx < 0)
				{
					ts = ta;
					tc = tb;
					survivor = cycle0;
					crasher = cycle1;
				}
				else
					assert(0); // if their cross product is zero, wtf
			}
			
			PSMotorcycleMotorcycleCrash* crash = [[PSMotorcycleMotorcycleCrash alloc] init];
			
			crash.cycle0 = crasher;
			crash.cycle1 = survivor;
			crash.crashTimeSqr = hitTime;
			crash.time0Sqr = tc;
			crash.time1Sqr = ts;
			crash.location = xloc;
			
			//id key = [NSValue valueWithPointer: (__bridge void*)crasher];
			
			[motorcycleCrashes addObject: crash];
			[crash.cycle0.crashQueue addObject: crash];
			//[crash.cycle1.crashQueue addObject: crash]; // survivor doesn't care, isn't affected by crash
					  

		}

	}

}

/*
static double _lltodouble(vmlongerfix_t a)
{
	double x = a.x;
	x *= ((vmlonger_t)1 << a.shift);
	return x;
}
*/
- (NSArray*) crashMotorcycles: (NSArray*) motorcycles atTime: (double) time withLimit: (double) motorLimit executedCrashes: (NSSet*) executedCrashes
{
	// prune expired events
	
	while (motorcycleCrashes.count)
	{
		PSMotorcycleCrash* crash = motorcycleCrashes.firstObject;
		
		// purge events at beginning if they refer to terminated cycles
		if (crash.cycle0.terminationTime)
		{
			[motorcycleCrashes popFirstObject];
		}
		else
			break;
		
	}	
	
	return motorcycleCrashes.count ? @[[motorcycleCrashes popFirstObject]] : @[];
}


- (void) runMotorcycles
{
//	assert([edges count] == [vertices count]);
	
	NSMutableArray* eventLog = [NSMutableArray array];
	
	r3i_t mr = riInfRange([(PSSourceVertex*)[vertices lastObject] position].shift);
	
	for (PSSourceVertex* vertex in vertices)
	{
		mr = riUnionRange(mr, riCreateFromVectors(vertex.position, vertex.position));
	}
	
	v3i_t rr = v3iSub(mr.max, mr.min);
	
	MPVector2D* RR = [MPVector2D vectorWith3i: rr];
	
	MPDecimal* motorLimit = [RR.x max: RR.y];
	
	

	
	// start by generating the initial motorcycles
	NSMutableArray* motorcycles = [NSMutableArray array];
	
	for (NSArray* edges in edgeLoops)
		for (PSSourceEdge* edge0 in edges)
		{
			PSSourceEdge* edge1 = edge0.rightVertex.rightEdge;
			assert(edge0.rightVertex.rightEdge);
			
			vmlongfix_t area = v3iCross2D(edge0.edge, edge1.edge);
			
			if (area.x <= 0)
			{
				PSMotorcycle* cycle = [[PSMotorcycle alloc] init];
				cycle.sourceVertex = edge0.rightVertex;
				cycle.leftEdge = edge0;
				cycle.rightEdge = edge1;
				
				/*
				MPVector2D* mpv = cycle.mpVelocity;
				
				vector_t fv = cycle.floatVelocity;
				assert(!vIsInf(fv));
				*/
				[motorcycles addObject: cycle];
				[edge0.rightVertex addMotorcycle: cycle];
			}
		}
	
	[motorcycles enumerateObjectsUsingBlock:^(PSMotorcycle* obj, NSUInteger idx, BOOL *stop) {
		obj.leftNeighbour = [motorcycles objectAtIndex: (motorcycles.count + idx-1) % motorcycles.count];
		obj.rightNeighbour = [motorcycles objectAtIndex: (idx+1) % motorcycles.count];
	}];
	
	if (motorcycles.count)
	{
		//NSLog(@"some motorcycles!");
	}
	
	// next up: figure out collisions
	/*
	 A motorcycle can collide with:
		- other motorcycles
		- polygon edges
	 */
	
	
	// build crash lists

	PSSpatialHash* spaceHash = [[PSSpatialHash alloc] initWithGridSize: (vmintfix_t){16 << 16, 16} numCells: 201];
	 
	for (NSArray* edges in edgeLoops)
	{
		@autoreleasepool {
			[spaceHash addEdgeSegments: edges];
		}
	}

	
	for (PSMotorcycle* motorcycle in motorcycles)
	{
		@autoreleasepool {
			PSMotorcycleCrash* crash = [spaceHash crashMotorcycleIntoEdges: motorcycle withLimit: motorLimit];
			
			assert(crash);
			[motorcycleCrashes addObject: crash];
			[motorcycle.crashQueue addObject: crash];
			
			motorcycle.limitingEdgeCrashLocation = [MPVector2D vectorWith3i: crash.location];
			
			//[self crashMotorcycle: motorcycle intoEdgesWithLimit: motorLimit];
		}
	}
	
	[spaceHash addMotorcycles: motorcycles];
	

	for (PSMotorcycle* motorcycle in motorcycles)
	{
		PriorityQueue* crashes = [spaceHash crashMotorcycleIntoMotorcycles: motorcycle];
		
		[motorcycleCrashes addObjectsFromArray: crashes.allObjects];
		
		//[self crashMotorcycle: motorcycle intoMotorcycles: motorcycles withLimit: motorLimit.toDouble];
	}
	
	
	// build event list

	NSMutableArray* splittingVertices = [NSMutableArray array];
	
	
	while (motorcycleCrashes.count)
	{
		while (motorcycleCrashes.count)
		{
			PSMotorcycleCrash* crash = motorcycleCrashes.firstObject;
			
			// purge events at beginning if they refer to terminated cycles
			if (crash.cycle0.terminationTime)
			{
				[motorcycleCrashes popFirstObject];
			}
			else if ([crash isKindOfClass: [PSMotorcycleMotorcycleCrash class]])
			{
				PSMotorcycleMotorcycleCrash* mcrash = (id) crash;
				if (mcrash.cycle1.terminalVertex && !_locationOnEdge_boxTest(mcrash.cycle1.sourceVertex.position, mcrash.cycle1.terminalVertex.position, crash.location))
				{
					[motorcycleCrashes popFirstObject];

				}
				else
					break;
			}
			else
				break;
			
		}
		
		if (!motorcycleCrashes.count)
			break;

		PSMotorcycleCrash* crash = [motorcycleCrashes popFirstObject];
			
		[eventLog addObject: [NSString stringWithFormat: @"%f: processing crash", (crash.crashTimeSqr.toDouble)]];
			
			
		if ([crash isKindOfClass: [PSMotorcycleVertexCrash class]])
		{
			PSMotorcycleVertexCrash* vcrash = (id) crash;
			PSMotorcycle* cycle = vcrash.cycle0;
			PSRealVertex* vertex = vcrash.vertex;
			cycle.terminalVertex = vertex;
			cycle.terminationTime = vcrash.time0Sqr;
			cycle.leftNeighbour.rightNeighbour = cycle.rightNeighbour;
			cycle.rightNeighbour.leftNeighbour = cycle.leftNeighbour;
			
			[vertex addMotorcycle: cycle];

		}
		else if ([crash isKindOfClass: [PSMotorcycleEdgeCrash class]])
		{
			PSMotorcycleEdgeCrash* ecrash = (id) crash;
			PSMotorcycle* cycle = ecrash.cycle0;
			PSRealVertex* vertex = [cycle getVertexOnMotorcycleAtLocation: crash.location];
			
			if (!vertex)
			{
				vertex = [[PSCrashVertex alloc] init];
				vertex.position = crash.location;
				[interiorVertices addObject: vertex];
			}
			cycle.terminationTime = ecrash.time0Sqr;
			cycle.terminalVertex = vertex;
			cycle.leftNeighbour.rightNeighbour = cycle.rightNeighbour;
			cycle.rightNeighbour.leftNeighbour = cycle.leftNeighbour;
			
			[vertex addMotorcycle: cycle];
			
			[ecrash.edge1 addSplittingMotorcycle: cycle];
			
			[splittingVertices addObject: @[ecrash, vertex]];
			
			
		}
		else if ([crash isKindOfClass: [PSMotorcycleMotorcycleCrash class]])
		{
			PSMotorcycleMotorcycleCrash* mcrash = (id) crash;
			
			PSMotorcycle* crasher = mcrash.cycle0;
			PSMotorcycle* survivor = mcrash.cycle1;
			crasher.terminationTime = mcrash.time0Sqr;
			
			
			PSRealVertex* vertex = [survivor getVertexOnMotorcycleAtLocation: crash.location];
			if (!vertex)
			{
				vertex = [crasher getVertexOnMotorcycleAtLocation: crash.location];
			}
			if (!vertex)
			{
				vertex = [[PSCrashVertex alloc] init];
				vertex.position = crash.location;
				[interiorVertices addObject: vertex];
			}
			
			
			crasher.terminalVertex = vertex;

			[vertex addMotorcycle: crasher];
			[vertex addMotorcycle: survivor];

		}
		else
			assert(0); // unknown crash type
		
		[terminatedMotorcycles addObject: crash.cycle0];
		[motorcycles removeObject: crash.cycle0];
		crash.cycle0.terminatingCrash = crash;
		
		
			
	}
	

#pragma mark Post-Process Edge Splits
	
	for (NSArray* info in splittingVertices)
	{
		
	}
	
#pragma mark Post-Process Motorcycles
	
	
	// check for opposing motorcycles ending on same vertices, and replace with a single motorcycle
	// FIXME: motorcycles may not share any vertex...
	
	/*
	 Conditions for opposition:
		colinear traces
		in opposite directions
		shared segment
	 easy conditions:
		shared, but opposing, source and terminal vertices
		one shared vertex, the other a crash site
	 hard condition:
		no shared vertices
		both ends crash sites
	 */
	
	// TODO: determine if this can be removed as no anti-spokes are used
	BOOL opposingMotorcyclesFound = NO;
	while (opposingMotorcyclesFound)
	{
		opposingMotorcyclesFound = NO;
		for (PSMotorcycle* cycle0 in [terminatedMotorcycles copy])
		{
			for (PSMotorcycle* cycle1 in [terminatedMotorcycles copy])
			{
				BOOL sharedEnd0 = v3iEqual(cycle0.terminalVertex.position, cycle1.sourceVertex.position);
				BOOL sharedEnd1 = v3iEqual(cycle1.terminalVertex.position, cycle0.sourceVertex.position);
				
				if (sharedEnd0 || sharedEnd1)
					sharedEnd0 = sharedEnd0;
				
				if ((cycle0.sourceVertex == cycle1.terminalVertex) && (cycle0.terminalVertex == cycle1.sourceVertex))
				{
					[terminatedMotorcycles removeObject: cycle1];
					
					[cycle1.sourceVertex removeMotorcycle: cycle1];
					[cycle1.terminalVertex removeMotorcycle: cycle1];
					
					NSArray* crashVertices = cycle1.crashVertices;
					
					for (PSCrashVertex* vertex in crashVertices)
					{
						[vertex removeMotorcycle: cycle1];
						NSArray* incoming = vertex.incomingMotorcycles;

						for (PSMotorcycle* crashedCycle in incoming)
						{
							
							crashedCycle.terminator = cycle0;
						}
						[vertex addMotorcycle: cycle0];
					}
					
					// merge crash vertices, and sort
					crashVertices = [crashVertices arrayByAddingObjectsFromArray: cycle0.crashVertices];
					
					MPVector2D* p0 = cycle0.sourceVertex.mpPosition;
					
					crashVertices = [crashVertices sortedArrayWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PSCrashVertex* obj0, PSCrashVertex* obj1) {
						MPVector2D* r0 = [obj0.mpPosition sub: p0];
						MPVector2D* r1 = [obj1.mpPosition sub: p0];
						
						MPDecimal* d0 = [r0 dot: r0];
						MPDecimal* d1 = [r1 dot: r1];
						
						
						return [d0 compare: d1];
					}];
					
					cycle0.crashVertices = crashVertices;
					
					
					opposingMotorcyclesFound = YES;
				}
				else if (
						 (cycle1.terminalVertex == cycle0.sourceVertex)
						 && (![cycle1.terminalVertex isKindOfClass: [PSCrashVertex class]])
						 && ([cycle0.terminalVertex isKindOfClass: [PSCrashVertex class]])
						 && cycle0.terminator == cycle1
						 )
				{
					// do nothing, handled when cycle0/cycle1 are checked in reverse
				}
				else if (
						 (cycle0.terminalVertex == cycle1.sourceVertex)
						 && (![cycle0.terminalVertex isKindOfClass: [PSCrashVertex class]])
						 && ([cycle1.terminalVertex isKindOfClass: [PSCrashVertex class]])
						 && cycle1.terminator == cycle0
						 )
				{
					// the wrong crash vertex should have an equivalent crash vertex on cycle0
					PSCrashVertex* wrongCrashVertex = (id)cycle1.terminalVertex;
					
					//NSLog(@"fixing asymmetric opposing motorcycles");
					
					assert(wrongCrashVertex.outgoingMotorcycles.count == 1);
					
					PSMotorcycle* outCycle = [wrongCrashVertex.outgoingMotorcycles lastObject];
					outCycle.crashVertices = [outCycle.crashVertices arrayByRemovingObject: wrongCrashVertex];
					
					vertices = [vertices arrayByRemovingObject: wrongCrashVertex];
					[traceCrashVertices removeObject: wrongCrashVertex];
					
					
					[terminatedMotorcycles removeObject: cycle1];
					
					[cycle1.sourceVertex removeMotorcycle: cycle1];
					[cycle1.terminalVertex removeMotorcycle: cycle1];
					
					NSArray* crashVertices = cycle1.crashVertices;
					
					for (PSCrashVertex* vertex in crashVertices)
					{
						
						
						
						[vertex removeMotorcycle: cycle1];
						NSArray* incoming = vertex.incomingMotorcycles;
						
						for (PSMotorcycle* crashedCycle in incoming)
						{							
							crashedCycle.terminator = cycle0;
						}
						[vertex addMotorcycle: cycle0];
					}
					
					// merge crash vertices, and sort
					crashVertices = [crashVertices arrayByAddingObjectsFromArray: cycle0.crashVertices];
					
					MPVector2D* p0 = cycle0.sourceVertex.mpPosition;
					
					crashVertices = [crashVertices sortedArrayWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PSCrashVertex* obj0, PSCrashVertex* obj1) {
						MPVector2D* r0 = [obj0.mpPosition sub: p0];
						MPVector2D* r1 = [obj1.mpPosition sub: p0];
						
						MPDecimal* d0 = [r0 dot: r0];
						MPDecimal* d1 = [r1 dot: r1];
						
						
						return [d0 compare: d1];
					}];
					
					cycle0.crashVertices = crashVertices;
					
					opposingMotorcyclesFound = YES;
				}
				/*
				else if (_terminatedMotorcyclesOpposing(cycle0, cycle1))
					assert(0); // FIXME: not implemented yet
				*/
				
				if (opposingMotorcyclesFound)
					break;
			}
			if (opposingMotorcyclesFound)
				break;
		}
	}
	
	// we shouldn't have any motorcycles left at this point. But if we do, we want to see them
	
	for (PSMotorcycle* cycle in motorcycles)
	{
		// FIXME: no cycles should have remained at this point
		assert(0);
		/*
		PSVertex* vertex = [[PSVertex alloc] init];
		vertex.position = v3Add(cycle.sourceVertex.position, v3MulScalar(cycle.velocity, motorLimit*2.0));
		vertices = [vertices arrayByAddingObject: vertex];
		
		cycle.terminalVertex = vertex;
		
		assert(!vIsNAN(vertex.position));
		
		assert(![terminatedMotorcycles containsObject: cycle]);
		terminatedMotorcycles = [terminatedMotorcycles arrayByAddingObject: cycle];
		 */
	}
	
	//assert(motorcycles.count == 0);
		
}

/*
static vector_t _spokeVertexAtTime(ps_spoke_t spoke, ps_vertex_t* vertices, double t)
{
	vector_t v = spoke.velocity;
	vector_t x = vertices[spoke.sourceVertex].position;
	return v3Add(x, v3MulScalar(v, t - spoke.start));
}

static inline int _eventSorter(const void * a, const void * b)
{
	const ps_event_t* e0 = a;
	const ps_event_t* e1 = b;
	double t0 = e0->time, t1 = e1->time;
	if (t0 < t1)
		return 1; // sort in descending order
	else if (t0 > t1)
		return -1;
	else return 0;
	
}
static size_t _findBigger(ps_event_t* events, size_t start, size_t end, double refTime)
{
	size_t pivot = (start+end)/2;
	
	if (start+1 >= end)
		return start;
	
	if (events[pivot].time < refTime)
		return _findBigger(events, start, pivot, refTime);
	else
		return _findBigger(events, pivot, end, refTime);
}
 */

- (NSArray*) insertEvent: (PSEvent*) event intoArray: (NSArray*) events
{

	return [events arrayByAddingObject: event];
	
/*
	size_t insertionPoint = _findBigger(events, 0, numEvents, event.time);
	
	memcpy(events + insertionPoint+1, events + insertionPoint, sizeof(*events)*(numEvents-insertionPoint));
	events[insertionPoint] = event;
*/
	
}

static BOOL _spokesSameDir(PSSimpleSpoke* spoke0, PSSimpleSpoke* spoke1)
{
	vector_t v0 = spoke0.floatVelocity;
	vector_t v1 = spoke1.floatVelocity;
	
	if (vLength(v0) == 0.0)
		return NO;
	if (vLength(v1) == 0.0)
		return NO;
	
	double angle = atan2(vCross(v0, v1).farr[2], vDot(v0, v1));
	
	return (fabs(angle) < FLT_EPSILON);
	
}

static BOOL _isSpokeUnique(PSSimpleSpoke* uspoke, NSArray* spokes)
{
	if (vLength(uspoke.floatVelocity) == 0.0)
		return YES;
	for (PSSimpleSpoke * spoke in spokes)
	{
		if (_spokesSameDir(spoke, uspoke))
			return NO;
	}
	return YES;
}

static void _assertSpokeUnique(PSSimpleSpoke* uspoke, NSArray* spokes)
{
	assert(_isSpokeUnique(uspoke, spokes));
}


static void _generateCycleSpoke(PSMotorcycle* cycle, NSMutableArray* spokes)
{
	PSRealVertex* vertex = cycle.sourceVertex;
	PSMotorcycleSpoke* spoke = [[PSMotorcycleSpoke alloc] init];
	spoke.sourceVertex = vertex;
	spoke.motorcycle = cycle;
	cycle.spoke = spoke;
	spoke.leftEdge = cycle.leftEdge;
	spoke.rightEdge = cycle.rightEdge;

	spoke.startLocation = vertex.position;
	spoke.startTimeSqr = [MPDecimal zero];
	
	[spokes addObject: spoke];
	_assertSpokeUnique(spoke, vertex.outgoingSpokes);
	[vertex addSpoke: spoke];
	
	//PSVertex* antiVertex = cycle.terminalVertex;
	
	
	
}

#if 0

static NSBezierPath* _bezierPathFromOffsetSegments(vector_t* vertices, size_t numVertices)
{
	NSBezierPath* path = [NSBezierPath bezierPath];
	
	assert(numVertices % 2 == 0);
	
	vector_t lastVertex = vZero();
	vector_t loopVertex = vZero();
	
	for (size_t i = 0; i < numVertices/2; ++i)
	{
		vector_t a = vertices[2*i+0];
		vector_t b = vertices[2*i+1];
		if (i == 0)
		{
			[path moveToPoint: NSMakePoint(a.farr[0], a.farr[1])];
			[path lineToPoint: NSMakePoint(b.farr[0], b.farr[1])];
			loopVertex = a;
			lastVertex = b;
		}
		else
		{
			
			if (vEqualWithin3D(a, lastVertex, FLT_EPSILON))
			{
				if (v3Equal(b, loopVertex))
					[path closePath];
				else
					[path lineToPoint: NSMakePoint(b.farr[0], vertices[2*i+1].farr[1])];
				lastVertex = b;
			}
			else
			{
				[path moveToPoint: NSMakePoint(a.farr[0], a.farr[1])];
				[path lineToPoint: NSMakePoint(b.farr[0], b.farr[1])];
				loopVertex = a;
				lastVertex = b;
			}
			
		}
	}
	
	
	return path;
}

- (NSBezierPath*) bezierPathFromOffsetSegments: (vector_t*) vs count: (size_t) count
{
	return _bezierPathFromOffsetSegments(vs, count);
}

#endif


MPVector2D* PSIntersectSpokes(PSSpoke* spoke0, PSSpoke* spoke1)
{
	PSEdge* edgeAB = spoke0.leftEdge;
	PSEdge* edgeBC = spoke0.rightEdge;
	PSEdge* edgeUV = spoke1.leftEdge;
	PSEdge* edgeVW = spoke1.rightEdge;
	
	assert(edgeAB);
	assert(edgeBC);
	assert(edgeUV);
	assert(edgeVW);
	
	assert(spoke1 != spoke0);
	
	assert(spoke0.sourceVertex.mpPosition);
	assert(spoke1.sourceVertex.mpPosition);
	
		
	MPVector2D* X = _crashLocationBisectors(spoke0.sourceVertex.mpPosition, edgeAB.mpEdge, edgeBC.mpEdge, spoke1.sourceVertex.mpPosition, edgeUV.mpEdge, edgeVW.mpEdge, YES);
	
	
	
	if (!X)
		return nil;
	
	// intersections outside of fixed point working space do not interest us
	if ((X.x.integerBits > 15) || (X.y.integerBits > 15))
	{
		return nil;
	}
		
	//if (!_mpLocationOnRayHalfPlaneTest(spoke0.mpDirection, [X sub: spoke0.sourceVertex.mpPosition]))
	if (![spoke0.leftEdge mpVertexInPositiveHalfPlane: X] || ![spoke0.rightEdge mpVertexInPositiveHalfPlane: X])
		return nil;
	if (![spoke1.leftEdge mpVertexInPositiveHalfPlane: X] || ![spoke1.rightEdge mpVertexInPositiveHalfPlane: X])
		return nil;
	
	return X;
}



static MPVector2D* _splitLocation(PSMotorcycleSpoke* mspoke)
{
	PSWaveFront* waveFront = mspoke.opposingWaveFront;
	assert(waveFront);
	assert(mspoke.motorcycle.sourceVertex);
	assert(waveFront.edge);
	
	
	
	v3i_t we = waveFront.edge.edge;
	v3i_t wn = _rotateEdgeToNormal(we);
	
	assert(mspoke.mpNumerator && !(mspoke.mpNumerator.x.isZero && mspoke.mpNumerator.y.isZero));
	MPDecimal* xx = [mspoke.mpDirection dot: [MPVector2D vectorWith3i: wn]];
	
	
	if (xx.isPositive || xx.isZero)
	{
		return nil;
	}
	
	MPVector2D* D = mspoke.mpNumerator;
	MPDecimal* d = mspoke.mpDenominator;
	
	MPVector2D* E = waveFront.edge.mpEdge;
	MPDecimal* El = E.length;
//	MPDecimal* EE = [E dot: E];
//	MPVector2D* N = E.rotateCCW;
	
	MPVector2D* V = mspoke.opposingWaveFront.edge.leftVertex.mpPosition;
	MPVector2D* B = mspoke.sourceVertex.mpPosition;
	
	
	MPDecimal* nom = [[V sub: B] cross: E];
	MPDecimal* den = [[D cross: E] add: [d mul: El]];

	MPVector2D* uR = [D scaleNum: nom den: den];
	MPVector2D* X = [B add: uR];
	
	if (X.minIntegerBits > 15)
		return nil;

	assert([waveFront.edge mpVertexInPositiveHalfPlane: X]);
	
	return X;
}



- (void) terminateWaveFront: (PSWaveFront*) waveFront atLocation: (v3i_t) loc
{
	waveFront.endLocation = loc;
	
	waveFront.terminationTimeSqr = [waveFront.edge timeSqrToLocation: [MPVector2D vectorWith3i: loc]];
	assert(waveFront.terminationTimeSqr);
	
	[terminatedWaveFronts addObject: waveFront];
}

static void _assertSpokeConsistent(PSSpoke* spoke)
{
	assert((spoke.leftWaveFront.rightSpoke == spoke));
	assert(spoke.rightWaveFront.leftSpoke == spoke);
	assert((spoke.rightWaveFront != spoke.leftWaveFront) || [spoke isKindOfClass: [PSDegenerateSpoke class]]);
	
}

static void _assertWaveFrontConsistent(PSWaveFront* waveFront)
{
	assert((waveFront.leftSpoke != waveFront.rightSpoke) || [waveFront.leftSpoke isKindOfClass: [PSDegenerateSpoke class]]);
	assert(waveFront.leftSpoke.rightWaveFront == waveFront);
	assert(waveFront.rightSpoke.leftWaveFront == waveFront);

	_assertSpokeConsistent(waveFront.leftSpoke);
	_assertSpokeConsistent(waveFront.rightSpoke);
	
	for (PSMotorcycleSpoke* spoke in waveFront.opposingSpokes)
	{
		assert(spoke.opposingWaveFront == waveFront);
	}
	
}

static void _assertWaveFrontsConsistent(NSArray* waveFronts)
{
	for (PSWaveFront* waveFront in waveFronts)
		_assertWaveFrontConsistent(waveFront);
}


- (PSEvent*) computeNextEventForMotorcycleSpoke: (PSMotorcycleSpoke*) mspoke atTime: (MPDecimal*) t0
{
	PSMotorcycle* cycle = mspoke.motorcycle;
	PSWaveFront* waveFront = mspoke.opposingWaveFront;
	
	if (!waveFront)
		return nil;
	if ((waveFront == mspoke.leftWaveFront) || (waveFront == mspoke.rightWaveFront))
		return nil;

	assert(cycle && waveFront);
	
	PSSpoke* leftSpoke = waveFront.leftSpoke;
	PSSpoke* rightSpoke = waveFront.rightSpoke;
	
	// FIXME: figure out how to cull swap/split events based on:
	// - is the split location inside both left and right spoke
	// - does the motorcycle spoke cross the left/right spokes from the outside
	
	
	
	// make list of possible events
	NSMutableArray* candidates = [NSMutableArray array];
	
	MPVector2D* xSplit = _splitLocation(mspoke);
	{
		
		if (xSplit)
		{
			BOOL shouldSplitLeft = [mspoke.leftWaveFront isWeaklyConvexTo: mspoke.opposingWaveFront];
			BOOL shouldSplitRight = [mspoke.opposingWaveFront isWeaklyConvexTo: mspoke.rightWaveFront];
			
			// FIXME: when terminating in motorcycle crash,
			// split should only occur AFTER split wavefront passed terminating point

			
			NSArray* timingEdges = @[mspoke.leftEdge, mspoke.rightEdge, waveFront.edge];
			
			/* FIXME: not needed test?
			if ([mspoke.motorcycle.terminator isKindOfClass: [PSMotorcycle class]])
			{
				PSMotorcycleSpoke* tspoke = ((PSMotorcycle*)mspoke.motorcycle.terminator).spoke;
				if ((tspoke == mspoke.opposingWaveFront.leftSpoke) || (tspoke == mspoke.opposingWaveFront.rightSpoke))
				{
					timingEdges = [timingEdges arrayByAddingObjectsFromArray: @[tspoke.leftEdge, tspoke.rightEdge]];
				}
			}
			 */
			//v3i_t x = [xSplit toVectorWithShift: 16];
			assert(mspoke.motorcycle.terminalVertex);
			
			//BOOL splitAtTerminal = v3iEqual(x, mspoke.motorcycle.terminalVertex.position);
			//splitAtTerminal = NO; // FIXME: setting to NO for testing
			// if split is at terminal vertex, and two motorcycles not opposing, dont split
			
			//MPVector2D* mdir = mspoke.mpDirection;
			
			
			if (shouldSplitLeft && shouldSplitRight)
				[candidates addObject: @[ xSplit, timingEdges, [[PSSplitEvent alloc] initWithLocation: xSplit time: nil creationTime: t0 motorcycleSpoke: mspoke] ] ];
		}
	}
	
	{
		MPVector2D* xLeftSwap = PSIntersectSpokes(leftSpoke, mspoke);
				
		BOOL swapOut = (mspoke.opposingWaveFront != leftSpoke.rightWaveFront);
		
		if (xLeftSwap && swapOut)
			[candidates addObject: @[ xLeftSwap, @[leftSpoke.leftEdge, leftSpoke.rightEdge], [[PSSwapEvent alloc] initWithLocation: xLeftSwap time: nil creationTime: t0 motorcycleSpoke: mspoke pivotSpoke: leftSpoke] ] ];
	}
	{
		MPVector2D* xRightSwap = PSIntersectSpokes(rightSpoke, mspoke);
		
		BOOL swapOut = (mspoke.opposingWaveFront != rightSpoke.leftWaveFront);
		if (xRightSwap && swapOut)
			[candidates addObject: @[ xRightSwap, @[rightSpoke.leftEdge, rightSpoke.rightEdge], [[PSSwapEvent alloc] initWithLocation: xRightSwap time: nil creationTime: t0 motorcycleSpoke: mspoke pivotSpoke: rightSpoke] ] ];
	}
	
	// cull locations in wrong half plane
	candidates = [candidates select: ^BOOL(NSArray* candidate) {
		
		MPVector2D* X = [candidate objectAtIndex: 0];
		NSArray* edges = [candidate objectAtIndex: 1];
		
		BOOL ok = YES;
		for (PSEdge* edge in edges)
		{
			ok = ok && [edge mpVertexInPositiveHalfPlane: X];
		}
		
		return ok;
		
	}].mutableCopy;
	
	// figure out times
	candidates = [candidates map: ^id(NSArray* candidate) {
		
		MPVector2D* X = [candidate objectAtIndex: 0];
		NSArray* edges = [candidate objectAtIndex: 1];
		
		MPDecimal* tSqr = _maxTimeSqrFromEdges(edges, X);
		
		PSEvent* event = candidate.lastObject;
		event.timeSqr = tSqr;
		
		return candidate;
		
	}].mutableCopy;
	
	// sort by time, ascending
	[candidates sortWithOptions: NSSortStable usingComparator: ^NSComparisonResult(NSArray* obj0, NSArray* obj1) {
		return [(PSEvent*)obj0.lastObject compare: (PSEvent*)obj1.lastObject];
	}];
	
	if (candidates.count)
	{
		PSEvent* event = [[candidates objectAtIndex: 0] lastObject];
		
		return event;
	}
	
	return nil;
}

- (PSEvent*) computeCollapseEventForWaveFront: (PSWaveFront*) waveFront atTime: (MPDecimal* ) t0
{
	assert(waveFront);
	assert(waveFront.leftSpoke);
	assert(waveFront.rightSpoke);
	
	{
		PSCollapseEvent* previousCollapse = waveFront.collapseEvent;
		
		if (previousCollapse)
			return previousCollapse;
		else
			waveFront.collapseEvent = nil;
	}

// remove test and move to dependency check phase in main loop
//	if (waveFront.opposingSpokes.count) // not allowed to collapse with inbound splitting spoke
//		return nil;
	
	MPVector2D* X = waveFront.computeCollapseLocation;
	
	MPDecimal* maxTimeSqr = [MPDecimal largerThan32Sqr];

	PSSpoke* leftSpoke = waveFront.leftSpoke;
	PSSpoke* rightSpoke = waveFront.rightSpoke;
	
	if (X)
	{
		// we don't actually care for waveFront.edge, as for the new spoke the two neighbours matter
		MPDecimal* tSqr = _maxTimeSqrFromEdges(@[leftSpoke.leftEdge, rightSpoke.rightEdge], X);
		
		if (([tSqr compare: maxTimeSqr] == NSOrderedAscending))
		//	if (([tSqr compare: maxTimeSqr] < 0) && ([tSqr compare: t0] >= 0))
		{
			PSCollapseEvent* event = [[PSCollapseEvent alloc] initWithLocation: X time: tSqr creationTime: t0 waveFront: waveFront];
			
			waveFront.collapseEvent = event;
					
			return event;
		}
	}

	return nil;
}

- (PSEvent*) computeNextCollapseEventForSpoke: (PSSpoke*) spoke atTime: (MPDecimal*) t0
{
	if ([spoke isKindOfClass: [PSMotorcycleSpoke class]])
	{
		spoke = spoke;
	}
	
	assert(spoke.leftWaveFront);
	assert(spoke.rightWaveFront);
	
	assert(spoke.leftWaveFront.rightSpoke == spoke);
	assert(spoke.rightWaveFront.leftSpoke == spoke);
	
	PSEvent* leftEvent = [self computeCollapseEventForWaveFront: spoke.leftWaveFront atTime: t0];
	PSEvent* rightEvent = [self computeCollapseEventForWaveFront: spoke.rightWaveFront atTime: t0];
	
	// check left and right collapses, only add event which is closer to source
	if (0 && leftEvent && rightEvent)
	{
		MPVector2D* Dl = [leftEvent.mpLocation sub: spoke.sourceVertex.mpPosition];
		MPVector2D* Dr = [rightEvent.mpLocation sub: spoke.sourceVertex.mpPosition];
		
		MPDecimal* dl = [Dl dot: Dl];
		MPDecimal* dr = [Dr dot: Dr];
		
		NSComparisonResult cmp = [dl compare: dr];
		
		if (cmp > 0)
			leftEvent = nil;
		else if (cmp < 0)
			rightEvent = nil;
	}
	
	
	NSMutableArray* events = [NSMutableArray array];
	
	if (leftEvent)
		[events addObject: leftEvent];
	
	if (rightEvent)
		[events addObject: rightEvent];
	
	[events sortWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PSEvent* obj0, PSEvent* obj1) {
		
		return [obj0 compare: obj1];
	}];
	
	if (events.count)
		return [events objectAtIndex: 0];

	return nil;
}

- (PSEvent*) computeNextEventForSpoke: (PSSpoke*) spoke atTime: (MPDecimal*) t0
{
	NSMutableArray* events = [NSMutableArray array];

	if ([spoke isKindOfClass: [PSMotorcycleSpoke class]])
	{
		PSEvent* motorEvent = [self computeNextEventForMotorcycleSpoke: (id) spoke atTime: t0];
		if (motorEvent)
			[events addObject: motorEvent];
	}
	
	{
		PSEvent* collapseEvent = [self computeNextCollapseEventForSpoke: spoke atTime: t0];
		if (collapseEvent)
			[events addObject: collapseEvent];
	}
	
	[events sortWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PSEvent* obj0, PSEvent* obj1) {
		
		v3i_t x0 = obj0.location;
		v3i_t x1 = obj1.location;
		
		v3i_t start = spoke.startLocation;
		
		vmlongfix_t l0 = v3iDot(v3iSub(x0, start), v3iSub(x0, start));
		vmlongfix_t l1 = v3iDot(v3iSub(x1, start), v3iSub(x1, start));
		
		assert(l0.shift == l1.shift);
		NSComparisonResult cmpl = lcompare(l0.x, l1.x);
		
		if (cmpl != NSOrderedSame)
			return cmpl;
		
		return [obj0 compare: obj1];
	}];

	if (events.count)
		return [events objectAtIndex: 0];
	else
		return nil;
}


- (void) insertNextEventForSpoke: (PSSpoke*) espoke intoList: (NSMutableArray*) events atTime: (MPDecimal*) t0
{
	PSEvent* event = [self computeNextEventForSpoke: espoke atTime: t0];
	
	
	if (espoke.upcomingEvent)
		[events removeObject: espoke.upcomingEvent];
	espoke.upcomingEvent = event;

	
	if (event)
	{
		[events addObject: event];
		/*
		NSArray* affectedSpokes = event.spokes;
		for (PSSpoke* spoke in affectedSpokes)
		{
			if (!spoke.upcomingEvent || ([spoke.upcomingEvent.timeSqr compare: event.timeSqr] > 0))
			{
				if (spoke.upcomingEvent)
					[events removeObject: spoke.upcomingEvent];
				spoke.upcomingEvent = event;
				
			}
		}
		 */
	
	}
	
}

static PSSpoke* _newSpokeBetweenWavefrontsNoInsert(PSWaveFront* leftFront, PSWaveFront* rightFront, v3i_t loc, NSMutableArray* vertices, BOOL convexOnly)
{
	PSVirtualVertex* xVertex = [[PSVirtualVertex alloc] init];
	xVertex.leftEdge = leftFront.edge;
	xVertex.rightEdge = rightFront.edge;
	
	MPDecimal* cross = [[MPVector2D vectorWith3i: leftFront.edge.edge] cross: [MPVector2D vectorWith3i: rightFront.edge.edge]];
	
	if (convexOnly && !cross.isPositive && !cross.isZero)
		return nil; // a new spoke must be between convex edges
	
	[vertices addObject: xVertex];
	
	PSSpoke* newSpoke = [[PSSimpleSpoke alloc] init];
	
	newSpoke.startLocation = loc;
	newSpoke.sourceVertex = xVertex;
	newSpoke.leftEdge = leftFront.edge;
	newSpoke.rightEdge = rightFront.edge;
	newSpoke.leftWaveFront = leftFront;
	newSpoke.rightWaveFront = rightFront;
	
	return newSpoke;
}



static PSSpoke* _newSpokeBetweenWavefronts(PSWaveFront* leftFront, PSWaveFront* rightFront, v3i_t loc, NSMutableArray* vertices, BOOL convexOnly)
{
	PSSpoke* newSpoke = _newSpokeBetweenWavefrontsNoInsert(leftFront, rightFront, loc, vertices, convexOnly);
	if (!newSpoke)
		return nil;
	
	rightFront.leftSpoke.endLocation = loc;
	leftFront.rightSpoke.endLocation = loc;
	
	leftFront.rightSpoke = newSpoke;
	rightFront.leftSpoke = newSpoke;
	
	
	assert(rightFront.leftSpoke == newSpoke);
	assert(leftFront.rightSpoke == newSpoke);
	
	return newSpoke;
	
}

static PSSpoke* _continuedSpoke(PSSpoke* spoke, PSWaveFront* leftFront, PSWaveFront* rightFront, v3i_t loc)
{
	PSSpoke* newSpoke = [[[spoke class] alloc] init];
	
	newSpoke.startLocation = loc;
	newSpoke.sourceVertex = spoke.sourceVertex;
	newSpoke.leftEdge = spoke.leftEdge;
	newSpoke.rightEdge = spoke.rightEdge;
	newSpoke.leftWaveFront = leftFront;
	newSpoke.rightWaveFront = rightFront;

		
	leftFront.rightSpoke = newSpoke;
	rightFront.leftSpoke = newSpoke;
	
	if ([spoke isKindOfClass: [PSMotorcycleSpoke class]])
	{
		PSMotorcycleSpoke* mspoke = (id) spoke;
		PSMotorcycleSpoke* newmSpoke = (id) newSpoke;
		
		newmSpoke.motorcycle = mspoke.motorcycle;
		newmSpoke.opposingWaveFront = mspoke.opposingWaveFront;
		
		newmSpoke.motorcycle.spoke = newmSpoke;
		
		if (newmSpoke.opposingWaveFront)
		{
			newmSpoke.opposingWaveFront.opposingSpokes = [newmSpoke.opposingWaveFront.opposingSpokes arrayByRemovingObject: mspoke];
			newmSpoke.opposingWaveFront.opposingSpokes = [newmSpoke.opposingWaveFront.opposingSpokes arrayByAddingObject: newmSpoke];
		}
	}
	
	
	return newSpoke;
	
}



- (PSWaveFrontSnapshot*) emitSnapshot: (NSArray*) waveFronts atTime: (MPDecimal*) time
{
	NSMutableSet* remainingWaveFronts = [NSMutableSet setWithArray: waveFronts];
	
	PSWaveFrontSnapshot* snapshot = [[PSWaveFrontSnapshot alloc] init];
	snapshot.time = time;
	
	NSMutableArray* loops = [NSMutableArray array];
	
	while (remainingWaveFronts.count)
	{
		PSWaveFront* refFront = [remainingWaveFronts anyObject];
		[remainingWaveFronts removeObject: refFront];
		
		NSMutableArray* loop = [NSMutableArray arrayWithObject: refFront];
		
		PSWaveFront* otherFront = refFront.rightSpoke.rightWaveFront;
		while (otherFront && (otherFront != refFront))
		{
			[loop addObject: otherFront];
			[remainingWaveFronts removeObject: otherFront];
			
			otherFront = otherFront.rightSpoke.rightWaveFront;
		}
		
		[loops addObject: loop];
	}
	
	snapshot.loops = loops;
	
	return snapshot;
}


- (void) emitOffsetOutlineForWaveFronts: (NSArray*) waveFronts atTime: (MPDecimal*) timeSqr
{
	// FIXME: emit not just visual outline, but proper outline path
	
	MPDecimal* time = timeSqr.sqrt;
	
	PSWaveFrontSnapshot* snapshot = [self emitSnapshot: waveFronts atTime: time];
	
	size_t numVertices = waveFronts.count*2;
	
	if (!numVertices)
		return;
	
	GfxMesh* mesh = [[GfxMesh alloc] init];
	
	vector_t* vs = calloc(sizeof(*vs), numVertices);
	vector_t* colors = calloc(sizeof(*colors), numVertices);
	uint32_t* indices = calloc(sizeof(*indices), numVertices);
	
	for (size_t i = 0; i < numVertices; ++i)
	{
		colors[i] = vCreate(0.5, 0.5, 0.5, 1.0);
		indices[i] = i;
	}
	
	size_t k = 0;
	
	for (PSWaveFront* waveFront in waveFronts)
	{
		v3i_t p0 = waveFront.leftSpoke.startLocation;
		v3i_t p1 = waveFront.rightSpoke.startLocation;
		
		BOOL leftFast = waveFront.leftSpoke.mpDenominator.isZero;
		BOOL rightFast = waveFront.rightSpoke.mpDenominator.isZero;
		
		v3i_t x0 = v3iCreate(0, 0, 0, 0);
		v3i_t x1 = v3iCreate(0, 0, 0, 0);
		
		if (!leftFast && !rightFast)
		{
			PSSimpleSpoke* leftSpoke = (id)waveFront.leftSpoke;
			PSSimpleSpoke* rightSpoke = (id)waveFront.rightSpoke;
			x0 = [leftSpoke positionAtTime: time];
			x1 = [rightSpoke positionAtTime: time];
			
		}
		else if (leftFast && rightFast)
		{
			PSSimpleSpoke* leftSpoke = (id)waveFront.leftSpoke;
			PSSimpleSpoke* rightSpoke = (id)waveFront.rightSpoke;
			if (leftSpoke.terminalVertex)
				x0 = leftSpoke.endLocation;
			else
				x0 = v3iScale(v3iAdd(p0, p1), 0, 2);
			
			if (rightSpoke.terminalVertex)
				x1 = rightSpoke.endLocation;
			else
				x1 = v3iScale(v3iAdd(p0, p1), 0, 2);
		}
		else if (leftFast)
		{
			PSSimpleSpoke* leftSpoke = (id)waveFront.leftSpoke;
			PSSimpleSpoke* rightSpoke = (id)waveFront.rightSpoke;
			
			x1 = [rightSpoke positionAtTime: time];
			
			if (leftSpoke.terminalVertex)
				x0 = leftSpoke.endLocation;
			else
				x0 = x1;
			
		}
		else if (rightFast)
		{
			PSSimpleSpoke* leftSpoke = (id)waveFront.leftSpoke;
			PSSimpleSpoke* rightSpoke = (id)waveFront.rightSpoke;
			
			x0 = [leftSpoke positionAtTime: time];
			
			if (rightSpoke.terminalVertex)
				x1 = rightSpoke.endLocation;
			else
				x1 = x0;
		}
		
		
		vs[k++] = v3iToFloat(x0);
		vs[k++] = v3iToFloat(x1);
	}
	
	assert(k == numVertices);
	
	[mesh addVertices: vs count: numVertices];
	[mesh addColors: colors count: numVertices];
	[mesh addDrawArrayIndices: indices count: numVertices withMode: GL_LINES];
	
	if (emitCallback)
	{
		emitCallback(self, snapshot);
	}
	
	free(vs);
	free(colors);
	free(indices);
	
	assert(outlineMeshes);
	
	[outlineMeshes addObject: mesh];
	
}

- (NSArray*) resolveMotorcycleConnections: (NSArray*) motorcycleSpokes recursively: (BOOL) recursive
{
	NSMutableArray* motorcycleSpokesToResolve = motorcycleSpokes.mutableCopy;
	while (motorcycleSpokesToResolve.count)
	{
		@autoreleasepool {
			NSArray* aryCopy = motorcycleSpokesToResolve.copy;
			for (PSMotorcycleSpoke* spoke in aryCopy)
			{
				PSMotorcycleCrash* crash = spoke.motorcycle.terminatingCrash;
				
				if ([crash isKindOfClass: [PSMotorcycleMotorcycleCrash class]])
				{
					// the opposing front is left or right front of terminating motorcycle
					// we rely on crashing order of motorcycleSpokes to make sure the terminating cycle is already connected to its wavefronts
					PSMotorcycleMotorcycleCrash* mcrash = (id) crash;
					
					PSMotorcycle* terminator = mcrash.cycle1;
					PSMotorcycleSpoke* tspoke = terminator.spoke;
					PSWaveFront* leftFront = tspoke.leftWaveFront;
					PSWaveFront* rightFront = tspoke.rightWaveFront;
					
					assert(leftFront);
					assert(rightFront);
					
					BOOL isLeft = [terminator.spoke isVertexCCWFromSpoke: spoke.sourceVertex.mpPosition];
					BOOL isRight = [terminator.spoke isVertexCWFromSpoke: spoke.sourceVertex.mpPosition];

					
					if (isLeft)
					{
						PSWaveFront* termOpponent = tspoke.opposingWaveFront;
						if (!termOpponent && recursive)
							continue;
						//NSMutableArray* tmpVertices = [NSMutableArray array];
						//PSSpoke* tmpSpoke = _newSpokeBetweenWavefrontsNoInsert(tspoke.leftWaveFront, termOpponent, crash.location, tmpVertices);
						
						MPVector2D* splitLoc = (termOpponent ? _splitLocation(tspoke) : nil);
						
						BOOL oppositeOk = termOpponent ? [[termOpponent.edge.mpEdge.rotateCCW dot: spoke.mpDirection] isNegative] : NO;
						BOOL neighbourOk = [[leftFront.edge.mpEdge.rotateCCW dot: spoke.mpDirection] isNegative];
						
						BOOL splitsAfterTerm = splitLoc && [[termOpponent.edge timeSqrToLocation: splitLoc] compare: [termOpponent.edge timeSqrToLocation: spoke.motorcycle.terminalVertex.mpPosition]] > 0;
						
						
						if (splitsAfterTerm && termOpponent && oppositeOk)
						{
							spoke.opposingWaveFront = termOpponent;
							termOpponent.opposingSpokes = [termOpponent.opposingSpokes arrayByAddingObject: spoke];
							
						}
						else if (neighbourOk)
						{
							spoke.opposingWaveFront = leftFront;
							leftFront.opposingSpokes = [leftFront.opposingSpokes arrayByAddingObject: spoke];
						}
						
						assert(!spoke.opposingWaveFront || [[spoke.opposingWaveFront.edge.mpEdge.rotateCCW dot: spoke.mpDirection] isNegative]);
					}
					else if (isRight)
					{
						PSWaveFront* termOpponent = tspoke.opposingWaveFront;
						if (!termOpponent && recursive)
							continue;
						
						MPVector2D* splitLoc = (termOpponent ? _splitLocation(tspoke) : nil);
						
						BOOL oppositeOk = termOpponent ? [[termOpponent.edge.mpEdge.rotateCCW dot: spoke.mpDirection] isNegative] : NO;
						BOOL neighbourOk = [[rightFront.edge.mpEdge.rotateCCW dot: spoke.mpDirection] isNegative];
						
						
						
						BOOL splitsAfterTerm = splitLoc && [[termOpponent.edge timeSqrToLocation: splitLoc] compare: [termOpponent.edge timeSqrToLocation: spoke.motorcycle.terminalVertex.mpPosition]] > 0;
						
						
						if (splitsAfterTerm && termOpponent && oppositeOk)
						{
							spoke.opposingWaveFront = termOpponent;
							termOpponent.opposingSpokes = [termOpponent.opposingSpokes arrayByAddingObject: spoke];
							
						}
						else if (neighbourOk)
						{
							spoke.opposingWaveFront = rightFront;
							rightFront.opposingSpokes = [rightFront.opposingSpokes arrayByAddingObject: spoke];
							assert([[spoke.opposingWaveFront.edge.mpEdge.rotateCCW dot: spoke.mpDirection] isNegative]);

						}

						assert(!spoke.opposingWaveFront || [[spoke.opposingWaveFront.edge.mpEdge.rotateCCW dot: spoke.mpDirection] isNegative]);
					}
					else
						assert(0);
					
				}
				else if ([crash isKindOfClass: [PSMotorcycleEdgeCrash class]])
				{
					PSMotorcycleEdgeCrash* ecrash = (id) crash;
					PSEdge* edge = ecrash.edge1;
					
					assert(edge.waveFronts.count == 1);
					
					PSWaveFront* opposing = edge.waveFronts.lastObject;
					
					spoke.opposingWaveFront = opposing;
					opposing.opposingSpokes = [opposing.opposingSpokes arrayByAddingObject: spoke];

					assert([[spoke.opposingWaveFront.edge.mpEdge.rotateCCW dot: spoke.mpDirection] isNegative]);
				}
				else if ([crash isKindOfClass: [PSMotorcycleVertexCrash class]])
				{
					PSMotorcycleVertexCrash* vcrash = (id) crash;
					PSSourceVertex* vertex = vcrash.vertex;
					
					assert(vertex.outgoingSpokes.count == 1);
					PSSpoke* outSpoke = vertex.outgoingSpokes.lastObject;
					
					PSWaveFront* leftFront = outSpoke.leftWaveFront;
					PSWaveFront* rightFront = outSpoke.rightWaveFront;
					
					
					// we have the vertex, so now figure out which wavefront we belong to
					if ([outSpoke isVertexCCWFromSpoke: spoke.motorcycle.sourceVertex.mpPosition])
					{
						spoke.opposingWaveFront = leftFront;
						leftFront.opposingSpokes = [leftFront.opposingSpokes arrayByAddingObject: spoke];
					}
					else
					{
						spoke.opposingWaveFront = rightFront;
						rightFront.opposingSpokes = [rightFront.opposingSpokes arrayByAddingObject: spoke];
						
					}
					
					assert([[spoke.opposingWaveFront.edge.mpEdge.rotateCCW dot: spoke.mpDirection] isNegative]);
					assert(spoke.opposingWaveFront);
				}
				
				
				if (spoke.opposingWaveFront)
				{
					assert([[spoke.opposingWaveFront.edge.mpEdge.rotateCCW dot: spoke.mpDirection] isNegative]);
				}

				[motorcycleSpokesToResolve removeObject: spoke];
			}
			if (aryCopy.count == motorcycleSpokesToResolve.count)
			{
				NSLog(@"unresolved motorcycles: %lu", (unsigned long)aryCopy.count);
				
				break;
			}
		}
	}
	return motorcycleSpokesToResolve;
}

- (void) runSpokes
{
	if (extensionLimit == 0.0)
		return;

	NSMutableArray* motorcycleSpokes = [NSMutableArray array];

	NSMutableArray* activeSpokes = [NSMutableArray array];

	@autoreleasepool {
		for (PSMotorcycle* motorcycle in terminatedMotorcycles)
		{
			NSMutableArray* newCycleSpokes = [NSMutableArray array];
			_generateCycleSpoke(motorcycle, newCycleSpokes);
			
			[motorcycleSpokes addObjectsFromArray: newCycleSpokes];
			
			[activeSpokes addObjectsFromArray: newCycleSpokes];
		}
	}

	for (PSSourceVertex* vertex in originalVertices)
	{
		@autoreleasepool {
			
			PSSourceEdge* edge0 = vertex.leftEdge;
			PSSourceEdge* edge1 = vertex.rightEdge;
			assert(edge0.rightVertex == vertex);
			assert(edge1.leftVertex == vertex);
			
			vmlongfix_t area = v3iCross2D(edge0.edge, edge1.edge);
			
			if (area.x > 0)
			{
				PSSimpleSpoke* spoke = [[PSSimpleSpoke alloc] init];
				spoke.sourceVertex = vertex;
				spoke.startLocation = vertex.position;
				spoke.startTimeSqr = [MPDecimal zero];
				
				spoke.leftEdge = edge0;
				spoke.rightEdge = edge1;
				
				assert(spoke.leftEdge.rightVertex == spoke.rightEdge.leftVertex);
				
				BOOL spokeExists = NO;
				
				for (PSSimpleSpoke* vspoke in vertex.outgoingSpokes)
				{
					if (_spokesSameDir(spoke, vspoke))
					{
						spokeExists = YES;
						break;
					}
				}
				
				if (!spokeExists)
				{
					_assertSpokeUnique(spoke, vertex.outgoingSpokes);
					
					[activeSpokes addObject: spoke];
					[vertex addSpoke: spoke];
				}
			}
			else
				assert(vertex.outgoingMotorcycles);
			assert(vertex.outgoingSpokes.count);
		}
		
	}

	NSMutableArray* activeWaveFronts = [NSMutableArray array];
	
	// if no anti-spokes are generated, then all starting spokes are unique, and there is one spoke per vertex
	// multiple outgoing spokes would only occur if acute reflex vertices emitted multiple motorcycles, which they currently do not
	// ergo: assume one spoke per vertex.
	
	
	@autoreleasepool {

		for (NSArray* edges in edgeLoops)
		{
			for (PSSourceEdge* edge in edges)
			{
				PSVertex* leftVertex = edge.leftVertex;
				PSVertex* rightVertex = edge.rightVertex;
				
				assert(leftVertex.outgoingSpokes.count == 1);
				assert(rightVertex.outgoingSpokes.count == 1);
				
				PSSpoke* leftSpoke = leftVertex.outgoingSpokes.lastObject;
				PSSpoke* rightSpoke = rightVertex.outgoingSpokes.lastObject;
				
				assert(leftSpoke);
				assert(rightSpoke);

				assert(!leftSpoke.rightWaveFront);
				assert(!rightSpoke.leftWaveFront);
				
				PSWaveFront* waveFront = [[PSWaveFront alloc] init];
				waveFront.leftSpoke = leftSpoke;
				waveFront.rightSpoke = rightSpoke;
				
				leftSpoke.rightWaveFront = waveFront;
				rightSpoke.leftWaveFront = waveFront;
				
				assert(waveFront.leftSpoke != waveFront.rightSpoke);
				assert(waveFront.leftSpoke && waveFront.rightSpoke);
				
				[activeWaveFronts addObject: waveFront];
				
				assert(!edge.waveFronts.count); // assert there are no wavefronts yet
				edge.waveFronts = @[waveFront];
				waveFront.edge = edge;
			}
		}
	}
	
	// now the wavefronts are setup, it's time to connect the motorcycle spokes to their opposing wavefronts
	
	NSArray* motorcycleSpokesToResolve = [self resolveMotorcycleConnections: motorcycleSpokes recursively: YES];
	motorcycleSpokesToResolve = [self resolveMotorcycleConnections: motorcycleSpokesToResolve recursively: NO];
	
	for (PSMotorcycleSpoke* mspoke in motorcycleSpokes)
	{
		if (mspoke.opposingWaveFront)
		{
			MPVector2D* norm = mspoke.opposingWaveFront.edge.mpEdge.rotateCCW;
			assert([[norm dot: mspoke.mpDirection] isNegative]);
		}
	}

	
	
	MPDecimal* t0 = [[MPDecimal alloc] initWithInt64: 0 shift: 16];

	NSMutableArray* events = [NSMutableArray array];
	
	//	for (NSNumber* timeval in [emissionTimes arrayByAddingObject: [NSNumber numberWithDouble: extensionLimit]])
	for (NSNumber* timeval in emissionTimes)
	{
		MPDecimal* time = [[MPDecimal alloc] initWithDouble: timeval.doubleValue*timeval.doubleValue];
		PSEmitEvent* event = [[PSEmitEvent alloc] initWithLocation: [MPVector2D vectorWith3i: v3iCreate(INT32_MAX, INT32_MAX, INT32_MAX, 16)] time: time creationTime: t0];
		
		[events addObject: event];
	}
#pragma mark generate events
	
	for (PSSpoke* spoke in activeSpokes)
	{
		//if (spoke.upcomingEvent)
		//	continue;
		@autoreleasepool {
			[self insertNextEventForSpoke: spoke intoList: events atTime: t0];
		}
	}

	
#pragma mark start loop
	NSMutableArray* eventLog = [NSMutableArray array];
	
	static id trigger = nil;
	
	while (events.count)
	{
		@autoreleasepool {
			/*
			events = [events select: ^BOOL(PSEvent* event) {
				for (PSSpoke* spoke in event.spokes)
				{
					if ((spoke.upcomingEvent != event) && ([spoke.upcomingEvent compare: event] == NSOrderedDescending))
						return NO;
				}
				return YES;

			}].mutableCopy;
			*/
			
			[events sortWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PSEvent* obj0, PSEvent* obj1) {
				return [obj0 compare: obj1];
			}];
			
			/* cull events based on dependency
			 */
			
			while (events.count)
			{
				PSEvent* event = events.firstObject;
				
				if (event == trigger)
					NSLog(@"trigger");
				
				if (!event.isIndependent)
					[events removeObjectAtIndex: 0];
				else
					break;
			}

			if (!events.count)
				break;
			
			PSEvent* firstEvent = [events objectAtIndex: 0];
			
			if ([firstEvent.timeSqr compare: [[MPDecimal alloc] initWithDouble: extensionLimit*extensionLimit]] > 0)
				break;
			

			NSMutableSet* changedSpokes = [[NSMutableSet alloc] init];
			NSMutableSet* terminationCandidateSpokes = [[NSMutableSet alloc] init];

			if ([firstEvent isKindOfClass: [PSCollapseEvent class]])
			{

#pragma mark FP Collapse Event Handling
			
				PSCollapseEvent* event = (id)firstEvent;
				
			
				PSWaveFront* waveFront = event.collapsingWaveFront;
				assert(!waveFront.opposingSpokes.count);
				assert(v3iEqual([[waveFront computeCollapseLocation] toVectorWithShift: 16], event.location)); // a check to make sure that no "stray" events are processed

			
				PSSpoke* leftSpoke = waveFront.leftSpoke;
				PSSpoke* rightSpoke = waveFront.rightSpoke;
				
				[eventLog addObject: [NSString stringWithFormat: @"%f: collapsing @ (%f, %f)", event.timeSqr.sqrt.toDouble, event.floatLocation.farr[0], event.floatLocation.farr[1]]];
				[eventLog addObject: [NSString stringWithFormat: @"  wavefront %@", waveFront]];
				[eventLog addObject: [NSString stringWithFormat: @"  %@", waveFront.leftSpoke]];
				[eventLog addObject: [NSString stringWithFormat: @"  %@", waveFront.rightSpoke]];

				//assert((leftSpoke.upcomingEvent == firstEvent) || ([leftSpoke.upcomingEvent.timeSqr compare: event.timeSqr] >= 0) || !leftSpoke.upcomingEvent);
				//assert((rightSpoke.upcomingEvent == firstEvent) || ([rightSpoke.upcomingEvent.timeSqr compare: event.timeSqr] >= 0) || !rightSpoke.upcomingEvent);
				
				PSWaveFront* leftFront = leftSpoke.leftWaveFront;
				PSWaveFront* rightFront = rightSpoke.rightWaveFront;
				
				assert(waveFront);
				assert(leftSpoke);
				assert(rightSpoke);
				assert(leftFront);
				assert(rightFront);
				_assertWaveFrontConsistent(waveFront);


				// leftSpoke and rightSpoke need not to be added to changedSpokes, as their event is being consumed in this collapse, but their outer neighbour spokes events need to be recomputed.
				[changedSpokes addObjectsFromArray: @[leftSpoke, rightSpoke, leftFront.leftSpoke, rightFront.rightSpoke]];
				[changedSpokes addObjectsFromArray: leftSpoke.upcomingEvent.spokes];
				[changedSpokes addObjectsFromArray: rightSpoke.upcomingEvent.spokes];
				[changedSpokes addObjectsFromArray: leftFront.leftSpoke.upcomingEvent.spokes];
				[changedSpokes addObjectsFromArray: rightFront.rightSpoke.upcomingEvent.spokes];

				[terminationCandidateSpokes addObjectsFromArray: @[leftSpoke, rightSpoke]];
				
				NSArray* opposingSpokes = waveFront.opposingSpokes;
								
				if (leftSpoke.terminalVertex && rightSpoke.terminalVertex)
				{
					// no new spokes will come of this
					[eventLog addObject: [NSString stringWithFormat: @"  nothing to do, left and right spokes already terminated"]];
				}
				else
				{
					PSRealVertex* vertex = leftSpoke.terminalVertex;
					if (!vertex)
						vertex = rightSpoke.terminalVertex;
					if (!vertex)
					{
						vertex = [[PSRealVertex alloc] init];
						vertex.position = event.location;
						vertex.time = event.timeSqr;
						[interiorVertices addObject: vertex];
					}
					
					// FIXME: maybe not true for weird final collapses
					if (1)
					{
						v3i_t diff = v3iSub(vertex.position, event.location);
						long h = lmax(labs(diff.x), labs(diff.y));
						assert(h < 3);
					}
					
					// checks to make sure event location is near the spoke rays
					if (0 && ![leftSpoke isKindOfClass: [PSDegenerateSpoke class]] && ![rightSpoke isKindOfClass: [PSDegenerateSpoke class]])
					{
						vector_t s = v3iToFloat(leftSpoke.startLocation);
						vector_t x = v3iToFloat(event.location);
						vector_t v = leftSpoke.mpDirection.toFloatVector;
						
						s.farr[2] = 0.0;
						
						vector_t r = v3Sub(x, s);
						
						vector_t rp = vProjectAOnB(r, v);
						
						vector_t delta = v3Sub(r, rp);
						
						double ll = vDot(delta, delta);
						
						double limit = 2.0/(1 << 16);
						
						assert(ll < limit*limit);
					}
					if (0 && ![leftSpoke isKindOfClass: [PSDegenerateSpoke class]] && ![rightSpoke isKindOfClass: [PSDegenerateSpoke class]])
					{
						vector_t s = v3iToFloat(rightSpoke.startLocation);
						vector_t x = v3iToFloat(event.location);
						vector_t v = rightSpoke.mpDirection.toFloatVector;
						
						s.farr[2] = 0.0;
						
						vector_t r = v3Sub(x, s);
						
						vector_t rp = vProjectAOnB(r, v);
						
						vector_t delta = v3Sub(r, rp);
						
						double ll = vDot(delta, delta);
						
						double limit = 2.0/(1 << 16);
						
						assert(ll < limit*limit);
					}

					
					if (!leftSpoke.terminalVertex)
					{
						leftSpoke.terminalVertex = vertex;
						leftSpoke.endLocation = event.location;
						[terminationCandidateSpokes addObject: leftSpoke];
					}
					if (!rightSpoke.terminalVertex)
					{
						rightSpoke.terminalVertex = vertex;
						rightSpoke.endLocation = event.location;
						[terminationCandidateSpokes addObject: rightSpoke];
					}

					[eventLog addObject: [NSString stringWithFormat: @"  vertex %@", vertex]];
					
										
					BOOL lrConvex = [leftFront isWeaklyConvexTo: rightFront];
					
					BOOL loop = (leftFront == rightFront) && (leftFront.leftSpoke.leftWaveFront == waveFront) && (rightFront.rightSpoke.rightWaveFront == waveFront);
					
					// FIXME: is this test good?
					//if (!lrConvex || (leftFront == rightFront))
					//if (!lrConvex || loop)
					if (loop)
					{
						[eventLog addObject: [NSString stringWithFormat: @"  looks like we're already all collapsed"]];
						[eventLog addObject: [NSString stringWithFormat: @"    waveL %@", leftFront]];
						[eventLog addObject: [NSString stringWithFormat: @"    waveR %@", rightFront]];
						
						assert(leftSpoke.terminalVertex || rightSpoke.terminalVertex);
						
						/*
						[activeWaveFronts removeObjectsInArray: @[leftFront, rightFront]];
						if (!leftFront.terminationTimeSqr)
							[self terminateWaveFront: leftFront atLocation: event.location];
						if (!rightFront.terminationTimeSqr)
							[self terminateWaveFront: rightFront atLocation: event.location];
						*/
						
					}
					else if (!lrConvex)
					{
						PSSpoke* newSpoke = [[PSDegenerateSpoke alloc] init];
						newSpoke.startTimeSqr = event.timeSqr;
						assert(newSpoke.startTimeSqr);
						
						PSVirtualVertex* xVertex = [[PSVirtualVertex alloc] init];
						[interiorVertices addObject: xVertex];
						
						xVertex.leftEdge = leftFront.edge;
						xVertex.rightEdge = rightFront.edge;

						newSpoke.startLocation = event.location;
						newSpoke.sourceVertex = xVertex;
						newSpoke.leftEdge = leftFront.edge;
						newSpoke.rightEdge = rightFront.edge;
						newSpoke.leftWaveFront = leftFront;
						newSpoke.rightWaveFront = rightFront;
												
						leftFront.rightSpoke = newSpoke;
						rightFront.leftSpoke = newSpoke;

						[activeSpokes addObject: newSpoke];
						[changedSpokes addObject: newSpoke];

						[eventLog addObject: [NSString stringWithFormat: @"  new degenerate spoke %@", newSpoke]];

					}
					else
					{
						PSSpoke* newSpoke = _newSpokeBetweenWavefronts(leftFront, rightFront, event.location, interiorVertices, YES);
						assert(newSpoke);
						newSpoke.startTimeSqr = event.timeSqr;
						assert(newSpoke.startTimeSqr);
						
						[eventLog addObject: [NSString stringWithFormat: @"  new spoke %@", newSpoke]];
						[eventLog addObject: [NSString stringWithFormat: @"    left %@", newSpoke.leftWaveFront]];
						[eventLog addObject: [NSString stringWithFormat: @"   right %@", newSpoke.rightWaveFront]];

						
						_assertWaveFrontConsistent(leftFront);
						_assertWaveFrontConsistent(rightFront);
						
						[activeSpokes addObject: newSpoke];
						[changedSpokes addObject: newSpoke];
						
						// FIXME: as collapse is not allowed with opposing spokes, this should be deleted?
						for (PSMotorcycleSpoke* ospoke in opposingSpokes)
						{
							// re-assign opposing wavefront to left or right neighbour
							[eventLog addObject: [NSString stringWithFormat: @"    re-assign %@", ospoke]];
							
							if ([newSpoke isVertexCCWFromSpoke: ospoke.sourceVertex.mpPosition])
							{
								ospoke.opposingWaveFront = leftFront;
								leftFront.opposingSpokes = [leftFront.opposingSpokes arrayByAddingObject: ospoke];
							}
							else
							{
								ospoke.opposingWaveFront = rightFront;
								rightFront.opposingSpokes = [rightFront.opposingSpokes arrayByAddingObject: ospoke];
							}

							[eventLog addObject: [NSString stringWithFormat: @"      to %@", ospoke.opposingWaveFront]];
						}
					}
					
				
				}
				
				[changedSpokes addObjectsFromArray: opposingSpokes];
			
			}
			else if ([firstEvent isKindOfClass: [PSSplitEvent class]])
			{
#pragma mark FIXP Split Event Handling
	
				PSSplitEvent* event = (id)firstEvent;
				
				PSMotorcycleSpoke* motorcycleSpoke = event.motorcycleSpoke;
				PSWaveFront* opposingFront = motorcycleSpoke.opposingWaveFront;
				PSWaveFront* leftFront = motorcycleSpoke.leftWaveFront;
				PSWaveFront* rightFront = motorcycleSpoke.rightWaveFront;
				
				assert(motorcycleSpoke);
				assert(motorcycleSpoke.motorcycle);
				assert(!motorcycleSpoke.motorcycle.terminatedWithoutSplit);
				assert(!motorcycleSpoke.motorcycle.terminatedWithSplit);

				motorcycleSpoke.motorcycle.terminatedWithSplit = YES;
				[eventLog addObject: [NSString stringWithFormat: @"%f: split @ %f, %f", event.timeSqr.sqrt.toDouble, event.floatLocation.farr[0], event.floatLocation.farr[1]]];
				[eventLog addObject: [NSString stringWithFormat: @"  motorcycle: %@", motorcycleSpoke]];
				[eventLog addObject: [NSString stringWithFormat: @"   wavefront: %@", opposingFront]];
				
				[terminationCandidateSpokes addObjectsFromArray: @[motorcycleSpoke, opposingFront.leftSpoke, opposingFront.rightSpoke]];
								
				motorcycleSpoke.endLocation = event.location;
				
				[changedSpokes addObjectsFromArray: @[motorcycleSpoke, leftFront.leftSpoke, rightFront.rightSpoke, opposingFront.leftSpoke, opposingFront.rightSpoke]];
				[changedSpokes addObjectsFromArray: opposingFront.opposingSpokes];
				[changedSpokes addObjectsFromArray: leftFront.leftSpoke.upcomingEvent.spokes];
				[changedSpokes addObjectsFromArray: rightFront.rightSpoke.upcomingEvent.spokes];
				[changedSpokes addObjectsFromArray: opposingFront.leftSpoke.upcomingEvent.spokes];
				[changedSpokes addObjectsFromArray: opposingFront.rightSpoke.upcomingEvent.spokes];

				PSRealVertex* splitVertex = [[PSRealVertex alloc] init];
				[interiorVertices addObject: splitVertex];
				splitVertex.position = event.location;
				
				motorcycleSpoke.terminalVertex = splitVertex;
								
				{
					PSRealVertex* leftTerm = [[PSRealVertex alloc] init];
					[interiorVertices addObject: leftTerm];
					leftTerm.position = [opposingFront.leftSpoke positionAtTime: event.timeSqr.sqrt];
					opposingFront.leftSpoke.terminalVertex = leftTerm;
					opposingFront.leftSpoke.endLocation = leftTerm.position;
				}
				{
					PSRealVertex* rightTerm = [[PSRealVertex alloc] init];
					[interiorVertices addObject: rightTerm];
					rightTerm.position = [opposingFront.rightSpoke positionAtTime: event.timeSqr.sqrt];
					opposingFront.rightSpoke.terminalVertex = rightTerm;
					opposingFront.rightSpoke.endLocation = rightTerm.position;
				}
				
				{
					MPVector2D* v = motorcycleSpoke.mpDirection;
					MPVector2D* n = v.rotateCCW;
					
					MPVector2D* r = [event.mpLocation sub: motorcycleSpoke.sourceVertex.mpPosition];
					
					MPDecimal* d = [[n dot: r] div: n.length].abs;
					
					assert([d compare: [MPDecimal decimalWithInt64: 1 shift: 16]] == NSOrderedAscending);
				}

				
				// unlike the earlier FP implementation, a split can't occur on a terminated motorcycle spoke.
				assert(motorcycleSpoke.leftWaveFront);
				assert(motorcycleSpoke.rightWaveFront);
				
				_assertWaveFrontConsistent(opposingFront);
				_assertWaveFrontConsistent(leftFront);
				_assertWaveFrontConsistent(rightFront);

				//assert(![motorcycleSpoke.mpNumerator dot: [MPVector2D vectorWith3i: _rotateEdgeToNormal(opposingFront.edge.edge)]].isZero);
				//assert(![motorcycleSpoke.mpNumerator dot: [MPVector2D vectorWith3i: _rotateEdgeToNormal(opposingFront.edge.edge)]].isPositive);
				
				
				
				BOOL shouldSplitLeft = [leftFront isWeaklyConvexTo: opposingFront];
				BOOL shouldSplitRight = [opposingFront isWeaklyConvexTo: rightFront];
				
				assert(shouldSplitLeft && shouldSplitRight); // according to lore, a split when one side also collapses is now illegal
				
				
				

				PSWaveFront* newLeftFront = nil;
				PSWaveFront* newRightFront = nil;

				newLeftFront = [[PSWaveFront alloc] init];
				newRightFront = [[PSWaveFront alloc] init];

				//_splitWaveFront(opposingFront, newLeftFront, newRightFront);
				
				newLeftFront.edge = opposingFront.edge;
				newRightFront.edge = opposingFront.edge;
				
				{
					PSSpoke* newSpoke = _continuedSpoke(opposingFront.leftSpoke, opposingFront.leftSpoke.leftWaveFront, newLeftFront, opposingFront.leftSpoke.endLocation);
					//PSSpoke* newSpoke = _newSpokeBetweenWavefronts(opposingFront.leftSpoke.leftWaveFront, newLeftFront, opposingFront.leftSpoke.endLocation, interiorVertices, NO);
					newSpoke.startTimeSqr = event.timeSqr;
					assert(newSpoke);
					[activeSpokes addObject: newSpoke];
					[changedSpokes addObject: newSpoke];

				}
				{
					PSSpoke* newSpoke = _continuedSpoke(opposingFront.rightSpoke, newRightFront, opposingFront.rightSpoke.rightWaveFront, opposingFront.rightSpoke.endLocation);
					//PSSpoke* newSpoke = _newSpokeBetweenWavefronts(newRightFront, opposingFront.rightSpoke.rightWaveFront, opposingFront.rightSpoke.endLocation, interiorVertices, NO);
					newSpoke.startTimeSqr = event.timeSqr;
					assert(newSpoke);
					[activeSpokes addObject: newSpoke];
					[changedSpokes addObject: newSpoke];
					
				}


				[activeWaveFronts addObjectsFromArray: @[newLeftFront, newRightFront]];
				
				PSSpoke* leftSpoke = _newSpokeBetweenWavefronts(leftFront,  newRightFront, event.location, interiorVertices, YES);
				assert(leftSpoke);
				leftSpoke.startTimeSqr = event.timeSqr;
				
				[eventLog addObject: [NSString stringWithFormat: @"     new left spoke:  %@", leftSpoke]];

				[activeSpokes addObject: leftSpoke];
				[changedSpokes addObject: leftSpoke];

				PSSpoke* rightSpoke = _newSpokeBetweenWavefronts(newLeftFront, rightFront, event.location, interiorVertices, YES);
				assert(rightSpoke);
				rightSpoke.startTimeSqr = event.timeSqr;
				
				[eventLog addObject: [NSString stringWithFormat: @"    new right spoke:  %@", rightSpoke]];

				[activeSpokes addObject: rightSpoke];
				[changedSpokes addObject: rightSpoke];
				[changedSpokes addObject: newLeftFront.leftSpoke];
				[changedSpokes addObject: rightFront.rightSpoke];
				
				assert(fabs([rightSpoke.mpDirection angleTo: leftSpoke.mpDirection]) > 1e-3); // check that the two spokes do point in different directions

				//_assertWaveFrontConsistent(leftFront);
				//_assertWaveFrontConsistent(rightFront);

				{
					_assertWaveFrontConsistent(newLeftFront);
					_assertWaveFrontConsistent(newLeftFront.leftSpoke.leftWaveFront);
					_assertWaveFrontConsistent(rightFront);
					_assertWaveFrontConsistent(rightFront.rightSpoke.rightWaveFront);
				}

				{
					_assertWaveFrontConsistent(newRightFront);
					_assertWaveFrontConsistent(newRightFront.rightSpoke.rightWaveFront);
					_assertWaveFrontConsistent(leftFront);
					_assertWaveFrontConsistent(leftFront.leftSpoke.leftWaveFront);
				}

				if ([activeSpokes containsObject: opposingFront])
					_assertWaveFrontConsistent(opposingFront);
				
				// check if we've got a case of vestigal wavefronts having been formed
				
				{
					BOOL newLeftFrontSourceCoincident = [newLeftFront.leftSpoke.sourceVertex.mpPosition isEqual: newLeftFront.rightSpoke.sourceVertex.mpPosition];
					BOOL newLeftFrontColinear = [[newLeftFront.leftSpoke.mpDirection cross: newLeftFront.rightSpoke.mpDirection] isZero];
					
					if (newLeftFrontSourceCoincident && newLeftFrontColinear)
					{
						[eventLog addObject: [NSString stringWithFormat: @"    removing new left front again because of colinearity"]];
						[activeSpokes removeObject: rightSpoke];
						[activeWaveFronts removeObject: newLeftFront];
						PSSpoke* spoke = _disconnectLeftWaveFront(rightSpoke);
						[changedSpokes addObject: spoke];
						[changedSpokes addObject: spoke.leftWaveFront.leftSpoke];
						[changedSpokes addObject: spoke.rightWaveFront.rightSpoke];
					}
				}
				
				{
					BOOL newRightFrontSourceCoincident = [newRightFront.leftSpoke.sourceVertex.mpPosition isEqual: newRightFront.rightSpoke.sourceVertex.mpPosition];
					BOOL newRightFrontColinear = [[newRightFront.leftSpoke.mpDirection cross: newRightFront.rightSpoke.mpDirection] isZero];

					if (newRightFrontSourceCoincident && newRightFrontColinear)
					{					
						[eventLog addObject: [NSString stringWithFormat: @"    removing new right front again because of colinearity"]];
						[activeSpokes removeObject: leftSpoke];
						[activeWaveFronts removeObject: newRightFront];
						PSSpoke* spoke = _disconnectRightWaveFront(leftSpoke);
						[changedSpokes addObject: spoke];
						[changedSpokes addObject: spoke.leftWaveFront.leftSpoke];
						[changedSpokes addObject: spoke.rightWaveFront.rightSpoke];
					}
				}
				

				NSArray* opposingSpokes = opposingFront.opposingSpokes.copy;

				for (PSMotorcycleSpoke* mspoke in opposingSpokes)
				{
					[eventLog addObject: [NSString stringWithFormat: @"  opponent: %@", motorcycleSpoke]];
					BOOL isLeft = [motorcycleSpoke isVertexCCWFromSpoke: mspoke.sourceVertex.mpPosition];
					
					if (isLeft)
					{
						mspoke.opposingWaveFront = newRightFront;
						newRightFront.opposingSpokes = [newRightFront.opposingSpokes arrayByAddingObject: mspoke];
					}
					else
					{
						mspoke.opposingWaveFront = newLeftFront;
						newLeftFront.opposingSpokes = [newLeftFront.opposingSpokes arrayByAddingObject: mspoke];
					}
					[eventLog addObject: [NSString stringWithFormat: @"    to: %@", mspoke.opposingWaveFront]];
					
				}
				opposingFront.opposingSpokes = @[];
			}
			else if ([firstEvent isKindOfClass: [PSEmitEvent class]])
			{
#pragma mark FIXP Emit Event Handling
				[self emitOffsetOutlineForWaveFronts: activeWaveFronts atTime: firstEvent.timeSqr];
			
			}
			else if ([firstEvent isKindOfClass: [PSSwapEvent class]])
			{
#pragma mark FIXP Swap Event Handling
				PSSwapEvent* event = (id)firstEvent;
				
				PSMotorcycleSpoke* motorcycleSpoke = event.motorcycleSpoke;
				PSSpoke* pivot = event.pivotSpoke;
				PSWaveFront* opposingFront = motorcycleSpoke.opposingWaveFront;
				PSWaveFront* leftFront = pivot.leftWaveFront;
				PSWaveFront* rightFront = pivot.rightWaveFront;
				
				
				assert(pivot);
				assert(motorcycleSpoke);
				assert(motorcycleSpoke.motorcycle);
				
				[eventLog addObject: [NSString stringWithFormat: @"%f: swap @ %f, %f", event.timeSqr.sqrt.toDouble, event.floatLocation.farr[0], event.floatLocation.farr[1]]];
				[eventLog addObject: [NSString stringWithFormat: @"     mspoke: %@", motorcycleSpoke]];
				[eventLog addObject: [NSString stringWithFormat: @"  wavefront: %@", opposingFront]];
				[eventLog addObject: [NSString stringWithFormat: @"      pivot: %@", pivot]];

				[changedSpokes addObject: motorcycleSpoke];
				[changedSpokes addObject: pivot];
				
				opposingFront.opposingSpokes = [opposingFront.opposingSpokes arrayByRemovingObject: motorcycleSpoke];
				motorcycleSpoke.opposingWaveFront = nil;
				
				BOOL pivotTerminatesSpoke = [pivot isKindOfClass: [PSMotorcycleSpoke class]] && ([(PSMotorcycleSpoke*)pivot motorcycle] == motorcycleSpoke.motorcycle.terminator);
				BOOL spokeTerminatesPivot = [pivot isKindOfClass: [PSMotorcycleSpoke class]] && ([(PSMotorcycleSpoke*)pivot motorcycle].terminator == motorcycleSpoke.motorcycle);
				
				// if motorcycle runs along front, it's dead
				if (pivotTerminatesSpoke || spokeTerminatesPivot)
				{
					// do nothing, swap doesn't matter
					pivotTerminatesSpoke = pivotTerminatesSpoke;
					[eventLog addObject: [NSString stringWithFormat: @"    ignoring swap, terminal"]];
				}
				else if ([pivot isVertexCCWFromSpoke: motorcycleSpoke.sourceVertex.mpPosition])
				{
					PSWaveFront* front = leftFront;
					if ((front != motorcycleSpoke.leftWaveFront) && (front != motorcycleSpoke.rightWaveFront) && [motorcycleSpoke.mpDirection dot: [MPVector2D vectorWith3i: _rotateEdgeToNormal(front.edge.edge)]].isNegative)
					{
						[eventLog addObject: [NSString stringWithFormat: @"  new front: %@", front]];
						motorcycleSpoke.opposingWaveFront = front;
						front.opposingSpokes = [front.opposingSpokes arrayByAddingObject: motorcycleSpoke];
					}
				}
				else
				{
					PSWaveFront* front = rightFront;
					if ((front != motorcycleSpoke.leftWaveFront) && (front != motorcycleSpoke.rightWaveFront) && [motorcycleSpoke.mpDirection dot: [MPVector2D vectorWith3i: _rotateEdgeToNormal(front.edge.edge)]].isNegative)
					{
						[eventLog addObject: [NSString stringWithFormat: @"  new front: %@", front]];
						motorcycleSpoke.opposingWaveFront = front;
						front.opposingSpokes = [front.opposingSpokes arrayByAddingObject: motorcycleSpoke];
					}
				}

				
			}
			else
				assert(0); // unknown event type, oops
			
			

			[events removeObject: firstEvent];
			
			NSMutableSet* invalidEvents = [NSMutableSet set];
			NSMutableSet* terminationCandidateWavefronts = [NSMutableSet set];
			
			
			for (PSSpoke* spoke in terminationCandidateSpokes)
			{
				[eventLog addObject: [NSString stringWithFormat: @"  TERM SPOKE: %@", spoke]];

				if (![spoke isKindOfClass: [PSDegenerateSpoke class]])
				{
					vector_t s = v3iToFloat(spoke.startLocation);
					vector_t x = v3iToFloat(spoke.endLocation);
					vector_t v = spoke.mpDirection.toFloatVector;
					
					s.farr[2] = 0.0;
					
					vector_t r = v3Sub(x, s);
					
					vector_t rp = vProjectAOnB(r, v);
					
					vector_t delta = v3Sub(r, rp);
					
					double ll = vDot(delta, delta);
					
					double limit = 2.0/(1 << 16);
					
					if(ll > limit*limit)
					{
						[eventLog addObject: [NSString stringWithFormat: @"    delta: %f", sqrt(ll)]];
						
					}
				}

				if ([spoke isKindOfClass: [PSMotorcycleSpoke class]])
				{
					PSMotorcycleSpoke* mspoke = (id) spoke;
					
					if (mspoke.opposingWaveFront)
					{
						mspoke.opposingWaveFront.opposingSpokes = [mspoke.opposingWaveFront.opposingSpokes arrayByRemovingObject: mspoke];
						mspoke.opposingWaveFront = nil;
					}

				}
				
				if (spoke.leftWaveFront.leftSpoke.terminalVertex)
				{
					[terminationCandidateWavefronts addObject: spoke.leftWaveFront];
				}
				if (spoke.rightWaveFront.rightSpoke.terminalVertex)
				{
					[terminationCandidateWavefronts addObject: spoke.rightWaveFront];
				}
				spoke.terminationTimeSqr = firstEvent.timeSqr;
				[terminatedSpokes addObject: spoke];
				[activeSpokes removeObject: spoke];
			}
			
			for (PSWaveFront* waveFront in terminationCandidateWavefronts)
			{
				[eventLog addObject: [NSString stringWithFormat: @"  TERM WAVE: %@", waveFront]];
				for (PSMotorcycleSpoke* mspoke in waveFront.opposingSpokes)
				{
					if (mspoke.opposingWaveFront == waveFront)
						mspoke.opposingWaveFront = nil;
					
					[changedSpokes addObject: mspoke];
					
					[eventLog addObject: [NSString stringWithFormat: @"    remove opp: %@", mspoke]];
				}

				[activeWaveFronts removeObject: waveFront];
				[self terminateWaveFront: waveFront atLocation: firstEvent.location];
				waveFront.terminationTimeSqr = firstEvent.timeSqr;
				
				waveFront.opposingSpokes = nil;

			}
			
			_assertWaveFrontsConsistent(activeWaveFronts);
		
			for (PSSpoke* spoke in changedSpokes)
			{
				
				if (spoke.upcomingEvent)
				{
					[invalidEvents addObject: spoke.upcomingEvent];
					if (spoke.upcomingEvent == trigger)
						NSLog(@"trigger");
				}
				spoke.upcomingEvent = nil;
				if (spoke.leftWaveFront.collapseEvent)
					[invalidEvents addObject: spoke.leftWaveFront.collapseEvent];
				if (spoke.rightWaveFront.collapseEvent)
					[invalidEvents addObject: spoke.rightWaveFront.collapseEvent];
				spoke.leftWaveFront.collapseEvent = nil;
				spoke.rightWaveFront.collapseEvent = nil;
			}
			
			[events removeObjectsInArray: invalidEvents.allObjects];
			
			NSSet* activeChanged = [changedSpokes objectsPassingTest: ^BOOL(id obj, BOOL *stop) {
				return [activeSpokes containsObject: obj];
			}];
			
			
			for (PSSpoke* spoke in activeChanged)
			{
				// while waveFronts shouldnt be added to the changedWaveFronts more than once, it could happen, and we want to handle it gracefully at this point.
				
				[eventLog addObject: [NSString stringWithFormat: @"  CHANGE SPOKE: %@", spoke]];
			
				[self insertNextEventForSpoke: spoke intoList: events atTime: firstEvent.timeSqr];
			}

		} // end of event loop @autoreleasepool
	} // end of event loop

#pragma mark FP wavefront post processing

	MPDecimal* limitSqr = [[MPDecimal alloc] initWithDouble: extensionLimit*extensionLimit];
	
	for (PSWaveFront* waveFront in activeWaveFronts)
	{
		waveFront.terminationTimeSqr = limitSqr;
		[self terminateWaveFront: waveFront atLocation: [waveFront.leftSpoke positionAtTime: limitSqr.sqrt]];
	}
	
	for (PSSimpleSpoke* spoke in activeSpokes)
	{
		v3i_t x = [spoke positionAtTime: limitSqr.sqrt];
		
		PSRealVertex* vertex = [[PSRealVertex alloc] init];
		vertex.position = x;
		vertex.time = limitSqr.sqrt;
		
		spoke.terminalVertex = vertex;
		spoke.terminationTimeSqr = limitSqr;
		
		[interiorVertices addObject: vertex];
		
		[terminatedSpokes addObject: spoke];
	}
	
}


- (void) generateSkeleton
{
	[self runMotorcycles];
	[self runSpokes];
}


- (NSArray*) offsetMeshes
{
	return outlineMeshes;
}

- (NSArray*) motorcycleDisplayPaths
{
	NSBezierPath* bpath = [NSBezierPath bezierPath];
	
	
	for (PSMotorcycle* motorcycle in terminatedMotorcycles)
	{
		vector_t a = v3iToFloat(motorcycle.sourceVertex.position);
		vector_t b = v3iToFloat(motorcycle.terminalVertex.position);
		[bpath moveToPoint: NSMakePoint(a.farr[0], a.farr[1])];
		[bpath lineToPoint: NSMakePoint(b.farr[0], b.farr[1])];
	}
	
	return @[ bpath ];
}

- (NSArray*) spokeDisplayPaths
{
	NSBezierPath* bpath = [NSBezierPath bezierPath];
	
	
	for (PSSpoke* spoke in terminatedSpokes)
	{
		vector_t a = v3iToFloat(spoke.startLocation);
		vector_t b = v3iToFloat(spoke.terminalVertex.position);
		[bpath moveToPoint: NSMakePoint(a.farr[0], a.farr[1])];
		[bpath lineToPoint: NSMakePoint(b.farr[0], b.farr[1])];
	}
	
	return @[ bpath ];
}

- (NSArray*) outlineDisplayPaths
{
	NSBezierPath* bpath = [NSBezierPath bezierPath];
	
	
	for (NSArray* edges in edgeLoops)
		for (PSEdge* edge in edges)
		{
			vector_t a = v3iToFloat(edge.leftVertex.position);
			vector_t b = v3iToFloat(edge.rightVertex.position);
			[bpath moveToPoint: NSMakePoint(a.farr[0], a.farr[1])];
			[bpath lineToPoint: NSMakePoint(b.farr[0], b.farr[1])];
		}
	
	return @[ bpath ];
}


- (GfxMesh*) skeletonMesh
{
	size_t numCycles = terminatedMotorcycles.count;
	size_t numVertices = vertices.count;
	
	uint32_t* indices = calloc(sizeof(*indices), numCycles*2);
	vector_t* positions = calloc(sizeof(*positions), numVertices*2);
	vector_t* colors = calloc(sizeof(*colors), numVertices*2);
	
	size_t vi = 0;
	for (PSRealVertex* vertex in vertices)
	{
		positions[vi] = v3iToFloat(vertex.position);
		colors[vi] = vCreate(0.0, 0.5, 1.0, 1.0);
		++vi;
	}

	size_t ni = 0;
	
	for (PSMotorcycle* cycle in terminatedMotorcycles)
	{
		indices[ni++] = [vertices indexOfObject: cycle.sourceVertex];
		indices[ni++] = [vertices indexOfObject: cycle.terminalVertex];
	}
	
	GfxMesh* mesh = [[GfxMesh alloc] init];
	[mesh setVertices:positions count:numVertices copy: NO];
	[mesh setColors: colors count: numVertices copy: NO];
	[mesh addDrawArrayIndices: indices count: ni withMode: GL_LINES];
	
	NSLog(@"Skeleton generated with %zd indices", ni);
	
	free(indices);
	
	return mesh;
}

- (NSArray*) waveFrontsTerminatedAfter: (MPDecimal*) tBegin upTo: (MPDecimal*) tEnd
{
	NSArray* waveFronts = [terminatedWaveFronts select: ^BOOL(PSWaveFront* waveFront) {
		return (([waveFront.terminationTimeSqr.sqrt compare: tBegin] > 0) && ([waveFront.terminationTimeSqr.sqrt compare: tEnd] <= 0));
	}];
	return waveFronts;
}

- (NSArray*) waveFrontOutlinesTerminatedAfter: (MPDecimal*) tBegin upTo: (MPDecimal*) tEnd
{
	NSArray* waveFronts = [self waveFrontsTerminatedAfter: tBegin upTo: tEnd];
	
	MPDecimal* tBeginSqr = [tBegin mul: tBegin];
	
	NSArray* paths = [waveFronts map: ^id(PSWaveFront* waveFront) {
		
		NSBezierPath* bpath = [NSBezierPath bezierPath];
		NSMutableArray* verts = [NSMutableArray array];
		
		PSSpoke* lastRighty = [waveFront.retiredRightSpokes lastObject];

		for (PSSpoke* spoke in waveFront.retiredRightSpokes)
		{
			if (([spoke.startTimeSqr compare: tBeginSqr] >= 0))
				[verts addObject: spoke.sourceVertex];
			else if ([spoke.terminationTimeSqr compare: tBeginSqr] >= 0)
			{
				PSRealVertex* vertex = [[PSRealVertex alloc] init];
				vertex.position = [spoke positionAtTime: tBegin];
				[verts addObject: vertex];
			}
			
		}
		
		[verts addObject: lastRighty.terminalVertex];

		for (PSSpoke* spoke in [waveFront.retiredLeftSpokes reverseObjectEnumerator])
		{
			
			if (([spoke.startTimeSqr compare: tBeginSqr] >= 0))
				[verts addObject: spoke.sourceVertex];
			else if ([spoke.terminationTimeSqr compare: tBeginSqr])
			{
				PSRealVertex* vertex = [[PSRealVertex alloc] init];
				vertex.position = [spoke positionAtTime: tBegin];
				[verts addObject: vertex];
			}
		}
		
		for (size_t i = 0; i < verts.count; ++i)
		{
			vector_t pos = v3iToFloat([(PSRealVertex*)[verts objectAtIndex: i] position]);
			if (i == 0)
				[bpath moveToPoint: CGPointMake(pos.farr[0], pos.farr[1])];
			else
				[bpath lineToPoint: CGPointMake(pos.farr[0], pos.farr[1])];
			
		}

		[bpath closePath];
		return bpath;
	}];
	
	return paths;
}

@end






