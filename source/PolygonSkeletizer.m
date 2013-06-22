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

static v3l_t _intToLongVector(v3i_t a, long shift)
{
	assert(shift > 0);
	return (v3l_t){((vmlong_t)a.x) << shift, ((vmlong_t)a.y) << shift, ((vmlong_t)a.z) << shift, a.shift + shift};
}

/* unused
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

static MPVector2D* _crashLocationBisectors(MPVector2D* B, MPVector2D* E_AB, MPVector2D* E_BC, MPVector2D* V, MPVector2D* E_UV, MPVector2D* E_VW)
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
		// if they're anti-parallel, they're defined to meet in the middle.
		// if they're parallel, never meet
		MPDecimal* dot = [E_ABC dot: E_UVW];
		if (dot.isPositive)
			return nil;
		else
			return [[B add: V] scale: [MPDecimal oneHalf]];
		[NSException raise: @"PolgyonSkeletizer.crashException" format: @"A bisector is invalid"];
	}
	return nil;
}



/*
- (void) crashMotorcycle: (PSMotorcycle*) cycle intoEdgesWithLimit: (vmint_t) motorLimit
{
	
	// crash against edges
	for (NSArray* edges in edgeLoops)
		for (PSEdge* edge in edges)
		{
			@autoreleasepool {
				// skip edges motorcycle started from
				if ((edge.leftVertex == cycle.sourceVertex) || (edge.rightVertex == cycle.sourceVertex))
					continue;
				
				MPVector2D* X = [cycle crashIntoEdge: edge];
				
	
							
				if (X)
				{
					v3i_t x = [X toVectorWithShift: 16];
					
					
					
					vmlongerfix_t ta0 = _linePointDistanceSqr(cycle.leftEdge.leftVertex.position, cycle.leftEdge.rightVertex.position, x);
					vmlongerfix_t ta1 = _linePointDistanceSqr(cycle.rightEdge.leftVertex.position, cycle.rightEdge.rightVertex.position, x);

					
					vmlongerfix_t ta = llfixmax(ta0, ta1);
					
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
						[motorcycleCrashes addObject: crash];
						[cycle.crashQueue addObject: crash];
					}
				}
			}
		}

}
*/

/* unused
static vmlongerfix_t _linePointDistanceSqr(v3i_t A, v3i_t B, v3i_t P)
{
	v3i_t AP = v3iSub(P, A);
	v3i_t AB = v3iSub(B, A);
	
	vmlongfix_t num = v3iDot(AP, AB);
	vmlongfix_t den = v3iDot(AB, AB);
	
	v3l_t PAB = v3lScaleFloor(_intToLongVector(AB, AB.shift), num, den);
	
	v3l_t APl = _intToLongVector(AP, AP.shift);
	
	v3l_t D = v3lSub(APl, PAB);
	
	return v3lDot2D(D,D);
}
*/

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
						
			if ([ta compare: tb] <= 0)
			{
				ts = ta;
				tc = tb;
				survivor = cycle0;
				crasher = cycle1;
			}
			else
			{
				ts = tb;
				tc = ta;
				survivor = cycle1;
				crasher = cycle0;
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


#if 0
static BOOL _terminatedMotorcyclesOpposing(PSMotorcycle* cycle0, PSMotorcycle* cycle1)
{
	vector_t p0 = cycle0.sourceVertex.position;
	vector_t p1 = cycle1.sourceVertex.position;
	vector_t x0 = cycle0.terminalVertex.position;
	vector_t x1 = cycle1.terminalVertex.position;
	vector_t v0 = v3Sub(x0, p0);
	vector_t v1 = v3Sub(x1, p1);
	
	double anglev = vAngleBetweenVectors2D(cycle0.velocity, vNegate(cycle1.velocity));

	
	
//	double asin = vCross(v0, vNegate(v1)).farr[2]/(vLength(v0)*vLength(v1));
	
	double angle = vAngleBetweenVectors2D(v0, vNegate(v1));
	
	// parallel
	if ((fabs(angle) < FLT_EPSILON) || ((fabs(anglev) < FLT_EPSILON)))
	{
		
		if ((cycle0.sourceVertex == cycle1.terminalVertex) || (cycle0.terminalVertex == cycle1.sourceVertex))
		{
			return YES;
		}
		
		double anglep0 = vAngleBetweenVectors2D(v0, v3Sub(p1,p0));
		double anglep1 = vAngleBetweenVectors2D(v1, v3Sub(p0,p1));
		double anglepv0 = vAngleBetweenVectors2D(cycle0.velocity, v3Sub(p1,p0));
		double anglepv1 = vAngleBetweenVectors2D(cycle1.velocity, v3Sub(p0,p1));

		// collinear
		if (((fabs(anglep0) < FLT_EPSILON) && (fabs(anglep1) < FLT_EPSILON)) || ((fabs(anglepv0) < FLT_EPSILON) && (fabs(anglepv1) < FLT_EPSILON)))
		{
		
			double ll0 = vDot(v3Sub(x0, p0), v0);
			double ll1 = vDot(v3Sub(x1, p1), v1);
			double lx0 = vDot(v3Sub(x1, p0), v0);
			double lx1 = vDot(v3Sub(x0, p1), v1);

			BOOL x1InC0 = (lx0 > 0.0) && (lx0 < ll0);
			BOOL x0InC1 = (lx1 > 0.0) && (lx1 < ll1);
			
			// overlapping
			if (x1InC0 || x0InC1 )
				return YES;
		}
	}
	
	return NO;
}
#endif

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
			
			if (area.x < 0)
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
	
	[spokes addObject: spoke];
	_assertSpokeUnique(spoke, vertex.outgoingSpokes);
	[vertex addSpoke: spoke];
	
	//PSVertex* antiVertex = cycle.terminalVertex;
	
	
	
}

#if 0
- (PSSplitEvent*) computeSimpleSplitEvent: (PSMotorcycleSpoke*) cycleSpoke atTime: (double) creationTime
{
	PSAntiSpoke* antiSpoke = cycleSpoke.antiSpoke;
	
	if (vLength(antiSpoke.velocity) == 0)
		return nil;
	
	if (cycleSpoke.motorcycle.terminatedWithoutSplit)
		return nil;
	
	assert(cycleSpoke.sourceVertex);
	assert(antiSpoke.sourceVertex);
	
	double ts0 = cycleSpoke.start;
	double ts1 = antiSpoke.start;
	
	double tsx = fmax(ts0, ts1);
	
	vector_t vv = v3Sub(cycleSpoke.velocity, antiSpoke.velocity);
	
	
	vector_t delta = v3Sub(
						   v3Add(antiSpoke.sourceVertex.position, v3MulScalar(antiSpoke.velocity, tsx-ts1)),
						   v3Add(cycleSpoke.sourceVertex.position, v3MulScalar(cycleSpoke.velocity, tsx-ts0))
						   );
	
	// FIXME: Bishop.stl
	assert(vDot(vv, delta) >= 0.0);
	
	double tc = tsx + vLength(delta)/vLength(vv);
	
	
	PSSplitEvent* event = [[PSSplitEvent alloc] init];
	event.time = tc;
	event.creationTime = creationTime;
	event.location = v3Add(cycleSpoke.sourceVertex.position, v3MulScalar(cycleSpoke.velocity, tc - cycleSpoke.start));
	
	event.antiSpoke = antiSpoke;
	
	return event;
}



- (PSCollapseEvent*) computeSimpleCollapseEvent: (PSWaveFront*) waveFront
{
	assert([waveFront.leftSpoke isKindOfClass: [PSSimpleSpoke class]]);
	assert([waveFront.rightSpoke isKindOfClass: [PSSimpleSpoke class]]);
	
	PSSimpleSpoke* leftSpoke = (id)waveFront.leftSpoke;
	PSSimpleSpoke* rightSpoke = (id)waveFront.rightSpoke;
	
	assert(waveFront.leftSpoke.sourceVertex);
	assert(waveFront.rightSpoke.sourceVertex);
	vector_t v0 = leftSpoke.velocity;
	vector_t v1 = rightSpoke.velocity;
	
	double angle = vAngleBetweenVectors2D(v0, v1);
	
	if (angle < 0.0) // if angle is negative between the two spokes, they are not converging
		return nil;
	
	
	vector_t p0 = waveFront.leftSpoke.sourceVertex.position;
	vector_t p1 = waveFront.rightSpoke.sourceVertex.position;
	
	double vv0 = vDot(v0, v0);
	double vv1 = vDot(v1, v1);
	
	double t0 = waveFront.leftSpoke.start;
	double t1 = waveFront.rightSpoke.start;
	
	// FIXME: using a virtual starting point at t=0.0 seems like a numerically stupid idea.
	//vector_t tx = xRays2D(v3Add(p0, v3MulScalar(v0, -t0)), v0, v3Add(p1, v3MulScalar(v1, -t1)), v1);
	vector_t tx = xRays2D(p0, v0, p1, v1);
	
	double ta = tx.farr[0] + t0;
	double tb = tx.farr[1] + t1;
	
	double tc = 0.5*(ta+tb);
	
	// TODO: verify if this is better numerically if one spoke is quite fast
	if (vv0 < vv1)
		tc = tb;
	else
		tc = ta;
	
	
	if (tc < MAX(t0,t1))
		tc = MAX(t0,t1);
	
	assert(tc > 0.0);
	
	
	PSCollapseEvent* event = [[PSCollapseEvent alloc] init];
	event.collapsingWaveFront = waveFront;
	event.time = tc;
	event.location = v3Add(p0, v3MulScalar(v0, tc-t0));
	
	
	return event;

}

- (PSCollapseEvent*) computeCollapseEvent: (PSWaveFront*) waveFront
{

	if ([waveFront.leftSpoke isKindOfClass: [PSSimpleSpoke class]] && [waveFront.rightSpoke isKindOfClass: [PSSimpleSpoke class]])
		return [self computeSimpleCollapseEvent: waveFront];
	
	assert(waveFront.leftSpoke);
	assert(waveFront.rightSpoke);
	
	BOOL leftFast = [waveFront.leftSpoke isKindOfClass: [PSFastSpoke class]];
	BOOL rightFast = [waveFront.rightSpoke isKindOfClass: [PSFastSpoke class]];

	double t0 = waveFront.leftSpoke.start;
	double t1 = waveFront.rightSpoke.start;
	
	vector_t p0 = waveFront.leftSpoke.sourceVertex.position;
	vector_t p1 = waveFront.rightSpoke.sourceVertex.position;

	if (leftFast && ! rightFast)
	{
		PSFastSpoke* leftSpoke = (id) waveFront.leftSpoke;
		PSSimpleSpoke* rightSpoke = (id) waveFront.rightSpoke;

		vector_t r0 = leftSpoke.direction;
		vector_t v1 = rightSpoke.velocity;

		double angle = vAngleBetweenVectors2D(r0, v1);
		
		if (angle <= 0.0) // if angle is negative between the two spokes, they are not converging
			return nil;


		vector_t tx = xRays2D(p0, r0, p1, v1);
		tx.farr[1] += t1;
		
		double tc = fmax(fmax(t0,t1), tx.farr[1]);
		

		PSCollapseEvent* event = [[PSCollapseEvent alloc] init];
		event.collapsingWaveFront = waveFront;
		event.time = tc;
		event.location = v3Add(p1, v3MulScalar(v1, tc-t1));
		return event;
	}
	else if (!leftFast && rightFast)
	{
		PSSimpleSpoke* leftSpoke = (id) waveFront.leftSpoke;
		PSFastSpoke* rightSpoke = (id) waveFront.rightSpoke;
		
		vector_t v0 = leftSpoke.velocity;
		vector_t r1 = rightSpoke.direction;

		double angle = vAngleBetweenVectors2D(v0, r1);
		
		if (angle <= 0.0)
			return nil;
		

		vector_t tx = xRays2D(p0, v0, p1, r1);
		tx.farr[0] += t0;
		
		double tc = fmax(fmax(t0,t1), tx.farr[0]);

		assert(tc >= 0.0);

		PSCollapseEvent* event = [[PSCollapseEvent alloc] init];
		event.collapsingWaveFront = waveFront;
		event.time = tc;
		event.location = v3Add(p0, v3MulScalar(v0, tc-t0));
		return event;
	}
	else // two fast spokes
	{
		// as fast spokes are only generated with anti-parallel faces, it is safe to assume immediate collapse. faces on both sides of the collapsing face should already have collapsed.
		
		//double tc = nextafter(fmax(t0, t1), HUGE_VAL);
		double tc = fmax(t0, t1);

		PSCollapseEvent* event = [[PSCollapseEvent alloc] init];
		event.collapsingWaveFront = waveFront;
		event.time = tc;
		event.location = v3MulScalar(v3Add(p0, p1), 0.5);
		return event;
	}
}


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

- (PSEvent*) nextEventForMotorcycle: (PSMotorcycle*) motorcycle atTime: (double) theTime
{
	NSArray* events = [self computeEventsForMotorcycle: motorcycle atTime: theTime];
	
	events = [events select: ^BOOL(PSEvent* obj) {
		return obj.time >= theTime;
	}];

	if (events.count)
		return [events objectAtIndex: 0];
	else return nil;
}

