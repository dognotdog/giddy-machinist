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
#import "FoundationExtensions.h"
#import "PolygonSkeletizerObjects.h"




@implementation PolygonSkeletizer
{
	NSArray* vertices;
	NSArray* originalVertices;
	NSArray* splitVertices;
	NSArray* edges;
	
	
	NSMutableArray* traceCrashVertices;
	NSMutableArray* mergeCrashVertices;
	
	NSArray* terminatedMotorcycles;
	NSMutableSet* terminatedSpokes;
	NSMutableArray* terminatedWaveFronts;
	
	NSMutableArray* outlineMeshes;
	NSArray* emissionTimes;
	
	NSMutableDictionary* motorcycleEdgeCrashes;
	NSMutableDictionary* motorcycleMotorcycleCrashes;
	
}

@synthesize extensionLimit, mergeThreshold, eventCallback, emitCallback;

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
	terminatedMotorcycles = [NSArray array];
	terminatedSpokes = [NSMutableSet set];
	terminatedWaveFronts = [NSMutableArray array];
	
	outlineMeshes = [NSMutableArray array];
	
	motorcycleEdgeCrashes = [NSMutableDictionary dictionary];
	motorcycleMotorcycleCrashes = [NSMutableDictionary dictionary];
	
	emissionTimes = @[@1.0, @2.0, @5.0, @10.0, @11.0, @12.0,@13.0,@14.0, @15.0, @16.0,@17.0,@18.0,@19.0, @20.0, @25.0, @30.0, @35.0, @40.0, @45.0, @50.0];

	return self;
}

- (void) dealloc
{
}



static inline vector_t _edgeToNormal(vector_t e)
{
	return vSetLength(vCreate(-e.farr[1], e.farr[0], 0.0, 0.0), 1.0);
}

static inline vector_t _normalToEdge(vector_t n)
{
	return vCreate(n.farr[1], -n.farr[0], 0.0, 0.0);
}


- (void) addClosedPolygonWithVertices: (vector_t*) vv count: (size_t) vcount
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
		vector_t a = edge.leftVertex.position;
		vector_t b = edge.rightVertex.position;
		vector_t e = v3Sub(b, a);
		edge.normal = _edgeToNormal(e);
		edge.edge = e;
		
		assert(e.farr[2] == 0.0);

		assert(vLength(e) >= mergeThreshold);
		
		[newEdges addObject: edge];
	}

	edges = [edges arrayByAddingObjectsFromArray: newEdges];
	vertices = [vertices arrayByAddingObjectsFromArray: newVertices];
	originalVertices = [originalVertices arrayByAddingObjectsFromArray: newVertices];

}
static inline vector_t bisectorVelocity(vector_t v0, vector_t v1, vector_t e0, vector_t e1)
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

- (void) crashMotorcycle: (PSMotorcycle*) cycle intoEdgesWithLimit: (double) motorLimit
{
	vector_t motorv = cycle.velocity;
	vector_t motorp = cycle.sourceVertex.position;
	// crash against edges
	for (PSEdge* edge in edges)
	{
		@autoreleasepool {
			// skip edges motorcycle started from
			if ((edge.leftVertex == cycle.sourceVertex) || (edge.rightVertex == cycle.sourceVertex))
				continue;
			
			
			//vector_t delta = v3Sub(motorp, edge.startVertex.position);
			vector_t tx = xRays2D(motorp, motorv, edge.leftVertex.position, v3Sub(edge.rightVertex.position, edge.leftVertex.position));
			double t = tx.farr[0] + cycle.start;
			
			//assert(vCross(edge.edge, delta).farr[2] >= 0.0);
			
			if ((t > cycle.start) && (t < motorLimit))
			{
				vector_t x = v3Add(motorp, v3MulScalar(motorv, t - cycle.start));
				
				vector_t ax = v3Sub(x, edge.leftVertex.position);
				vector_t bx = v3Sub(x, edge.rightVertex.position);
				
				BOOL hitStart = (vDot(ax, ax) < mergeThreshold*mergeThreshold);
				BOOL hitEnd = (vDot(bx, bx) < mergeThreshold*mergeThreshold);
				
				id crash = nil;
				
				if (hitStart)
				{
					crash = @[[NSNumber numberWithDouble: t], cycle, edge.leftVertex];
				}
				else if (hitEnd)
				{
					crash = @[[NSNumber numberWithDouble: t], cycle, edge.rightVertex];
				}
				else if ((tx.farr[1] > 0.0) && (tx.farr[1] < 1.0))
				{
					crash = @[[NSNumber numberWithDouble: t], cycle, edge, [NSNumber numberWithDouble: tx.farr[0]], [NSNumber numberWithDouble: tx.farr[1]]];
				}
				
				if (crash)
				{
					id key = [NSValue valueWithPointer: (__bridge void*)cycle];
					id oldCrash = [motorcycleEdgeCrashes objectForKey: key];
					if (!oldCrash || ([[oldCrash objectAtIndex: 0] doubleValue] > t))
						[motorcycleEdgeCrashes setObject: crash forKey: key];
				}
			}
		}
	}

}

- (void) crashMotorcycle: (PSMotorcycle*) cycle0 intoMotorcycles: (NSArray*) motorcycles withLimit: (double) motorLimit
{
	vector_t motorv = cycle0.velocity;
	vector_t motorp = cycle0.sourceVertex.position;
	
	NSUInteger k = [motorcycles indexOfObject: cycle0];
	for (PSMotorcycle* cycle1 in [motorcycles subarrayWithRange: NSMakeRange(k+1, [motorcycles count] - k - 1)])
	{
		vector_t tx = xRays2D(motorp, motorv, cycle1.sourceVertex.position, cycle1.velocity);
		
		double ta = tx.farr[0] + cycle0.start;
		double tb = tx.farr[1] + cycle1.start;

		if ((ta > cycle0.start) && (ta <= motorLimit) && (tb > cycle1.start) && (tb <= motorLimit))
		{
			double hitTime = fmax(ta, tb);
			
			vector_t ax = v3Add(cycle0.sourceVertex.position, v3MulScalar(cycle0.velocity, hitTime - cycle0.start));
			vector_t bx = v3Add(cycle1.sourceVertex.position, v3MulScalar(cycle1.velocity, hitTime - cycle1.start));
			vector_t dx = v3Sub(ax, bx);
			
			if (ta < tb)
				dx = ax;
			else if (ta > tb)
				dx = bx;
			
			id crash = @[[NSNumber numberWithDouble: hitTime], cycle0, cycle1, [NSNumber numberWithDouble: tx.farr[0]], [NSNumber numberWithDouble: tx.farr[1]], [NSNumber numberWithBool: NO]];

			id key = (ta <= tb ? [NSValue valueWithPointer: (__bridge void*)cycle1] : [NSValue valueWithPointer: (__bridge void*)cycle0]);
					  
			NSMutableArray* crashes = [motorcycleMotorcycleCrashes objectForKey: key];
			if (!crashes)
				crashes = [NSMutableArray arrayWithObject: crash];
			else
				[crashes addObject: crash];

		}

	}

}

