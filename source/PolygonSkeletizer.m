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
	NSMutableArray* traceCrashVertices;
	NSMutableArray* mergeCrashVertices;
	NSArray* edges;
	
	NSArray* terminatedMotorcycles;
	NSMutableSet* terminatedSpokes;
	NSMutableArray* terminatedWaveFronts;
	
	NSMutableArray* outlineMeshes;
	NSArray* emissionTimes;
	
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

- (NSArray*) crashMotorcycles: (NSArray*) motorcycles withLimit: (double) motorLimit
{
	NSMutableArray* crashes = [NSMutableArray array];
	size_t k = 0;
	for (PSMotorcycle* cycle in motorcycles)
	{
		@autoreleasepool {
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
						
						if (hitStart)
						{
							id crash = @[[NSNumber numberWithDouble: t], cycle, edge.leftVertex];
							[crashes addObject: crash];
						}
						else if (hitEnd)
						{
							id crash = @[[NSNumber numberWithDouble: t], cycle, edge.rightVertex];
							[crashes addObject: crash];
						}
						else if ((tx.farr[1] > 0.0) && (tx.farr[1] < 1.0))
						{
							id crash = @[[NSNumber numberWithDouble: t], cycle, edge, [NSNumber numberWithDouble: tx.farr[0]], [NSNumber numberWithDouble: tx.farr[1]]];
							[crashes addObject: crash];
						}
						
					}
				}
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
	
	for (NSArray* crashInfo in crashes)
	{
		PSMotorcycle* cycle0 = [crashInfo objectAtIndex: 1];
		PSMotorcycle* cycle1 = [crashInfo objectAtIndex: 2];
		
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
						cycle.terminalVertex = vertex;
						cycle.leftNeighbour.rightNeighbour = cycle.rightNeighbour;
						cycle.rightNeighbour.leftNeighbour = cycle.leftNeighbour;
						
						[vertex addMotorcycle: cycle];
						
					}
					
					[motorcycles removeObjectsInArray: [cycles allObjects]];
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
					}
					
					[crashedCycles enumerateObjectsUsingBlock:^(PSMotorcycle* cycle, BOOL *stop) {
						[eventLog addObject: [NSString stringWithFormat: @"  cycle: (%f, %f) from (%f, %f)", cycle.velocity.farr[0], cycle.velocity.farr[1], cycle.sourceVertex.position.farr[0], cycle.sourceVertex.position.farr[1]]];

					}];
					
					PSCrashVertex* vertex = [[PSCrashVertex alloc] init];
					vertex.position = x;
					vertex.time = survivorTime;
					vertices = [vertices arrayByAddingObject: vertex];
					[traceCrashVertices addObject: vertex];
					
					assert(survivor);
					[crashedCycles removeObject: survivor];
										
					[eventLog addObject: [NSString stringWithFormat: @"  survivor towards: %f, %f @%f", survivor.velocity.farr[0], survivor.velocity.farr[1], survivorTime]];
					
					// terminate each motorcycle and insert an edge
					for (PSMotorcycle* cycle in crashedCycles)
					{
						cycle.terminalVertex = vertex;
						cycle.terminator = survivor;
						cycle.leftNeighbour.rightNeighbour = cycle.rightNeighbour;
						cycle.rightNeighbour.leftNeighbour = cycle.leftNeighbour;
						[vertex addMotorcycle: cycle];
						
					}
					[vertex addMotorcycle: survivor];
					survivor.crashVertices = [survivor.crashVertices arrayByAddingObject: vertex];

					[motorcycles removeObjectsInArray: [crashedCycles allObjects]];
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
						cycle.terminalVertex = vertex;
						cycle.terminator = escapedCycle;
						[vertex addMotorcycle: cycle];
					}
					
					[motorcycles removeObjectsInArray: [terminatedCycles allObjects]];
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
	spoke.start = vertex.time;
	
	[spokes addObject: spoke];
	_assertSpokeUnique(spoke, vertex.outgoingSpokes);
	[vertex addSpoke: spoke];
	
	PSAntiSpoke* antiSpoke = [[PSAntiSpoke alloc] init];
	PSVertex* antiVertex = cycle.terminalVertex;
	
	antiSpoke.sourceVertex = antiVertex;
	antiSpoke.start = antiVertex.time;
	
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

static void _generateCycleSpokes(PSVertex* vertex, NSMutableArray* spokes, NSMutableArray* antiSpokes)
{
	for (PSMotorcycle* cycle in vertex.outgoingMotorcycles)
	{
		_generateCycleSpoke(cycle, spokes, antiSpokes);
	}

}

- (PSSplitEvent*) computeSimpleSplitEvent: (PSMotorcycleSpoke*) cycleSpoke
{
	PSAntiSpoke* antiSpoke = cycleSpoke.antiSpoke;
	
	if (vLength(antiSpoke.velocity) == 0)
		return nil;
	
	vector_t delta = v3Sub(
						   v3Add(cycleSpoke.sourceVertex.position, v3MulScalar(cycleSpoke.velocity, -cycleSpoke.start)),
						   v3Add(antiSpoke.sourceVertex.position, v3MulScalar(antiSpoke.velocity, -antiSpoke.start))
						   );
	double distance = vLength(delta);
	
	double v0 = vLength(cycleSpoke.velocity);
	double v1 = vLength(antiSpoke.velocity);
	
	
	double tc = distance/(v0+v1);
	
	PSSplitEvent* event = [[PSSplitEvent alloc] init];
	event.time = tc;
	event.location = v3Add(cycleSpoke.sourceVertex.position, v3MulScalar(cycleSpoke.velocity, tc - cycleSpoke.start));
	
	event.antiSpoke = antiSpoke;
	
	return event;
}