- (NSArray*) computeEventsForMotorcycle: (PSMotorcycle*) motorcycle atTime: (double) creationTime
{
	PSMotorcycleSpoke* cycleSpoke = motorcycle.spoke;
	PSAntiSpoke* antiSpoke = motorcycle.antiSpoke;
	NSMutableArray* motorcycleEvents = [NSMutableArray array];
	
	if (cycleSpoke.terminalVertex && antiSpoke.terminalVertex)
	{
		// do nothing, we're finished.
	}
	else if (cycleSpoke.terminalVertex)
	{
		// if our motorcycle spoke has been terminated (by a collapse, it should have been), the only event left is a forced split
		assert(cycleSpoke.sourceVertex);
		assert(antiSpoke.sourceVertex);
		PSSplitEvent* splitEvent = [[PSSplitEvent alloc] init];
		splitEvent.creationTime = creationTime;
		splitEvent.time = creationTime; // when? now would be a good time.
		splitEvent.location = cycleSpoke.terminalVertex.position;
		splitEvent.antiSpoke = antiSpoke;
		
		[motorcycleEvents addObject: splitEvent];
		
		
		
	}
	else if (antiSpoke.terminalVertex)
	{
		PSSplitEvent* splitEvent = [[PSSplitEvent alloc] init];
		splitEvent.creationTime = creationTime;
		splitEvent.time = creationTime; // when? now would be a good time.
		splitEvent.location = antiSpoke.terminalVertex.position;
		splitEvent.antiSpoke = antiSpoke;
		
		[motorcycleEvents addObject: splitEvent];

	}
	else
	{
		
		if (vLength(antiSpoke.velocity) > 0.0)
		{		
			
			for (PSCrashVertex* crashVertex in motorcycle.crashVertices)
			{
				if (crashVertex == antiSpoke.passedCrashVertex)
					continue;
				
				PSEvent* reverseEvent = [self computeReverseBranchEventForMotorcycle: motorcycle vertex: crashVertex];
				reverseEvent.creationTime = creationTime;
				
				if (reverseEvent)
					[motorcycleEvents addObject: reverseEvent];
				
			}
			
			
		}



		for (PSCrashVertex* vertex in motorcycle.crashVertices)
		{
			if (vertex == cycleSpoke.passedCrashVertex)
				continue;
			
			vector_t delta = v3Sub(vertex.position, cycleSpoke.sourceVertex.position);
			double adot = vDot(delta, cycleSpoke.velocity);
			double time = vLength(delta)/vLength(cycleSpoke.velocity);
			
			if (adot <=  0.0) // no event if crash vertex lies behind us
				continue;
			
			PSBranchEvent* event = [[PSBranchEvent alloc] init];
			event.creationTime = creationTime;
			event.rootSpoke = cycleSpoke;
			event.time = cycleSpoke.start + time;
			assert(event.time >= event.rootSpoke.start); // if event's supposed to be before the spoke starts, something's wrong
			event.location = vertex.position;
			event.branchVertex = vertex;
			vertex.forwardEvent = event;
			
			[motorcycleEvents addObject: event];
		}


		PSSplitEvent* splitEvent = [self computeSimpleSplitEvent: cycleSpoke atTime: creationTime];
		if (splitEvent)
			[motorcycleEvents addObject: splitEvent];
	}
		
	
	[motorcycleEvents sortWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PSEvent* obj1, PSEvent* obj2) {
		double a = obj1.time;
		double b = obj2.time;
		return fcompare(a, b);
	}];
	
	return motorcycleEvents;
}

- (void) addVertex: (PSVertex*) vertex
{
	
}

- (PSSimpleSpoke*) swapSpoke: (PSSimpleSpoke*) motorcycleSpoke
{
	PSSimpleSpoke* simpleSpoke = [[PSSimpleSpoke alloc] init];
	simpleSpoke.start = motorcycleSpoke.start;
	simpleSpoke.sourceVertex = motorcycleSpoke.sourceVertex;
	simpleSpoke.velocity = motorcycleSpoke.velocity;
	simpleSpoke.terminalVertex = motorcycleSpoke.terminalVertex;
	simpleSpoke.terminationTime = motorcycleSpoke.terminationTime;
	simpleSpoke.leftWaveFront = motorcycleSpoke.leftWaveFront;
	simpleSpoke.rightWaveFront = motorcycleSpoke.rightWaveFront;
	
	[motorcycleSpoke.leftWaveFront swapSpoke: motorcycleSpoke forSpoke: simpleSpoke];
	[motorcycleSpoke.rightWaveFront swapSpoke: motorcycleSpoke forSpoke: simpleSpoke];
	
	[simpleSpoke.sourceVertex removeSpoke: motorcycleSpoke];
	motorcycleSpoke.sourceVertex = nil;
	[simpleSpoke.sourceVertex addSpoke: simpleSpoke];

	for (PSWaveFront* waveFront in motorcycleSpoke.retiredWaveFronts)
		[waveFront swapSpoke: motorcycleSpoke forSpoke: simpleSpoke];
	[simpleSpoke.retiredWaveFronts addObjectsFromArray: motorcycleSpoke.retiredWaveFronts];
	[motorcycleSpoke.retiredWaveFronts removeAllObjects];
	
	if (simpleSpoke.terminalVertex)
	{
		[simpleSpoke.terminalVertex removeSpoke: motorcycleSpoke];
		motorcycleSpoke.terminationTime = INFINITY;
		motorcycleSpoke.terminalVertex = nil;
		[simpleSpoke.terminalVertex addSpoke: simpleSpoke];
		
	}
	if ([terminatedSpokes containsObject: motorcycleSpoke])
	{
		[terminatedSpokes removeObject: motorcycleSpoke];
		[terminatedSpokes addObject: simpleSpoke];
	}
	
	motorcycleSpoke.leftWaveFront = nil;
	motorcycleSpoke.rightWaveFront = nil;
	return simpleSpoke;
}

static PSSpoke* _createSpokeBetweenFronts(PSWaveFront* leftFront, PSWaveFront* rightFront, PSVertex* vertex, double time)
{
	if (_waveFrontsAreAntiParallel(leftFront, rightFront))
	{
		vector_t newDirection = v3MulScalar(v3Add(vNegate(_normalToEdge(leftFront.direction)), _normalToEdge(rightFront.direction)), 0.5);
		
		PSFastSpoke* newSpoke = [[PSFastSpoke alloc] init];
		newSpoke.sourceVertex = vertex;
		newSpoke.start = time;
		newSpoke.direction = newDirection;
		[vertex addSpoke: newSpoke];
		
		return newSpoke;
	}
	else
	{
		PSSimpleSpoke* newSpoke = [[PSSimpleSpoke alloc] init];
		newSpoke.velocity = bisectorVelocity(leftFront.direction, rightFront.direction, _normalToEdge(leftFront.direction), _normalToEdge(rightFront.direction));
		newSpoke.start = time;
		newSpoke.sourceVertex = vertex;
		[vertex addSpoke: newSpoke];

		return newSpoke;
	}
}

static double _angleBetweenSpokes(id leftSpoke, id rightSpoke)
{
	BOOL leftFast = [leftSpoke isKindOfClass: [PSFastSpoke class]];
	BOOL rightFast = [rightSpoke isKindOfClass: [PSFastSpoke class]];
	if (leftFast && rightFast)
	{
		return vAngleBetweenVectors2D([leftSpoke direction], [rightSpoke direction]);
	}
	else if (leftFast)
	{
		return vAngleBetweenVectors2D([leftSpoke direction], [rightSpoke velocity]);
	}
	else if (rightFast)
	{
		return vAngleBetweenVectors2D([leftSpoke velocity], [rightSpoke direction]);
	}
	else
		return vAngleBetweenVectors2D([leftSpoke velocity], [rightSpoke velocity]);
}

#endif


static MPVector2D* _intersectSpokes(PSSpoke* spoke0, PSSpoke* spoke1)
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
	
		
	MPVector2D* X = _crashLocationBisectors(spoke0.sourceVertex.mpPosition, edgeAB.mpEdge, edgeBC.mpEdge, spoke1.sourceVertex.mpPosition, edgeUV.mpEdge, edgeVW.mpEdge);
	
	
	
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
	
	
	MPDecimal* tguess = [MPDecimal zero];
	v3i_t xGuess = mspoke.motorcycle.sourceVertex.position;
	
	v3i_t we = waveFront.edge.edge;
	v3i_t wn = _rotateEdgeToNormal(we);
	
	assert(mspoke.mpNumerator && !(mspoke.mpNumerator.x.isZero && mspoke.mpNumerator.y.isZero));
	MPDecimal* xx = [mspoke.mpDirection dot: [MPVector2D vectorWith3i: wn]];
	
	
	if (xx.isPositive || xx.isZero)
	{
		return nil;
	}
	
	v3i_t oscGuess = xGuess; // for oscillation detection
	
	MPDecimal* tmin = tguess;

	while (1)
	{
		v3i_t XM = [mspoke positionAtTime: tguess];
		
		if (v3iEqual(xGuess, XM))
			break;
		
		if (v3iEqual(oscGuess, XM))
		{
			
			MPDecimal* tx = _maxTimeSqrFromEdges(@[waveFront.edge, mspoke.leftEdge, mspoke.rightEdge], [MPVector2D vectorWith3i: XM]);
			MPDecimal* to = _maxTimeSqrFromEdges(@[waveFront.edge, mspoke.leftEdge, mspoke.rightEdge], [MPVector2D vectorWith3i: oscGuess]);
			
			NSComparisonResult cmp = [tx compare: to];
			if (cmp > 0)
			{
				xGuess = oscGuess;
				break;
			}
			else if (cmp < 0)
			{
				xGuess = XM;
				break;
			}
			else
			{
				xGuess = XM;
				break;
			}
			
		}
		
		assert(waveFront.edge);
		MPDecimal* tsqr = [waveFront.edge timeSqrToLocation: [MPVector2D vectorWith3i: XM]];
		
		MPDecimal* twall = [tsqr sqrt];
		
		MPDecimal* tdiff = [twall sub: tguess];
		
		// 0x7f >> 8 : a little less than half, to avoid hunting
		MPDecimal* newGuess = [tguess add: [tdiff mul: [MPDecimal decimalWithInt64: INT32_MAX shift: 32]]];
		
		
		// if twall is greater than tguess, our new minimum bound is tguess
		if ([twall compare: tguess] > 0)
		{
			tmin = [tmin max: tguess];
		}
				
		// if the new guess would be less than our minimum bound, it means we're oscillating!
		if ([newGuess compare: tmin] <= 0)
		{
			break;
		}

		assert(!isnan(newGuess.toDouble));
		assert(!isinf(newGuess.toDouble));
		assert(newGuess.isPositive);
		tguess = newGuess;
		
		oscGuess = xGuess;
		xGuess = XM;
		
	}
	
	assert(_locationOnRayHalfPlaneTest(_rotateEdgeToNormal(we), v3iSub(xGuess, waveFront.edge.leftVertex.position)));
	
	return [MPVector2D vectorWith3i: xGuess];
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
	assert(spoke.rightWaveFront != spoke.leftWaveFront);
	
}

static void _assertWaveFrontConsistent(PSWaveFront* waveFront)
{
	assert(waveFront.leftSpoke != waveFront.rightSpoke);
	assert(waveFront.leftSpoke.rightWaveFront == waveFront);
	assert(waveFront.rightSpoke.leftWaveFront == waveFront);

	_assertSpokeConsistent(waveFront.leftSpoke);
	_assertSpokeConsistent(waveFront.rightSpoke);
	
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
			BOOL shouldSplitLeft = [mspoke.leftWaveFront isConvexTo: mspoke.opposingWaveFront];
			BOOL shouldSplitRight = [mspoke.opposingWaveFront isConvexTo: mspoke.rightWaveFront];
			
			// FIXME: when terminating in motorcycle crash,
			// split should only occur AFTER split wavefront passed terminating point

			
			NSArray* timingEdges = @[mspoke.leftEdge, mspoke.rightEdge, waveFront.edge];
			
			if ([mspoke.motorcycle.terminator isKindOfClass: [PSMotorcycle class]])
			{
				PSMotorcycleSpoke* tspoke = ((PSMotorcycle*)mspoke.motorcycle.terminator).spoke;
				if ((tspoke == mspoke.opposingWaveFront.leftSpoke) || (tspoke == mspoke.opposingWaveFront.rightSpoke))
				{
					timingEdges = [timingEdges arrayByAddingObjectsFromArray: @[tspoke.leftEdge, tspoke.rightEdge]];
				}
			}

			v3i_t x = [xSplit toVectorWithShift: 16];
			assert(mspoke.motorcycle.terminalVertex);
			if (!v3iEqual(x, mspoke.motorcycle.terminalVertex.position) && shouldSplitLeft && shouldSplitRight)
				[candidates addObject: @[ xSplit, timingEdges, [[PSSplitEvent alloc] initWithLocation: [xSplit toVectorWithShift: 16] time: nil creationTime: t0 motorcycleSpoke: mspoke] ] ];
		}
	}
	
	{
		MPVector2D* xLeftSwap = _intersectSpokes(leftSpoke, mspoke);
		
		BOOL splitConflict = NO;
		if (xSplit && xLeftSwap)
		{
			v3i_t x = [xSplit toVectorWithShift: 16];
			v3i_t xw = [xLeftSwap toVectorWithShift: 16];
			
			splitConflict = v3iEqual(x, xw);
			
		}
		
		// check if the swap would be after termination
		if (xLeftSwap && leftSpoke.terminalVertex && ([[leftSpoke timeSqrToLocation: xLeftSwap] compare: [leftSpoke timeSqrToLocation: leftSpoke.terminalVertex.mpPosition]] >= 0))
			splitConflict = YES;
		
		splitConflict = splitConflict || leftSpoke.terminalVertex;
		
		BOOL swapFromLeft = [leftSpoke isVertexCCWFromSpoke: mspoke.sourceVertex.mpPosition];
		
		if (xLeftSwap && swapFromLeft && !splitConflict)
			[candidates addObject: @[ xLeftSwap, @[leftSpoke.leftEdge, leftSpoke.rightEdge, mspoke.leftEdge, mspoke.rightEdge], [[PSSwapEvent alloc] initWithLocation: [xLeftSwap toVectorWithShift: 16] time: nil creationTime: t0 motorcycleSpoke: mspoke pivotSpoke: leftSpoke] ] ];
	}
	{
		MPVector2D* xRightSwap = _intersectSpokes(rightSpoke, mspoke);

		BOOL splitConflict = NO;
		if (xSplit && xRightSwap)
		{
			v3i_t x = [xSplit toVectorWithShift: 16];
			v3i_t xw = [xRightSwap toVectorWithShift: 16];
			
			splitConflict = v3iEqual(x, xw);
			
		}

		if (xRightSwap && rightSpoke.terminalVertex && ([[rightSpoke timeSqrToLocation: xRightSwap] compare: [rightSpoke timeSqrToLocation: rightSpoke.terminalVertex.mpPosition]] >= 0))
			splitConflict = YES;

		splitConflict = splitConflict || rightSpoke.terminalVertex;

		BOOL swapFromLeft = [rightSpoke isVertexCCWFromSpoke: mspoke.sourceVertex.mpPosition];
		if (xRightSwap && !swapFromLeft && !splitConflict)
			[candidates addObject: @[ xRightSwap, @[rightSpoke.leftEdge, rightSpoke.rightEdge, mspoke.leftEdge, mspoke.rightEdge], [[PSSwapEvent alloc] initWithLocation: [xRightSwap toVectorWithShift: 16] time: nil creationTime: t0 motorcycleSpoke: mspoke pivotSpoke: rightSpoke] ] ];
	}
	