- (NSArray*) crashMotorcycles: (NSArray*) motorcycles withLimit: (double) motorLimit
{
	NSMutableArray* crashes = [NSMutableArray array];
	size_t k = 0;
	for (PSMotorcycle* cycle in motorcycles)
	{
		
		
		
		@autoreleasepool {
			vector_t motorv = cycle.velocity;
			vector_t motorp = cycle.sourceVertex.position;
			
			// crash against edges (use cached result)
			id edgeCrash = [motorcycleEdgeCrashes objectForKey: [NSValue valueWithPointer: (__bridge void*)cycle]];
			
			if (edgeCrash)
			{
				[crashes addObject: edgeCrash];
			}
			
			
			for (PSMotorcycle* cycle1 in [motorcycles subarrayWithRange: NSMakeRange(k+1, [motorcycles count] - k - 1)])
			{
				vector_t tx = xRays2D(motorp, motorv, cycle1.sourceVertex.position, cycle1.velocity);
				
				double ta = tx.farr[0] + cycle.start;
				double tb = tx.farr[1] + cycle1.start;
				
				if ((ta > cycle.start) && (ta <= motorLimit) && (tb > cycle1.start) && (tb <= motorLimit))
				{				
					double hitTime = fmax(ta, tb);
					
					vector_t ax = v3Add(cycle.sourceVertex.position, v3MulScalar(cycle.velocity, hitTime - cycle.start));
					vector_t bx = v3Add(cycle1.sourceVertex.position, v3MulScalar(cycle1.velocity, hitTime - cycle1.start));
					vector_t dx = v3Sub(ax, bx);
					BOOL merge = (vDot(dx, dx) < mergeThreshold*mergeThreshold);
					
					if (merge )
						merge = merge; // debug catch
					merge = NO; // screw it, no merges allowed! TWO SPOKES ENTER, ONE SPOKE EXITS!
					
					id crash = @[[NSNumber numberWithDouble: hitTime], cycle, cycle1, [NSNumber numberWithDouble: tx.farr[0]], [NSNumber numberWithDouble: tx.farr[1]], [NSNumber numberWithBool: merge]];
					
					[crashes addObject: crash];
				}
				
				
			}
			for (PSMotorcycle* cycle1 in terminatedMotorcycles)
			{
				vector_t tx = xRays2D(motorp, motorv, cycle1.sourceVertex.position, v3Sub(cycle1.terminalVertex.position, cycle1.sourceVertex.position));
				
				double ta = tx.farr[0] + cycle.start;
				double tb = tx.farr[1];
				
				if ((ta > cycle.start) && (ta <= motorLimit) && (tb > 0.0) && (tb < 1.0) && (ta > tb + cycle1.start) && (cycle1.terminator != cycle))
				{
					vector_t x = v3Add(cycle.sourceVertex.position, v3MulScalar(cycle.velocity,  tx.farr[0]));
					double t1 = vLength(v3Sub(x, cycle1.sourceVertex.position))/vLength(cycle1.velocity);
				
					id crash = @[[NSNumber numberWithDouble: ta], cycle, cycle1, [NSNumber numberWithDouble: tx.farr[0]], [NSNumber numberWithDouble: t1], [NSNumber numberWithBool: NO]];
					[crashes addObject: crash];
				}
				
				
			}
			
			++k;
		}
	}

	
	NSArray* keys = [motorcycles map: ^id(id obj) {
		return [NSValue valueWithPointer: (__bridge void*)obj];
	}];
	
	NSArray* mmCrashes = [motorcycleMotorcycleCrashes objectsForKeys: keys notFoundMarker: [NSNull null]];
	
	mmCrashes = [mmCrashes map:^id(id obj) {
		return [obj lastObject];
	}];
	
	FIXME HERE! continue cached collisions impl
	
	
	return crashes;
}

static id _crashObject(NSArray* crashInfo)
{
	return [crashInfo objectAtIndex: 2];
}
static vector_t _crashLocation(NSArray* crashInfo)
{
	if ([[crashInfo objectAtIndex: 2] isKindOfClass: [PSVertex class]])
	{
		return [(PSVertex*)[crashInfo objectAtIndex: 2] position];
	}
	else
	{
		PSMotorcycle* cycle = [crashInfo objectAtIndex: 1];
		double tx = [[crashInfo objectAtIndex: 3] doubleValue];
		return v3Add(cycle.sourceVertex.position, v3MulScalar(cycle.velocity, tx));
	}
}

static BOOL _isMergeCrash(NSArray* crashInfo)
{
	return [[crashInfo objectAtIndex: 2] isKindOfClass: [PSMotorcycle class]] && [[crashInfo objectAtIndex: 5] boolValue];
}

static BOOL _isTraceCrash(NSArray* crashInfo)
{
	return [[crashInfo objectAtIndex: 2] isKindOfClass: [PSMotorcycle class]] && ![[crashInfo objectAtIndex: 5] boolValue];
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
	edge1.edge = v3Sub(edge1.rightVertex.position, edge1.leftVertex.position);
	
	edge0.rightVertex = vertex;
	vertex.leftEdge = edge0;
	vertex.rightEdge = edge1;
	
	NSMutableArray* edgeArray = [edges mutableCopy];
	[edgeArray insertObject: edge1 atIndex: [edgeArray indexOfObject: edge0]+1];
	
	edges = edgeArray;
	
	splitVertices = [splitVertices arrayByAddingObject: vertex];
}