- (PSSplitEvent*) computeCrashedSplitEvent: (PSMotorcycleSpoke*) cycleSpoke
{
	PSMotorcycle* motorcycle = cycleSpoke.motorcycle;
	assert([motorcycle.terminalVertex isKindOfClass: [PSCrashVertex class]]);
	
	
	PSAntiSpoke* antiSpoke = cycleSpoke.antiSpoke;

	if (vLength(antiSpoke.velocity) == 0)
		return nil;
	

	PSCrashVertex* vertex = (id)motorcycle.terminalVertex;
	
	assert(vertex.outgoingMotorcycles.count == 1);
	PSMotorcycle* winningCycle = [vertex.outgoingMotorcycles lastObject];
	
	double asina = vCross(winningCycle.velocity, motorcycle.velocity).farr[2];
	
	vector_t wallDir = vZero();
	
	if (asina > 0.0) // alpha > 0 == to the right
	{
		wallDir = winningCycle.rightEdge.normal;
	}
	else
	{
		wallDir = winningCycle.leftEdge.normal;
	}
	
	vector_t antiVel = vReverseProject(wallDir, motorcycle.velocity);
	antiSpoke.velocity = antiVel;
	
	return [self computeSimpleSplitEvent: cycleSpoke];
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
		tc = INFINITY;
	
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

	if (!waveFront.leftSpoke.convex || !waveFront.rightSpoke.convex) // non-convex means it's going to split, basically
		return nil;

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
			
			if (v3Equal(a, lastVertex))
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

- (NSArray*) computeEventsForMotorcycle: (PSMotorcycle*) motorcycle
{
	PSMotorcycleSpoke* cycleSpoke = motorcycle.spoke;
	PSAntiSpoke* antiSpoke = motorcycle.antiSpoke;
	NSMutableArray* motorcycleEvents = [NSMutableArray array];
		
	//if ([motorcycle.terminalVertex isKindOfClass: [PSSplitVertex class]] || [motorcycle.terminalVertex isKindOfClass: [PSSourceVertex class]])
	if (vLength(antiSpoke.velocity) > 0.0)
	{		
		if ([motorcycle.sourceVertex isKindOfClass: [PSMergeVertex class]])
		{
			
			PSEvent* reverseEvent = [self computeReverseMergeEventForMotorcycle: motorcycle];
			if (reverseEvent)
				[motorcycleEvents addObject: reverseEvent];
			
		}
		
		for (PSCrashVertex* crashVertex in motorcycle.crashVertices)
		{
			PSEvent* reverseEvent = [self computeReverseBranchEventForMotorcycle: motorcycle vertex: crashVertex];
			
			if (reverseEvent)
				[motorcycleEvents addObject: reverseEvent];
			
		}
		
		
	}
	
	if ([cycleSpoke.motorcycle.terminalVertex isKindOfClass: [PSCrashVertex class]])
	{
		if (vLength(antiSpoke.velocity) > 0.0)
		{
			PSSplitEvent* splitEvent = [self computeSimpleSplitEvent: cycleSpoke];
			if (splitEvent)
				[motorcycleEvents addObject: splitEvent];
		}
	}
	else if ([cycleSpoke.motorcycle.terminalVertex isKindOfClass: [PSMergeVertex class]])
	{
		if (vLength(antiSpoke.velocity) > 0.0)
		{
			PSSplitEvent* splitEvent = [self computeSimpleSplitEvent: cycleSpoke];
			if (splitEvent)
				[motorcycleEvents addObject: splitEvent];
		}
	}
	else
	{
		PSSplitEvent* splitEvent = [self computeSimpleSplitEvent: cycleSpoke];
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

- (PSSimpleSpoke*) swapMotorcycleSpoke: (PSAntiSpoke*) motorcycleSpoke
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
	return simpleSpoke;

}
- (PSSimpleSpoke*) swapAntiSpoke: (PSAntiSpoke*) antiSpoke 
{
	PSSimpleSpoke* simpleSpoke = [[PSSimpleSpoke alloc] init];
	simpleSpoke.start = antiSpoke.start;
	simpleSpoke.sourceVertex = antiSpoke.sourceVertex;
	simpleSpoke.velocity = antiSpoke.velocity;
	simpleSpoke.terminalVertex = antiSpoke.terminalVertex;
	
	simpleSpoke.leftWaveFront = antiSpoke.leftWaveFront;
	simpleSpoke.rightWaveFront = antiSpoke.rightWaveFront;
	simpleSpoke.leftWaveFront.rightSpoke = simpleSpoke;
	simpleSpoke.rightWaveFront.leftSpoke = simpleSpoke;
	
	[simpleSpoke.sourceVertex removeSpoke: antiSpoke];
	[simpleSpoke.sourceVertex addSpoke: simpleSpoke];
	if (simpleSpoke.terminalVertex)
	{
		[simpleSpoke.terminalVertex removeSpoke: antiSpoke];
		[simpleSpoke.terminalVertex addSpoke: simpleSpoke];
	}
	if ([terminatedSpokes containsObject: antiSpoke])
	{
		[terminatedSpokes removeObject: antiSpoke];
		[terminatedSpokes addObject: simpleSpoke];
	}
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
//	assert(vEqualWithin3D(vProjectAOnB(waveFront.rightSpoke.velocity, waveFront.direction), waveFront.direction, FLT_EPSILON));
//	assert(vEqualWithin3D(vProjectAOnB(waveFront.leftSpoke.velocity, waveFront.direction), waveFront.direction, FLT_EPSILON));
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
/*
	NSMutableArray* crashVertices = [[traceCrashVertices arrayByAddingObjectsFromArray: mergeCrashVertices] mutableCopy];
	
	[crashVertices sortUsingComparator:^NSComparisonResult(PSVertex* obj1, PSVertex* obj2) {
		double a = obj1.time;
		double b = obj2.time;
		if (a < b)
			return NSOrderedAscending;
		else if (a > b)
			return NSOrderedDescending;
		else
			return NSOrderedSame;
	}];
*/
	for (PSCrashVertex* vertex in traceCrashVertices)
	{
		PSBranchEvent* event = [[PSBranchEvent alloc] init];
		event.time = vertex.time;
		event.location = vertex.position;
		event.branchVertex = vertex;
		vertex.forwardEvent = event;
		event.rootSpoke = [[vertex.outgoingMotorcycles objectAtIndex: 0] spoke];
		// time = vLength(v3Sub(event.rootSpoke.sourceVertex.position, event.location))/vLength(event.rootSpoke.velocity)
		
		[events addObject: event];
	}

	for (PSMergeVertex* vertex in mergeCrashVertices)
	{
		PSMergeEvent* event = [[PSMergeEvent alloc] init];
		event.time = vertex.time;
		event.location = vertex.position;
		event.mergeVertex = vertex;
		vertex.forwardEvent = event;
		
		[events addObject: event];
	}
	
	for (PSMotorcycleSpoke* cycleSpoke in motorcycleSpokes)
	{
		NSArray* motorcycleEvents = [self computeEventsForMotorcycle: cycleSpoke.motorcycle];
		
		
		if (motorcycleEvents.count)
		{
			cycleSpoke.upcomingEvent = [motorcycleEvents objectAtIndex: 0];
			[events addObject: [motorcycleEvents objectAtIndex: 0]];
		}
	}
	// prune events that occur after extensionLimit
	
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
			
			[eventLog addObject: [NSString stringWithFormat: @"%f: collapsing wavefront %@, bounded by %@, %@", event.time, waveFront, waveFront.leftSpoke, waveFront.rightSpoke]];

			PSVertex* newVertex = [[PSVertex alloc] init];
			newVertex.time = event.time;
			[collapsedVertices addObject: newVertex];
			
			//BOOL leftFast = [leftSpoke isKindOfClass: [PSFastSpoke class]];
			//BOOL rightFast = [leftSpoke isKindOfClass: [PSFastSpoke class]];
			
			
			vector_t xPos = event.location;

			newVertex.position = xPos;
			
			leftSpoke.terminalVertex = newVertex;
			rightSpoke.terminalVertex = newVertex;
			[terminatedSpokes addObject: leftSpoke];
			[terminatedSpokes addObject: rightSpoke];
			
			if ([leftSpoke isKindOfClass: [PSMotorcycleSpoke class]])
			{
				PSMotorcycleSpoke* motorcycleSpoke = (id) leftSpoke;
				[eventLog addObject: [NSString stringWithFormat: @"  removing motorcycle %@", motorcycleSpoke]];
				
				[self swapAntiSpoke: motorcycleSpoke.antiSpoke];
				
				for (PSCrashVertex* cv in motorcycleSpoke.motorcycle.crashVertices)
				{
					if (cv.forwardEvent)
						[events removeObject: cv.forwardEvent];
					cv.forwardEvent = nil;
					/*
					if (cv.reverseEvent)
						[events removeObject: cv.reverseEvent];
					cv.reverseEvent = nil;
					 */
				}
				if (motorcycleSpoke.upcomingEvent)
					[events removeObject: motorcycleSpoke.upcomingEvent];
				motorcycleSpoke.upcomingEvent = nil;

			}
			if ([rightSpoke isKindOfClass: [PSMotorcycleSpoke class]])
			{
				PSMotorcycleSpoke* motorcycleSpoke = (id) rightSpoke;
				[eventLog addObject: [NSString stringWithFormat: @"  removing motorcycle %@", motorcycleSpoke]];
				
				[self swapAntiSpoke: motorcycleSpoke.antiSpoke];
				
				for (PSCrashVertex* cv in motorcycleSpoke.motorcycle.crashVertices)
				{
					if (cv.forwardEvent)
						[events removeObject: cv.forwardEvent];
					cv.forwardEvent = nil;
					/*
					if (cv.reverseEvent)
						[events removeObject: cv.reverseEvent];
					cv.reverseEvent = nil;
					 */
				}

				if (motorcycleSpoke.upcomingEvent)
					[events removeObject: motorcycleSpoke.upcomingEvent];
				motorcycleSpoke.upcomingEvent = nil;
				
			}
			
			if ([leftSpoke isKindOfClass: [PSAntiSpoke class]] && (vDot(rightFront.direction, ((PSAntiSpoke*)leftSpoke).velocity) > 0.0))
			{
				PSAntiSpoke* antiSpoke = (id)leftSpoke;


				PSSimpleSpoke* simpleSpoke = [self swapAntiSpoke: antiSpoke];
				
				antiSpoke.terminalVertex = nil;
				antiSpoke.start = event.time;
				antiSpoke.sourceVertex = simpleSpoke.terminalVertex;
				[antiSpoke.sourceVertex addSpoke: antiSpoke];

				PSSimpleSpoke* newSpoke = [[PSSimpleSpoke alloc] init];
				newSpoke.velocity = bisectorVelocity(leftFront.direction, rightFront.direction, _normalToEdge(leftFront.direction), _normalToEdge(rightFront.direction));
				newSpoke.start = event.time;
				newSpoke.sourceVertex = newVertex;
				[newVertex addSpoke: newSpoke];
				
				double angle = vAngleBetweenVectors2D(antiSpoke.velocity, newSpoke.velocity);
				BOOL isLeft = angle > 0.0;

				vector_t direction = isLeft ? rightFront.direction : leftFront.direction;
				
				antiSpoke.velocity = vReverseProject(direction, antiSpoke.motorcycle.velocity);

				PSWaveFront* newFront = [[PSWaveFront alloc] init];
				newFront.direction = direction;
				newFront.leftSpoke = isLeft ? newSpoke : antiSpoke;
				newFront.rightSpoke = isLeft ? antiSpoke : newSpoke;
				
				leftFront.rightSpoke = isLeft ? newSpoke : antiSpoke;
				rightFront.leftSpoke = isLeft ? antiSpoke : newSpoke;
				
				leftFront.rightSpoke.leftWaveFront = leftFront;
				leftFront.rightSpoke.rightWaveFront = newFront;
				rightFront.leftSpoke.leftWaveFront = newFront;
				rightFront.leftSpoke.rightWaveFront = rightFront;
				
				if (antiSpoke.motorcycleSpoke.upcomingEvent)
					[events removeObject: antiSpoke.motorcycleSpoke.upcomingEvent];
				
				NSArray* motorcycleEvents = [self computeEventsForMotorcycle: antiSpoke.motorcycle];
				
				motorcycleEvents = [motorcycleEvents select: ^BOOL(PSEvent* obj) {
					if (obj.class == event.class)
						return obj.time > firstEvent.time;
					else
						return obj.time >= firstEvent.time;
				}];
				
				
				if (motorcycleEvents.count)
				{
					antiSpoke.motorcycleSpoke.upcomingEvent = [motorcycleEvents objectAtIndex: 0];
					[events addObject: antiSpoke.motorcycleSpoke.upcomingEvent];
				}

				
				[changedWaveFronts addObject: leftFront];
				[changedWaveFronts addObject: rightFront];
				[changedWaveFronts addObject: newFront];
				[activeWaveFronts addObject: newFront];
				
				[activeWaveFronts removeObject: waveFront];
				[changedWaveFronts addObject: waveFront];
				
				[self terminateWaveFront: waveFront];

			}
			else if ([rightSpoke isKindOfClass: [PSAntiSpoke class]] && (vDot(leftFront.direction, ((PSAntiSpoke*)rightSpoke).velocity) > 0.0))
			{
				PSAntiSpoke* antiSpoke = (id)rightSpoke;


				PSSimpleSpoke* simpleSpoke = [self swapAntiSpoke: antiSpoke];
				
				antiSpoke.terminalVertex = nil;
				antiSpoke.start = event.time;
				antiSpoke.sourceVertex = simpleSpoke.terminalVertex;
				[antiSpoke.sourceVertex addSpoke: antiSpoke];
				
				
				PSSimpleSpoke* newSpoke = [[PSSimpleSpoke alloc] init];
				newSpoke.velocity = bisectorVelocity(leftFront.direction, rightFront.direction, _normalToEdge(leftFront.direction), _normalToEdge(rightFront.direction));
				newSpoke.start = event.time;
				newSpoke.sourceVertex = newVertex;
				[newVertex addSpoke: newSpoke];
				
				double angle = vAngleBetweenVectors2D(antiSpoke.velocity, newSpoke.velocity);
				BOOL isLeft = angle > 0.0;
				
				vector_t direction = isLeft ? rightFront.direction : leftFront.direction;
				
				antiSpoke.velocity = vReverseProject(direction, antiSpoke.motorcycle.velocity);
				
				PSWaveFront* newFront = [[PSWaveFront alloc] init];
				newFront.direction = direction;
				newFront.leftSpoke = isLeft ? newSpoke : antiSpoke;
				newFront.rightSpoke = isLeft ? antiSpoke : newSpoke;
				
				leftFront.rightSpoke = isLeft ? newSpoke : antiSpoke;
				rightFront.leftSpoke = isLeft ? antiSpoke : newSpoke;
				
				leftFront.rightSpoke.leftWaveFront = leftFront;
				leftFront.rightSpoke.rightWaveFront = newFront;
				rightFront.leftSpoke.leftWaveFront = newFront;
				rightFront.leftSpoke.rightWaveFront = rightFront;				
				
				if (antiSpoke.motorcycleSpoke.upcomingEvent)
					[events removeObject: antiSpoke.motorcycleSpoke.upcomingEvent];
				
				NSArray* motorcycleEvents = [self computeEventsForMotorcycle: antiSpoke.motorcycle];
				
				motorcycleEvents = [motorcycleEvents select: ^BOOL(PSEvent* obj) {
					if (obj.class == event.class)
						return obj.time > firstEvent.time;
					else
						return obj.time >= firstEvent.time;
				}];
				
				
				if (motorcycleEvents.count)
				{
					antiSpoke.motorcycleSpoke.upcomingEvent = [motorcycleEvents objectAtIndex: 0];
					[events addObject: antiSpoke.motorcycleSpoke.upcomingEvent];
				}
				
				
				[changedWaveFronts addObject: leftFront];
				[changedWaveFronts addObject: rightFront];
				[changedWaveFronts addObject: newFront];
				[activeWaveFronts addObject: newFront];
				
				[activeWaveFronts removeObject: waveFront];
				[changedWaveFronts addObject: waveFront];
				
				[self terminateWaveFront: waveFront];

				
			}
			else if (leftFront == rightFront)
			{

				[activeWaveFronts removeObject: leftFront];
				[changedWaveFronts addObject: leftFront];
				
				[self terminateWaveFront: leftFront];

				[activeWaveFronts removeObject: waveFront];
				[changedWaveFronts addObject: waveFront];
				
				[self terminateWaveFront: waveFront];
			}
			else if (_waveFrontsAreAntiParallel(leftFront, rightFront)) // test for anti-parallel faces
			{
				vector_t newDirection = v3MulScalar(v3Add(vNegate(_normalToEdge(leftFront.direction)), _normalToEdge(rightFront.direction)), 0.5);
			
				[eventLog addObject: [NSString stringWithFormat: @"  creating fast spoke to %.3f, %.3f", newDirection.farr[0], newDirection.farr[1]]];
				PSFastSpoke* newSpoke = [[PSFastSpoke alloc] init];
				newSpoke.sourceVertex = newVertex;
				newSpoke.start = event.time;
				newSpoke.direction = newDirection;

				
				leftFront.rightSpoke = newSpoke;
				rightFront.leftSpoke = newSpoke;
				newSpoke.leftWaveFront = leftFront;
				newSpoke.rightWaveFront	= rightFront;
				
				[changedWaveFronts addObject: waveFront];
				[changedWaveFronts addObject: leftFront];
				[changedWaveFronts addObject: rightFront];
				
				[activeWaveFronts removeObject: waveFront];
				[changedWaveFronts addObject: waveFront];
				
				[self terminateWaveFront: waveFront];

			}
			else if (vCross(leftFront.direction, rightFront.direction).farr[2] < 0.0)
			{
				// this case marks a "closing" collapse, no new spoke should be generated, as it would just go the "wrong" direction
				// it is assumed that the neighbouring wavefronts also collapse simultaneously, on their own
				_assertWaveFrontConsistent(waveFront);
				[activeWaveFronts removeObject: waveFront];
				[changedWaveFronts addObject: waveFront];
				[self terminateWaveFront: waveFront];
				
			}
			else
			{
				vector_t newVelocity = bisectorVelocity(leftFront.direction, rightFront.direction, _normalToEdge(leftFront.direction), _normalToEdge(rightFront.direction));
				
				
				PSSimpleSpoke* newSpoke = [[PSSimpleSpoke alloc] init];
				newSpoke.sourceVertex = newVertex;
				newSpoke.start = event.time;
				newSpoke.velocity = newVelocity;
				
				
				leftFront.rightSpoke = newSpoke;
				rightFront.leftSpoke = newSpoke;
				newSpoke.leftWaveFront = leftFront;
				newSpoke.rightWaveFront	= rightFront;
				
				[changedWaveFronts addObject: waveFront];
				[changedWaveFronts addObject: leftFront];
				[changedWaveFronts addObject: rightFront];
				
				[activeWaveFronts removeObject: waveFront];
				[changedWaveFronts addObject: waveFront];

				[self terminateWaveFront: waveFront];
				
				_assertWaveFrontConsistent(leftFront);
				_assertWaveFrontConsistent(rightFront);
				
				
				if (!leftSpoke.convex)
				{
					id spoke = leftSpoke;
					if ([spoke motorcycle].spoke.upcomingEvent)
					{
						[events removeObject: [spoke motorcycle].spoke.upcomingEvent];
					}
				}
				if (!rightSpoke.convex)
				{
					id spoke = rightSpoke;
					if ([spoke motorcycle].spoke.upcomingEvent)
					{
						[events removeObject: [spoke motorcycle].spoke.upcomingEvent];
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
			[eventLog addObject: [NSString stringWithFormat: @"%f: splitting wavefront anti-spoke %@", firstEvent.time, event.antiSpoke]];
			
			PSAntiSpoke* antiSpoke = event.antiSpoke;
			PSMotorcycleSpoke* motorcycleSpoke = antiSpoke.motorcycleSpoke;
			
			_assertSpokeConsistent(antiSpoke);
			_assertSpokeConsistent(motorcycleSpoke);
			
			_assertWaveFrontConsistent(antiSpoke.leftWaveFront);
			_assertWaveFrontConsistent(antiSpoke.rightWaveFront);
			_assertWaveFrontConsistent(motorcycleSpoke.leftWaveFront);
			_assertWaveFrontConsistent(motorcycleSpoke.rightWaveFront);
			
			PSVertex* newVertex = [[PSVertex alloc] init];
			newVertex.time = event.time;
			newVertex.position = v3Add(antiSpoke.sourceVertex.position, v3MulScalar(antiSpoke.velocity, event.time - antiSpoke.start));
			[collapsedVertices addObject: newVertex];
			
			antiSpoke.terminalVertex = newVertex;
			motorcycleSpoke.terminalVertex = newVertex;
			[terminatedSpokes addObject: antiSpoke];
			[terminatedSpokes addObject: motorcycleSpoke];
			
			if (_waveFrontsAreAntiParallel(antiSpoke.leftWaveFront, motorcycleSpoke.rightWaveFront))
			{

				PSWaveFront* leftFront = antiSpoke.leftWaveFront;
				PSWaveFront* rightFront = motorcycleSpoke.rightWaveFront;
				
				vector_t newDirection = v3MulScalar(v3Add(vNegate(_normalToEdge(leftFront.direction)), _normalToEdge(rightFront.direction)), 0.5);
				
				[eventLog addObject: [NSString stringWithFormat: @"  creating fast spoke to %.3f, %.3f", newDirection.farr[0], newDirection.farr[1]]];
				PSFastSpoke* newSpoke = [[PSFastSpoke alloc] init];
				newSpoke.sourceVertex = newVertex;
				newSpoke.start = event.time;
				newSpoke.direction = newDirection;
				
				
				leftFront.rightSpoke = newSpoke;
				rightFront.leftSpoke = newSpoke;
				newSpoke.leftWaveFront = leftFront;
				newSpoke.rightWaveFront	= rightFront;
				
				[changedWaveFronts addObject: leftFront];
				[changedWaveFronts addObject: rightFront];
				
			}
			else
			{
				PSSimpleSpoke* newSpoke = [[PSSimpleSpoke alloc] init];
				newSpoke.sourceVertex = newVertex;
				[newVertex addSpoke: newSpoke];
				newSpoke.start = event.time;
				newSpoke.leftWaveFront = antiSpoke.leftWaveFront;
				newSpoke.rightWaveFront = motorcycleSpoke.rightWaveFront;
				
				vector_t newVelocity = bisectorVelocity(newSpoke.leftWaveFront.direction, newSpoke.rightWaveFront.direction, _normalToEdge(newSpoke.leftWaveFront.direction), _normalToEdge(newSpoke.rightWaveFront.direction));
				newSpoke.velocity = newVelocity;
				
				newSpoke.leftWaveFront.rightSpoke = newSpoke;
				newSpoke.rightWaveFront.leftSpoke = newSpoke;
				
				_assertWaveFrontConsistent(newSpoke.leftWaveFront);
				_assertWaveFrontConsistent(newSpoke.rightWaveFront);
				
				[changedWaveFronts addObject: newSpoke.leftWaveFront];
				[changedWaveFronts addObject: newSpoke.rightWaveFront];
				
			}
			
			if (_waveFrontsAreAntiParallel(antiSpoke.rightWaveFront, motorcycleSpoke.leftWaveFront))
			{
				PSWaveFront* leftFront = motorcycleSpoke.leftWaveFront;
				PSWaveFront* rightFront = antiSpoke.rightWaveFront;
				
				vector_t newDirection = v3MulScalar(v3Add(vNegate(_normalToEdge(leftFront.direction)), _normalToEdge(rightFront.direction)), 0.5);
				
				[eventLog addObject: [NSString stringWithFormat: @"  creating fast spoke to %.3f, %.3f", newDirection.farr[0], newDirection.farr[1]]];
				PSFastSpoke* newSpoke = [[PSFastSpoke alloc] init];
				newSpoke.sourceVertex = newVertex;
				newSpoke.start = event.time;
				newSpoke.direction = newDirection;
				
				
				leftFront.rightSpoke = newSpoke;
				rightFront.leftSpoke = newSpoke;
				newSpoke.leftWaveFront = leftFront;
				newSpoke.rightWaveFront	= rightFront;
				
				[changedWaveFronts addObject: leftFront];
				[changedWaveFronts addObject: rightFront];
			}
			else
			{
				PSSimpleSpoke* newSpoke = [[PSSimpleSpoke alloc] init];
				newSpoke.sourceVertex = newVertex;
				[newVertex addSpoke: newSpoke];
				newSpoke.start = event.time;
				newSpoke.leftWaveFront = motorcycleSpoke.leftWaveFront;
				newSpoke.rightWaveFront = antiSpoke.rightWaveFront;
				
				vector_t newVelocity = bisectorVelocity(newSpoke.leftWaveFront.direction, newSpoke.rightWaveFront.direction, _normalToEdge(newSpoke.leftWaveFront.direction), _normalToEdge(newSpoke.rightWaveFront.direction));
				newSpoke.velocity = newVelocity;

				newSpoke.leftWaveFront.rightSpoke = newSpoke;
				newSpoke.rightWaveFront.leftSpoke = newSpoke;
				
				
				_assertWaveFrontConsistent(newSpoke.leftWaveFront);
				_assertWaveFrontConsistent(newSpoke.rightWaveFront);
				
				[changedWaveFronts addObject: newSpoke.leftWaveFront];
				[changedWaveFronts addObject: newSpoke.rightWaveFront];
				
			}

		}
		else if ([firstEvent isKindOfClass: [PSBranchEvent class]])
		{
#pragma mark Branch Event Handling
			// TODO: debug branch
			PSBranchEvent* event = (id) firstEvent;
			[eventLog addObject: [NSString stringWithFormat: @"%f: branchinng %@", firstEvent.time, event.rootSpoke]];
			// a branch simply inserts a new spoke+wavefront into the list, in the same direction as its parent
			
			assert(event.rootSpoke);
			assert(event.rootSpoke.rightWaveFront);
			assert(event.rootSpoke.leftWaveFront);
			
			_assertSpokeConsistent(event.rootSpoke);
			//_assertWaveFrontConsistent(event.rootSpoke.leftWaveFront);
			//_assertWaveFrontConsistent(event.rootSpoke.rightWaveFront);
			
			// FIXME: won't handle insertion of multiple branches right
			assert(event.branchVertex.incomingMotorcycles.count < 3);
			for (PSMotorcycle* motorcycle in event.branchVertex.incomingMotorcycles)
			{
				if (motorcycle.terminalVertex != event.branchVertex)
					continue;
				
				PSWaveFront* newFront = [[PSWaveFront alloc] init];
				PSAntiSpoke* newSpoke = motorcycle.antiSpoke;
				PSSimpleSpoke* rootSpoke = event.rootSpoke;
				
				PSWaveFront* leftFront = rootSpoke.leftWaveFront;
				PSWaveFront* rightFront = rootSpoke.rightWaveFront;
				
				assert(newSpoke.sourceVertex == event.branchVertex);
				
				//double asinAlpha = vCross(event.rootSpoke.velocity, vNegate(motorcycle.velocity)).farr[2];
				double asinAlpha = vCross(rootSpoke.velocity, motorcycle.velocity).farr[2];
				
				if (asinAlpha > 0.0) // alpha > 0 == to the right
				{
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
				
				NSArray* motorcycleEvents = [self computeEventsForMotorcycle: motorcycle];
				
				motorcycleEvents = [motorcycleEvents select: ^BOOL(PSEvent* obj) {
					if (obj.class == event.class)
						return obj.time > firstEvent.time;
					else
						return obj.time >= firstEvent.time;
				}];
				
				
				if (motorcycleEvents.count)
				{
					motorcycle.spoke.upcomingEvent = [motorcycleEvents objectAtIndex: 0];
					[events addObject: motorcycle.spoke.upcomingEvent];
				}
			}
			
		}
		else if ([firstEvent isKindOfClass: [PSMergeEvent class]])
		{
#pragma mark Merge Event Handling
			[eventLog addObject: [NSString stringWithFormat: @"%f: merging", firstEvent.time]];
			
			PSMergeEvent* event = (id) firstEvent;

			PSMergeVertex* mergeVertex = event.mergeVertex;
			
			PSMotorcycleSpoke* outCycleSpoke = nil;
			
			if (mergeVertex.outgoingMotorcycles.count == 1)
			{
				PSMotorcycle* motorcycle = [mergeVertex.outgoingMotorcycles lastObject];
				PSMotorcycleSpoke* cycleSpoke = motorcycle.spoke;
				assert(cycleSpoke);
				outCycleSpoke = cycleSpoke;
				
			}
			
			NSArray* incomingCycles = mergeVertex.incomingMotorcycles;
			
			incomingCycles = [incomingCycles sortedArrayWithOptions: NSSortStable usingComparator: ^NSComparisonResult(PSMotorcycle* obj0, PSMotorcycle* obj1)
			{
				double a0 = atan2(obj0.velocity.farr[1], obj0.velocity.farr[0]);
				double a1 = atan2(obj1.velocity.farr[1], obj1.velocity.farr[0]);
				
				if (a0 < a1)
					return NSOrderedAscending;
				else if (a0 > a1)
					return NSOrderedDescending;
				else
					return NSOrderedSame;
			}];
			
			for (size_t i = 0; i < incomingCycles.count; ++i)
			{
				PSMotorcycle* mcLeft = [incomingCycles objectAtIndex: i];
				PSMotorcycle* mcRight = [incomingCycles objectAtIndex: (i+1) % incomingCycles.count];
				
				PSMotorcycleSpoke* mcSpokeLeft = mcLeft.spoke;
				PSMotorcycleSpoke* mcSpokeRight = mcRight.spoke;
				
				if (_waveFrontsAreAntiParallel(mcSpokeLeft.leftWaveFront, mcSpokeRight.rightWaveFront))
				{
					PSWaveFront* leftFront = mcSpokeLeft.leftWaveFront;
					PSWaveFront* rightFront = mcSpokeRight.rightWaveFront;
					
					vector_t newDirection = v3MulScalar(v3Add(vNegate(_normalToEdge(leftFront.direction)), _normalToEdge(rightFront.direction)), 0.5);
					
					[eventLog addObject: [NSString stringWithFormat: @"  creating fast spoke to %.3f, %.3f", newDirection.farr[0], newDirection.farr[1]]];
					PSFastSpoke* newSpoke = [[PSFastSpoke alloc] init];
					newSpoke.sourceVertex = mergeVertex;
					newSpoke.start = event.time;
					newSpoke.direction = newDirection;
					
					
					leftFront.rightSpoke = newSpoke;
					rightFront.leftSpoke = newSpoke;
					newSpoke.leftWaveFront = leftFront;
					newSpoke.rightWaveFront	= rightFront;
					
					[changedWaveFronts addObject: leftFront];
					[changedWaveFronts addObject: rightFront];
				}
				else
				{
					PSSimpleSpoke* newSpoke = nil;
					if (outCycleSpoke && (outCycleSpoke.motorcycle.leftParent == mcLeft) && (outCycleSpoke.motorcycle.rightParent == mcRight))
					{
						newSpoke = outCycleSpoke;
					}
					else
					{
						newSpoke = [[PSSimpleSpoke alloc] init];
						newSpoke.sourceVertex = mergeVertex;
						newSpoke.start = event.time;
						
						[mergeVertex addSpoke: newSpoke];
						
						vector_t newVelocity = bisectorVelocity(mcLeft.leftEdge.normal, mcRight.rightEdge.normal, _normalToEdge(mcLeft.leftEdge.normal), _normalToEdge(mcRight.rightEdge.normal));
						
						newSpoke.velocity = newVelocity;
					}
					
					newSpoke.leftWaveFront = mcSpokeLeft.leftWaveFront;
					newSpoke.rightWaveFront = mcSpokeRight.rightWaveFront;
					newSpoke.leftWaveFront.rightSpoke = newSpoke;
					newSpoke.rightWaveFront.leftSpoke = newSpoke;
					
					_assertWaveFrontConsistent(newSpoke.leftWaveFront);
					_assertWaveFrontConsistent(newSpoke.rightWaveFront);

					[changedWaveFronts addObject: newSpoke.leftWaveFront];
					[changedWaveFronts addObject: newSpoke.rightWaveFront];

				}
				
				
			}
			
			for (PSMotorcycle* motorcycle in incomingCycles)
			{
				motorcycle.spoke.terminalVertex = mergeVertex;
				[terminatedSpokes addObject: motorcycle.spoke];
			}
			
			
		}
		else if ([firstEvent isKindOfClass: [PSReverseMergeEvent class]])
		{
#pragma mark Reverse Merge Event Handling
			[eventLog addObject: [NSString stringWithFormat: @"%f: tsunami merge", firstEvent.time]];
			
			PSReverseMergeEvent* event = (id) firstEvent;
			assert([event.rootSpoke isKindOfClass: [PSAntiSpoke class]]);
			
			PSAntiSpoke* reverseSpoke = event.rootSpoke;
			PSMergeVertex* vertex = (id) reverseSpoke.motorcycle.sourceVertex;
			
			if (vertex.forwardEvent)
				[events removeObject: vertex.forwardEvent];
			
			assert(vertex.incomingMotorcycles.count >= 2);
			
			PSWaveFront* leftFront = reverseSpoke.leftWaveFront;
			PSWaveFront* rightFront = reverseSpoke.rightWaveFront;
			
			NSArray* mergedMotorcycles = [vertex mergedMotorcyclesCCW];
			
			assert(mergedMotorcycles.count > 1);
			
			
			PSSimpleSpoke* newSpoke = nil;
			
			if (!v3Equal(leftFront.direction, rightFront.direction))
			{
				// ok, so we need a new central spoke. First to check if one of the motorcycles already matches that direction
				PSMotorcycle* cycle = nil;
				for (PSMotorcycle* mc in mergedMotorcycles)
				{
					if (vEqualWithin3D(vSetLength(mc.velocity, -1.0), vSetLength(reverseSpoke.velocity, 1.0), FLT_EPSILON))
					{
						cycle = mc;
					}
				}
				
				if (cycle)
				{
					newSpoke = cycle.antiSpoke;
					newSpoke.velocity = reverseSpoke.velocity;
					newSpoke.start = event.time;
				}
				else
				{
					newSpoke = [[PSSimpleSpoke alloc] init];
					[vertex addSpoke: newSpoke];
					newSpoke.sourceVertex = vertex;
					newSpoke.velocity = reverseSpoke.velocity;
					newSpoke.start = event.time;
				}
				assert(vLength(newSpoke.velocity) > 0.0);
			}
			
			_assertWaveFrontConsistent(leftFront);
			_assertWaveFrontConsistent(rightFront);
			
			[changedWaveFronts addObject: leftFront];
			[changedWaveFronts addObject: rightFront];
			
			NSMutableArray* adjustedSpokes = [NSMutableArray arrayWithCapacity: mergedMotorcycles.count];
			
			for (PSMotorcycle* motorcycle in mergedMotorcycles)
			{
				PSAntiSpoke* antiSpoke = motorcycle.antiSpoke;
				[adjustedSpokes addObject: antiSpoke];
				vector_t direction = vZero();
				if (newSpoke)
				{
					double angle = vAngleBetweenVectors2D(newSpoke.velocity, vNegate(motorcycle.velocity));
					if (angle > 0.0)
						direction = leftFront.direction;
					else
						direction = rightFront.direction;
				}
				else
					direction = leftFront.direction;
				
				assert(vLength(direction) > 0.0);
				
				antiSpoke.velocity = vReverseProject(direction, antiSpoke.motorcycle.velocity);
				antiSpoke.start = event.time;
				
				if (motorcycle.spoke.upcomingEvent)
					[events removeObject: motorcycle.spoke.upcomingEvent];
			}

			
			for (int i = 0; i+1 < mergedMotorcycles.count; ++i)
			{
				PSAntiSpoke* rightSpoke = [[mergedMotorcycles objectAtIndex: i] antiSpoke];
				PSAntiSpoke* leftSpoke = [[mergedMotorcycles objectAtIndex: i+1] antiSpoke];
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
				if (i+1 == mergedMotorcycles.count-1)
				{
					leftSpoke.leftWaveFront = leftFront;
					leftFront.rightSpoke = leftSpoke;
				}
				
				
				if (newSpoke)
				{
					double angle = vAngleBetweenVectors2D(newSpoke.velocity, leftSpoke.velocity);
					if (angle > 0.0)
						newFront.direction = leftFront.direction;
					else
						newFront.direction = rightFront.direction;
					
				}
				else // else both directions are the same, so just pick one
					newFront.direction = leftFront.direction;
				
				_assertWaveFrontConsistent(newFront);
				[changedWaveFronts addObject: newFront];
				[activeWaveFronts addObject: newFront];
			}
			
			for (PSMotorcycle* motorcycle in mergedMotorcycles)
			{
				assert(motorcycle.antiSpoke.leftWaveFront);
				assert(motorcycle.antiSpoke.rightWaveFront);

				NSArray* motorcycleEvents = [self computeEventsForMotorcycle: motorcycle];
				
				motorcycleEvents = [motorcycleEvents select: ^BOOL(PSEvent* obj) {
					if (obj.class == event.class)
						return obj.time > firstEvent.time;
					else
						return obj.time >= firstEvent.time;
				}];
				
				
				if (motorcycleEvents.count)
				{
					motorcycle.spoke.upcomingEvent = [motorcycleEvents objectAtIndex: 0];
					[events addObject: motorcycle.spoke.upcomingEvent];
				}
			}
			
			if (newSpoke && ![newSpoke isKindOfClass: [PSAntiSpoke class]])
			{
				// if we're backpropagating a corner, we have an extra spoke to stow
				
				PSAntiSpoke* leftSpoke = nil;
				PSAntiSpoke* rightSpoke = nil;
				{
					NSEnumerator* rightEnum = [mergedMotorcycles objectEnumerator];
					PSAntiSpoke* spk = nil;
					while ((spk = [[rightEnum nextObject] antiSpoke]))
					{
						double angle = vAngleBetweenVectors2D(newSpoke.velocity, rightSpoke.velocity);
						if (angle < 0.0)
							rightSpoke = spk;
						else
							break;
					}
				}
				{
					NSEnumerator* leftEnum = [mergedMotorcycles reverseObjectEnumerator];
					PSAntiSpoke* spk = nil;
					while ((spk = [[leftEnum nextObject] antiSpoke]))
					{
						double angle = vAngleBetweenVectors2D(newSpoke.velocity, rightSpoke.velocity);
						if (angle > 0.0)
							leftSpoke = spk;
						else
							break;
					}
				}
				
				assert(leftSpoke);
				assert(rightSpoke);
				
				PSWaveFront* newRightFront = [[PSWaveFront alloc] init];
				newRightFront.direction = rightFront.direction;
				newRightFront.rightSpoke = rightSpoke;
				rightSpoke.leftWaveFront = newRightFront;
				
				PSWaveFront* newLeftFront = leftSpoke.rightWaveFront;
				assert(newLeftFront);
				
				newSpoke.leftWaveFront = newLeftFront;
				newSpoke.rightWaveFront = newRightFront;
				newLeftFront.rightSpoke = newSpoke;
				newRightFront.leftSpoke = newSpoke;
				
				
				_assertWaveFrontConsistent(newRightFront);
				[changedWaveFronts addObject: newRightFront];
				[activeWaveFronts addObject: newRightFront];
				
				
			}
			
			
			_assertWaveFrontConsistent(leftFront);
			_assertWaveFrontConsistent(rightFront);
			
			reverseSpoke.terminalVertex = vertex;
			[terminatedSpokes addObject: event.rootSpoke];
			
			
		}
		else if ([firstEvent isKindOfClass: [PSReverseBranchEvent class]])
		{
#pragma mark Reverse Branch Event Handling
			[eventLog addObject: [NSString stringWithFormat: @"%f: tsunami branch", firstEvent.time]];

			PSReverseBranchEvent* event = (id) firstEvent;
			assert([event.rootSpoke isKindOfClass: [PSAntiSpoke class]]);
			
			PSAntiSpoke* reverseSpoke = event.rootSpoke;
			PSCrashVertex* vertex = (id) event.branchVertex;
			
			if (vertex.forwardEvent)
				[events removeObject: vertex.forwardEvent];
			
			PSWaveFront* leftFront = reverseSpoke.leftWaveFront;
			PSWaveFront* rightFront = reverseSpoke.rightWaveFront;
			
			NSArray* incomingMotorcycles = [vertex incomingMotorcyclesCCW];
			
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

				if (motorcycle.spoke.upcomingEvent)
					[events removeObject: motorcycle.spoke.upcomingEvent];

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
				
				for (PSMotorcycle* motorcycle in incomingMotorcycles)
				{
					assert(motorcycle.antiSpoke.leftWaveFront);
					assert(motorcycle.antiSpoke.rightWaveFront);
					_assertWaveFrontConsistent(motorcycle.antiSpoke.leftWaveFront);
					_assertWaveFrontConsistent(motorcycle.antiSpoke.rightWaveFront);

					
					NSArray* motorcycleEvents = [self computeEventsForMotorcycle: motorcycle];
					
					motorcycleEvents = [motorcycleEvents select: ^BOOL(PSEvent* obj) {
						if (obj.class == event.class)
							return obj.time > firstEvent.time;
						else
							return obj.time >= firstEvent.time;
					}];
					
					
					if (motorcycleEvents.count)
					{
						motorcycle.spoke.upcomingEvent = [motorcycleEvents objectAtIndex: 0];
						[events addObject: motorcycle.spoke.upcomingEvent];
					}
				}

			}
			
			_assertWaveFrontConsistent(leftFront);
			_assertWaveFrontConsistent(rightFront);

		}
		else
			assert(0); // oops, handle other event types
		
		
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
	
	
	
	double time = antiSpoke.start + vLength(v3Sub(motorcycle.terminalVertex.position, crashVertex.position))/vLength(antiSpoke.velocity);
	
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