/*
	// if we gotta account for branches, add those, too
	if (mspoke.remainingBranchVertices.count)
	{
		PSCrashVertex* branchVertex = [mspoke.remainingBranchVertices objectAtIndex: 0];
		PSCrashVertex* revBranchVertex = [mspoke.remainingBranchVertices lastObject];
		v3i_t xBranch = branchVertex.position;
		v3i_t xRevBranch = revBranchVertex.position;
		
		[candidates addObject: @[
					  @[ [MPVector2D vectorWith3i: xBranch], mspoke.leftEdge, mspoke.rightEdge, waveFront.edge, [[PSBranchEvent alloc] initWithLocation: xBranch time: nil creationTime: t0 rootSpoke: mspoke branchVertex: branchVertex] ],
					  @[ [MPVector2D vectorWith3i: xRevBranch], waveFront.edge, waveFront.edge, waveFront.edge, [[PSReverseBranchEvent alloc] initWithLocation: xRevBranch time: nil creationTime: t0 rootSpoke: mspoke branchVertex: revBranchVertex] ],
					  ] ];
	}
*/	
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
	
	MPDecimal* maxTimeSqr = [[MPDecimal alloc] initWithInt64: INT64_MAX shift: 32];
	NSMutableArray* events = [NSMutableArray array];
	
	
	if (waveFront.retiredLeftSpokes.count)
	{
		PSSimpleSpoke* retiredSpoke = waveFront.retiredLeftSpokes.lastObject;
		MPVector2D* XL = _intersectSpokes(retiredSpoke, waveFront.rightSpoke);

		if (XL && (XL.minIntegerBits < 16) && v3iEqual(waveFront.leftSpoke.startLocation, [XL toVectorWithShift: 16]))
		{
			// we don't actually care for waveFront.edge, as for the new spoke the two neighbour matter
			MPDecimal* tSqr = _maxTimeSqrFromEdges(@[waveFront.rightSpoke.rightEdge, retiredSpoke.leftEdge], XL);

			if (([tSqr compare: maxTimeSqr] < 0))
			{
				PSCollapseEvent* event = [[PSCollapseEvent alloc] initWithLocation: [XL toVectorWithShift: 16] time: tSqr creationTime: t0 waveFront: waveFront];
				
				[events addObject: event];
			}
		}
	}
	
	if (waveFront.retiredRightSpokes.count)
	{
		PSSimpleSpoke* retiredSpoke = waveFront.retiredRightSpokes.lastObject;
		MPVector2D* XL = _intersectSpokes(waveFront.leftSpoke, retiredSpoke);
		
		if (XL && (XL.minIntegerBits < 16) && v3iEqual(waveFront.rightSpoke.startLocation, [XL toVectorWithShift: 16]))
		{
			
			// we don't actually care for waveFront.edge, as for the new spoke the two neighbour matter
			MPDecimal* tSqr = _maxTimeSqrFromEdges(@[waveFront.leftSpoke.leftEdge, retiredSpoke.rightEdge], XL);
			
			if (([tSqr compare: maxTimeSqr] < 0))
			{
				PSCollapseEvent* event = [[PSCollapseEvent alloc] initWithLocation: [XL toVectorWithShift: 16] time: tSqr creationTime: t0 waveFront: waveFront];
				
				[events addObject: event];
			}
		}
	}
	

	
	
	MPVector2D* X = _intersectSpokes(waveFront.leftSpoke, waveFront.rightSpoke);
	
	if (!X)
	{
		PSSpoke* leftSpoke = waveFront.leftSpoke;
		PSSpoke* rightSpoke = waveFront.rightSpoke;
		MPVector2D* ldir = leftSpoke.mpDirection;
		MPVector2D* rdir = rightSpoke.mpDirection;
		MPVector2D* e = waveFront.edge.mpEdge;
		
		if ([ldir dot: e].isPositive && [rdir dot: e].isNegative && [ldir cross: rdir].isZero)
		{
			// the spokes are anti-parallel, facing inwards
			// it necessarily follows that they are both of the infinite-speed variety
			X = [[[MPVector2D vectorWith3i: leftSpoke.startLocation] add: [MPVector2D vectorWith3i: rightSpoke.startLocation]] scale: [MPDecimal oneHalf]];
		}
		else
			; // spokes are parallel, so never intersect
	}
	
	if (X)
	{
		PSSpoke* leftSpoke = waveFront.leftSpoke;
		PSSpoke* rightSpoke = waveFront.rightSpoke;
		// we don't actually care for waveFront.edge, as for the new spoke the two neighbour matter
		MPDecimal* tSqr = _maxTimeSqrFromEdges(@[leftSpoke.leftEdge, rightSpoke.rightEdge], X);
		
		if (([tSqr compare: maxTimeSqr] < 0))
		//	if (([tSqr compare: maxTimeSqr] < 0) && ([tSqr compare: t0] >= 0))
		{
			PSCollapseEvent* event = [[PSCollapseEvent alloc] initWithLocation: [X toVectorWithShift: 16] time: tSqr creationTime: t0 waveFront: waveFront];
					
			[events addObject: event];
		}
	}
	[events sortWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PSEvent* obj0, PSEvent* obj1) {
		return [obj0 compare: obj1];
	}];
	
	if (events.count)
		return [events objectAtIndex: 0];

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