static PSMotorcycle* _findEscapeDirection(NSArray* crashes)
{
	NSMutableDictionary* angles = [NSMutableDictionary dictionary];
	
	double crashTime = INFINITY;
	
	for (NSArray* crashInfo in crashes)
	{
		PSMotorcycle* cycle0 = [crashInfo objectAtIndex: 1];
		PSMotorcycle* cycle1 = [crashInfo objectAtIndex: 2];
		crashTime = fmin(crashTime, [[crashInfo objectAtIndex: 0] doubleValue]);
		
		double angle0 = atan2(cycle0.velocity.farr[1], cycle0.velocity.farr[0]);
		double angle1 = atan2(cycle1.velocity.farr[1], cycle1.velocity.farr[0]);
		[angles setObject: [NSNumber numberWithDouble: angle0] forKey: [NSValue valueWithPointer: (void*)cycle0]];
		[angles setObject: [NSNumber numberWithDouble: angle1] forKey: [NSValue valueWithPointer: (void*)cycle1]];
	}
	
	NSArray* sortedKeys = [angles keysSortedByValueWithOptions: NSSortStable usingComparator: ^NSComparisonResult(id obj0, id obj1) {
		
		double a0 = [[angles objectForKey: obj0] doubleValue];
		double a1 = [[angles objectForKey: obj1] doubleValue];
		
		if (a1 > a0)
			return NSOrderedAscending;
		else if (a0 > a1)
			return NSOrderedDescending;
		else
			return NSOrderedSame;
	}];
	
	
	for (long i = 0; i < sortedKeys.count; ++i)
	{
		PSMotorcycle* cycle0 = [[sortedKeys objectAtIndex: i] pointerValue];
		PSMotorcycle* cycle1 = [[sortedKeys objectAtIndex: (i+1) % sortedKeys.count] pointerValue];
		
		vector_t r0 = cycle0.velocity;
		vector_t r1 = cycle1.velocity;
		
		double cycleAngle = atan2(vCross(r0, r1).farr[2], vDot(r0, r1));
		
		if (cycleAngle < 0.0)
			cycleAngle += 2.0*M_PI;
		
		if (cycleAngle > M_PI)
		{
			PSMotorcycle* newCycle = [[PSMotorcycle alloc] init];
			newCycle.leftParent = cycle1;
			newCycle.rightParent = cycle0;
			newCycle.leftNeighbour = cycle1.leftNeighbour;
			newCycle.rightNeighbour = cycle0.rightNeighbour;
			newCycle.leftEdge = cycle1.leftEdge;
			newCycle.rightEdge = cycle0.rightEdge;
			//newCycle.leftNormal = cycle1.leftNormal;
			//newCycle.rightNormal = cycle0.rightNormal;
			newCycle.velocity = bisectorVelocity(newCycle.leftEdge.normal, newCycle.rightEdge.normal, _normalToEdge(newCycle.leftEdge.normal), _normalToEdge(newCycle.rightEdge.normal));
			
			assert(!vIsNAN(newCycle.velocity));
			
			newCycle.start = crashTime;

			return newCycle;
		}
	}
	
	return nil;
}


