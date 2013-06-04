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
#import "PSWaveFrontSnapshot.h"
#import "PriorityQueue.h"
#import "MPVector2D.h"
#import "MPInteger.h"

@implementation PolygonSkeletizer
{
	NSArray* vertices;
	NSArray* originalVertices;
	NSArray* splitVertices;
	NSArray* edges;
	
	
	NSMutableArray* traceCrashVertices;
	NSMutableArray* mergeCrashVertices;
	
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
	splitVertices = [NSArray array];
	traceCrashVertices = [NSMutableArray array];
	mergeCrashVertices = [NSMutableArray array];
	edges = [NSArray array];
	terminatedMotorcycles = [NSMutableArray array];
	terminatedSpokes = [NSMutableSet set];
	terminatedWaveFronts = [NSMutableArray array];
	
	outlineMeshes = [NSMutableArray array];
	
	motorcycleCrashes = [[PriorityQueue alloc] initWithCompareBlock:^NSComparisonResult(PSMotorcycleCrash* obj0, PSMotorcycleCrash* obj1) {
		vmlongerfix_t t0 = obj0.crashTimeSqr;
		vmlongerfix_t t1 = obj1.crashTimeSqr;
		assert(t0.shift == t1.shift);
		
		return i128compare(t0.x, t1.x);
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
		PSVertex* vertex = [[PSSourceVertex alloc] init];
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
		edge.normal = _edgeToNormal(e);
		edge.edge = e;
		
	//	assert(vLength(e) >= mergeThreshold);
		
		[newEdges addObject: edge];
	}

	edges = [edges arrayByAddingObjectsFromArray: newEdges];
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

static v3l_t _scaleLong(v3i_t a, vmintfix_t b)
{
	vmlong_t tmpx = (vmlong_t)a.x*b.x;
	vmlong_t tmpy = (vmlong_t)a.y*b.x;
	vmlong_t tmpz = (vmlong_t)a.z*b.x;
	
	return (v3l_t){tmpx, tmpy, tmpz, a.shift + b.shift};
}

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

static vmlongfix_t _longerReduce(vmlongerfix_t a)
{
	long shift = a.shift/2;
	vmlonger_t tmp = a.x >> (a.shift-shift);
	assert(tmp <= INT64_MAX);
	assert(tmp >= INT64_MIN);
	return (vmlongfix_t){tmp, shift};
}

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

static vmlongfix_t _lmulReduce(vmlongfix_t a, vmlongfix_t b)
{
	long shift = a.shift;
	long mulShift = a.shift+b.shift;
	assert(shift < mulShift);
	vmlonger_t y = (vmlonger_t)a.x*b.x;
	
	return (vmlongfix_t){y >> mulShift - shift, shift};
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



//static v3i_t _crashLocationME(PSMotorcycle* ma, PSEdge* eb, long* isValid)
static v3i_t _crashLocationME2(v3i_t B, v3i_t E_AB, v3i_t E_BC, v3i_t U, v3i_t V, long* isValid)
{
	v3i_t D = v3iSub(U, B);
	v3l_t DU = _intToLongVector(D, D.shift);
	v3l_t DV = _intToLongVector(v3iNegate(D), D.shift);
	
	v3i_t S = v3iSub(V, U);
	v3l_t Sl = _intToLongVector(S, S.shift);

	vmlongfix_t E_ABxBC = v3iCross2D(E_AB, E_BC);

	vmintfix_t l_E_AB = v3iLength2D(E_AB);
	vmintfix_t l_E_BC = v3iLength2D(E_BC);

	v3l_t E_ABC = v3lSub(_scaleLong(E_BC, l_E_AB), _scaleLong(E_AB, l_E_BC));

	vmlongfix_t denum = _longerReduce(v3lCross2D(E_ABC, Sl));
	
	if (denum.x == 0)
	{
		*isValid = NO;
		return v3iCreate(0, 0, 0, 0);
	}
	
	vmlongfix_t numU = _longerReduce(v3lCross2D(DU, E_ABC));
	vmlongfix_t numV = _lmulReduce(_longerReduce(v3lCross2D(DV, Sl)), E_ABxBC);
	vmlongfix_t denumU = _lmulReduce(denum, E_ABxBC);
	vmlongfix_t denumV = denum;

	v3l_t uRl = v3lScaleFloor(E_ABC, numU, denumU);
	v3l_t vSl = v3lScaleFloor(Sl, numV, denumV);
	
	v3i_t uR = _longToIntVector(uRl, uRl.shift/2);
	v3i_t vS = _longToIntVector(vSl, vSl.shift/2);
	
	v3i_t XR = v3iAdd(B, uR);
	v3i_t XS = v3iAdd(U, vS);
	
	// FIXME: dummy call
	v3lToFloat(E_ABC);
	
	assert(v3iEqual(XR, XS));
	
	
	
	// is valid crash if it it's on the edge, and after t=0
	*isValid = _locationOnEdge_boxTest(U,V, XR) && ((vmlonger_t)numU.x*denumU.x >= 0);
	return XR;
	
}

static v3i_t _crashLocationME3(v3i_t _B, v3i_t _E_AB, v3i_t _E_BC, v3i_t _U, v3i_t _V, long* isValid)
{
	MPVector2D* B = [MPVector2D vectorWith3i: _B];
	MPVector2D* E_AB = [MPVector2D vectorWith3i: _E_AB];
	MPVector2D* E_BC = [MPVector2D vectorWith3i: _E_BC];
	MPVector2D* U = [MPVector2D vectorWith3i: _U];
	MPVector2D* V = [MPVector2D vectorWith3i: _V];
	
	MPVector2D* D = [U sub: B];
	
	MPVector2D* S = [V sub: U];
	
	MPDecimal* E_ABxBC = [E_AB cross: E_BC];
	
	MPDecimal* l_E_AB = E_AB.length;
	MPDecimal* l_E_BC = E_BC.length;
	
	MPVector2D* E_ABC = [[E_BC scale: l_E_AB] sub: [E_AB scale: l_E_BC]];
	
	MPDecimal* denum = [E_ABC cross: S];
	
	
	if (denum.isZero)
	{
		*isValid = NO;
		return v3iCreate(0, 0, 0, 0);
	}
	
	MPDecimal* numU = [D cross: E_ABC];
	MPDecimal* numV = [[D cross: S] mul: E_ABxBC];
	
	MPDecimal* denumU = [denum mul: E_ABxBC];
	MPDecimal* denumV = denum;
	
	MPVector2D* uRl = [E_ABC scaleNum: numU den: denumU];
	MPVector2D* vSl = [S scaleNum: numV den: denumV];
	
	BOOL ROK = uRl.minIntegerBits < 16;
	BOOL SOK = vSl.minIntegerBits < 16;
	
	if (!ROK || !SOK)
	{
		*isValid = NO;
		return v3iCreate(0, 0, 0, 0);
	}
	
	//	NSLog(@"%@", uRl.x.stringValue);
	
	v3i_t uR = [uRl toVectorWithShift: 16];
	v3i_t vS = [vSl toVectorWithShift: 16];
	
	v3i_t XR = v3iAdd(_B, uR);
	v3i_t XS = v3iAdd(_U, vS);
	
	
	// FIXME: dummy call
	//v3lToFloat(_E_ABC);
	
	
	
	
	// is valid crash if it it's on the edge, and after t=0
	*isValid = _locationOnEdge_boxTest(_U,_V, XR) && (numU.sign*denumU.sign >= 0);
	
	if (*isValid)
		assert(v3iEqual(XR, XS));
	
	
	return XR;
	
}

static v3i_t _crashLocationME(v3i_t _B, v3i_t _E_AB, v3i_t _E_BC, v3i_t _U, v3i_t _V, long* isValid)
{
	MPVector2D* B = [MPVector2D vectorWith3i: _B];
	MPVector2D* E_AB = [MPVector2D vectorWith3i: _E_AB];
	MPVector2D* E_BC = [MPVector2D vectorWith3i: _E_BC];
	MPVector2D* U = [MPVector2D vectorWith3i: _U];
	MPVector2D* V = [MPVector2D vectorWith3i: _V];
	
	
	MPVector2D* S = [V sub: U];
	
	MPDecimal* E_ABxBC = [E_AB cross: E_BC];
	
	MPDecimal* l_E_AB = E_AB.length;
	MPDecimal* l_E_BC = E_BC.length;
	
	MPVector2D* E_ABC = [[E_BC scale: l_E_AB] sub: [E_AB scale: l_E_BC]];
	
	MPDecimal* denum = [E_ABC cross: S];
			
	
	if (denum.isZero)
	{
		*isValid = NO;
		return v3iCreate(0, 0, 0, 0);
	}
	
	MPVector2D* RQS = [E_ABC scale: [V cross: S]];
	MPVector2D* SPR = [S scale: [B cross: E_ABC]];
	
	MPVector2D* X = [[RQS sub: SPR] scaleNum: [[MPDecimal alloc] initWithInt64: 1 shift: 0] den: denum];
	

	
	if (X.minIntegerBits > 16)
	{
		*isValid = NO;
		return v3iCreate(0, 0, 0, 0);
	}
	v3i_t Xi = [X toVectorWithShift: 16];
		
	
	
	v3i_t R = [[E_ABC scaleNum: [[MPDecimal alloc] initWithInt64: 1 shift: 0] den: E_ABxBC] toVectorWithShift: 16];
	// is valid crash if it it's on the edge, and after t=0
	*isValid = _locationOnEdge_boxTest(_U,_V, Xi) && _locationOnRayHalfPlaneTest(R, v3iSub(Xi, _B));
	
	
	return Xi;
	
}

static v3i_t _crashLocationMM(PSMotorcycle* ma, PSMotorcycle* mb, long* isValid)
{
	*isValid = NO;
	MPVector2D* B = [MPVector2D vectorWith3i: ma.sourceVertex.position];
	MPVector2D* V = [MPVector2D vectorWith3i: mb.sourceVertex.position];
	
	MPVector2D* E_AB = [MPVector2D vectorWith3i: ma.leftEdge.edge];
	MPVector2D* E_BC = [MPVector2D vectorWith3i: ma.rightEdge.edge];
	MPVector2D* E_UV = [MPVector2D vectorWith3i: mb.leftEdge.edge];
	MPVector2D* E_VW = [MPVector2D vectorWith3i: mb.rightEdge.edge];
	
	MPDecimal* E_ABxBC = [E_AB cross: E_BC];
	MPDecimal* E_UVxVW = [E_UV cross: E_VW];
	
	MPDecimal* l_E_AB = [E_AB length];
	MPDecimal* l_E_BC = [E_BC length];
	MPDecimal* l_E_UV = [E_UV length];
	MPDecimal* l_E_VW = [E_VW length];

	MPVector2D* E_ABC = [[E_BC scale: l_E_AB] sub: [E_AB scale: l_E_BC]];
	MPVector2D* E_UVW = [[E_VW scale: l_E_UV] sub: [E_UV scale: l_E_VW]];
		
	MPVector2D* R = ma.mpVelocity;
	MPVector2D* S = mb.mpVelocity;
	
	if ((!E_ABxBC.isZero) && ((!E_UVxVW.isZero)))
	{
		MPDecimal* denum = [E_ABC cross: E_UVW];

		
		if (!denum.isZero)
		{
			MPVector2D* RQS = [E_ABC scale: [V cross: E_UVW]];
			MPVector2D* SPR = [E_UVW scale: [B cross: E_ABC]];
			MPVector2D* XD = [RQS sub: SPR];
			
			MPVector2D* X = [XD scaleNum: [[MPDecimal alloc] initWithInt64: 1 shift: 0] den: denum];
						
			if (X.minIntegerBits < 16)
			{

				
				v3i_t Xi = [X toVectorWithShift: 16];
				*isValid = YES;
				return Xi;
				
			}
		}
		else
		{
			*isValid = NO;
		}
	}
	else
	{
		[NSException raise: @"PolgyonSkeletizer.crashException" format: @"A motorcycle is invalid"];
	}
	return v3iCreate(0, 0, 0, 0);
}

static v3i_t _crashLocationMM2(PSMotorcycle* ma, PSMotorcycle* mb, long* isValid)
{
	*isValid = NO;
	MPVector2D* B = [MPVector2D vectorWith3i: ma.sourceVertex.position];
	MPVector2D* V = [MPVector2D vectorWith3i: mb.sourceVertex.position];
	MPVector2D* D = [V sub: B];
	
	MPVector2D* E_AB = [MPVector2D vectorWith3i: ma.leftEdge.edge];
	MPVector2D* E_BC = [MPVector2D vectorWith3i: ma.rightEdge.edge];
	MPVector2D* E_UV = [MPVector2D vectorWith3i: mb.leftEdge.edge];
	MPVector2D* E_VW = [MPVector2D vectorWith3i: mb.rightEdge.edge];
	
	MPDecimal* E_ABxBC = [E_AB cross: E_BC];
	MPDecimal* E_UVxVW = [E_UV cross: E_VW];
	
	MPDecimal* l_E_AB = [E_AB length];
	MPDecimal* l_E_BC = [E_BC length];
	MPDecimal* l_E_UV = [E_UV length];
	MPDecimal* l_E_VW = [E_VW length];
	
	MPVector2D* E_ABC = [[E_BC scale: l_E_AB] sub: [E_AB scale: l_E_BC]];
	MPVector2D* E_UVW = [[E_VW scale: l_E_UV] sub: [E_UV scale: l_E_VW]];
	
	MPVector2D* R = ma.mpVelocity;
	MPVector2D* S = mb.mpVelocity;
	
	if ((!E_ABxBC.isZero) && ((!E_UVxVW.isZero)))
	{
		MPDecimal* denum = [E_ABC cross: E_UVW];
		
		MPDecimal* numU = [[D cross: E_ABC] mul: E_UVxVW];
		MPDecimal* numV = [[D cross: E_UVW] mul: E_ABxBC];
		
		MPDecimal* denumU = [denum mul: E_ABxBC];
		MPDecimal* denumV = [denum mul: E_UVxVW];
		
		
		if ((!denumU.isZero) && (!denumV.isZero))
		{
			MPVector2D* uRl = [E_ABC scaleNum: numU den: denumU];
			MPVector2D* vSl = [E_UVW scaleNum: numV den: denumV];
			
			if ((uRl.minIntegerBits < 32) && (vSl.minIntegerBits < 32))
			{
				
				MPVector2D* XRl = [B add: uRl];
				MPVector2D* XSl = [V add: vSl];
				
				v3i_t XR = [XRl toVectorWithShift: 16];
				v3i_t XS = [XSl toVectorWithShift: 16];
				
				
				assert(v3iEqual(XR, XS));
				
				*isValid = YES;
				return XR;
				
			}
		}
		else
		{
			*isValid = NO;
		}
	}
	else
	{
		[NSException raise: @"PolgyonSkeletizer.crashException" format: @"A motorcycle is invalid"];
	}
	return v3iCreate(0, 0, 0, 0);
}


- (void) crashMotorcycle: (PSMotorcycle*) cycle intoEdgesWithLimit: (vmint_t) motorLimit
{
	// crash against edges
	for (PSEdge* edge in edges)
	{
		@autoreleasepool {
			// skip edges motorcycle started from
			if ((edge.leftVertex == cycle.sourceVertex) || (edge.rightVertex == cycle.sourceVertex))
				continue;
			
			long isValidCrash = NO;
			
			v3i_t xloc = _crashLocationME(cycle.sourceVertex.position, cycle.leftEdge.edge, cycle.rightEdge.edge, edge.leftVertex.position, edge.rightVertex.position, &isValidCrash);
						
						
			if (isValidCrash)
			{
				v3i_t x = xloc;
				
				// match test, intersection points must equal for reversed edge
				{
					long isValidCrashRev = NO;
					
					v3i_t xlocrev = _crashLocationME(cycle.sourceVertex.position, cycle.leftEdge.edge, cycle.rightEdge.edge, edge.rightVertex.position, edge.leftVertex.position, &isValidCrashRev);
					assert(isValidCrashRev && v3iEqual(xlocrev, x));
				}
				
				
				vmlongerfix_t ta0 = _linePointDistanceSqr(cycle.leftEdge.leftVertex.position, cycle.leftEdge.rightVertex.position, xloc);
				vmlongerfix_t ta1 = _linePointDistanceSqr(cycle.rightEdge.leftVertex.position, cycle.rightEdge.rightVertex.position, xloc);

				
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

- (void) crashMotorcycle: (PSMotorcycle*) cycle0 intoMotorcycles: (NSArray*) motorcycles withLimit: (double) motorLimit
{
	
	NSUInteger k = [motorcycles indexOfObject: cycle0];
	for (PSMotorcycle* cycle1 in [motorcycles subarrayWithRange: NSMakeRange(k+1, [motorcycles count] - k - 1)])
	{
		
		long isValidCrash = NO;
		v3i_t xloc = _crashLocationMM(cycle0, cycle1, &isValidCrash);
		
		//xiLineSegments2DFrac(motorp, v3iAdd(motorp, motorv), cycle1.sourceVertex.position, v3iAdd(cycle1.sourceVertex.position, cycle1.velocity), &t0, &t1, &den);

				
		//vmlong_t ta = t0;
		//vmlong_t tb = t1;

		if (isValidCrash)
		{
			vmlongerfix_t ta0 = _linePointDistanceSqr(cycle0.leftEdge.leftVertex.position, cycle0.leftEdge.rightVertex.position, xloc);
			vmlongerfix_t ta1 = _linePointDistanceSqr(cycle0.rightEdge.leftVertex.position, cycle0.rightEdge.rightVertex.position, xloc);
			vmlongerfix_t tb0 = _linePointDistanceSqr(cycle1.leftEdge.leftVertex.position, cycle1.leftEdge.rightVertex.position, xloc);
			vmlongerfix_t tb1 = _linePointDistanceSqr(cycle1.rightEdge.leftVertex.position, cycle1.rightEdge.rightVertex.position, xloc);
			vmlongerfix_t ta = llfixmax(ta0, ta1);
			vmlongerfix_t tb = llfixmax(tb0, tb1);
			vmlongerfix_t hitTime = llfixmax(ta, tb);
			id survivor = nil;
			id crasher = nil;
			vmlongerfix_t ts = {0,0}, tc = {0,0};
						
			if (ta.x <= tb.x)
			{
				ts = ta;
				tc = tb;
				survivor = cycle0;
				crasher = cycle1;
			}
			else if (ta.x > tb.x)
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

static double _lltodouble(vmlongerfix_t a)
{
	double x = a.x;
	x *= ((vmlonger_t)1 << a.shift);
	return x;
}

- (NSArray*) crashMotorcycles: (NSArray*) motorcycles atTime: (double) time withLimit: (double) motorLimit executedCrashes: (NSSet*) executedCrashes
{
	// prune expired events
	
	while (motorcycleCrashes.count)
	{
		PSMotorcycleCrash* crash = motorcycleCrashes.firstObject;
		
		// purge events at beginning if they refer to terminated cycles
		if (crash.cycle0.terminationTime.x != INT128_MAX)
		{
			[motorcycleCrashes popFirstObject];
		}
		else
			break;
		
	}	
	
	return motorcycleCrashes.count ? @[[motorcycleCrashes popFirstObject]] : @[];
}

static id _crashObject(NSArray* crashInfo)
{
	return [crashInfo objectAtIndex: 2];
}

static BOOL _isTraceCrash(NSArray* crashInfo)
{
	return [[crashInfo objectAtIndex: 2] isKindOfClass: [PSMotorcycle class]];
}


static BOOL _isWallCrash(NSArray* crashInfo)
{
	return [[crashInfo objectAtIndex: 2] isKindOfClass: [PSVertex class]] || [[crashInfo objectAtIndex: 2] isKindOfClass: [PSEdge class]];
}

- (void) splitEdge: (PSSourceEdge*) edge0 atVertex: (PSSplitVertex*) vertex
{
	assert([edge0 isKindOfClass: [PSSourceEdge class]]);
	PSSourceEdge* edge1 = [[[edge0 class] alloc] init];
	
	assert(edge0.leftVertex.rightEdge == edge0);
	assert(edge0.rightVertex.leftEdge == edge0);
		
	edge1.leftVertex = vertex;
	edge1.rightVertex = edge0.rightVertex;
	edge1.rightVertex.leftEdge = edge1;
	
	edge1.normal = edge0.normal;
	edge1.edge = v3iSub(edge1.rightVertex.position, edge1.leftVertex.position);
	
	edge0.rightVertex = vertex;
	vertex.leftEdge = edge0;
	vertex.rightEdge = edge1;
	
	NSMutableArray* edgeArray = [edges mutableCopy];
	[edgeArray insertObject: edge1 atIndex: [edgeArray indexOfObject: edge0]+1];
	
	edges = edgeArray;
	
	splitVertices = [splitVertices arrayByAddingObject: vertex];
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
	assert([edges count] == [vertices count]);
	
	NSMutableArray* eventLog = [NSMutableArray array];
	
	r3i_t mr = riInfRange([(PSVertex*)[vertices lastObject] position].shift);
	
	for (PSVertex* vertex in vertices)
	{
		mr = riUnionRange(mr, riCreateFromVectors(vertex.position, vertex.position));
	}
	
	v3i_t rr = v3iSub(mr.max, mr.min);
	double motorLimit = lmax(2*rr.x, 2*rr.y);
	

	
	// start by generating the initial motorcycles
	NSMutableArray* motorcycles = [NSMutableArray array];
	
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
			
			MPVector2D* mpv = cycle.mpVelocity;
			
			vector_t fv = cycle.floatVelocity;
			assert(!vIsInf(fv));
			
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
	for (PSMotorcycle* motorcycle in motorcycles)
	{
		[self crashMotorcycle: motorcycle intoEdgesWithLimit: motorLimit];
		[self crashMotorcycle: motorcycle intoMotorcycles: motorcycles withLimit: motorLimit];
	}
	
	
	// build event list

	NSMutableArray* splittingVertices = [NSMutableArray array];
	
	
	while (motorcycleCrashes.count)
	{
		while (motorcycleCrashes.count)
		{
			PSMotorcycleCrash* crash = motorcycleCrashes.firstObject;
			
			// purge events at beginning if they refer to terminated cycles
			if (crash.cycle0.terminationTime.x != INT128_MAX)
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
			
		[eventLog addObject: [NSString stringWithFormat: @"%f: processing crash", _lltodouble(crash.crashTimeSqr)]];
			
			
		if ([crash isKindOfClass: [PSMotorcycleVertexCrash class]])
		{
			PSMotorcycleVertexCrash* vcrash = (id) crash;
			PSMotorcycle* cycle = vcrash.cycle0;
			PSVertex* vertex = vcrash.vertex;
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
			PSVertex* vertex = [cycle getVertexOnMotorcycleAtLocation: crash.location];
			
			if (!vertex)
			{
				vertex = [[PSVertex alloc] init];
				vertex.position = crash.location;
			}
			cycle.terminationTime = ecrash.time0Sqr;
			cycle.terminalVertex = vertex;
			cycle.leftNeighbour.rightNeighbour = cycle.rightNeighbour;
			cycle.rightNeighbour.leftNeighbour = cycle.leftNeighbour;
			
			[vertex addMotorcycle: cycle];
			
			[splittingVertices addObject: @[ecrash, vertex]];
			
			
		}
		else if ([crash isKindOfClass: [PSMotorcycleMotorcycleCrash class]])
		{
			PSMotorcycleMotorcycleCrash* mcrash = (id) crash;
			
			PSMotorcycle* crasher = mcrash.cycle0;
			PSMotorcycle* survivor = mcrash.cycle1;
			crasher.terminationTime = mcrash.time0Sqr;
			
			PSVertex* vertex = [survivor getVertexOnMotorcycleAtLocation: crash.location];
			if (!vertex)
			{
				vertex = [crasher getVertexOnMotorcycleAtLocation: crash.location];
			}
			if (!vertex)
			{
				vertex = [[PSVertex alloc] init];
				vertex.position = crash.location;
			}
			
			
			crasher.terminalVertex = vertex;

			[vertex addMotorcycle: crasher];
			[vertex addMotorcycle: survivor];
			
			// FIXME: add vertex to some set for later stages?
			
		}
		else
			assert(0); // unknown crash type
		
		[motorcycles removeObject: crash.cycle0];
		[terminatedMotorcycles addObject: crash.cycle0];
		
		
			
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
	
#if 0
	BOOL opposingMotorcyclesFound = YES;
	while (opposingMotorcyclesFound)
	{
		opposingMotorcyclesFound = NO;
		for (PSMotorcycle* cycle0 in [terminatedMotorcycles copy])
		{
			for (PSMotorcycle* cycle1 in [terminatedMotorcycles copy])
			{
				BOOL sharedEnd = cycle0.terminalVertex == cycle1.sourceVertex;
				
				if (sharedEnd)
					sharedEnd = sharedEnd;
				
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
					
					vector_t p0 = cycle0.sourceVertex.position;
					vector_t v0 = cycle0.velocity;
					
					crashVertices = [crashVertices sortedArrayWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PSCrashVertex* obj1, PSCrashVertex* obj2) {
						double u1 = vDot(v0, v3Sub(obj1.position, p0));
						double u2 = vDot(v0, v3Sub(obj2.position, p0));
						
						return fcompare(u1, u2);
					}];
					
					cycle0.crashVertices = crashVertices;
					
					
					opposingMotorcyclesFound = YES;
				}
				else if (
						 (cycle1.terminalVertex == cycle0.sourceVertex)
						 && (![cycle1.terminalVertex isKindOfClass: [PSCrashVertex class]])
						 && ([cycle0.terminalVertex isKindOfClass: [PSCrashVertex class]])
						 && _terminatedMotorcyclesOpposing(cycle1, cycle0)
						 )
				{
					// do nothing, handled when cycle0/cycle1 are checked in reverse
				}
				else if (
						 (cycle0.terminalVertex == cycle1.sourceVertex)
						 && (![cycle0.terminalVertex isKindOfClass: [PSCrashVertex class]])
						 && ([cycle1.terminalVertex isKindOfClass: [PSCrashVertex class]])
						 && _terminatedMotorcyclesOpposing(cycle0, cycle1)
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
					
					
					terminatedMotorcycles = [terminatedMotorcycles arrayByRemovingObject: cycle1];
					
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
					
					vector_t p0 = cycle0.sourceVertex.position;
					vector_t v0 = cycle0.velocity;
					
					crashVertices = [crashVertices sortedArrayWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PSCrashVertex* obj1, PSCrashVertex* obj2) {
						double u1 = vDot(v0, v3Sub(obj1.position, p0));
						double u2 = vDot(v0, v3Sub(obj2.position, p0));
						
						return fcompare(u1, u2);
					}];
					
					cycle0.crashVertices = crashVertices;
					
					opposingMotorcyclesFound = YES;
				}
				else if (_terminatedMotorcyclesOpposing(cycle0, cycle1))
					assert(0); // FIXME: not implemented yet
				
				if (opposingMotorcyclesFound)
					break;
			}
			if (opposingMotorcyclesFound)
				break;
		}
	}
#endif
	
	// we shouldn't have any motorcycles left at this point. But if we do, we want to see them
	
	for (PSMotorcycle* cycle in motorcycles)
	{
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

#if 0
static BOOL _spokesSameDir(PSSimpleSpoke* spoke0, PSSimpleSpoke* spoke1)
{
	vector_t v0 = spoke0.velocity;
	vector_t v1 = spoke1.velocity;
	
	if (vLength(v0) == 0.0)
		return NO;
	if (vLength(v1) == 0.0)
		return NO;
	
	double angle = atan2(vCross(v0, v1).farr[2], vDot(v0, v1));
	
	return (fabs(angle) < FLT_EPSILON);
	
}

static BOOL _isSpokeUnique(PSSimpleSpoke* uspoke, NSArray* spokes)
{
	if (vLength(uspoke.velocity) == 0.0)
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


static void _generateCycleSpoke(PSMotorcycle* cycle, NSMutableArray* spokes, NSMutableArray* antiSpokes)
{
	PSVertex* vertex = cycle.sourceVertex;
	PSMotorcycleSpoke* spoke = [[PSMotorcycleSpoke alloc] init];
	spoke.sourceVertex = vertex;
	spoke.motorcycle = cycle;
	cycle.spoke = spoke;

	spoke.velocity = cycle.velocity;
	assert(!vIsNAN(spoke.velocity));
	spoke.start = (vertex.time != 0.0 ? INFINITY : 0.0);
	
	[spokes addObject: spoke];
	_assertSpokeUnique(spoke, vertex.outgoingSpokes);
	[vertex addSpoke: spoke];
	
	PSAntiSpoke* antiSpoke = [[PSAntiSpoke alloc] init];
	PSVertex* antiVertex = cycle.terminalVertex;
	
	antiSpoke.sourceVertex = antiVertex;
	antiSpoke.start = (antiVertex.time != 0.0 ? INFINITY : 0.0);
	
	spoke.antiSpoke = antiSpoke;
	cycle.antiSpoke = antiSpoke;
	antiSpoke.motorcycleSpoke = spoke;
	antiSpoke.motorcycle = cycle;
	
	PSSourceEdge* antiEdge = nil;
	if ([antiVertex isKindOfClass: [PSCrashVertex class]])
	{
		// cant precompute velocity at this point
	}
	else if ([antiVertex isKindOfClass: [PSMergeVertex class]])
	{
		// cant precompute velocity at this point
	}
	else if ([antiVertex isKindOfClass: [PSSplitVertex class]])
	{
		antiEdge = antiVertex.leftEdge; // in this case, both are colinear
		assert(antiEdge);
	}
	else	 // else figure out which direction we'd hit
	{
		vector_t v = bisectorVelocity(antiVertex.leftEdge.normal, antiVertex.rightEdge.normal, antiVertex.leftEdge.edge, antiVertex.rightEdge.edge);
		double area = vCross(v, vNegate(cycle.velocity)).farr[2];
		if (area > 0.0)
			antiEdge = antiVertex.leftEdge;
		else
			antiEdge = antiVertex.rightEdge;
		assert(antiEdge);
		
	}
	if (antiEdge)
	{
		antiSpoke.velocity = vReverseProject(antiEdge.normal, cycle.velocity);
	}
	
	[antiSpokes addObject: antiSpoke];
	_assertSpokeUnique(antiSpoke, antiVertex.outgoingSpokes);
	[antiVertex addSpoke: antiSpoke];
	
}
#endif

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

- (PSWaveFrontSnapshot*) emitSnapshot: (NSArray*) waveFronts atTime: (double) time
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

- (void) emitOffsetOutlineForWaveFronts: (NSArray*) waveFronts atTime: (double) time
{
	// FIXME: emit not just visual outline, but proper outline path
	
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
		vector_t p0 = waveFront.leftSpoke.sourceVertex.position;
		vector_t p1 = waveFront.rightSpoke.sourceVertex.position;
		
		BOOL leftFast = [waveFront.leftSpoke isKindOfClass: [PSFastSpoke class]];
		BOOL rightFast = [waveFront.rightSpoke isKindOfClass: [PSFastSpoke class]];
		
		vector_t x0 = vCreatePos(NAN, NAN, NAN);
		vector_t x1 = vCreatePos(NAN, NAN, NAN);
		
		if (!leftFast && !rightFast)
		{
			PSSimpleSpoke* leftSpoke = (id)waveFront.leftSpoke;
			PSSimpleSpoke* rightSpoke = (id)waveFront.rightSpoke;
			x0 = v3Add(p0, v3MulScalar(leftSpoke.velocity, time - leftSpoke.start));
			x1 = v3Add(p1, v3MulScalar(rightSpoke.velocity, time - rightSpoke.start));
			
		}
		else if (leftFast && rightFast)
		{
			PSFastSpoke* leftSpoke = (id)waveFront.leftSpoke;
			PSFastSpoke* rightSpoke = (id)waveFront.rightSpoke;
			if (leftSpoke.terminalVertex)
				x0 = leftSpoke.terminalVertex.position;
			else
				x0 = v3MulScalar(v3Add(p0, p1), 0.5);
			
			if (rightSpoke.terminalVertex)
				x1 = rightSpoke.terminalVertex.position;
			else
				x1 = v3MulScalar(v3Add(p0, p1), 0.5);
		}
		else if (leftFast)
		{
			PSFastSpoke* leftSpoke = (id)waveFront.leftSpoke;
			PSSimpleSpoke* rightSpoke = (id)waveFront.rightSpoke;

			x1 = v3Add(p1, v3MulScalar(rightSpoke.velocity, time - rightSpoke.start));

			if (leftSpoke.terminalVertex)
				x0 = leftSpoke.terminalVertex.position;
			else
				x0 = x1;

		}
		else if (rightFast)
		{
			PSSimpleSpoke* leftSpoke = (id)waveFront.leftSpoke;
			PSFastSpoke* rightSpoke = (id)waveFront.rightSpoke;

			x0 = v3Add(p0, v3MulScalar(leftSpoke.velocity, time - leftSpoke.start));

			if (rightSpoke.terminalVertex)
				x1 = rightSpoke.terminalVertex.position;
			else
				x1 = x0;
		}
		
		
		x0.farr[3] = 1.0;
		x1.farr[3] = 1.0;
		
		assert(vIsNormal(x0));
		assert(vIsNormal(x1));
		
		vs[k++] = x0;
		vs[k++] = x1;
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

static BOOL _directionsAreAntiParallel(vector_t a, vector_t b)
{
	double lrdot = vDot(a, b);
	double lrcross = vCross(a, b).farr[2];
	
	return ((fabs(lrdot + 1.0) < FLT_EPSILON) && (fabs(lrcross) < FLT_EPSILON));
	//return fabs(atan2(l-rcross, lrdot)) < FLT_EPSILON;
	
}

static BOOL _vectorsAreAntiParallel(vector_t a, vector_t b)
{
	return _directionsAreAntiParallel(vSetLength(a, 1.0), vSetLength(b, 1.0));
	
}


static BOOL _waveFrontsAreAntiParallel(PSWaveFront* leftFront, PSWaveFront* rightFront)
{
	return _directionsAreAntiParallel(leftFront.direction, rightFront.direction);

}

- (void) terminateWaveFront: (PSWaveFront*) waveFront atTime: (double) time
{
	waveFront.terminationTime = time;
	
	[terminatedWaveFronts addObject: waveFront];
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

static void _assertSpokeConsistent(PSSpoke* spoke)
{
	assert((spoke.leftWaveFront.rightSpoke == spoke));
	assert(spoke.rightWaveFront.leftSpoke == spoke);
	/*
	assert(vEqualWithin3D(vProjectAOnB(spoke.velocity, spoke.leftWaveFront.direction), spoke.leftWaveFront.direction, FLT_EPSILON));
	assert(vEqualWithin3D(vProjectAOnB(spoke.velocity, spoke.rightWaveFront.direction), spoke.rightWaveFront.direction, FLT_EPSILON));
	assert(vEqualWithin3D(vReverseProject(spoke.leftWaveFront.direction, spoke.velocity), spoke.velocity, FLT_EPSILON));
	assert(vEqualWithin3D(vReverseProject(spoke.rightWaveFront.direction, spoke.velocity), spoke.velocity, FLT_EPSILON));
*/
	
}

static void _assertWaveFrontConsistent(PSWaveFront* waveFront)
{
	_assertSpokeConsistent(waveFront.leftSpoke);
	_assertSpokeConsistent(waveFront.rightSpoke);
	
	assert(waveFront.leftSpoke != waveFront.rightSpoke);
	assert(waveFront.leftSpoke.rightWaveFront == waveFront);
	assert(waveFront.rightSpoke.leftWaveFront == waveFront);
	assert(waveFront.rightSpoke.leftWaveFront == waveFront);
//	assert(vEqualWithin3D(vProjectAOnB(waveFront.rightSpoke.velocity, waveFront.direction), waveFront.direction, FLT_EPSILON));
//	assert(vEqualWithin3D(vProjectAOnB(waveFront.leftSpoke.velocity, waveFront.direction), waveFront.direction, FLT_EPSILON));
}

static void _assertWaveFrontsConsistent(NSArray* waveFronts)
{
	for (PSWaveFront* waveFront in waveFronts)
		_assertWaveFrontConsistent(waveFront);
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
	//[self runSpokes];
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
		vector_t a = v3iToFloat(spoke.sourceVertex.position);
		vector_t b = v3iToFloat(spoke.terminalVertex.position);
		[bpath moveToPoint: NSMakePoint(a.farr[0], a.farr[1])];
		[bpath lineToPoint: NSMakePoint(b.farr[0], b.farr[1])];
	}
	
	return @[ bpath ];
}

- (NSArray*) outlineDisplayPaths
{
	NSBezierPath* bpath = [NSBezierPath bezierPath];
	
	
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
	for (PSVertex* vertex in vertices)
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

- (NSArray*) waveFrontsTerminatedAfter: (double) tBegin upTo: (double) tEnd
{
	NSArray* waveFronts = [terminatedWaveFronts select: ^BOOL(PSWaveFront* waveFront) {
		return ((waveFront.terminationTime > tBegin) && (waveFront.terminationTime <= tEnd));
	}];
	return waveFronts;
}

- (NSArray*) waveFrontOutlinesTerminatedAfter: (double) tBegin upTo: (double) tEnd
{
	NSArray* waveFronts = [self waveFrontsTerminatedAfter: tBegin upTo: tEnd];
	
	NSArray* paths = [waveFronts map: ^id(PSWaveFront* waveFront) {
		
		NSBezierPath* bpath = [NSBezierPath bezierPath];
		NSMutableArray* verts = [NSMutableArray array];
		
		PSSpoke* lastRighty = [waveFront.retiredRightSpokes lastObject];

		for (PSSpoke* spoke in waveFront.retiredRightSpokes)
		{
			if ((spoke.start >= tBegin))
				[verts addObject: spoke.sourceVertex];
			else if ((spoke.terminationTime >= tBegin))
			{
				PSVertex* vertex = [[PSVertex alloc] init];
				vertex.position = [spoke positionAtTime: tBegin];
				[verts addObject: vertex];
			}
			
		}
		
		[verts addObject: lastRighty.terminalVertex];

		for (PSSpoke* spoke in [waveFront.retiredLeftSpokes reverseObjectEnumerator])
		{
			
			if ((spoke.start >= tBegin))
				[verts addObject: spoke.sourceVertex];
			else if ((spoke.terminationTime >= tBegin))
			{
				PSVertex* vertex = [[PSVertex alloc] init];
				vertex.position = [spoke positionAtTime: tBegin];
				[verts addObject: vertex];
			}
		}
		
		for (size_t i = 0; i < verts.count; ++i)
		{
			vector_t pos = v3iToFloat([(PSVertex*)[verts objectAtIndex: i] position]);
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