static PSSpoke* _newSpokeBetweenWavefrontsNoInsert(PSWaveFront* leftFront, PSWaveFront* rightFront, v3i_t loc, NSMutableArray* vertices)
{
	PSVirtualVertex* xVertex = [[PSVirtualVertex alloc] init];
	xVertex.leftEdge = leftFront.edge;
	xVertex.rightEdge = rightFront.edge;
	
	MPDecimal* cross = [[MPVector2D vectorWith3i: leftFront.edge.edge] cross: [MPVector2D vectorWith3i: rightFront.edge.edge]];
	
	if (!cross.isPositive && !cross.isZero)
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
static PSSpoke* _newSpokeBetweenWavefronts(PSWaveFront* leftFront, PSWaveFront* rightFront, v3i_t loc, NSMutableArray* vertices)
{	
	PSSpoke* newSpoke = _newSpokeBetweenWavefrontsNoInsert(leftFront, rightFront, loc, vertices);
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

static void _splitWaveFront(PSWaveFront* waveFront, PSWaveFront* leftFront, PSWaveFront* rightFront)
{

	
	leftFront.retiredLeftSpokes = waveFront.retiredLeftSpokes;
	rightFront.retiredRightSpokes = waveFront.retiredRightSpokes;
	
	leftFront.leftSpoke = waveFront.leftSpoke;
	rightFront.rightSpoke = waveFront.rightSpoke;
	
	leftFront.leftSpoke.rightWaveFront = leftFront;
	rightFront.rightSpoke.leftWaveFront = rightFront;
	
	leftFront.edge = waveFront.edge;
	rightFront.edge = waveFront.edge;
	
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
			
			if (area.x >= 0.0)
			{
				PSSimpleSpoke* spoke = [[PSSimpleSpoke alloc] init];
				spoke.sourceVertex = vertex;
				spoke.startLocation = vertex.position;
				
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
					
					if (isLeft)
					{
						PSWaveFront* termOpponent = tspoke.opposingWaveFront;
						if (!termOpponent)
							continue;
						//NSMutableArray* tmpVertices = [NSMutableArray array];
						//PSSpoke* tmpSpoke = _newSpokeBetweenWavefrontsNoInsert(tspoke.leftWaveFront, termOpponent, crash.location, tmpVertices);
						
						MPVector2D* splitLoc = _splitLocation(tspoke);
						
						BOOL splitsBeforeTerm = splitLoc && [[termOpponent.edge timeSqrToLocation: splitLoc] compare: [termOpponent.edge timeSqrToLocation: spoke.motorcycle.terminalVertex.mpPosition]] < 0;
						
						BOOL isOpposite = !splitsBeforeTerm;
						
						if (isOpposite)
						{
							spoke.opposingWaveFront = termOpponent;
							termOpponent.opposingSpokes = [termOpponent.opposingSpokes arrayByAddingObject: spoke];
							
						}
						else
						{
							spoke.opposingWaveFront = leftFront;
							leftFront.opposingSpokes = [leftFront.opposingSpokes arrayByAddingObject: spoke];
						}
						
					}
					else
					{
						PSWaveFront* termOpponent = tspoke.opposingWaveFront;
						if (!termOpponent)
							continue;

						MPVector2D* splitLoc = _splitLocation(tspoke);
						
						BOOL splitsBeforeTerm = splitLoc && [[termOpponent.edge timeSqrToLocation: splitLoc] compare: [termOpponent.edge timeSqrToLocation: spoke.motorcycle.terminalVertex.mpPosition]] < 0;
						
						BOOL isOpposite = !splitsBeforeTerm;
						
						if (isOpposite)
						{
							spoke.opposingWaveFront = termOpponent;
							termOpponent.opposingSpokes = [termOpponent.opposingSpokes arrayByAddingObject: spoke];
							
						}
						else
						{
							spoke.opposingWaveFront = rightFront;
							rightFront.opposingSpokes = [rightFront.opposingSpokes arrayByAddingObject: spoke];
						}
					}
					
				}
				else if ([crash isKindOfClass: [PSMotorcycleEdgeCrash class]])
				{
					PSMotorcycleEdgeCrash* ecrash = (id) crash;
					PSEdge* edge = ecrash.edge1;
					
					assert(edge.waveFronts.count == 1);
					
					PSWaveFront* opposing = edge.waveFronts.lastObject;
					
					spoke.opposingWaveFront = opposing;
					opposing.opposingSpokes = [opposing.opposingSpokes arrayByAddingObject: spoke];
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
					
					assert(spoke.opposingWaveFront);
				}
				
				[motorcycleSpokesToResolve removeObject: spoke];
			}
			if (aryCopy.count == motorcycleSpokesToResolve.count)
				break;
		}
	}
	
	MPDecimal* t0 = [[MPDecimal alloc] initWithInt64: 0 shift: 16];
	//MPDecimal* maxTimeSqr = [[MPDecimal alloc] initWithInt64: INT64_MAX shift: 32];

	NSMutableArray* events = [NSMutableArray array];
	
	//	for (NSNumber* timeval in [emissionTimes arrayByAddingObject: [NSNumber numberWithDouble: extensionLimit]])
	for (NSNumber* timeval in emissionTimes)
	{
		MPDecimal* time = [[MPDecimal alloc] initWithDouble: timeval.doubleValue*timeval.doubleValue];
		PSEmitEvent* event = [[PSEmitEvent alloc] initWithLocation: v3iCreate(INT32_MAX, INT32_MAX, INT32_MAX, 16) time: time creationTime: t0];
		
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
	
	while (events.count)
	{
		@autoreleasepool {
			
			[events sortWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PSEvent* obj0, PSEvent* obj1) {
				return [obj0 compare: obj1];
			}];

			// we have to coalesce events.
			// previously, we took care to only insert one event per involved spoke into the list, so now we should only have to combine consecutive events.
			
			
			PSEvent* firstEvent = [events objectAtIndex: 0];
			
			if ([firstEvent.timeSqr compare: [[MPDecimal alloc] initWithDouble: extensionLimit*extensionLimit]] > 0)
				break;
			
			NSMutableArray* concurrentEvents = [NSMutableArray array];
			
			for (PSEvent* event in events)
			{
				if (v3iEqual(firstEvent.location, event.location))
					[concurrentEvents addObject: event];
				else
					break;
			}

			NSMutableArray* changedSpokes = [NSMutableArray array];

			if ([firstEvent isKindOfClass: [PSCollapseEvent class]])
			{

#pragma mark FP Collapse Event Handling
			
				PSCollapseEvent* event = (id)firstEvent;
			
				PSWaveFront* waveFront = event.collapsingWaveFront;
			
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
				
				[activeSpokes removeObjectsInArray: @[leftSpoke, rightSpoke]];
				[activeWaveFronts removeObject: waveFront];
				[self terminateWaveFront: waveFront atLocation: event.location];
				
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
					//assert(v3iEqual(vertex.position, event.location));
					
					
					if (!leftSpoke.terminalVertex)
					{
						leftSpoke.terminalVertex = vertex;
						leftSpoke.endLocation = event.location;
						[terminatedSpokes addObject: leftSpoke];
						[activeSpokes removeObject: leftSpoke];
					}
					if (!rightSpoke.terminalVertex)
					{
						rightSpoke.terminalVertex = vertex;
						rightSpoke.endLocation = event.location;
						[terminatedSpokes addObject: rightSpoke];
						[activeSpokes removeObject: rightSpoke];
					}

					[eventLog addObject: [NSString stringWithFormat: @"  vertex %@", vertex]];
					
					
					
					if ([leftSpoke isKindOfClass: [PSMotorcycleSpoke class]])
					{
						PSMotorcycleSpoke* mspoke = (id) leftSpoke;
						//assert((mspoke.upcomingEvent == event) || (mspoke.upcomingEvent && ([mspoke.upcomingEvent.timeSqr compare: event.timeSqr] > 0)) || !mspoke.upcomingEvent);
						
						if (mspoke.opposingWaveFront)
						{							
							mspoke.opposingWaveFront.opposingSpokes = [mspoke.opposingWaveFront.opposingSpokes arrayByRemovingObject: mspoke];
							mspoke.opposingWaveFront = nil;
						}
					}
					if ([rightSpoke isKindOfClass: [PSMotorcycleSpoke class]])
					{
						PSMotorcycleSpoke* mspoke = (id) rightSpoke;
						//assert((mspoke.upcomingEvent == event) || (mspoke.upcomingEvent && ([mspoke.upcomingEvent.timeSqr compare: event.timeSqr] > 0)) || !mspoke.upcomingEvent);
						
						if (mspoke.opposingWaveFront)
						{							
							mspoke.opposingWaveFront.opposingSpokes = [mspoke.opposingWaveFront.opposingSpokes arrayByRemovingObject: mspoke];
							mspoke.opposingWaveFront = nil;
						}
					}
					
					BOOL lrConvex = [leftFront isConvexTo: rightFront];
					
					if (!lrConvex || (leftFront == rightFront))
					{
						[eventLog addObject: [NSString stringWithFormat: @"  looks like we're already all collapsed"]];
						[eventLog addObject: [NSString stringWithFormat: @"    waveL %@", leftFront]];
						[eventLog addObject: [NSString stringWithFormat: @"    waveR %@", rightFront]];
						
						assert(leftSpoke.terminalVertex || rightSpoke.terminalVertex);
						
						[activeWaveFronts removeObjectsInArray: @[leftFront, rightFront]];
						if (!leftFront.terminationTimeSqr)
							[self terminateWaveFront: leftFront atLocation: event.location];
						if (!rightFront.terminationTimeSqr)
							[self terminateWaveFront: rightFront atLocation: event.location];
						
						
					}
					else
					{
						PSSpoke* newSpoke = _newSpokeBetweenWavefronts(leftFront, rightFront, event.location, interiorVertices);
						
						[eventLog addObject: [NSString stringWithFormat: @"  new spoke to %@", newSpoke]];
						[eventLog addObject: [NSString stringWithFormat: @"    left %@", newSpoke.leftWaveFront]];
						[eventLog addObject: [NSString stringWithFormat: @"   right %@", newSpoke.rightWaveFront]];

						
						_assertWaveFrontConsistent(leftFront);
						_assertWaveFrontConsistent(rightFront);
						
						[activeSpokes addObject: newSpoke];
						[changedSpokes addObject: newSpoke];
						
						for (PSMotorcycleSpoke* ospoke in opposingSpokes)
						{
							// re-assign opposing wavefront to left or right neighbour
							
							if ([newSpoke isVertexCCWFromSpoke: ospoke.sourceVertex.mpPosition])
							{
								ospoke.opposingWaveFront = leftFront;
								leftFront.opposingSpokes = [leftFront.opposingSpokes arrayByAddingObject: ospoke];
							}
							else {
								ospoke.opposingWaveFront = rightFront;
								rightFront.opposingSpokes = [rightFront.opposingSpokes arrayByAddingObject: ospoke];
							}

						}
					}
				
				}
				
				[changedSpokes addObjectsFromArray: opposingSpokes];
			
			}
			else if ([firstEvent isKindOfClass: [PSSplitEvent class]])
			{
#pragma mark FP Split Event Handling
	
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
				
				[terminatedSpokes addObject: motorcycleSpoke];
				[changedSpokes addObject: motorcycleSpoke];
				[activeSpokes removeObject: motorcycleSpoke];
				motorcycleSpoke.endLocation = event.location;
				
				[changedSpokes addObjectsFromArray: @[leftFront.leftSpoke, rightFront.rightSpoke, opposingFront.leftSpoke, opposingFront.rightSpoke]];

				
				PSRealVertex* splitVertex = [[PSRealVertex alloc] init];
				[interiorVertices addObject: splitVertex];
				splitVertex.position = event.location;
				
				motorcycleSpoke.terminalVertex = splitVertex;
				
				opposingFront.opposingSpokes = [opposingFront.opposingSpokes arrayByRemovingObject: motorcycleSpoke];
				
				
				
				
				// unlike the earlier FP implementation, a split can't occur on a terminated motorcycle spoke.
				assert(motorcycleSpoke.leftWaveFront);
				assert(motorcycleSpoke.rightWaveFront);
				
				_assertWaveFrontConsistent(opposingFront);
				_assertWaveFrontConsistent(leftFront);
				_assertWaveFrontConsistent(rightFront);

				//assert(![motorcycleSpoke.mpNumerator dot: [MPVector2D vectorWith3i: _rotateEdgeToNormal(opposingFront.edge.edge)]].isZero);
				//assert(![motorcycleSpoke.mpNumerator dot: [MPVector2D vectorWith3i: _rotateEdgeToNormal(opposingFront.edge.edge)]].isPositive);
				
				
				
				BOOL shouldSplitLeft = [leftFront isConvexTo: opposingFront];
				BOOL shouldSplitRight = [opposingFront isConvexTo: rightFront];
				[eventLog addObject: [NSString stringWithFormat: @"   split left: %d", shouldSplitLeft]];
				[eventLog addObject: [NSString stringWithFormat: @"  split right: %d", shouldSplitRight]];

				PSWaveFront* newLeftFront = nil;
				PSWaveFront* newRightFront = nil;

				if (shouldSplitLeft && shouldSplitRight)
				{
					newLeftFront = [[PSWaveFront alloc] init];
					newRightFront = [[PSWaveFront alloc] init];

					_splitWaveFront(opposingFront, newLeftFront, newRightFront);

					[eventLog addObject: [NSString stringWithFormat: @"     new left:  %@", newLeftFront]];
					[eventLog addObject: [NSString stringWithFormat: @"    new right:  %@", newRightFront]];
					

					[activeWaveFronts removeObject: opposingFront];
					[self terminateWaveFront: opposingFront atLocation: event.location];
					[activeWaveFronts addObjectsFromArray: @[newLeftFront, newRightFront]];
				}
				else if (shouldSplitLeft)
				{
					newRightFront = opposingFront;
					
				}
				else if (shouldSplitRight)
				{
					newLeftFront = opposingFront;
				}
				
				if (shouldSplitLeft)
				{
					PSSpoke* leftSpoke =_newSpokeBetweenWavefronts(leftFront,  newRightFront, event.location, interiorVertices);
					assert(leftSpoke);
					
					[eventLog addObject: [NSString stringWithFormat: @"     new left spoke:  %@", leftSpoke]];

					[activeSpokes addObject: leftSpoke];
					[changedSpokes addObject: leftSpoke];
					[changedSpokes addObject: newRightFront.rightSpoke];
					[changedSpokes addObject: leftFront.leftSpoke];
				}
				else
				{
					[activeWaveFronts removeObject: leftFront];
					[self terminateWaveFront: leftFront atLocation: event.location];

					if (!leftFront.leftSpoke.terminalVertex)
					{
						[terminatedSpokes addObject: leftFront.leftSpoke];
						[activeSpokes removeObject: leftFront.leftSpoke];
						leftFront.leftSpoke.endLocation = event.location;
						leftFront.leftSpoke.terminalVertex = splitVertex;
					}
				}
				
				if (shouldSplitRight)
				{
					PSSpoke* rightSpoke =_newSpokeBetweenWavefronts(newLeftFront, rightFront, event.location, interiorVertices);
					assert(rightSpoke);
					
					[eventLog addObject: [NSString stringWithFormat: @"    new right spoke:  %@", rightSpoke]];

					[activeSpokes addObject: rightSpoke];
					[changedSpokes addObject: rightSpoke];
					[changedSpokes addObject: newLeftFront.leftSpoke];
					[changedSpokes addObject: rightFront.rightSpoke];
				}
				else
				{
					[self terminateWaveFront: rightFront atLocation: event.location];
					[activeWaveFronts removeObject: rightFront];

					if (!rightFront.rightSpoke.terminalVertex)
					{
						[terminatedSpokes addObject: rightFront.rightSpoke];
						[activeSpokes removeObject: rightFront.rightSpoke];
						rightFront.rightSpoke.endLocation = event.location;
						rightFront.rightSpoke.terminalVertex = splitVertex;
					}
				}
				
				if (shouldSplitLeft && shouldSplitRight)
				{
					assert(fabs([newLeftFront.rightSpoke.mpDirection angleTo: newRightFront.leftSpoke.mpDirection]) > 1e-3);
				}
				
				//_assertWaveFrontConsistent(leftFront);
				//_assertWaveFrontConsistent(rightFront);
				if (newLeftFront)
				{
					_assertWaveFrontConsistent(newLeftFront);
					_assertWaveFrontConsistent(newLeftFront.leftSpoke.leftWaveFront);
					_assertWaveFrontConsistent(rightFront);
					_assertWaveFrontConsistent(rightFront.rightSpoke.rightWaveFront);
				}
				if (newRightFront)
				{
					_assertWaveFrontConsistent(newRightFront);
					_assertWaveFrontConsistent(newRightFront.rightSpoke.rightWaveFront);
					_assertWaveFrontConsistent(leftFront);
					_assertWaveFrontConsistent(leftFront.leftSpoke.leftWaveFront);
				}
				if (!(shouldSplitLeft && shouldSplitRight))
					_assertWaveFrontConsistent(opposingFront);
				if ([activeSpokes containsObject: opposingFront])
					_assertWaveFrontConsistent(opposingFront);

				NSArray* opposingSpokes = opposingFront.opposingSpokes.copy;
				opposingFront.opposingSpokes = @[];
				
				for (PSMotorcycleSpoke* mspoke in opposingSpokes)
				{
					[changedSpokes addObject: mspoke];
					
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
					
				}
				
			}
			else if ([firstEvent isKindOfClass: [PSEmitEvent class]])
			{
#pragma mark FP Emit Event Handling
				[self emitOffsetOutlineForWaveFronts: activeWaveFronts atTime: firstEvent.timeSqr];
			
			}
			else if ([firstEvent isKindOfClass: [PSSwapEvent class]])
			{
#pragma mark FP Swap Event Handling
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
				}
				else if ([pivot isVertexCCWFromSpoke: motorcycleSpoke.sourceVertex.mpPosition])
				{
					PSWaveFront* front = leftFront;
					if ((front != motorcycleSpoke.leftWaveFront) && (front != motorcycleSpoke.rightWaveFront) && [motorcycleSpoke.mpDirection dot: [MPVector2D vectorWith3i: _rotateEdgeToNormal(front.edge.edge)]].isNegative)
					{
						motorcycleSpoke.opposingWaveFront = front;
						front.opposingSpokes = [front.opposingSpokes arrayByAddingObject: motorcycleSpoke];
					}
				}
				else
				{
					PSWaveFront* front = rightFront;
					if ((front != motorcycleSpoke.leftWaveFront) && (front != motorcycleSpoke.rightWaveFront) && [motorcycleSpoke.mpDirection dot: [MPVector2D vectorWith3i: _rotateEdgeToNormal(front.edge.edge)]].isNegative)
					{
						motorcycleSpoke.opposingWaveFront = front;
						front.opposingSpokes = [front.opposingSpokes arrayByAddingObject: motorcycleSpoke];
					}
				}

				
			}
			else
				assert(0); // unknown event type, oops
			
			
			_assertWaveFrontsConsistent(activeWaveFronts);

			[events removeObject: firstEvent];
			
			NSMutableSet* invalidEvents = [NSMutableSet set];
			
			for (PSSpoke* spoke in changedSpokes)
			{
				
				if (spoke.upcomingEvent)
					[invalidEvents addObject: spoke.upcomingEvent];
				spoke.upcomingEvent = nil;
			}
			
			[events removeObjectsInArray: invalidEvents.allObjects];
			
			
			for (PSSpoke* spoke in changedSpokes)
			{
				// while waveFronts shouldnt be added to the changedWaveFronts more than once, it could happen, and we want to handle it gracefully at this point.
				if (spoke.upcomingEvent)
					continue;
				if (![activeSpokes containsObject: spoke])
					continue;
				
				
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
		
		[interiorVertices addObject: vertex];
		
		[terminatedSpokes addObject: spoke];
	}
	
}