- (void) runMotorcycles
{
	assert([edges count] == [vertices count]);
	
	NSMutableArray* eventLog = [NSMutableArray array];
	
	range3d_t mr = rInfRange();
	
	for (PSVertex* vertex in vertices)
	{
		mr = rUnionRange(mr, rCreateFromVectors(vertex.position, vertex.position));
	}
	
	double motorLimit = vLength(v3Sub(mr.maxv, mr.minv));
	

	
	// start by generating the initial motorcycles
	NSMutableArray* motorcycles = [NSMutableArray array];
	
	for (PSSourceEdge* edge0 in edges)
	{
		PSSourceEdge* edge1 = edge0.rightVertex.rightEdge;
		assert(edge0.rightVertex.rightEdge);
		
		vector_t v = bisectorVelocity(edge0.normal, edge1.normal, _normalToEdge(edge0.normal), _normalToEdge(edge1.normal));
		double area = vCross(edge0.edge, edge1.edge).farr[2];
		
		if (area < 0.0)
		{
			PSMotorcycle* cycle = [[PSMotorcycle alloc] init];
			cycle.sourceVertex = edge0.rightVertex;
			cycle.start = 0.0;
			cycle.velocity = v;
			cycle.leftEdge = edge0;
			cycle.rightEdge = edge1;
			
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
		NSLog(@"some motorcycles!");
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
	
	// sort cycle/cycle crash arrays
	for (NSMutableArray* crashes in [motorcycleMotorcycleCrashes allValues])
	{
		[crashes sortWithOptions: NSSortStable usingComparator: ^NSComparisonResult(NSArray* e0, NSArray* e1) {
			double t0 = [[e0 objectAtIndex: 0] doubleValue], t1 = [[e1 objectAtIndex: 0] doubleValue];
			if (t0 < t1)
				return NSOrderedDescending; // reverse sort, so last is first
			else if (t0 > t1)
				return NSOrderedAscending;
			else
				return NSOrderedSame;
		}];
	}
		
	
	// build event list
	NSArray* crashes = [self crashMotorcycles: motorcycles withLimit: motorLimit];
	
	
	while ([crashes count])
	{
		@autoreleasepool {
			crashes = [crashes sortedArrayWithOptions: NSSortStable usingComparator: ^NSComparisonResult(NSArray* e0, NSArray* e1) {
				double t0 = [[e0 objectAtIndex: 0] doubleValue], t1 = [[e1 objectAtIndex: 0] doubleValue];
				if (t0 < t1)
					return NSOrderedDescending; // sort in descending order
				else if (t0 > t1)
					return NSOrderedAscending;
				else
					return NSOrderedSame;
			}];

			double tmin = [[[crashes lastObject] objectAtIndex: 0] doubleValue];
			crashes = [crashes select:^BOOL(NSArray* obj) {
				return [[obj objectAtIndex: 0] doubleValue] < tmin + mergeThreshold;
			}];
			
			if (!crashes.count)
				break;
			
			NSArray* initialCrashInfo = [crashes lastObject];
			id initialCrashObject = _crashObject(initialCrashInfo);
			crashes = [crashes arrayByRemovingLastObject];
			
			NSMutableArray* simultaneousCrashes = [NSMutableArray arrayWithObject: initialCrashInfo];
			
			
			
			for (NSArray* crashInfo in [crashes reverseObjectEnumerator])
			{
				vector_t xa = _crashLocation(initialCrashInfo);
				vector_t xb = _crashLocation(crashInfo);
				id objB = _crashObject(crashInfo);
				
				if (objB != initialCrashObject)
					break;
				
				vector_t dx = v3Sub(xb, xa);
				if (vDot(dx, dx) < mergeThreshold*mergeThreshold)
				{
					[simultaneousCrashes addObject: crashInfo];
				}
			}
			
			[eventLog addObject: [NSString stringWithFormat: @"%f: processing %ld crashes", tmin, simultaneousCrashes.count]];
			
			assert(simultaneousCrashes.count);
			
			if ([simultaneousCrashes count])
			{
				BOOL mergeCrash = NO;
				BOOL wallCrash = NO;
				BOOL traceCrash = NO;
				
				for (NSArray* crashInfo in simultaneousCrashes)
				{
					mergeCrash = mergeCrash || _isMergeCrash(crashInfo);
					wallCrash = wallCrash || _isWallCrash(crashInfo);
					traceCrash = traceCrash || _isTraceCrash(crashInfo);
					
					
				}
				
				[eventLog addObject: [NSString stringWithFormat: @"  wall: %d, trace: %d, merge: %d", wallCrash, traceCrash, mergeCrash]];

				vector_t x = _crashLocation(initialCrashInfo);
				[eventLog addObject: [NSString stringWithFormat: @"  location: %f, %f", x.farr[0], x.farr[1]]];

				/*
				 if we hit a wall, it's a wall crash, no worry about merging, similarly, if it's a trace crash
				 however, if it's a merge crash only, we have to figure out which way to send the new motorcycle, when its multiple crashes
				 */
				
				if (wallCrash)
				{
					
					NSMutableSet* cycles = [NSMutableSet set];
					NSMutableSet* crashWalls = [NSMutableSet set];
					NSMutableSet* crashVertices = [NSMutableSet set];

					for (NSArray* crashInfo in simultaneousCrashes)
					{
						id obj0 = [crashInfo objectAtIndex: 1];
						id obj1 = [crashInfo objectAtIndex: 2];
						[cycles addObject: obj0];
						if ([obj1 isKindOfClass: [PSMotorcycle class]])
							[cycles addObject: obj1];
						else if ([obj1 isKindOfClass: [PSEdge class]])
							[crashWalls addObject: obj1];
						else if ([obj1 isKindOfClass: [PSVertex class]])
							[crashVertices addObject: obj1];
					}
					
					assert([crashWalls count] < 2);
					assert([crashVertices count] < 2);
					
					PSVertex* vertex = nil;
					
					// if we hit a vertex, we take it
					if (crashVertices.count)
					{
						vertex = [crashVertices anyObject];
					}
					else
					{
						PSSourceEdge* edge = [crashWalls anyObject];
						vertex = [[PSSplitVertex alloc] init];
						vertex.position = x;
						vertices = [vertices arrayByInsertingObject: vertex atIndex: [vertices indexOfObject: edge.leftVertex]+1];
						
						
						[self splitEdge: edge atVertex: (id)vertex];
						
					}
					
					// terminate each motorcycle
					for (PSMotorcycle* cycle in cycles)
					{
						[eventLog addObject: [NSString stringWithFormat: @"  cycle: (%f, %f) from (%f, %f)", cycle.velocity.farr[0], cycle.velocity.farr[1], cycle.sourceVertex.position.farr[0], cycle.sourceVertex.position.farr[1]]];
						assert(!cycle.terminalVertex);
						cycle.terminalVertex = vertex;
						cycle.leftNeighbour.rightNeighbour = cycle.rightNeighbour;
						cycle.rightNeighbour.leftNeighbour = cycle.leftNeighbour;
						
						[vertex addMotorcycle: cycle];
						
					}
					
					[motorcycles removeObjectsInArray: [cycles allObjects]];
					for (id cycle in cycles)
						assert(![terminatedMotorcycles containsObject: cycle]);
					terminatedMotorcycles = [terminatedMotorcycles arrayByAddingObjectsFromArray:[cycles allObjects]];
				}
				else if (traceCrash)
				{
					NSMutableSet* crashedCycles = [NSMutableSet set];
					double survivorTime = INFINITY;
					PSMotorcycle* survivor = nil;
					
					for (NSArray* crashInfo in simultaneousCrashes)
					{
						PSMotorcycle* cycle0 = [crashInfo objectAtIndex: 1];
						PSMotorcycle* cycle1 = [crashInfo objectAtIndex: 2];
						BOOL merge = [[crashInfo objectAtIndex: 5] boolValue];
						if (merge)
						{
							[crashedCycles addObject: cycle0];
							[crashedCycles addObject: cycle1];
							continue;
						}
						
						double t0 = [[crashInfo objectAtIndex: 3] doubleValue] + cycle0.start;
						double t1 = [[crashInfo objectAtIndex: 4] doubleValue] + cycle1.start;
						
						[crashedCycles addObject: cycle0];
						[crashedCycles addObject: cycle1];
						if (t0 < survivorTime)
						{
							survivor = cycle0;
							survivorTime = t0;
						}
						if (t1 < survivorTime)
						{
							survivor = cycle1;
							survivorTime = t1;
						}
						assert(survivorTime >= survivor.start);
					}
					
					
					[crashedCycles enumerateObjectsUsingBlock:^(PSMotorcycle* cycle, BOOL *stop) {
						[eventLog addObject: [NSString stringWithFormat: @"  cycle: (%f, %f) from (%f, %f)", cycle.velocity.farr[0], cycle.velocity.farr[1], cycle.sourceVertex.position.farr[0], cycle.sourceVertex.position.farr[1]]];

					}];
					
					PSCrashVertex* vertex = [[PSCrashVertex alloc] init];
					vertex.position = x;
					vertex.time = survivorTime;
					vertices = [vertices arrayByAddingObject: vertex];
					[traceCrashVertices addObject: vertex];
					
					assert(survivorTime >= survivor.start);

					assert(survivor);
					[crashedCycles removeObject: survivor];
										
					[eventLog addObject: [NSString stringWithFormat: @"  survivor towards: %f, %f @%f", survivor.velocity.farr[0], survivor.velocity.farr[1], survivorTime]];
					
					// terminate each motorcycle and insert an edge
					for (PSMotorcycle* cycle in crashedCycles)
					{
						assert(!cycle.terminalVertex);
						cycle.terminalVertex = vertex;
						cycle.terminator = survivor;
						cycle.leftNeighbour.rightNeighbour = cycle.rightNeighbour;
						cycle.rightNeighbour.leftNeighbour = cycle.leftNeighbour;
						[vertex addMotorcycle: cycle];
						
					}
					[vertex addMotorcycle: survivor];
					survivor.crashVertices = [survivor.crashVertices arrayByAddingObject: vertex];

					[motorcycles removeObjectsInArray: [crashedCycles allObjects]];
					for (id cycle in crashedCycles)
						assert(![terminatedMotorcycles containsObject: cycle]);
					terminatedMotorcycles = [terminatedMotorcycles arrayByAddingObjectsFromArray: [crashedCycles allObjects]];
					
				}
				else if (mergeCrash)
				{				
					PSMergeVertex* vertex = [[PSMergeVertex alloc] init];
					vertex.position = x;
					vertex.time = tmin;
					vertices = [vertices arrayByAddingObject: vertex];
					[mergeCrashVertices addObject: vertex];
					
					PSMotorcycle* escapedCycle = _findEscapeDirection(simultaneousCrashes);
					
					NSMutableSet* terminatedCycles = [NSMutableSet set];
					
					
					
					for (NSArray* crashInfo in simultaneousCrashes)
					{
						NSArray* cycles = @[[crashInfo objectAtIndex: 1], [crashInfo objectAtIndex: 2]];
						[terminatedCycles addObjectsFromArray: cycles];
					}
					
					for (PSMotorcycle* cycle in terminatedCycles)
					{
						assert(!cycle.terminalVertex);
						cycle.terminalVertex = vertex;
						cycle.terminator = escapedCycle;
						[vertex addMotorcycle: cycle];
					}
					
					[motorcycles removeObjectsInArray: [terminatedCycles allObjects]];
					for (id cycle in terminatedCycles)
					{
						assert(![terminatedMotorcycles containsObject: cycle]);
					}
					terminatedMotorcycles = [terminatedMotorcycles arrayByAddingObjectsFromArray: [terminatedCycles allObjects]];
					
					if (escapedCycle)
					{
						escapedCycle.sourceVertex = vertex;
						[vertex addMotorcycle: escapedCycle];
						[motorcycles addObject: escapedCycle];
					}
					
				}
			}
			
			
			
			
			
			crashes = [self crashMotorcycles: motorcycles withLimit: motorLimit];
		}
	}
	
	// we shouldn't have any motorcycles left at this point. But if we do, we want to see them
	
	for (PSMotorcycle* cycle in motorcycles)
	{
		PSVertex* vertex = [[PSVertex alloc] init];
		vertex.position = v3Add(cycle.sourceVertex.position, v3MulScalar(cycle.velocity, motorLimit*2.0-cycle.start));
		vertices = [vertices arrayByAddingObject: vertex];
		
		cycle.terminalVertex = vertex;
		
		assert(!vIsNAN(vertex.position));
		
		assert(![terminatedMotorcycles containsObject: cycle]);
		terminatedMotorcycles = [terminatedMotorcycles arrayByAddingObject: cycle];

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
	vector_t v0 = spoke0.velocity;
	vector_t v1 = spoke1.velocity;
	
	if (vLength(v0) == 0.0)
		return NO;
	if (vLength(v1) == 0.0)
		return NO;
	
	return (fabs(atan2(vCross(v0, v1).farr[2], vDot(v0, v1))) <= FLT_EPSILON);
	
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

static void _generateAntiSpokes(PSVertex* vertex, NSMutableArray* spokes)
{
	
	PSSourceEdge* edge0 = vertex.leftEdge;
	PSSourceEdge* edge1 = vertex.rightEdge;
	assert(edge0.rightVertex == vertex);
	assert(edge1.leftVertex == vertex);
	
	
	for (PSMotorcycle* cycle in vertex.incomingMotorcycles)
	{
		PSAntiSpoke* spoke = [[PSAntiSpoke alloc] init];
		spoke.sourceVertex = vertex;
		spoke.motorcycle = cycle;
		cycle.antiSpoke = spoke;
		spoke.motorcycleSpoke = cycle.spoke;
		
		if (spoke.motorcycleSpoke)
			spoke.motorcycleSpoke.antiSpoke = spoke;
		
		spoke.start = vertex.time;
		
		// figure out which edge is relevant
		PSSourceEdge* edge = nil;
		if ([vertex isKindOfClass: [PSSplitVertex class]])
		{
			edge = edge0; // in this case, both are colinear
		}
		else	 // else figure out which direction we'd hit
		{
			vector_t v = bisectorVelocity(edge0.normal, edge1.normal, edge0.edge, edge1.edge);
			
			double area = vCross(v, vNegate(cycle.velocity)).farr[2];
			if (area > 0.0)
				edge = edge0;
			else
				edge = edge1;
		}

		
		spoke.velocity = vReverseProject(edge.normal, cycle.velocity);
		
		assert(!vIsNAN(spoke.velocity));
		
		_assertSpokeUnique(spoke, vertex.outgoingSpokes);
		
		[spokes addObject: spoke];
		[vertex addSpoke: spoke];
	}
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
		cycle.reverseWaveVelocity = antiEdge.normal;
	}
	
	[antiSpokes addObject: antiSpoke];
	_assertSpokeUnique(antiSpoke, antiVertex.outgoingSpokes);
	[antiVertex addSpoke: antiSpoke];
	
}

/*
static void _generateCycleSpokes(PSVertex* vertex, NSMutableArray* spokes, NSMutableArray* antiSpokes)
{
	for (PSMotorcycle* cycle in vertex.outgoingMotorcycles)
	{
		_generateCycleSpoke(cycle, spokes, antiSpokes);
	}

}
*/
- (PSSplitEvent*) computeSimpleSplitEvent: (PSMotorcycleSpoke*) cycleSpoke atTime: (double) creationTime
{
	PSAntiSpoke* antiSpoke = cycleSpoke.antiSpoke;
	
	if (vLength(antiSpoke.velocity) == 0)
		return nil;
	
	double ts0 = cycleSpoke.start;
	double ts1 = antiSpoke.start;
	
	double tsx = fmax(ts0, ts1);
	
	vector_t vv = v3Sub(cycleSpoke.velocity, antiSpoke.velocity);
	
	
	vector_t delta = v3Sub(
						   v3Add(antiSpoke.sourceVertex.position, v3MulScalar(antiSpoke.velocity, tsx-ts1)),
						   v3Add(cycleSpoke.sourceVertex.position, v3MulScalar(cycleSpoke.velocity, tsx-ts0))
						   );
	
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
	
	if (angle <= 0.0) // if angle is negative between the two spokes, they are not converging
		return nil;
	
	
	vector_t p0 = waveFront.leftSpoke.sourceVertex.position;
	vector_t p1 = waveFront.rightSpoke.sourceVertex.position;
	
	double t0 = waveFront.leftSpoke.start;
	double t1 = waveFront.rightSpoke.start;
	
	vector_t tx = xRays2D(v3Add(p0, v3MulScalar(v0, -t0)), v0, v3Add(p1, v3MulScalar(v1, -t1)), v1);
	
	
	double tc = 0.5*(tx.farr[0]+tx.farr[1]);
	
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
	// FIXME: should we have split AND collapse?
//	if (!waveFront.leftSpoke.convex && !waveFront.rightSpoke.convex) // non-convex means it's going to split, basically
//		return nil;

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


		vector_t tx = xRays2D(p0, r0, v3Add(p1, v3MulScalar(v1, -t1)), v1);
		
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
		

		vector_t tx = xRays2D(v3Add(p0, v3MulScalar(v0, -t0)), v0, p1, r1);

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

- (void) emitOffsetOutlineForWaveFronts: (NSArray*) waveFronts atTime: (double) time
{
	// FIXME: emit not just visual outline, but proper outline path
	
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
		NSBezierPath* path = [self bezierPathFromOffsetSegments: vs count: numVertices];
		emitCallback(self, path);
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

static BOOL _waveFrontsAreAntiParallel(PSWaveFront* leftFront, PSWaveFront* rightFront)
{
	double lrdot = vDot(leftFront.direction, rightFront.direction);
	double lrcross = vCross(leftFront.direction, rightFront.direction).farr[2];
	
	return ((fabs(lrdot + 1.0) < FLT_EPSILON) && (fabs(lrcross) < FLT_EPSILON)); // test for anti-parallel faces

}

- (void) terminateWaveFront: (PSWaveFront*) waveFront
{
	[terminatedWaveFronts addObject: waveFront];
//	[terminatedSpokes addObject: waveFront.leftSpoke];
//	[terminatedSpokes addObject: waveFront.rightSpoke];
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
			if ([motorcycle.sourceVertex isKindOfClass: [PSMergeVertex class]])
			{
				
				PSEvent* reverseEvent = [self computeReverseMergeEventForMotorcycle: motorcycle];
				reverseEvent.creationTime = creationTime;
				if (reverseEvent)
					[motorcycleEvents addObject: reverseEvent];
				
			}
			
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
		if (a < b)
			return NSOrderedAscending;
		else if (a > b)
			return NSOrderedDescending;
		else
			return NSOrderedSame;
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
	
	simpleSpoke.leftWaveFront = motorcycleSpoke.leftWaveFront;
	simpleSpoke.rightWaveFront = motorcycleSpoke.rightWaveFront;
	simpleSpoke.leftWaveFront.rightSpoke = simpleSpoke;
	simpleSpoke.rightWaveFront.leftSpoke = simpleSpoke;
	
	[simpleSpoke.sourceVertex removeSpoke: motorcycleSpoke];
	[simpleSpoke.sourceVertex addSpoke: simpleSpoke];
	if (simpleSpoke.terminalVertex)
	{
		[simpleSpoke.terminalVertex removeSpoke: motorcycleSpoke];
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
	
	for (NSNumber* timeval in [emissionTimes arrayByAddingObject: [NSNumber numberWithDouble: extensionLimit]])
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
	
	while (events.count)
	{ @autoreleasepool {

		[events sortWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PSEvent* obj0, PSEvent* obj1) {
			
			double t0 = obj0.time;
			double t1 = obj1.time;
			
			if (t0 == t1)
				return NSOrderedSame;
			else if (t0 < t1)
				return NSOrderedAscending;
			else
				return NSOrderedDescending;
		}];

		PSEvent* firstEvent = [events objectAtIndex: 0];
		
		if (firstEvent.time > extensionLimit)
			break;
		
		assert(firstEvent.time >= lastEventTime);
		lastEventTime = firstEvent.time;
		
		NSMutableSet* changedWaveFronts = [NSMutableSet set];
		
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
			
			[eventLog addObject: [NSString stringWithFormat: @"%f: collapsing wavefront %@", event.time, waveFront]];
			[eventLog addObject: [NSString stringWithFormat: @"  %@", waveFront.leftSpoke]];
			[eventLog addObject: [NSString stringWithFormat: @"  %@", waveFront.rightSpoke]];

			
			[activeWaveFronts removeObject: waveFront];
			[changedWaveFronts addObject: waveFront];
			[self terminateWaveFront: waveFront];

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
					newVertex = leftSpoke.terminalVertex;
					[terminatedSpokes addObject: rightSpoke];
					[changedWaveFronts addObject: rightFront];
				}
				else if (rightSpoke.terminalVertex && !newVertex)
				{
					leftSpoke.terminalVertex = rightSpoke.terminalVertex;
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
						[terminatedSpokes addObject: leftSpoke];
					}
					if (!rightSpoke.terminalVertex)
					{
						rightSpoke.terminalVertex = newVertex;
						[terminatedSpokes addObject: rightSpoke];
					}
					[changedWaveFronts addObject: leftFront];
					[changedWaveFronts addObject: rightFront];
				
				}
				
				assert(newVertex);
				
				
				if ((leftCycle) || (rightCycle))
				{
					/*
					 fundamentally, this is for flipping anti-spokes. the vDot() condition is important, it checks if the neighbouring front is coming up "backwards" relative to the antiSpoke. if that is the case, the anti-spoke can be terminated as a regular spoke, without needing to be "flipped".
					 
					 A condition like
					 (((PSAntiSpoke*)leftSpoke).motorcycleSpoke.leftWaveFront.leftSpoke != rightSpoke)
					 is too narrow and does not work for the same purpose.
					 */
					
					BOOL motorContinues = NO;
					
					if (leftCycle && (vDot(rightFront.direction, ((PSMotorcycleSpoke*)leftSpoke).velocity) > 0.0))
						motorContinues = YES;
					else if (rightCycle && (vDot(leftFront.direction, ((PSMotorcycleSpoke*)rightSpoke).velocity) > 0.0))
						motorContinues = YES;

					if (motorContinues)
					{
						PSSimpleSpoke* motorSpoke = (id)(leftCycle ? leftSpoke : rightSpoke);
						PSMotorcycle* motorcycle = [(id)motorSpoke motorcycle];
						[eventLog addObject: [NSString stringWithFormat: @"  collapsing motorcycle %@", motorSpoke]];
						
						
						if (v3Equal(leftFront.direction, motorSpoke.leftWaveFront.direction) && v3Equal(rightFront.direction, motorSpoke.rightWaveFront.direction))
						{
							// seems to work
							
							[self swapSpoke: motorSpoke];
							
							motorSpoke.terminalVertex = nil;
							motorSpoke.start = event.time;
							motorSpoke.sourceVertex = newVertex;
							[newVertex addSpoke: motorSpoke];
							
							leftFront.rightSpoke = motorSpoke;
							rightFront.leftSpoke = motorSpoke;
							motorSpoke.leftWaveFront = leftFront;
							motorSpoke.rightWaveFront = rightFront;
						}
						else
						{
						
							PSSpoke* newSpoke = _createSpokeBetweenFronts(leftFront, rightFront, newVertex, event.time);
							assert(newSpoke.sourceVertex);
							[eventLog addObject: [NSString stringWithFormat: @"  new spoke to %@", newSpoke]];
							
							double angle = _angleBetweenSpokes(motorSpoke, newSpoke);
							BOOL isLeft = angle > 0.0;
							

							PSSpoke* simpleSpoke = [self swapSpoke: motorSpoke];
							assert(simpleSpoke.sourceVertex);
							
							motorSpoke.terminalVertex = nil;
							motorSpoke.start = event.time;
							motorSpoke.sourceVertex = simpleSpoke.terminalVertex;
							[motorSpoke.sourceVertex addSpoke: motorSpoke];
							
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
						
			if (!motorcycleSpoke.leftWaveFront || !motorcycleSpoke.rightWaveFront)
			{
				[eventLog addObject: [NSString stringWithFormat: @"%f: ignoring wavefront split due to cancelled motorcycle: %@", firstEvent.time, event.antiSpoke]];
				
			}
			else
			{
				[eventLog addObject: [NSString stringWithFormat: @"%f: splitting wavefront anti-spoke %@", firstEvent.time, event.antiSpoke]];
				
				
				
				PSVertex* newVertex = nil;

				if (antiSpoke.terminalVertex && motorcycleSpoke.terminalVertex)
				{
					newVertex = motorcycleSpoke.terminalVertex;
				}
				else if (motorcycleSpoke.terminalVertex)
				{
					[eventLog addObject: [NSString stringWithFormat: @"  motorcycle spoke already terminated %@", motorcycleSpoke]];
					//_assertSpokeConsistent(antiSpoke);
					
					newVertex = motorcycleSpoke.terminalVertex;

					antiSpoke.terminalVertex = newVertex;
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
					[newVertex addSpoke: motorcycleSpoke];
					
					motorcycleSpoke.upcomingEvent = nil;
					[changedWaveFronts addObject: motorcycleSpoke.leftWaveFront];
					[changedWaveFronts addObject: motorcycleSpoke.rightWaveFront];
					[terminatedSpokes addObject: motorcycleSpoke];
					
				}
				else
				{
					
					_assertSpokeConsistent(antiSpoke);
					_assertSpokeConsistent(motorcycleSpoke);
					
					_assertWaveFrontConsistent(antiSpoke.leftWaveFront);
					_assertWaveFrontConsistent(antiSpoke.rightWaveFront);
					_assertWaveFrontConsistent(motorcycleSpoke.leftWaveFront);
					_assertWaveFrontConsistent(motorcycleSpoke.rightWaveFront);
					
					newVertex = [[PSVertex alloc] init];
					newVertex.time = event.time;
					newVertex.position = v3Add(antiSpoke.sourceVertex.position, v3MulScalar(antiSpoke.velocity, event.time - antiSpoke.start));
					[collapsedVertices addObject: newVertex];
					
					antiSpoke.terminalVertex = newVertex;
					motorcycleSpoke.terminalVertex = newVertex;
					[terminatedSpokes addObject: antiSpoke];
					[terminatedSpokes addObject: motorcycleSpoke];
				}
				
				assert(newVertex);

				
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
							[newVertex addSpoke: incomingSpoke];
							
							[terminatedSpokes addObject: incomingSpoke];
							
						}
						
						if ([activeWaveFronts containsObject: rightWaveFront])
						{
							[self terminateWaveFront: rightWaveFront];
							[activeWaveFronts removeObject: rightWaveFront];
							[changedWaveFronts addObject: rightWaveFront];
						}
						if ([activeWaveFronts containsObject: leftWaveFront])
						{
							[self terminateWaveFront: leftWaveFront];
							[activeWaveFronts removeObject: leftWaveFront];
							[changedWaveFronts addObject: leftWaveFront];
						}
					}
					else
					{
						PSSpoke* newSpoke = _createSpokeBetweenFronts(antiSpoke.leftWaveFront, motorcycleSpoke.rightWaveFront, newVertex,  event.time);
						
						assert(_angleBetweenSpokes(antiSpoke, newSpoke) > 0.0);
						newSpoke.leftWaveFront = antiSpoke.leftWaveFront;
						newSpoke.rightWaveFront = motorcycleSpoke.rightWaveFront;
												
						newSpoke.leftWaveFront.rightSpoke = newSpoke;
						newSpoke.rightWaveFront.leftSpoke = newSpoke;
						
						_assertWaveFrontConsistent(newSpoke.leftWaveFront);
						_assertWaveFrontConsistent(newSpoke.rightWaveFront);
						
						[changedWaveFronts addObject: newSpoke.leftWaveFront];
						[changedWaveFronts addObject: newSpoke.rightWaveFront];
						
						[eventLog addObject: [NSString stringWithFormat: @"  new spoke to the left %@", newSpoke]];
						
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
							[newVertex addSpoke: incomingSpoke];
							
							[terminatedSpokes addObject: incomingSpoke];
							
						}
						
						if ([activeWaveFronts containsObject: rightWaveFront])
						{
							[self terminateWaveFront: rightWaveFront];
							[activeWaveFronts removeObject: rightWaveFront];
							[changedWaveFronts addObject: rightWaveFront];
						}
						if ([activeWaveFronts containsObject: leftWaveFront])
						{
							[self terminateWaveFront: leftWaveFront];
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
			[eventLog addObject: [NSString stringWithFormat: @"%f: branchinng %@", firstEvent.time, event.rootSpoke]];
			// a branch simply inserts a new spoke+wavefront into the list, in the same direction as its parent
			
			assert(event.rootSpoke);
			assert(event.rootSpoke.rightWaveFront);
			assert(event.rootSpoke.leftWaveFront);
			
			_assertSpokeConsistent(event.rootSpoke);
			//_assertWaveFrontConsistent(event.rootSpoke.leftWaveFront);
			//_assertWaveFrontConsistent(event.rootSpoke.rightWaveFront);
			
			assert(event.branchVertex.incomingMotorcycles.count < 3);
			for (PSMotorcycle* motorcycle in event.branchVertex.incomingMotorcycles)
			{
				if (motorcycle.terminalVertex != event.branchVertex)
					continue;
				
				PSAntiSpoke* newSpoke = motorcycle.antiSpoke;
				PSSimpleSpoke* rootSpoke = event.rootSpoke;
				
				PSWaveFront* leftFront = rootSpoke.leftWaveFront;
				PSWaveFront* rightFront = rootSpoke.rightWaveFront;

				[eventLog addObject: [NSString stringWithFormat: @"  branch moto: %@", motorcycle]];
				
				newSpoke.start = event.time;

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
						 continue;

					
					newFront.direction = rightFront.direction;
					newSpoke.leftWaveFront = newFront;
					newSpoke.rightWaveFront = rightFront;
					newFront.leftSpoke = rootSpoke;
					newFront.rightSpoke = newSpoke;
					
					rightFront.leftSpoke = newSpoke;
					
					rootSpoke.rightWaveFront = newFront;
					
					[changedWaveFronts addObject: rightFront];
					
				}
				else // to the left
				{
					double dotAlpha = vDot(leftFront.direction, motorcycle.velocity);
					
					if (dotAlpha >= 0.0)
						continue;

					
					newFront.direction = leftFront.direction;
					newSpoke.leftWaveFront = leftFront;
					newSpoke.rightWaveFront = newFront;
					newFront.leftSpoke = newSpoke;
					newFront.rightSpoke = rootSpoke;
					
					leftFront.rightSpoke = newSpoke;
					rootSpoke.leftWaveFront = newFront;

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
			
		}
		else if ([firstEvent isKindOfClass: [PSReverseBranchEvent class]])
		{
#pragma mark Reverse Branch Event Handling
			[eventLog addObject: [NSString stringWithFormat: @"%f: tsunami branch", firstEvent.time]];

			PSReverseBranchEvent* event = (id) firstEvent;
			assert([event.rootSpoke isKindOfClass: [PSAntiSpoke class]]);
			
			PSAntiSpoke* reverseSpoke = event.rootSpoke;
			PSCrashVertex* vertex = (id) event.branchVertex;

			[eventLog addObject: [NSString stringWithFormat: @"  root %@", reverseSpoke]];
			[eventLog addObject: [NSString stringWithFormat: @"  vertex %@", vertex]];
			
			reverseSpoke.passedCrashVertex = vertex;
			

			if (vertex.forwardEvent)
				[events removeObject: vertex.forwardEvent];
			
			PSWaveFront* leftFront = reverseSpoke.leftWaveFront;
			PSWaveFront* rightFront = reverseSpoke.rightWaveFront;
			
			NSArray* incomingMotorcycles = [vertex incomingMotorcyclesCCW];
			
			// dump those cycles that are going the wrong way
			incomingMotorcycles = [incomingMotorcycles select: ^BOOL(PSMotorcycle* motorcycle) {
				double asinAlpha = vCross(reverseSpoke.velocity, motorcycle.velocity).farr[2];
				if (asinAlpha > 0.0)
				{
					double dotAlpha = vDot(rightFront.direction, motorcycle.velocity);
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
					
					if (antiSpoke == reverseSpoke)
						continue;
					
					vector_t direction = vZero();
					
					double angle = vAngleBetweenVectors2D(reverseSpoke.velocity, vNegate(motorcycle.velocity));
					if (angle > 0.0)
						direction = leftFront.direction;
					else
						direction = rightFront.direction;

					antiSpoke.velocity = vReverseProject(direction, antiSpoke.motorcycle.velocity);
					antiSpoke.start = event.time;


				}
				
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
						if (leftSpoke == reverseSpoke)
							newFront.direction = rightFront.direction;
						else if (angle > 0.0)
							newFront.direction = leftFront.direction;
						else
							newFront.direction = rightFront.direction;
						
					_assertWaveFrontConsistent(newFront);
					[changedWaveFronts addObject: newFront];
					[activeWaveFronts addObject: newFront];
					

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
		}
		
		[events removeObjectsInArray: invalidEvents];
		
		for (PSWaveFront* waveFront in changedWaveFronts)
		{
			PSCollapseEvent* event = [self computeCollapseEvent: waveFront];
			
			waveFront.collapseEvent = event;
			
			if (event && !isnan(event.time) && !isinf(event.time) && [activeWaveFronts containsObject: waveFront])
			{
				assert(event.time >= firstEvent.time);
				[events addObject: event];
				
			}
		}

		
	}	}
	
#pragma mark Terminate left over spokes
	
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
				[vertex addSpoke: spoke];
				
				[collapsedVertices addObject: vertex];
				[terminatedSpokes addObject: spoke];
			}
		}
	}
	
	vertices = [vertices arrayByAddingObjectsFromArray: collapsedVertices];
	
	BOOL maybe = NO;
	if (maybe)
		NSLog(@"%@", eventLog);
	
}

- (PSReverseBranchEvent*) computeReverseBranchEventForMotorcycle: (PSMotorcycle*) motorcycle vertex: (PSCrashVertex*) crashVertex;
{
	PSAntiSpoke* antiSpoke = motorcycle.antiSpoke;
	
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

- (PSReverseMergeEvent*) computeReverseMergeEventForMotorcycle: (PSMotorcycle*) motorcycle
{
	PSAntiSpoke* antiSpoke = motorcycle.antiSpoke;
	
	assert (vLength(antiSpoke.velocity) != 0.0);
	
	
	PSMergeVertex* mergeVertex = (id) motorcycle.sourceVertex;
	
	double time = antiSpoke.start + vLength(v3Sub(motorcycle.terminalVertex.position, motorcycle.sourceVertex.position))/vLength(antiSpoke.velocity);
	
	if (time < mergeVertex.time)
	{
		PSReverseMergeEvent* event = [[PSReverseMergeEvent alloc] init];
		event.time = time;
		event.rootSpoke = antiSpoke;
		event.location = mergeVertex.position;
		mergeVertex.reverseEvent = event;
		
		return event;
	}
	else
		return nil;
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
		vector_t a = motorcycle.sourceVertex.position;
		vector_t b = motorcycle.terminalVertex.position;
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
		vector_t a = spoke.sourceVertex.position;
		vector_t b = spoke.terminalVertex.position;
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
		vector_t a = edge.leftVertex.position;
		vector_t b = edge.rightVertex.position;
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
		positions[vi] = vertex.position;
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


@end