#if 0
- (void) runSpokes
{
	/*
	 The major events are:
		face collapse
		face split
			motorcycle hits face direct
			motorcycle hits face with trace crash
	 
	 spoke needs to be started for each vertex. 
	 
	 - each regular spoke may collide only with its direct neighbour
	 - a motorcycle spoke will collide with its anti-spoke
	 - anti-spokes may collide with neighbours, merge, and emit a new anti-spoke until the motorcycle spoke is reached.
	 
	 a motorcycle that hits an edge:
	  - may terminate in other wavefront, but: anti-spoke checks that.
	 
	 a motorcycle that hits a motorcycle trace:
	 - will necessarily terminate in a known wavefront
	 
	 */
	
	if (extensionLimit == 0.0)
		return;
	
	
	NSMutableArray* normalSpokes = [NSMutableArray array];
	NSMutableArray* motorcycleSpokes = [NSMutableArray array];
	NSMutableArray* antiSpokes = [NSMutableArray array];
	NSMutableArray* startingSpokes = [NSMutableArray array];

	
	/*
	 normal vertices emit motorcycle and normal spokes, and they might also emit anti-spokes
	 */
	
	@autoreleasepool {
		for (PSMotorcycle* motorcycle in terminatedMotorcycles)
		{
			NSMutableArray* newCycleSpokes = [NSMutableArray array];
			NSMutableArray* newAntiSpokes = [NSMutableArray array];
			_generateCycleSpoke(motorcycle, newCycleSpokes, newAntiSpokes);
			
			[startingSpokes addObjectsFromArray: newCycleSpokes];
			[startingSpokes addObjectsFromArray: newAntiSpokes];
			[motorcycleSpokes addObjectsFromArray: newCycleSpokes];
			[antiSpokes addObjectsFromArray: newAntiSpokes];
		}
	}
	
	for (PSVertex* vertex in originalVertices)
	{
		@autoreleasepool {
						
			PSSourceEdge* edge0 = vertex.leftEdge;
			PSSourceEdge* edge1 = vertex.rightEdge;
			assert(edge0.rightVertex == vertex);
			assert(edge1.leftVertex == vertex);
		
			vector_t v = bisectorVelocity(edge0.normal, edge1.normal, edge0.edge, edge1.edge);
			double area = vCross(edge0.edge, edge1.edge).farr[2];

			if (area >= 0.0)
			{
				PSSimpleSpoke* spoke = [[PSSimpleSpoke alloc] init];
				spoke.sourceVertex = vertex;
				spoke.velocity = v;
				spoke.start = 0.0;
				assert(!vIsNAN(spoke.velocity));

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
					
					[normalSpokes addObject: spoke];
					[startingSpokes addObject: spoke];
					[vertex addSpoke: spoke];
				}
			}
			else
				assert(vertex.outgoingMotorcycles);
			assert(vertex.outgoingSpokes.count);
		}
	
	}
	

	/*
	 spokes are setup, time to generate wavefronts
	 */
	
	NSMutableArray* activeWaveFronts = [NSMutableArray array];
	
	
	NSMutableArray* eventLog = [NSMutableArray array];

	for (PSSimpleSpoke* leftSpoke in startingSpokes)
	{
		@autoreleasepool {
			if (leftSpoke.start > 0.0)
				continue;
			
			
			PSVertex* sourceVertex = leftSpoke.sourceVertex;
			
			PSSpoke* rightSpoke = [sourceVertex nextSpokeClockwiseFrom: leftSpoke.velocity to: sourceVertex.rightEdge.edge];
			
			if (!rightSpoke)
			{
				PSVertex* nextVertex = sourceVertex.rightEdge.rightVertex;
				assert(nextVertex);
				rightSpoke = [nextVertex nextSpokeClockwiseFrom: vNegate(sourceVertex.rightEdge.edge) to: nextVertex.rightEdge.edge];
				assert(rightSpoke);
			}
			assert(rightSpoke);
			
			assert(!leftSpoke.rightWaveFront);
			assert(!rightSpoke.leftWaveFront);
			
			PSWaveFront* waveFront = [[PSWaveFront alloc] init];
			waveFront.leftSpoke = leftSpoke;
			waveFront.rightSpoke = rightSpoke;
			waveFront.direction = leftSpoke.sourceVertex.rightEdge.normal;
			
			leftSpoke.rightWaveFront = waveFront;
			rightSpoke.leftWaveFront = waveFront;
			
			assert(waveFront.leftSpoke != waveFront.rightSpoke);
			assert(waveFront.leftSpoke && waveFront.rightSpoke);
						
			[activeWaveFronts addObject: waveFront];
		}
	}
	
	// now we have the collapsing wavefronts, plus the motorcycle induced splits
	// the splits are just potential at this point, as a collapsing wavefront along an anti-spoke means the anti-spoke may change speed.

	// generate events
	
	NSMutableArray* events = [NSMutableArray array];
	
//	for (NSNumber* timeval in [emissionTimes arrayByAddingObject: [NSNumber numberWithDouble: extensionLimit]])
	for (NSNumber* timeval in emissionTimes)
	{
		PSEmitEvent* event = [[PSEmitEvent alloc] init];
		event.time = [timeval doubleValue];
		
		[events addObject: event];
	}
	
	
	for (PSWaveFront* waveFront in activeWaveFronts)
	{
		assert(waveFront.leftSpoke);
		assert(waveFront.rightSpoke);
		assert(waveFront.leftSpoke.leftWaveFront);
		assert(waveFront.rightSpoke.rightWaveFront);
		assert(waveFront.leftSpoke.rightWaveFront == waveFront);
		assert(waveFront.rightSpoke.leftWaveFront == waveFront);
		PSCollapseEvent* event = [self computeCollapseEvent: waveFront];
		
		waveFront.collapseEvent = event;

		if (event)
			[events addObject: event];
		
	}
	
	for (PSMotorcycleSpoke* cycleSpoke in motorcycleSpokes)
	{
		cycleSpoke.upcomingEvent = [self nextEventForMotorcycle: cycleSpoke.motorcycle atTime: 0.0];
		
		
		if (cycleSpoke.upcomingEvent)
		{
			[events addObject: cycleSpoke.upcomingEvent];
		}
	}
	
	// prune events that occur after extensionLimit
	if (0)
	{
		NSMutableArray* prunedEvents = [NSMutableArray array];
		
		for (PSEvent* event in events)
		{
			if (event.time <= extensionLimit)
				[prunedEvents addObject: event];
		}
		
		events = prunedEvents;
	}
	
	
	NSMutableArray* collapsedVertices = [NSMutableArray array];
	
	double lastEventTime = 0.0;
	
	NSArray* eventClassOrder = @[[PSBranchEvent class], [PSReverseBranchEvent class], [PSSplitEvent class], [PSCollapseEvent class], [PSEmitEvent class], [PSEvent class]];
	
	while (events.count)
	{ @autoreleasepool {

		[events sortWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PSEvent* obj0, PSEvent* obj1) {
			
			double t0 = obj0.time;
			double t1 = obj1.time;
			
			// FIXME: attempt to fix issue #1 by adding additional sort parameter (nope, doesnt seem to be it)
			if (t0 == t1)
			{
				NSUInteger i0 = [eventClassOrder indexOfObject: [obj0 class]];
				NSUInteger i1 = [eventClassOrder indexOfObject: [obj1 class]];
				if (i0 != i1)
					return ulcompare(i0, i1);
				else
					return fcompare(obj0.creationTime, obj1.creationTime);
			}
			
			return fcompare(t0, t1);
		}];

		PSEvent* firstEvent = [events objectAtIndex: 0];
		
		if (firstEvent.time > extensionLimit)
			break;
		
		assert(firstEvent.time >= lastEventTime);
		lastEventTime = firstEvent.time;
		
		// an array, not a set, to keep the relative ordering of "changes", eg first change should also result in first event if event times are equal.
		NSMutableArray* changedWaveFronts = [NSMutableArray array];
		
		if ([firstEvent isKindOfClass: [PSCollapseEvent class]])
		{
#pragma mark Collapse Event Handling
			PSCollapseEvent* event = (id)firstEvent;
			
			PSWaveFront* waveFront = event.collapsingWaveFront;
			
			
			
			PSSpoke* leftSpoke = waveFront.leftSpoke;
			PSSpoke* rightSpoke = waveFront.rightSpoke;
			
			PSWaveFront* leftFront = leftSpoke.leftWaveFront;
			PSWaveFront* rightFront = rightSpoke.rightWaveFront;
			
			_assertWaveFrontConsistent(waveFront);
//			_assertWaveFrontConsistent(leftFront);
//			_assertWaveFrontConsistent(rightFront);
			
			assert(waveFront);
			assert(leftSpoke);
			assert(rightSpoke);
			assert(leftFront);
			assert(rightFront);
			
			[eventLog addObject: [NSString stringWithFormat: @"%f: collapsing @ %f, %f", event.time, event.location.farr[0], event.location.farr[1]]];
			[eventLog addObject: [NSString stringWithFormat: @"  wavefront %@", waveFront]];
			[eventLog addObject: [NSString stringWithFormat: @"  %@", waveFront.leftSpoke]];
			[eventLog addObject: [NSString stringWithFormat: @"  %@", waveFront.rightSpoke]];

			
			[changedWaveFronts addObject: waveFront];
			[activeWaveFronts removeObject: waveFront];
			[self terminateWaveFront: waveFront atTime: event.time];
			
			// TODO: investigate when invalid collapse with both source vertices the same occurs
			// seems to have no ill effects, though, only occurs so far as the result of a three-way branch event.
			//assert(leftSpoke.sourceVertex != rightSpoke.sourceVertex);

			if (leftSpoke.terminalVertex && rightSpoke.terminalVertex)
			{
				// this doesn't quite seem correct
				[eventLog addObject: [NSString stringWithFormat: @"  nothing to do, left and right spokes already terminated"]];
			}
			else
			{
				BOOL leftCycle = NO;
				BOOL rightCycle = NO;
				
				PSVertex* newVertex = nil;

				BOOL bothMoto = ([leftSpoke isKindOfClass: [PSMotorcycleSpoke class]] || [leftSpoke isKindOfClass: [PSAntiSpoke class]]) && ([rightSpoke isKindOfClass: [PSMotorcycleSpoke class]] || [rightSpoke isKindOfClass: [PSAntiSpoke class]]);

				if ([leftSpoke isKindOfClass: [PSMotorcycleSpoke class]] && [rightSpoke isKindOfClass: [PSMotorcycleSpoke class]])
				{
					PSMotorcycleSpoke* leftCycleSpoke = (id) leftSpoke;
					PSMotorcycleSpoke* rightCycleSpoke = (id) rightSpoke;
					
					if (leftCycleSpoke.motorcycle == rightCycleSpoke.motorcycle.terminator)
					{
						leftCycle = YES;
						newVertex = rightCycleSpoke.motorcycle.terminalVertex;
					}
					else if (rightCycleSpoke.motorcycle == leftCycleSpoke.motorcycle.terminator)
					{
						rightCycle = YES;
						newVertex = leftCycleSpoke.motorcycle.terminalVertex;
					}
					else
						assert(0);
					
				}
				else if ([leftSpoke isKindOfClass: [PSMotorcycleSpoke class]] && ![rightSpoke isKindOfClass: [PSAntiSpoke class]])
					leftCycle = YES;
				else if ([rightSpoke isKindOfClass: [PSMotorcycleSpoke class]] && ![leftSpoke isKindOfClass: [PSAntiSpoke class]])
					rightCycle = YES;
				else if ([leftSpoke isKindOfClass: [PSAntiSpoke class]])
					leftCycle = YES;
				else if ([rightSpoke isKindOfClass: [PSAntiSpoke class]])
					rightCycle = YES;

				
				if (leftSpoke.terminalVertex && !newVertex)
				{
					rightSpoke.terminalVertex = leftSpoke.terminalVertex;
					rightSpoke.terminationTime = event.time;
					newVertex = leftSpoke.terminalVertex;
					[terminatedSpokes addObject: rightSpoke];
					[changedWaveFronts addObject: rightFront];
				}
				else if (rightSpoke.terminalVertex && !newVertex)
				{
					leftSpoke.terminalVertex = rightSpoke.terminalVertex;
					leftSpoke.terminationTime = event.time;
					newVertex = rightSpoke.terminalVertex;
					[terminatedSpokes addObject: leftSpoke];
					[changedWaveFronts addObject: leftFront];
				}
				else
				{
				
					if (!newVertex)
					{
						newVertex = [[PSVertex alloc] init];
						newVertex.time = event.time;
						[collapsedVertices addObject: newVertex];
						vector_t xPos = event.location;
						newVertex.position = xPos;
					}

					if (!leftSpoke.terminalVertex)
					{
						leftSpoke.terminalVertex = newVertex;
						leftSpoke.terminationTime = event.time;
						[terminatedSpokes addObject: leftSpoke];
					}
					if (!rightSpoke.terminalVertex)
					{
						rightSpoke.terminalVertex = newVertex;
						rightSpoke.terminationTime = event.time;
						[terminatedSpokes addObject: rightSpoke];
					}
					[changedWaveFronts addObject: leftFront];
					[changedWaveFronts addObject: rightFront];
				
				}
				
				assert(newVertex);
				
				[eventLog addObject: [NSString stringWithFormat: @"  newvertex %@", newVertex]];

				if ((leftCycle) || (rightCycle))
				{
					/*
					 fundamentally, this is for flipping anti-spokes. the vDot() condition is important, it checks if the neighbouring front is coming up "backwards" relative to the antiSpoke. if that is the case, the anti-spoke can be terminated as a regular spoke, without needing to be "flipped".
					 
					 A condition like
					 (((PSAntiSpoke*)leftSpoke).motorcycleSpoke.leftWaveFront.leftSpoke != rightSpoke)
					 is too narrow and does not work for the same purpose.
					 */
					
					PSSimpleSpoke* motorSpoke = (id)(leftCycle ? leftSpoke : rightSpoke);
//					PSSimpleSpoke* nonMotorSpoke = (id)(leftCycle ? rightSpoke : leftSpoke);
					PSMotorcycle* motorcycle = [(id)motorSpoke motorcycle];
					

					motorSpoke.terminalVertex = newVertex;
					motorSpoke.terminationTime = event.time;
					[newVertex addSpoke: motorSpoke];
					[terminatedSpokes addObject: motorSpoke];
					
					// make a "steamrolled" test
					//BOOL steamRolled = (vDot(motorSpoke.velocity, leftFront.direction) <= 0.0)
					//				|| (vDot(motorSpoke.velocity, rightFront.direction) <= 0.0);
					
					
					BOOL motorContinues = NO;
					
					BOOL antiParallel =
						_vectorsAreAntiParallel(motorSpoke.velocity, _normalToEdge(leftFront.direction))
					|| _vectorsAreAntiParallel(motorSpoke.velocity, _normalToEdge(rightFront.direction))
					|| _vectorsAreAntiParallel(motorSpoke.velocity, vNegate(_normalToEdge(leftFront.direction)))
					|| _vectorsAreAntiParallel(motorSpoke.velocity, vNegate(_normalToEdge(rightFront.direction)));
					

					
					
					if (leftCycle && (vDot(rightFront.direction, ((PSMotorcycleSpoke*)leftSpoke).velocity) > 0.0))
						motorContinues = YES;
					else if (rightCycle && (vDot(leftFront.direction, ((PSMotorcycleSpoke*)rightSpoke).velocity) > 0.0))
						motorContinues = YES;
					
					// if terminatedWithoutSplit is set, should not continue.
					motorContinues = motorContinues && !motorcycle.terminatedWithoutSplit;

					if (antiParallel)
					{
						/*
						 
						 in this case a more or less exactly perpendicular wavefront steamrolls the motorcycle from the side. the motorcycle will never split, so the motorcycle spokes can be stopped.
						 
						 
						 */
						motorcycle.terminatedWithoutSplit = YES;

						[eventLog addObject: [NSString stringWithFormat: @"  steamrolled motorcycle %@", motorSpoke]];
						[eventLog addObject: [NSString stringWithFormat: @"    leftFront %@", leftFront]];
						[eventLog addObject: [NSString stringWithFormat: @"    rightFront %@", rightFront]];
						
						
						PSSpoke* newSpoke = _createSpokeBetweenFronts(leftFront, rightFront, newVertex, event.time);
						assert(newSpoke.sourceVertex);
						[eventLog addObject: [NSString stringWithFormat: @"  new spoke to %@", newSpoke]];
						
						newSpoke.leftWaveFront = leftFront;
						newSpoke.rightWaveFront = rightFront;
						leftFront.rightSpoke = newSpoke;
						rightFront.leftSpoke = newSpoke;
						
						[changedWaveFronts addObject: leftFront];
						[changedWaveFronts addObject: rightFront];
						
						
						
						PSMotorcycleSpoke* motorcycleSpoke = motorcycle.spoke;
						if (motorcycleSpoke.upcomingEvent)
							[events removeObject: motorcycleSpoke.upcomingEvent];
						
					}
					else if (motorContinues)
					{
						[eventLog addObject: [NSString stringWithFormat: @"  collapsing motorcycle %@", motorSpoke]];
						
						[self swapSpoke: motorSpoke];
						
						motorSpoke.start = event.time;
						motorSpoke.sourceVertex = newVertex;
						[newVertex addSpoke: motorSpoke];
						
						// logic here is empirically established, not really thought through.
						// should create no new spoke if the continuing spoke is an "uncollapsed" motorycle, eg. the motorcycle is the angle bisector
						// or when the motorcycle is not the angle bisector, but both fronts are equal
						if (v3Equal(leftFront.direction, rightFront.direction) || bothMoto)
						//if (v3Equal(leftFront.direction, motorSpoke.leftWaveFront.direction) && v3Equal(rightFront.direction, motorSpoke.rightWaveFront.direction))
						{
							// seems to work
							[eventLog addObject: [NSString stringWithFormat: @"  no new spoke, wavefronts equal in direction or motorcycle is bisector"]];
							[eventLog addObject: [NSString stringWithFormat: @"    %@", leftFront]];
							[eventLog addObject: [NSString stringWithFormat: @"    %@", rightFront]];
							
							leftFront.rightSpoke = motorSpoke;
							rightFront.leftSpoke = motorSpoke;
							motorSpoke.leftWaveFront = leftFront;
							motorSpoke.rightWaveFront = rightFront;
							[changedWaveFronts addObject: leftFront];
							[changedWaveFronts addObject: rightFront];
						}
						else
						{
							assert(!v3Equal(leftFront.direction, rightFront.direction));
							PSSpoke* newSpoke = _createSpokeBetweenFronts(leftFront, rightFront, newVertex, event.time);
							assert(newSpoke.sourceVertex);
							[eventLog addObject: [NSString stringWithFormat: @"  new spoke to %@", newSpoke]];
							
							double angle = _angleBetweenSpokes(motorSpoke, newSpoke);
							BOOL isLeft = angle > 0.0;
							
							
							
							vector_t direction = isLeft ? rightFront.direction : leftFront.direction;
							
							motorSpoke.velocity = vReverseProject(direction, motorcycle.velocity);
							
							PSWaveFront* newFront = [[PSWaveFront alloc] init];
							newFront.direction = direction;
							newFront.leftSpoke = isLeft ? newSpoke : motorSpoke;
							newFront.rightSpoke = isLeft ? motorSpoke : newSpoke;
							
							leftFront.rightSpoke = isLeft ? newSpoke : motorSpoke;
							rightFront.leftSpoke = isLeft ? motorSpoke : newSpoke;
							
							leftFront.rightSpoke.leftWaveFront = leftFront;
							leftFront.rightSpoke.rightWaveFront = newFront;
							rightFront.leftSpoke.leftWaveFront = newFront;
							rightFront.leftSpoke.rightWaveFront = rightFront;

							
							[changedWaveFronts addObject: newFront];
							[activeWaveFronts addObject: newFront];
							
							waveFront.successor = newFront;
						}

						PSMotorcycleSpoke* motorcycleSpoke = motorcycle.spoke;
						if (motorcycleSpoke.upcomingEvent)
							[events removeObject: motorcycleSpoke.upcomingEvent];
						
						motorcycleSpoke.upcomingEvent = [self nextEventForMotorcycle: motorcycleSpoke.motorcycle atTime: event.time];
						if (motorcycleSpoke.upcomingEvent)
							[events addObject: motorcycleSpoke.upcomingEvent];
					}
					else
					{
						[eventLog addObject: [NSString stringWithFormat: @"  dead collapse, not continuing"]];
						
						
						// FIXME: we should get this out of the active loop, by reassigning non-motorcycle spoke.
						
						
						
						
						// FIXME: seems like we should look more carefully here, in case of a "backwards" steamroll
						/*
						leftFront.rightSpoke = newSpoke;
						rightFront.leftSpoke = newSpoke;
						newSpoke.leftWaveFront = leftFront;
						newSpoke.rightWaveFront	= rightFront;
						
						_assertWaveFrontConsistent(leftFront);
						_assertWaveFrontConsistent(rightFront);
						 */
					}
					
				}				
				else if (leftFront == rightFront)
				{
					// doing nothing here seems right
					
				}
				else if (vCross(leftFront.direction, rightFront.direction).farr[2] < 0.0)
				{
					// this case marks a "closing" collapse, no new spoke should be generated, as it would just go the "wrong" direction
					// it is assumed that the neighbouring wavefronts also collapse simultaneously, on their own
					[eventLog addObject: [NSString stringWithFormat: @"  closing collapse of %@", waveFront]];
					_assertWaveFrontConsistent(waveFront);
					
				}
				else
				{				
					PSSpoke* newSpoke = _createSpokeBetweenFronts(leftFront,  rightFront,  newVertex,  event.time);
					assert(newSpoke.sourceVertex);
					[eventLog addObject: [NSString stringWithFormat: @"  new spoke to %@", newSpoke]];

					leftFront.rightSpoke = newSpoke;
					rightFront.leftSpoke = newSpoke;
					newSpoke.leftWaveFront = leftFront;
					newSpoke.rightWaveFront	= rightFront;
									
					_assertWaveFrontConsistent(leftFront);
					_assertWaveFrontConsistent(rightFront);
									
					if (!leftSpoke.convex)
					{
						id spoke = leftSpoke;
						
						if ([spoke motorcycle].spoke.upcomingEvent)
							[events removeObject: [spoke motorcycle].spoke.upcomingEvent];

						if (([spoke motorcycle].spoke.upcomingEvent = [self nextEventForMotorcycle: [spoke motorcycle] atTime: event.time]))
							[events addObject: [spoke motorcycle].spoke.upcomingEvent];

						if (leftSpoke.leftWaveFront)
							[changedWaveFronts addObject: leftSpoke.leftWaveFront];
						if (leftSpoke.rightWaveFront)
							[changedWaveFronts addObject: leftSpoke.rightWaveFront];
					}
					if (!rightSpoke.convex)
					{
						id spoke = rightSpoke;
						
						if ([spoke motorcycle].spoke.upcomingEvent)
							[events removeObject: [spoke motorcycle].spoke.upcomingEvent];
						
						if (([spoke motorcycle].spoke.upcomingEvent = [self nextEventForMotorcycle: [spoke motorcycle] atTime: event.time]))
							[events addObject: [spoke motorcycle].spoke.upcomingEvent];

						if (rightSpoke.leftWaveFront)
							[changedWaveFronts addObject: rightSpoke.leftWaveFront];
						if (rightSpoke.rightWaveFront)
							[changedWaveFronts addObject: rightSpoke.rightWaveFront];
					}


				}
			}
		}
		else if ([firstEvent isKindOfClass: [PSEmitEvent class]])
		{
#pragma mark Emit Event Handling
			[self emitOffsetOutlineForWaveFronts: activeWaveFronts atTime: firstEvent.time];
		}
		else if ([firstEvent isKindOfClass: [PSSplitEvent class]])
		{
#pragma mark Split Event Handling
			PSSplitEvent* event = (id)firstEvent;
			PSAntiSpoke* antiSpoke = event.antiSpoke;
			PSMotorcycleSpoke* motorcycleSpoke = antiSpoke.motorcycleSpoke;
						
			assert(motorcycleSpoke);
			assert(motorcycleSpoke.motorcycle);
			assert(!motorcycleSpoke.motorcycle.terminatedWithoutSplit);
			assert(!motorcycleSpoke.motorcycle.terminatedWithSplit);
			
			motorcycleSpoke.motorcycle.terminatedWithSplit = YES;
			[eventLog addObject: [NSString stringWithFormat: @"%f: split @ %f, %f", event.time, event.location.farr[0], event.location.farr[1]]];

			
			if (!motorcycleSpoke.leftWaveFront || !motorcycleSpoke.rightWaveFront)
			{
				[eventLog addObject: [NSString stringWithFormat: @"  ignoring wavefront split due to cancelled motorcycle: %@", event.antiSpoke]];
				
			}
			else
			{
				[eventLog addObject: [NSString stringWithFormat: @"  splitting wavefront anti-spoke %@", event.antiSpoke]];
				
				
				
				PSVertex* newVertex = nil;

				if (antiSpoke.terminalVertex && motorcycleSpoke.terminalVertex)
				{
					[eventLog addObject: [NSString stringWithFormat: @"  both spokes already terminated %@", motorcycleSpoke]];
					newVertex = motorcycleSpoke.terminalVertex;
				}
				else if (motorcycleSpoke.terminalVertex)
				{
					[eventLog addObject: [NSString stringWithFormat: @"  motorcycle spoke already terminated %@", motorcycleSpoke]];
					//_assertSpokeConsistent(antiSpoke);
					
					newVertex = motorcycleSpoke.terminalVertex;

					antiSpoke.terminalVertex = newVertex;
					antiSpoke.terminationTime = event.time;
					[newVertex addSpoke: antiSpoke];
					
					motorcycleSpoke.upcomingEvent = nil;
					[changedWaveFronts addObject: antiSpoke.leftWaveFront];
					[changedWaveFronts addObject: antiSpoke.rightWaveFront];
					[terminatedSpokes addObject: antiSpoke];
				}
				else if (antiSpoke.terminalVertex)
				{
					[eventLog addObject: [NSString stringWithFormat: @"  anti spoke already terminated %@", motorcycleSpoke]];
					
					
					_assertSpokeConsistent(motorcycleSpoke);
					
					newVertex = antiSpoke.terminalVertex;
					
					motorcycleSpoke.terminalVertex = newVertex;
					motorcycleSpoke.terminationTime = event.time;
					[newVertex addSpoke: motorcycleSpoke];
					
					motorcycleSpoke.upcomingEvent = nil;
					[changedWaveFronts addObject: motorcycleSpoke.leftWaveFront];
					[changedWaveFronts addObject: motorcycleSpoke.rightWaveFront];
					[terminatedSpokes addObject: motorcycleSpoke];
					
				}
				else
				{
					[eventLog addObject: [NSString stringWithFormat: @"  creating new vertex"]];
					
					_assertSpokeConsistent(antiSpoke);
					_assertSpokeConsistent(motorcycleSpoke);
					
					_assertWaveFrontConsistent(antiSpoke.leftWaveFront);
					_assertWaveFrontConsistent(antiSpoke.rightWaveFront);
					_assertWaveFrontConsistent(motorcycleSpoke.leftWaveFront);
					_assertWaveFrontConsistent(motorcycleSpoke.rightWaveFront);
					
					newVertex = [[PSVertex alloc] init];
					newVertex.time = event.time;
					// FIXME: which spoke to chose, anti or normal?
					//newVertex.position = v3Add(antiSpoke.sourceVertex.position, v3MulScalar(antiSpoke.velocity, event.time - antiSpoke.start));
					newVertex.position = v3Add(motorcycleSpoke.sourceVertex.position, v3MulScalar(motorcycleSpoke.velocity, event.time - motorcycleSpoke.start));
					[collapsedVertices addObject: newVertex];
					
					antiSpoke.terminalVertex = newVertex;
					antiSpoke.terminationTime = event.time;
					motorcycleSpoke.terminalVertex = newVertex;
					motorcycleSpoke.terminationTime = event.time;
					[terminatedSpokes addObject: antiSpoke];
					[terminatedSpokes addObject: motorcycleSpoke];
				}
				
				assert(newVertex);

				{
					
					vector_t dx = v3Sub(newVertex.position, motorcycleSpoke.motorcycle.sourceVertex.position);
					double delta = fabs(vDot(dx, motorcycleSpoke.motorcycle.velocity) - vLength(dx)*vLength(motorcycleSpoke.motorcycle.velocity));
					if (delta > sqrt(FLT_EPSILON))
					{
						[eventLog addObject: [NSString stringWithFormat: @"  large deviation in vertex angle: %f", delta]];
						[eventLog addObject: [NSString stringWithFormat: @"    %@", newVertex]];
					}
					//assert(fabs(vDot(dx, motorcycleSpoke.motorcycle.velocity) - vLength(dx)*vLength(motorcycleSpoke.motorcycle.velocity)) < sqrt(FLT_EPSILON));
				}
				
				{
					if (antiSpoke.leftWaveFront.leftSpoke == motorcycleSpoke.rightWaveFront.rightSpoke)
					{
						[eventLog addObject: [NSString stringWithFormat: @"  looks like a terminating split to the left"]];

						PSSpoke* incomingSpoke = antiSpoke.leftWaveFront.leftSpoke;
						PSWaveFront* leftWaveFront = antiSpoke.leftWaveFront;
						PSWaveFront* rightWaveFront = motorcycleSpoke.rightWaveFront;
						
						if (!incomingSpoke.terminalVertex)
						{
							incomingSpoke.terminalVertex = newVertex;
							incomingSpoke.terminationTime = event.time;
							[newVertex addSpoke: incomingSpoke];
							
							[terminatedSpokes addObject: incomingSpoke];
							
						}
						
						if ([activeWaveFronts containsObject: rightWaveFront])
						{
							[self terminateWaveFront: rightWaveFront atTime: event.time];
							[activeWaveFronts removeObject: rightWaveFront];
							[changedWaveFronts addObject: rightWaveFront];
						}
						if ([activeWaveFronts containsObject: leftWaveFront])
						{
							[self terminateWaveFront: leftWaveFront atTime: event.time];
							[activeWaveFronts removeObject: leftWaveFront];
							[changedWaveFronts addObject: leftWaveFront];
						}
					}
					else
					{
						PSSpoke* newSpoke = _createSpokeBetweenFronts(antiSpoke.leftWaveFront, motorcycleSpoke.rightWaveFront, newVertex,  event.time);
						
						// FIXME: is it ok to remove this assert?
						//assert(_angleBetweenSpokes(antiSpoke, newSpoke) > 0.0);
						newSpoke.leftWaveFront = antiSpoke.leftWaveFront;
						newSpoke.rightWaveFront = motorcycleSpoke.rightWaveFront;
												
						newSpoke.leftWaveFront.rightSpoke = newSpoke;
						newSpoke.rightWaveFront.leftSpoke = newSpoke;
						
						_assertWaveFrontConsistent(newSpoke.leftWaveFront);
						_assertWaveFrontConsistent(newSpoke.rightWaveFront);
						
						[changedWaveFronts addObject: newSpoke.leftWaveFront];
						[changedWaveFronts addObject: newSpoke.rightWaveFront];
						
						[eventLog addObject: [NSString stringWithFormat: @"  new spoke to the left %@", newSpoke]];
						
						assert(_angleBetweenSpokes(antiSpoke, newSpoke) > 0.0);
					}
					
					if (antiSpoke.rightWaveFront.rightSpoke == motorcycleSpoke.leftWaveFront.leftSpoke)
					{
						[eventLog addObject: [NSString stringWithFormat: @"  looks like a terminating split to the right"]];

						PSSpoke* incomingSpoke = antiSpoke.rightWaveFront.rightSpoke;
						PSWaveFront* leftWaveFront = motorcycleSpoke.leftWaveFront;
						PSWaveFront* rightWaveFront = antiSpoke.rightWaveFront;
						
						if (!incomingSpoke.terminalVertex)
						{
							incomingSpoke.terminalVertex = newVertex;
							incomingSpoke.terminationTime = event.time;
							[newVertex addSpoke: incomingSpoke];
							
							[terminatedSpokes addObject: incomingSpoke];
							
						}
						
						if ([activeWaveFronts containsObject: rightWaveFront])
						{
							[self terminateWaveFront: rightWaveFront atTime: event.time];
							[activeWaveFronts removeObject: rightWaveFront];
							[changedWaveFronts addObject: rightWaveFront];
						}
						if ([activeWaveFronts containsObject: leftWaveFront])
						{
							[self terminateWaveFront: leftWaveFront atTime: event.time];
							[activeWaveFronts removeObject: leftWaveFront];
							[changedWaveFronts addObject: leftWaveFront];
						}
					}
					else
					{
						PSSpoke* newSpoke = _createSpokeBetweenFronts(motorcycleSpoke.leftWaveFront, antiSpoke.rightWaveFront, newVertex,  event.time);

						newSpoke.leftWaveFront = motorcycleSpoke.leftWaveFront;
						newSpoke.rightWaveFront = antiSpoke.rightWaveFront;
						

						newSpoke.leftWaveFront.rightSpoke = newSpoke;
						newSpoke.rightWaveFront.leftSpoke = newSpoke;
						
						
						_assertWaveFrontConsistent(newSpoke.leftWaveFront);
						_assertWaveFrontConsistent(newSpoke.rightWaveFront);
						
						[changedWaveFronts addObject: newSpoke.leftWaveFront];
						[changedWaveFronts addObject: newSpoke.rightWaveFront];
						
						[eventLog addObject: [NSString stringWithFormat: @"  new spoke to the right %@", newSpoke]];
						
						assert(_angleBetweenSpokes(antiSpoke, newSpoke) < 0.0);
					}
				}
			}

		}
		else if ([firstEvent isKindOfClass: [PSBranchEvent class]])
		{
#pragma mark Branch Event Handling
			PSBranchEvent* event = (id) firstEvent;
			[eventLog addObject: [NSString stringWithFormat: @"%f: branchinng @ %f, %f", event.time, event.location.farr[0], event.location.farr[1]]];
			[eventLog addObject: [NSString stringWithFormat: @"  root %@", event.rootSpoke]];
			// a branch simply inserts a new spoke+wavefront into the list, in the same direction as its parent
			
			assert(event.rootSpoke);
			assert(event.rootSpoke.rightWaveFront);
			assert(event.rootSpoke.leftWaveFront);
			
			_assertSpokeConsistent(event.rootSpoke);
			//_assertWaveFrontConsistent(event.rootSpoke.leftWaveFront);
			//_assertWaveFrontConsistent(event.rootSpoke.rightWaveFront);
			
			PSMotorcycleSpoke* rootMotorcycleSpoke = event.rootSpoke;
			rootMotorcycleSpoke.terminalVertex = event.branchVertex;
			rootMotorcycleSpoke.terminationTime = event.time;
			[terminatedSpokes addObject: rootMotorcycleSpoke];
			
			PSSimpleSpoke* rootSpoke = [self swapSpoke: rootMotorcycleSpoke];
			
			rootMotorcycleSpoke.sourceVertex = event.branchVertex;
			rootMotorcycleSpoke.start = event.time;
			[event.branchVertex addSpoke: rootMotorcycleSpoke];

			PSWaveFront* leftFront = rootSpoke.leftWaveFront;
			PSWaveFront* rightFront = rootSpoke.rightWaveFront;
			assert(leftFront);
			assert(rightFront);
			
			
			NSArray* vertexMotorcycles = event.branchVertex.multiBranchMotorcyclesCCW;
			NSMutableArray* killedMotorcycles = [NSMutableArray array];
			vertexMotorcycles = [vertexMotorcycles select: ^BOOL(PSMotorcycle* motorcycle) {
				vector_t mv = vNegate(motorcycle.velocity);
				if (motorcycle == rootMotorcycleSpoke.motorcycle)
					mv = motorcycle.velocity;
				double asinAlpha = vCross(rootSpoke.velocity, mv).farr[2];
				if (asinAlpha > 0.0)
				{
					double dotAlpha = vDot(leftFront.direction, mv);
					if (dotAlpha < 0.0)
					{
						[killedMotorcycles addObject: motorcycle];
						return NO;
					}
				}
				else
				{
					double dotAlpha = vDot(rightFront.direction, mv);
					if (dotAlpha < 0.0)
					{
						[killedMotorcycles addObject: motorcycle];
						return NO;
					}
				}
				return YES;
				
			}];
			if (vertexMotorcycles.count)
			{
				for (PSMotorcycle* motorcycle in vertexMotorcycles)
				{
					if (motorcycle == rootMotorcycleSpoke.motorcycle)
					{
						//PSMotorcycleSpoke* motorcycleSpoke = motorcycle.spoke;
						
						// do nothing, actually, its speed stays the same regardless
					}
					else
					{
						PSAntiSpoke* antiSpoke = motorcycle.antiSpoke;
						
						vector_t direction = vZero();
						
						double angle = vAngleBetweenVectors2D(rootSpoke.velocity, vNegate(motorcycle.velocity));
						if (angle > 0.0)
							direction = leftFront.direction;
						else
							direction = rightFront.direction;
						
						antiSpoke.velocity = vReverseProject(direction, antiSpoke.motorcycle.velocity);
						antiSpoke.start = event.time;
					}
					
				}
				
				if (vertexMotorcycles.count == 1)
				{
					rootMotorcycleSpoke.leftWaveFront = leftFront;
					rootMotorcycleSpoke.rightWaveFront = rightFront;
					leftFront.rightSpoke = rootMotorcycleSpoke;
					rightFront.leftSpoke = rootMotorcycleSpoke;
				}
				else
				{
					for (int i = 0; i+1 < vertexMotorcycles.count; ++i)
					{
						PSMotorcycle* motoR = [vertexMotorcycles objectAtIndex: i];
						PSMotorcycle* motoL = [vertexMotorcycles objectAtIndex: i+1];
						PSSimpleSpoke* rightSpoke = [motoR antiSpoke];
						PSSimpleSpoke* leftSpoke = [motoL antiSpoke];
						
						if (motoR == rootMotorcycleSpoke.motorcycle)
							rightSpoke = motoR.spoke;
						if (motoL == rootMotorcycleSpoke.motorcycle)
							leftSpoke = motoL.spoke;
						
						
						
						PSWaveFront* newFront = [[PSWaveFront alloc] init];
						
						newFront.leftSpoke = leftSpoke;
						newFront.rightSpoke = rightSpoke;
						leftSpoke.rightWaveFront = newFront;
						rightSpoke.leftWaveFront = newFront;
						
						if (i == 0)
						{
							rightSpoke.rightWaveFront = rightFront;
							rightFront.leftSpoke = rightSpoke;
						}
						if (i+1 == vertexMotorcycles.count-1)
						{
							leftSpoke.leftWaveFront = leftFront;
							leftFront.rightSpoke = leftSpoke;
						}
						
						
						double angle = vAngleBetweenVectors2D(rootSpoke.velocity, leftSpoke.velocity);
						if ((id)leftSpoke == rootMotorcycleSpoke)
							newFront.direction = rightFront.direction;
						else if (angle > 0.0)
							newFront.direction = leftFront.direction;
						else
							newFront.direction = rightFront.direction;
						
						//_assertWaveFrontConsistent(newFront);
						[changedWaveFronts addObject: newFront];
						[activeWaveFronts addObject: newFront];
					}
				}
				
			}
			for (PSMotorcycle* motorcycle in killedMotorcycles)
			{
				assert(motorcycle != rootMotorcycleSpoke.motorcycle);
				
				//PSAntiSpoke* deadSpoke = motorcycle.antiSpoke;

				[eventLog addObject: [NSString stringWithFormat: @"  killing spoke: %@", motorcycle.spoke]];
				motorcycle.terminatedWithoutSplit = YES;
				PSMotorcycleSpoke* cycleSpoke = motorcycle.spoke;
				cycleSpoke.terminationTime = event.time;
				cycleSpoke.terminalVertex = event.branchVertex;
				[terminatedSpokes addObject: cycleSpoke];

			}

			for (PSMotorcycle* motorcycle in vertexMotorcycles)
			{
				if (motorcycle != rootMotorcycleSpoke.motorcycle)
				{
					assert(motorcycle.antiSpoke.leftWaveFront);
					assert(motorcycle.antiSpoke.rightWaveFront);
					_assertWaveFrontConsistent(motorcycle.antiSpoke.leftWaveFront);
					_assertWaveFrontConsistent(motorcycle.antiSpoke.rightWaveFront);
					_assertSpokeConsistent(motorcycle.antiSpoke);
				}
				else
				{
					assert(motorcycle.spoke.leftWaveFront);
					assert(motorcycle.spoke.rightWaveFront);
					_assertWaveFrontConsistent(motorcycle.spoke.leftWaveFront);
					_assertWaveFrontConsistent(motorcycle.spoke.rightWaveFront);
					_assertSpokeConsistent(motorcycle.spoke);
				}
				
				if (motorcycle.spoke.upcomingEvent)
					[events removeObject: motorcycle.spoke.upcomingEvent];
				
				motorcycle.spoke.upcomingEvent = [self nextEventForMotorcycle: motorcycle atTime: event.time];
				if (motorcycle.spoke.upcomingEvent)
					[events addObject: motorcycle.spoke.upcomingEvent];
			}

			[changedWaveFronts addObject: leftFront];
			[changedWaveFronts addObject: rightFront];
			_assertWaveFrontConsistent(leftFront);
			_assertWaveFrontConsistent(rightFront);
#if 0 // FIXME: deprecated code branch, remove when no more regressions
			for (PSMotorcycle* motorcycle in vertexMotorcycles)
			{
				if (motorcycle.terminalVertex != event.branchVertex)
					continue;
				
				PSAntiSpoke* newSpoke = motorcycle.antiSpoke;
				

				[eventLog addObject: [NSString stringWithFormat: @"  branch moto: %@", motorcycle]];
				

				//double asinAlpha = vCross(event.rootSpoke.velocity, vNegate(motorcycle.velocity)).farr[2];
				double asinAlpha = vCross(rootSpoke.velocity, motorcycle.velocity).farr[2];
				
				
				PSWaveFront* newFront = [[PSWaveFront alloc] init];
				
				assert(newSpoke.sourceVertex == event.branchVertex);
				
				
				if (asinAlpha > 0.0) // alpha > 0 == to the right
				{
					/* check to make sure that motorcycle would ever exit the face. if it propagates opposite to the wavefront, its already obsolete
					 */
					double dotAlpha = vDot(rightFront.direction, motorcycle.velocity);
					
					if (dotAlpha >= 0.0)
					{
						[eventLog addObject: [NSString stringWithFormat: @"  killing spoke to the right: %@", motorcycle.spoke]];
						motorcycle.terminatedWithoutSplit = YES;
						PSMotorcycleSpoke* cycleSpoke = motorcycle.spoke;
						cycleSpoke.terminationTime = event.time;
						cycleSpoke.terminalVertex = event.branchVertex;
						[terminatedSpokes addObject: cycleSpoke];
						
						cycleSpoke.rightWaveFront.leftSpoke = rootMotorcycleSpoke;
						rootMotorcycleSpoke.rightWaveFront = cycleSpoke.rightWaveFront;
						rootMotorcycleSpoke.leftWaveFront = leftFront;
						leftFront.rightSpoke = rootMotorcycleSpoke;
						
						[changedWaveFronts addObject: cycleSpoke.rightWaveFront];
						
						PSWaveFront* waveFront = cycleSpoke.leftWaveFront;
						[activeWaveFronts removeObject: waveFront];
						[changedWaveFronts addObject: waveFront];
						[self terminateWaveFront: waveFront atTime: event.time];

						
						continue;
					}

					newSpoke.start = event.time;

					newFront.direction = rightFront.direction;
					newSpoke.leftWaveFront = newFront;
					newSpoke.rightWaveFront = rightFront;
					newFront.leftSpoke = rootMotorcycleSpoke;
					newFront.rightSpoke = newSpoke;
					
					rightFront.leftSpoke = newSpoke;
					leftFront.rightSpoke = rootMotorcycleSpoke;
					rootMotorcycleSpoke.leftWaveFront = leftFront;
					rootMotorcycleSpoke.rightWaveFront = newFront;
					
					[changedWaveFronts addObject: rightFront];

					
				}
				else // to the left
				{
					double dotAlpha = vDot(leftFront.direction, motorcycle.velocity);
					
					if (dotAlpha >= 0.0)
					{
						[eventLog addObject: [NSString stringWithFormat: @"  killing spoke to the left: %@", motorcycle.spoke]];
						motorcycle.terminatedWithoutSplit = YES;
						PSMotorcycleSpoke* cycleSpoke = motorcycle.spoke;
						cycleSpoke.terminationTime = event.time;
						cycleSpoke.terminalVertex = event.branchVertex;
						[terminatedSpokes addObject: cycleSpoke];
						
						cycleSpoke.leftWaveFront.rightSpoke = rootMotorcycleSpoke;
						rootMotorcycleSpoke.leftWaveFront = cycleSpoke.leftWaveFront;
						rootMotorcycleSpoke.rightWaveFront = rightFront;
						rightFront.leftSpoke = rootMotorcycleSpoke;
						
						[changedWaveFronts addObject: cycleSpoke.leftWaveFront];

						PSWaveFront* waveFront = cycleSpoke.rightWaveFront;
						[activeWaveFronts removeObject: waveFront];
						[changedWaveFronts addObject: waveFront];
						[self terminateWaveFront: waveFront atTime: event.time];
						
												
						
						continue;
					}
					
					newSpoke.start = event.time;

					newFront.direction = leftFront.direction;
					newSpoke.leftWaveFront = leftFront;
					newSpoke.rightWaveFront = newFront;
					newFront.leftSpoke = newSpoke;
					newFront.rightSpoke = rootMotorcycleSpoke;
					
					leftFront.rightSpoke = newSpoke;
					rightFront.leftSpoke = rootMotorcycleSpoke;
					rootMotorcycleSpoke.rightWaveFront = rightFront;
					rootMotorcycleSpoke.leftWaveFront = newFront;

					[changedWaveFronts addObject: leftFront];
				}
				
				newSpoke.velocity = vReverseProject(newFront.direction, (motorcycle.velocity));

				newSpoke.leftWaveFront.rightSpoke = newSpoke;
				newSpoke.rightWaveFront.leftSpoke = newSpoke;
				
				_assertWaveFrontConsistent(newSpoke.leftWaveFront);
				_assertWaveFrontConsistent(newSpoke.rightWaveFront);
				_assertWaveFrontConsistent(newFront);
				[changedWaveFronts addObject: newFront];
				[activeWaveFronts addObject: newFront];
				
				motorcycle.spoke.passedCrashVertex = event.branchVertex;
				
				if (motorcycle.spoke.upcomingEvent)
					[events removeObject: motorcycle.spoke.upcomingEvent];
				
				motorcycle.spoke.upcomingEvent = [self nextEventForMotorcycle: motorcycle atTime: event.time];
				if (motorcycle.spoke.upcomingEvent)
					[events addObject: motorcycle.spoke.upcomingEvent];
			}
			
			for (PSMotorcycle* motorcycle in event.branchVertex.outgoingMotorcycles)
			{
				motorcycle.spoke.passedCrashVertex = event.branchVertex;
				
				if (motorcycle.spoke.upcomingEvent)
					[events removeObject: motorcycle.spoke.upcomingEvent];
				
				motorcycle.spoke.upcomingEvent = [self nextEventForMotorcycle: motorcycle atTime: event.time];
				if (motorcycle.spoke.upcomingEvent)
					[events addObject: motorcycle.spoke.upcomingEvent];

			}
#endif
		}
		else if ([firstEvent isKindOfClass: [PSReverseBranchEvent class]])
		{
#pragma mark Reverse Branch Event Handling
			PSReverseBranchEvent* event = (id) firstEvent;

			[eventLog addObject: [NSString stringWithFormat: @"%f: reverse branch @ %f, %f", event.time, event.location.farr[0], event.location.farr[1]]];

			assert([event.rootSpoke isKindOfClass: [PSAntiSpoke class]]);
			
			PSAntiSpoke* reverseAntiSpoke = event.rootSpoke;
			PSCrashVertex* vertex = (id) event.branchVertex;
			
			reverseAntiSpoke.terminationTime = event.time;
			reverseAntiSpoke.terminalVertex = vertex;
			[terminatedSpokes addObject: reverseAntiSpoke];
			
			PSSimpleSpoke* reverseSpoke = [self swapSpoke: reverseAntiSpoke];
			
			reverseAntiSpoke.start = event.time;
			reverseAntiSpoke.sourceVertex = vertex;
			[vertex addSpoke: reverseAntiSpoke];
			

			[eventLog addObject: [NSString stringWithFormat: @"  root %@", reverseAntiSpoke]];
			[eventLog addObject: [NSString stringWithFormat: @"  vertex %@", vertex]];
			
			reverseAntiSpoke.passedCrashVertex = vertex;
			

			if (vertex.forwardEvent)
				[events removeObject: vertex.forwardEvent];
			
			PSWaveFront* leftFront = reverseSpoke.leftWaveFront;
			PSWaveFront* rightFront = reverseSpoke.rightWaveFront;
			
			NSArray* incomingMotorcycles = [vertex incomingMotorcyclesCCW];
			
			// dump those cycles that are going the wrong way
			// cycle goes the wrong way if: 
			incomingMotorcycles = [incomingMotorcycles select: ^BOOL(PSMotorcycle* motorcycle) {
				double asinAlpha = vCross(reverseSpoke.velocity, vNegate(motorcycle.velocity)).farr[2];
				if (asinAlpha > 0.0)
				{
					double dotAlpha = vDot(leftFront.direction, motorcycle.velocity);
					if (dotAlpha > 0.0)
						return NO;
				}
				else
				{
					double dotAlpha = vDot(rightFront.direction, motorcycle.velocity);
					if (dotAlpha > 0.0)
						return NO;
				}
				return YES;
				
			}];
			
			if (incomingMotorcycles.count)
			{
				for (PSMotorcycle* motorcycle in incomingMotorcycles)
				{
					PSAntiSpoke* antiSpoke = motorcycle.antiSpoke;
										
					vector_t direction = vZero();
					
					double angle = vAngleBetweenVectors2D(reverseSpoke.velocity, vNegate(motorcycle.velocity));
					if (angle > 0.0)
						direction = leftFront.direction;
					else
						direction = rightFront.direction;

					antiSpoke.velocity = vReverseProject(direction, antiSpoke.motorcycle.velocity);
					antiSpoke.start = event.time;


				}
				
				if (incomingMotorcycles.count == 1)
				{
					reverseAntiSpoke.leftWaveFront = leftFront;
					reverseAntiSpoke.rightWaveFront = rightFront;
					leftFront.rightSpoke = reverseAntiSpoke;
					rightFront.leftSpoke = reverseAntiSpoke;
				}
				else
				{
					for (int i = 0; i+1 < incomingMotorcycles.count; ++i)
					{
						PSAntiSpoke* rightSpoke = [[incomingMotorcycles objectAtIndex: i] antiSpoke];
						PSAntiSpoke* leftSpoke = [[incomingMotorcycles objectAtIndex: i+1] antiSpoke];
						PSWaveFront* newFront = [[PSWaveFront alloc] init];
						
						newFront.leftSpoke = leftSpoke;
						newFront.rightSpoke = rightSpoke;
						leftSpoke.rightWaveFront = newFront;
						rightSpoke.leftWaveFront = newFront;
						
						if (i == 0)
						{
							rightSpoke.rightWaveFront = rightFront;
							rightFront.leftSpoke = rightSpoke;
						}
						if (i+1 == incomingMotorcycles.count-1)
						{
							leftSpoke.leftWaveFront = leftFront;
							leftFront.rightSpoke = leftSpoke;
						}
						
						
							double angle = vAngleBetweenVectors2D(reverseSpoke.velocity, leftSpoke.velocity);
							if (leftSpoke == reverseAntiSpoke)
								newFront.direction = rightFront.direction;
							else if (angle > 0.0)
								newFront.direction = leftFront.direction;
							else
								newFront.direction = rightFront.direction;
							
						_assertWaveFrontConsistent(newFront);
						[changedWaveFronts addObject: newFront];
						[activeWaveFronts addObject: newFront];
						

					}
				}
				
				for (PSMotorcycle* motorcycle in incomingMotorcycles)
				{
					assert(motorcycle.antiSpoke.leftWaveFront);
					assert(motorcycle.antiSpoke.rightWaveFront);
					_assertWaveFrontConsistent(motorcycle.antiSpoke.leftWaveFront);
					_assertWaveFrontConsistent(motorcycle.antiSpoke.rightWaveFront);
					
					
					if (motorcycle.spoke.upcomingEvent)
						[events removeObject: motorcycle.spoke.upcomingEvent];
					
					motorcycle.spoke.upcomingEvent = [self nextEventForMotorcycle: motorcycle atTime: event.time];
					if (motorcycle.spoke.upcomingEvent)
						[events addObject: motorcycle.spoke.upcomingEvent];
				}

				
				[changedWaveFronts addObject: leftFront];
				[changedWaveFronts addObject: rightFront];
				_assertWaveFrontConsistent(leftFront);
				_assertWaveFrontConsistent(rightFront);
			}
		}
		else
			assert(0); // oops, handle other event types
		
		_assertWaveFrontsConsistent(activeWaveFronts);
		
		
		[events removeObject: firstEvent];
		
		NSMutableArray* invalidEvents = [NSMutableArray arrayWithCapacity: changedWaveFronts.count];

		for (PSWaveFront* waveFront in changedWaveFronts)
		{
			if (waveFront.collapseEvent)
				[invalidEvents addObject: waveFront.collapseEvent];
			waveFront.collapseEvent = nil;
		}
		
		[events removeObjectsInArray: invalidEvents];
		
		
		for (PSWaveFront* waveFront in changedWaveFronts)
		{
			// while waveFronts shouldnt be added to the changedWaveFronts more than once, it could happen, and we want to handle it gracefully at this point.
			if (waveFront.collapseEvent)
				continue;
			if (![activeWaveFronts containsObject: waveFront])
				continue;
			
			PSCollapseEvent* event = [self computeCollapseEvent: waveFront];
			
			waveFront.collapseEvent = event;
			
			if (event && !isnan(event.time) && !isinf(event.time) && [activeWaveFronts containsObject: waveFront])
			{
				assert(event.time >= firstEvent.time);
				[events addObject: event];
				
			}
		}

		
	}	}
	
#pragma mark terminate leftover wavefronts 
	
	for (PSWaveFront* waveFront in activeWaveFronts)
	{
		
		NSArray* spokes = @[waveFront.leftSpoke, waveFront.rightSpoke];
		
		for (PSSpoke* spoke in spokes)
		{
			if (!spoke.terminalVertex)
			{
				PSVertex* vertex = [[PSVertex alloc] init];
				vertex.time = lastEventTime;
				vertex.position = [spoke positionAtTime: lastEventTime];
				
				spoke.terminalVertex = vertex;
				spoke.terminationTime = lastEventTime;
				[vertex addSpoke: spoke];
				
				[collapsedVertices addObject: vertex];
				[terminatedSpokes addObject: spoke];
			}
		}
	}
	
	for (PSWaveFront* waveFront in terminatedWaveFronts)
	{
		waveFront.leftSpoke = nil;
		waveFront.rightSpoke = nil;
	}
	
	vertices = [vertices arrayByAddingObjectsFromArray: collapsedVertices];
	
	BOOL maybe = NO;
	if (maybe)
		NSLog(@"%@", eventLog);
	
}
#endif

#if 0
- (PSReverseBranchEvent*) computeReverseBranchEventForMotorcycle: (PSMotorcycle*) motorcycle vertex: (PSCrashVertex*) crashVertex;
{
	PSAntiSpoke* antiSpoke = motorcycle.antiSpoke;
	assert([antiSpoke isKindOfClass: [PSAntiSpoke class]]);
	
	assert (vLength(antiSpoke.velocity) != 0.0);
	
	
	vector_t r0 = v3Sub(crashVertex.position, antiSpoke.sourceVertex.position);
	
	double adot = vDot(r0, antiSpoke.velocity);
	
	if (adot <= 0.0) // anti-spoke is going away from crash vertex, so no dice
		return nil;
	
	double time = antiSpoke.start + vLength(r0)/vLength(antiSpoke.velocity);
	
	if (time < crashVertex.time)
	{
		PSReverseBranchEvent* event = [[PSReverseBranchEvent alloc] init];
		event.time = time;
		event.rootSpoke = antiSpoke;
		event.location = crashVertex.position;
		event.branchVertex = crashVertex;
		crashVertex.reverseEvent = event;
		
		return event;
	}
	else
		return nil;
}

#endif
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
	
	NSArray* paths = [waveFronts map: ^id(PSWaveFront* waveFront) {
		
		NSBezierPath* bpath = [NSBezierPath bezierPath];
		NSMutableArray* verts = [NSMutableArray array];
		
		PSSpoke* lastRighty = [waveFront.retiredRightSpokes lastObject];

		for (PSSpoke* spoke in waveFront.retiredRightSpokes)
		{
			if (([spoke.startTime compare: tBegin] >= 0))
				[verts addObject: spoke.sourceVertex];
			else if ((spoke.terminationTime >= tBegin))
			{
				PSRealVertex* vertex = [[PSRealVertex alloc] init];
				vertex.position = [spoke positionAtTime: tBegin];
				[verts addObject: vertex];
			}
			
		}
		
		[verts addObject: lastRighty.terminalVertex];

		for (PSSpoke* spoke in [waveFront.retiredLeftSpokes reverseObjectEnumerator])
		{
			
			if (([spoke.startTime compare: tBegin] >= 0))
				[verts addObject: spoke.sourceVertex];
			else if ((spoke.terminationTime >= tBegin))
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






