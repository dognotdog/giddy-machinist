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
	NSArray* traceCrashVertices;
	NSArray* mergeCrashVertices;
	NSArray* edges;
	
	NSArray* terminatedMotorcycles;
	
	NSMutableArray* outlineMeshes;
	NSArray* emissionTimes;
}

@synthesize extensionLimit, mergeThreshold;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	extensionLimit = 500.0;
	mergeThreshold = 0.001;
	
	vertices = [NSArray array];
	originalVertices = [NSArray array];
	splitVertices = [NSArray array];
	traceCrashVertices = [NSArray array];
	mergeCrashVertices = [NSArray array];
	edges = [NSArray array];
	terminatedMotorcycles = [NSArray array];
	
	outlineMeshes = [NSMutableArray array];
	
	emissionTimes = @[@1.0, @2.0, @5.0, @10.0, @20.0, @50.0];

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
		PSVertex* vertex = [[PSVertex alloc] init];
		vertex.position = vv[i];
		[newVertices addObject: vertex];
	}
	for (long i = 0; i < vcount; ++i)
	{
		PSSourceEdge* edge = [[PSSourceEdge alloc] init];
		edge.startVertex = [newVertices objectAtIndex: i];
		edge.endVertex = [newVertices objectAtIndex: (i+1) % vcount];
		[edge.startVertex addEdge: edge];
		[edge.endVertex addEdge: edge];
		vector_t a = edge.startVertex.position;
		vector_t b = edge.endVertex.position;
		vector_t e = v3Sub(b, a);
		edge.normal = _edgeToNormal(e);
		edge.edge = e;

		assert(vLength(e) >= mergeThreshold);
		
		[newEdges addObject: edge];
	}
	for (long i = 0; i < vcount; ++i)
	{
		PSSourceEdge* edge0 = [newEdges objectAtIndex: i];
		PSSourceEdge* edge1 = [newEdges objectAtIndex: (i+1) % vcount];
		
		edge0.next = edge1;
		edge1.prev = edge0;
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
	
	vector_t s = vCreateDir(0.0, 0.0, 0.0);
	
	
	if (fabs(vx) < 1.0*sqrt(FLT_EPSILON))// nearly parallel, threshold is a guess
	{
		s = v3MulScalar(v3Add(v0, v1), 0.5);
		//NSLog(@"nearly parallel %g, %g / %g, %g", v0.x, v0.y, v1.x, v1.y);
	}
	else
	{
		s = v3Add(vReverseProject(v0, e1), vReverseProject(v1, e0));
	}
	
	return s;
	
}

- (NSArray*) crashMotorcycles: (NSArray*) motorcycles
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
					if ((edge.startVertex == cycle.sourceVertex) || (edge.endVertex == cycle.sourceVertex))
						continue;
					
					
					//vector_t delta = v3Sub(motorp, edge.startVertex.position);
					vector_t tx = xRays2D(motorp, motorv, edge.startVertex.position, edge.edge);
					double t = tx.farr[0] + cycle.start;
					
					//assert(vCross(edge.edge, delta).farr[2] >= 0.0);
					
					if ((t > cycle.start) && (t < extensionLimit))
					{
						vector_t x = v3Add(motorp, v3MulScalar(motorv, t - cycle.start));
						
						vector_t ax = v3Sub(x, edge.startVertex.position);
						vector_t bx = v3Sub(x, edge.endVertex.position);
						
						BOOL hitStart = (vDot(ax, ax) < mergeThreshold*mergeThreshold);
						BOOL hitEnd = (vDot(bx, bx) < mergeThreshold*mergeThreshold);
						
						if (hitStart)
						{
							id crash = @[[NSNumber numberWithDouble: t], cycle, edge.startVertex];
							[crashes addObject: crash];
						}
						else if (hitEnd)
						{
							id crash = @[[NSNumber numberWithDouble: t], cycle, edge.endVertex];
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
				
				if ((ta > cycle.start) && (ta < extensionLimit) && (tb > cycle1.start) && (tb < extensionLimit))
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
				
				if ((ta > cycle.start) && (ta < extensionLimit) && (tb > 0.0) && (tb < 1.0) && (ta > tb + cycle1.start) && (cycle1.terminator != cycle))
				{
					double hitTime = ta;
					
					
					id crash = @[[NSNumber numberWithDouble: hitTime], cycle, cycle1, [NSNumber numberWithDouble: tx.farr[0]], [NSNumber numberWithDouble: tx.farr[1]], [NSNumber numberWithBool: NO]];
					[crashes addObject: crash];
				}
				
				
			}
			
			++k;
		}
	}

	return crashes;
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

- (void) splitEdge: (PSEdge*) edge atVertex: (PSSplitVertex*) vertex
{
	PSEdge* newEdge = [[[edge class] alloc] init];
	
	newEdge.startVertex = vertex;
	newEdge.endVertex = edge.endVertex;
	
	newEdge.normal = edge.normal;
	newEdge.edge = v3Sub(newEdge.endVertex.position, newEdge.startVertex.position);
	
	[edge.endVertex removeEdge: edge];
	edge.endVertex = vertex;
	[newEdge.endVertex addEdge: newEdge];
	
	[vertex addEdge: newEdge];
	[vertex addEdge: edge];
	
	edges = [edges arrayByAddingObject: newEdge];
	splitVertices = [splitVertices arrayByAddingObject: vertex];
	
	if ([edge isKindOfClass: [PSSourceEdge class]])
	{
		[(PSSourceEdge*)newEdge setNext: [(PSSourceEdge*)edge next]];
		[(PSSourceEdge*)newEdge setPrev: (PSSourceEdge*)edge];
		[(PSSourceEdge*)edge setNext: (PSSourceEdge*)newEdge];
		[[(PSSourceEdge*)newEdge next] setPrev: (PSSourceEdge*)edge];
	}
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
	
	NSArray* sortedKeys = [angles keysSortedByValueUsingComparator:^NSComparisonResult(id obj0, id obj1) {
		
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
			newCycle.leftNeighbour = cycle1.leftNeighbour;
			newCycle.rightNeighbour = cycle0.rightNeighbour;
			newCycle.leftNormal = cycle1.leftNormal;
			newCycle.rightNormal = cycle0.rightNormal;
			newCycle.velocity = bisectorVelocity(newCycle.leftNormal, newCycle.rightNormal, _normalToEdge(newCycle.leftNormal), _normalToEdge(newCycle.rightNormal));
			
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
	
	
	// start by generating the initial motorcycles
	NSMutableArray* motorcycles = [NSMutableArray array];
	
	for (PSSourceEdge* edge0 in edges)
	{
		PSSourceEdge* edge1 = edge0.next;
		assert(edge0.next);
		
		vector_t v = bisectorVelocity(edge0.normal, edge1.normal, edge0.edge, edge1.edge);
		double area = vCross(edge0.edge, edge1.edge).farr[2];
		
		if (area < 0.0)
		{
			PSMotorcycle* cycle = [[PSMotorcycle alloc] init];
			cycle.sourceVertex = edge0.endVertex;
			cycle.start = 0.0;
			cycle.velocity = v;
			cycle.leftNormal = edge0.normal;
			cycle.rightNormal = edge1.normal;
			
			[motorcycles addObject: cycle];
			[edge0.endVertex addMotorcycle: cycle];
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
	NSArray* crashes = [self crashMotorcycles: motorcycles];
	
	
	while ([crashes count])
	{
		@autoreleasepool {
			crashes = [crashes sortedArrayUsingComparator: ^NSComparisonResult(NSArray* e0, NSArray* e1) {
				double t0 = [[e0 objectAtIndex: 0] doubleValue], t1 = [[e1 objectAtIndex: 0] doubleValue];
				if (t0 < t1)
					return 1; // sort in descending order
				else if (t0 > t1)
					return -1;
				else
					return 0;
			}];

			double tmin = [[[crashes lastObject] objectAtIndex: 0] doubleValue];
			crashes = [crashes select:^BOOL(NSArray* obj) {
				return [[obj objectAtIndex: 0] doubleValue] < tmin + mergeThreshold;
			}];
			
			if (!crashes.count)
				break;
			
			NSArray* initialCrashInfo = [crashes lastObject];
			crashes = [crashes arrayByRemovingLastObject];
			
			NSMutableArray* simultaneousCrashes = [NSMutableArray arrayWithObject: initialCrashInfo];
			
			for (NSArray* crashInfo in [crashes reverseObjectEnumerator])
			{
				vector_t xa = _crashLocation(initialCrashInfo);
				vector_t xb = _crashLocation(crashInfo);
				
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
						vertex = [[PSSplitVertex alloc] init];
						vertex.position = x;
						vertices = [vertices arrayByAddingObject: vertex];
						
						PSEdge* edge = [crashWalls anyObject];
						
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
					
					assert(survivor);
					[crashedCycles removeObject: survivor];
					
					
					[eventLog addObject: [NSString stringWithFormat: @"  survivor towards: %f, %f", survivor.velocity.farr[0], survivor.velocity.farr[1]]];
					
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

					[motorcycles removeObjectsInArray: [crashedCycles allObjects]];
					terminatedMotorcycles = [terminatedMotorcycles arrayByAddingObjectsFromArray: [crashedCycles allObjects]];
					
				}
				else if (mergeCrash)
				{				
					PSMergeVertex* vertex = [[PSMergeVertex alloc] init];
					vertex.position = x;
					vertex.time = tmin;
					vertices = [vertices arrayByAddingObject: vertex];

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
			
			
			
			
			
			crashes = [self crashMotorcycles: motorcycles];
		}
	}
	
	// we shouldn't have any motorcycles left at this point. But if we do, we want to see them
	
	for (PSMotorcycle* cycle in motorcycles)
	{
		PSVertex* vertex = [[PSVertex alloc] init];
		vertex.position = v3Add(cycle.sourceVertex.position, v3MulScalar(cycle.velocity, extensionLimit*2.0-cycle.start));
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

static BOOL _spokesSameDir(PSSpoke* spoke0, PSSpoke* spoke1)
{
	vector_t v0 = spoke0.velocity;
	vector_t v1 = spoke1.velocity;
	
	return (fabs(atan2(vCross(v0, v1).farr[2], vDot(v0, v1))) <= FLT_EPSILON);
	
}

static BOOL _isSpokeUnique(PSSpoke* uspoke, NSArray* spokes)
{
	for (PSSpoke * spoke in spokes)
	{
		if (_spokesSameDir(spoke, uspoke))
			return NO;
	}
	return YES;
}


static void _assertSpokeUnique(PSSpoke* uspoke, NSArray* spokes)
{
	assert(_isSpokeUnique(uspoke, spokes));
}

static void _generateAntiSpokes(PSVertex* vertex, NSMutableArray* spokes)
{
	NSArray* vedges = vertex.edges;
	
	assert(vedges.count == 2);
	
	PSSourceEdge* edge0 = vertex.prevEdge;
	PSSourceEdge* edge1 = vertex.nextEdge;
	assert(edge0.endVertex == vertex);
	assert(edge1.startVertex == vertex);
	
	
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

static void _generateCycleSpokes(PSVertex* vertex, NSMutableArray* spokes)
{
	for (PSMotorcycle* cycle in vertex.outgoingMotorcycles)
	{
		PSMotorcycleSpoke* spoke = [[PSMotorcycleSpoke alloc] init];
		spoke.sourceVertex = vertex;
		spoke.motorcycle = cycle;
		spoke.antiSpoke = cycle.antiSpoke;
		if (spoke.antiSpoke)
			spoke.antiSpoke.motorcycleSpoke = spoke;
		spoke.velocity = cycle.velocity;
		assert(!vIsNAN(spoke.velocity));
		spoke.start = vertex.time;
		
		[spokes addObject: spoke];
		_assertSpokeUnique(spoke, vertex.outgoingSpokes);
		[vertex addSpoke: spoke];
	}

}


- (PSCollapseEvent*) computeCollapseEvent: (PSWaveFront*) waveFront
{
	assert(waveFront.leftSpoke);
	assert(waveFront.rightSpoke);
	assert(waveFront.leftSpoke.sourceVertex);
	assert(waveFront.rightSpoke.sourceVertex);
	vector_t v0 = waveFront.leftSpoke.velocity;
	vector_t v1 = waveFront.rightSpoke.velocity;
	
	vector_t p0 = waveFront.leftSpoke.sourceVertex.position;
	vector_t p1 = waveFront.rightSpoke.sourceVertex.position;
	
	double t0 = waveFront.leftSpoke.sourceVertex.time;
	double t1 = waveFront.rightSpoke.sourceVertex.time;
	
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
		vector_t v0 = v3Add(waveFront.leftSpoke.sourceVertex.position, v3MulScalar(waveFront.leftSpoke.velocity, time - waveFront.leftSpoke.start));
		vector_t v1 = v3Add(waveFront.rightSpoke.sourceVertex.position, v3MulScalar(waveFront.rightSpoke.velocity, time - waveFront.rightSpoke.start));
		
		v0.farr[3] = 1.0;
		v1.farr[3] = 1.0;
		
		assert(vIsNormal(v0));
		assert(vIsNormal(v1));
		
		vs[k++] = v0;
		vs[k++] = v1;
	}
	
	assert(k == numVertices);
	
	[mesh addVertices: vs count: numVertices];
	[mesh addColors: colors count: numVertices];
	[mesh addDrawArrayIndices: indices count: numVertices withMode: GL_LINES];
	
	
	free(vs);
	free(colors);
	free(indices);
	
	assert(outlineMeshes);
	
	[outlineMeshes addObject: mesh];
	
}

static BOOL _waveFrontsAreAntiParallel(PSWaveFront* leftFront, PSWaveFront* rightFront)
{
	double lrdot = vDot(leftFront.direction, rightFront.direction);
	double lrcross = vCross(leftFront.direction, rightFront.direction).farr[2];
	
	return ((fabs(lrdot + 1.0) < FLT_EPSILON) && (fabs(lrcross) < FLT_EPSILON)); // test for anti-parallel faces

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
	NSMutableArray* edgeAntiSpokes = [NSMutableArray array];
	NSMutableArray* traceAntiSpokes = [NSMutableArray array];
	NSMutableArray* mergeAntiSpokes = [NSMutableArray array];
	NSMutableArray* startingSpokes = [NSMutableArray array];

	
	/*
	 normal vertices emit motorcycle and normal spokes, and they might also emit anti-spokes
	 */
	for (PSVertex* vertex in originalVertices)
	{
		@autoreleasepool {
			NSMutableArray* newCycleSpokes = [NSMutableArray array];
			NSMutableArray* newAntiSpokes = [NSMutableArray array];
			
			_generateCycleSpokes(vertex, newCycleSpokes);
			_generateAntiSpokes(vertex, newAntiSpokes);
			
			[startingSpokes addObjectsFromArray: newCycleSpokes];
			[startingSpokes addObjectsFromArray: newAntiSpokes];
			[motorcycleSpokes addObjectsFromArray: newCycleSpokes];
			[edgeAntiSpokes addObjectsFromArray: newAntiSpokes];
			
			NSArray* vedges = vertex.edges;
			
			assert(vedges.count == 2);
			
			PSSourceEdge* edge0 = vertex.prevEdge;
			PSSourceEdge* edge1 = vertex.nextEdge;
			assert(edge0.endVertex == vertex);
			assert(edge1.startVertex == vertex);
		
			vector_t v = bisectorVelocity(edge0.normal, edge1.normal, edge0.edge, edge1.edge);
			double area = vCross(edge0.edge, edge1.edge).farr[2];

			if (area >= 0.0)
			{
				PSSpoke* spoke = [[PSSpoke alloc] init];
				spoke.sourceVertex = vertex;
				spoke.velocity = v;
				assert(!vIsNAN(spoke.velocity));

				BOOL spokeExists = NO;
				
				for (PSSpoke* vspoke in vertex.outgoingSpokes)
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
	 split vertices only generate anti-spokes
	 */
	for (PSSplitVertex* vertex in splitVertices)
	{
		NSMutableArray* newAntiSpokes = [NSMutableArray array];
		_generateAntiSpokes(vertex, newAntiSpokes);
		
		[edgeAntiSpokes addObjectsFromArray: newAntiSpokes];
		[startingSpokes addObjectsFromArray: newAntiSpokes];
	}
	
	/*
	 merge crash vertices emit anti-spokes
	 */
	for (PSCrashVertex* vertex in mergeCrashVertices)
	{
		_generateAntiSpokes(vertex, mergeAntiSpokes);
	}

	for (PSCrashVertex* vertex in traceCrashVertices)
	{
		_generateAntiSpokes(vertex, traceAntiSpokes);
	}
	
	
	/*
	 spokes are setup, time to generate wavefronts
	 */
	
	NSMutableArray* activeWaveFronts = [NSMutableArray array];
	
	
	NSMutableArray* eventLog = [NSMutableArray array];

	for (PSSpoke* leftSpoke in startingSpokes)
	{
		@autoreleasepool {
			
			PSVertex* sourceVertex = leftSpoke.sourceVertex;
			
			PSSpoke* rightSpoke = [sourceVertex nextSpokeClockwiseFrom: leftSpoke.velocity to: sourceVertex.nextEdge.edge];
			
			if (!rightSpoke)
			{
				PSVertex* nextVertex = sourceVertex.nextEdge.endVertex;
				assert(nextVertex);
				rightSpoke = [nextVertex nextSpokeClockwiseFrom: vNegate(sourceVertex.nextEdge.edge) to: nextVertex.nextEdge.edge];
				assert(rightSpoke);
			}
			assert(rightSpoke);
			
			assert(!leftSpoke.rightWaveFront);
			assert(!rightSpoke.leftWaveFront);
			
			PSWaveFront* waveFront = [[PSWaveFront alloc] init];
			waveFront.leftSpoke = leftSpoke;
			waveFront.rightSpoke = rightSpoke;
			waveFront.direction = leftSpoke.sourceVertex.nextEdge.normal;
			
			leftSpoke.rightWaveFront = waveFront;
			rightSpoke.leftWaveFront = waveFront;
			
			assert(waveFront.leftSpoke != waveFront.rightSpoke);
						
			[activeWaveFronts addObject: waveFront];
		}
	}
	
	// now we have the collapsing wavefronts, plus the motorcycle induced splits
	// the splits are just potential at this point, as a collapsing wavefront along an anti-spoke means the anti-spoke may change speed.

	// generate events
	
	NSMutableArray* events = [NSMutableArray array];
	
	for (NSNumber* timeval in emissionTimes)
	{
		PSEmitEvent* event = [[PSEmitEvent alloc] init];
		event.time = [timeval doubleValue];
		
		[events addObject: event];
	}
	
	
	for (PSWaveFront* waveFront in activeWaveFronts)
	{
		PSCollapseEvent* event = [self computeCollapseEvent: waveFront];
		
		waveFront.collapseEvent = event;

		[events addObject: event];
		
	}
	
	
	for (PSCrashVertex* vertex in traceCrashVertices)
	{
		PSBranchEvent* event = [[PSBranchEvent alloc] init];
		event.time = vertex.time;
		event.location = vertex.position;
		event.branchVertex = vertex;
		
		[events addObject: event];
	}

	for (PSMergeVertex* vertex in mergeCrashVertices)
	{
		PSMergeEvent* event = [[PSMergeEvent alloc] init];
		event.time = vertex.time;
		event.location = vertex.position;
		event.mergeVertex = vertex;
		
		[events addObject: event];
	}
	
	for (PSMotorcycleSpoke* cycleSpoke in motorcycleSpokes)
	{
		PSAntiSpoke* antiSpoke = cycleSpoke.antiSpoke;
		
		vector_t delta = v3Sub(
							   v3Add(cycleSpoke.sourceVertex.position, v3MulScalar(cycleSpoke.velocity, -cycleSpoke.sourceVertex.time)),
							   v3Add(antiSpoke.sourceVertex.position, v3MulScalar(antiSpoke.velocity, -antiSpoke.sourceVertex.time))
							   );
		double distance = vLength(delta);
		
		double v0 = vLength(cycleSpoke.velocity);
		double v1 = vLength(antiSpoke.velocity);
		
		double tc = distance/(v0+v1);
		
		PSSplitEvent* event = [[PSSplitEvent alloc] init];
		event.time = tc;
		event.location = v3Add(cycleSpoke.sourceVertex.position, v3MulScalar(cycleSpoke.velocity, -cycleSpoke.sourceVertex.time));
		
		event.antiSpoke = antiSpoke;
		
		[events addObject: event];
	}
	// prune events that occur after extensionLimit
	
	{
		NSMutableArray* prunedEvents = [NSMutableArray array];
		
		for (PSEvent* event in events)
		{
			if (event.time < extensionLimit)
				[prunedEvents addObject: event];
		}
		
		events = prunedEvents;
	}
	
	
	NSMutableArray* inactiveWaveFronts = [NSMutableArray array];
	NSMutableArray* collapsedVertices = [NSMutableArray array];
	
	double lastEventTime = 0.0;
	
	while (events.count)
	{ @autoreleasepool {

		[events sortUsingComparator: ^NSComparisonResult(PSEvent* obj0, PSEvent* obj1) {
			
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
		
		assert(firstEvent.time >= lastEventTime);
		lastEventTime = firstEvent.time;
		
		/*
		if (0)
		{
			NSMutableArray* simultaneousEvents = [NSMutableArray array];
			
			
			for (PSEvent* event in events)
			{
				if (event.time <= firstEvent.time + mergeThreshold)
				{
					vector_t delta = v3Sub(firstEvent.location, event.location);
					double dd = vDot(delta, delta);
					if (dd < mergeThreshold*mergeThreshold)
						[simultaneousEvents addObject: event];
				}
				else
					break;
			}
			
			BOOL branchEvent = NO;
			BOOL mergeEvent = NO;
			BOOL collapseEvent = NO;
			BOOL splitEvent = NO;
			
			for (id event in simultaneousEvents)
			{
				if ([event isKindOfClass: [PSCollapseEvent class]])
				{
					collapseEvent = YES;
				}
				if ([event isKindOfClass: [PSSplitEvent class]])
				{
					splitEvent = YES;
				}
				if ([event isKindOfClass: [PSBranchEvent class]])
				{
					branchEvent = YES;
				}
				if ([event isKindOfClass: [PSMergeEvent class]])
				{
					mergeEvent = YES;
				}
			}
		}
		*/
		NSMutableArray* changedWaveFronts = [NSMutableArray array];
		
		if ([firstEvent isKindOfClass: [PSCollapseEvent class]])
		{
			PSCollapseEvent* event = (id)firstEvent;
			
			PSWaveFront* waveFront = event.collapsingWaveFront;
			
			PSSpoke* leftSpoke = waveFront.leftSpoke;
			PSSpoke* rightSpoke = waveFront.rightSpoke;
			
			PSWaveFront* leftFront = leftSpoke.leftWaveFront;
			PSWaveFront* rightFront = rightSpoke.rightWaveFront;
			
			[eventLog addObject: [NSString stringWithFormat: @"%.f: collapsing wavefront %@, bounded by %@, %@", event.time, waveFront, waveFront.leftSpoke, waveFront.rightSpoke]];

			if (_waveFrontsAreAntiParallel(leftFront, rightFront)) // test for anti-parallel faces
			{
				[inactiveWaveFronts addObject: leftFront];
				[inactiveWaveFronts addObject: rightFront];
				[activeWaveFronts removeObject: leftFront];
				[activeWaveFronts removeObject: rightFront];

				[changedWaveFronts addObject: waveFront];
				[inactiveWaveFronts addObject: waveFront];
				[activeWaveFronts removeObject: waveFront];
				
			}
			else
			{
				vector_t newVelocity = bisectorVelocity(leftFront.direction, rightFront.direction, _normalToEdge(leftFront.direction), _normalToEdge(rightFront.direction));
				vector_t xPos = v3Add(leftSpoke.sourceVertex.position, v3MulScalar(leftSpoke.velocity, event.time - leftSpoke.start));
				
				PSVertex* newVertex = [[PSVertex alloc] init];
				newVertex.position = xPos;
				newVertex.time = event.time;
				[collapsedVertices addObject: newVertex];
				
				leftSpoke.terminalVertex = newVertex;
				rightSpoke.terminalVertex = newVertex;
				
				PSSpoke* newSpoke = [[PSSpoke alloc] init];
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
				
				[inactiveWaveFronts addObject: waveFront];
				[activeWaveFronts removeObject: waveFront];
				
				
				if ([leftSpoke isKindOfClass: [PSAntiSpoke class]])
				{
					double asinSpoke = vCross(leftSpoke.velocity, newSpoke.velocity).farr[2];
					assert(0); // TODO: finish anti-spoke handling
				}
				else if ([rightSpoke isKindOfClass: [PSAntiSpoke class]])
					assert(0); // TODO: finish anti-spoke handling
				
				
		
			}
		}
		else if ([firstEvent isKindOfClass: [PSEmitEvent class]])
		{
			[self emitOffsetOutlineForWaveFronts: activeWaveFronts atTime: firstEvent.time];
		}
		else if ([firstEvent isKindOfClass: [PSSplitEvent class]])
		{
			[eventLog addObject: [NSString stringWithFormat: @"splitting wavefront @ %f", firstEvent.time]];
			PSSplitEvent* event = (id)firstEvent;
			
			PSAntiSpoke* antiSpoke = event.antiSpoke;
			PSMotorcycleSpoke* motorcycleSpoke = antiSpoke.motorcycleSpoke;
			
			PSVertex* newVertex = [[PSVertex alloc] init];
			newVertex.time = event.time;
			newVertex.position = v3Add(antiSpoke.sourceVertex.position, v3MulScalar(antiSpoke.velocity, event.time - antiSpoke.sourceVertex.time));
			[collapsedVertices addObject: newVertex];
			
			antiSpoke.terminalVertex = newVertex;
			motorcycleSpoke.terminalVertex = newVertex;
			
			if (_waveFrontsAreAntiParallel(antiSpoke.leftWaveFront, motorcycleSpoke.rightWaveFront))
			{
				[inactiveWaveFronts addObject: antiSpoke.leftWaveFront];
				[inactiveWaveFronts addObject: motorcycleSpoke.rightWaveFront];
				[activeWaveFronts removeObject: antiSpoke.leftWaveFront];
				[activeWaveFronts removeObject: motorcycleSpoke.rightWaveFront];
			}
			else
			{
				PSSpoke* newSpoke = [[PSSpoke alloc] init];
				newSpoke.sourceVertex = newVertex;
				newSpoke.start = newVertex.time;
				newSpoke.leftWaveFront = antiSpoke.leftWaveFront;
				newSpoke.rightWaveFront = motorcycleSpoke.rightWaveFront;
				
				newSpoke.leftWaveFront.rightSpoke = newSpoke;
				newSpoke.rightWaveFront.leftSpoke = newSpoke;
				
				[changedWaveFronts addObject: newSpoke.leftWaveFront];
				[changedWaveFronts addObject: newSpoke.rightWaveFront];
				
			}
			
			if (_waveFrontsAreAntiParallel(antiSpoke.rightWaveFront, motorcycleSpoke.leftWaveFront))
			{
				[inactiveWaveFronts addObject: antiSpoke.rightWaveFront];
				[inactiveWaveFronts addObject: motorcycleSpoke.leftWaveFront];
				[activeWaveFronts removeObject: antiSpoke.rightWaveFront];
				[activeWaveFronts removeObject: motorcycleSpoke.leftWaveFront];
				
			}
			else
			{
				PSSpoke* newSpoke = [[PSSpoke alloc] init];
				newSpoke.sourceVertex = newVertex;
				newSpoke.start = newVertex.time;
				newSpoke.leftWaveFront = motorcycleSpoke.leftWaveFront;
				newSpoke.rightWaveFront = antiSpoke.rightWaveFront;
				
				newSpoke.leftWaveFront.rightSpoke = newSpoke;
				newSpoke.rightWaveFront.leftSpoke = newSpoke;
				
				[changedWaveFronts addObject: newSpoke.leftWaveFront];
				[changedWaveFronts addObject: newSpoke.rightWaveFront];
				
			}

		}
		else if ([firstEvent isKindOfClass: [PSBranchEvent class]])
		{
			[eventLog addObject: [NSString stringWithFormat: @"branching @ %f", firstEvent.time]];
			// a branch simply inserts a new spoke+wavefront into the list, in the same direction as its parent
			PSBranchEvent* event = (id) firstEvent;
			
			// left or right?
			// FIXME: won't handle insertion of multiple branches right
			assert(event.branchVertex.incomingMotorcycles.count < 3);
			for (PSMotorcycle* motorcycle in event.branchVertex.incomingMotorcycles)
			{
				if (motorcycle.terminalVertex != event.branchVertex)
					continue;
				
				PSWaveFront* newFront = [[PSWaveFront alloc] init];
				PSSpoke* newSpoke = [[PSSpoke alloc] init];
				
				newSpoke.start = event.time;
				newSpoke.sourceVertex = event.branchVertex;
				
				double asinAlpha = vCross(event.rootSpoke.velocity, vNegate(motorcycle.velocity)).farr[2];
				
				if (asinAlpha < 0.0) // alpha < 0 == to the right
				{
					newFront.direction = event.rootSpoke.rightWaveFront.direction;
					newSpoke.leftWaveFront = newFront;
					newSpoke.rightWaveFront = event.rootSpoke.rightWaveFront;
					
					
					[changedWaveFronts addObject: event.rootSpoke.rightWaveFront];
					
				}
				else // to the left
				{
					newFront.direction = event.rootSpoke.leftWaveFront.direction;
					newSpoke.rightWaveFront = newFront;
					newSpoke.leftWaveFront = event.rootSpoke.leftWaveFront;
					
					[changedWaveFronts addObject: event.rootSpoke.leftWaveFront];
				}
				
				newSpoke.leftWaveFront.rightSpoke = newSpoke;
				newSpoke.rightWaveFront.leftSpoke = newSpoke;
				
				[changedWaveFronts addObject: newFront];
				[activeWaveFronts addObject: newFront];
			}
			
		}
		else if ([firstEvent isKindOfClass: [PSMergeEvent class]])
		{
			[eventLog addObject: [NSString stringWithFormat: @"merging @ %f", firstEvent.time]];
			assert(0); // TODO: handle merge event

			
		}
		else
			assert(0); // TODO: handle other event types
		
		
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
	
	BOOL maybe = NO;
	if (maybe)
		NSLog(@"%@", eventLog);
	
}

- (void) generateSkeleton
{
	[self runMotorcycles];
	[self runSpokes];
}

#if 0
- (void) generateSkeleton2
{
	// start by generating the spokes for each edge
	assert(numEdges == numVertices);
	
	[self generateWalls];
	NSArray* events = [self initializeEvents];
	
	/*
	 need to group events somehow
	 */
	
	
	while ([events count])
	{
		events = [events sortedArrayUsingComparator: ^NSComparisonResult(PSEvent* e0, PSEvent* e1) {
			double t0 = e0.time, t1 = e1.time;
			if (t0 < t1)
				return 1; // sort in descending order
			else if (t0 > t1)
				return -1;
			else
				return 0;
		}];
		
		PSEvent* firstEvent = [events lastObject];
		PSEventGroup* timeGroup = [[PSEventGroup alloc] init];
		
		double tref = firstEvent.time;
		timeGroup.time = tref;
		
		for (PSEvent* event in [events reverseObjectEnumerator])
		{
			if (event.time > tref + mergeThreshold)
				break;
			timeGroup.events = [timeGroup.events arrayByAddingObject: event];
		}
		
		// now have a group of events roughly at the same time
		
		NSArray* eventChains = [self buildEventChains: timeGroup];
		
		eventChains = [self retireInteriorEvents: eventChains];

		
		mergesort(events, numEvents, sizeof(*events), _eventSorter);
		
		ps_event_t event = events[--numEvents];
//		NSLog(@"Skeletizing, %zd events remaining @%f", numEvents, event.time);
		
		if ((event.spoke != NSNotFound) && spokes[event.spoke].active && walls[event.wall].active) // split event
		{
			size_t newSpokeId[2], newWallId[2], newVertexId;
			[self allocateSpokesTo: newSpokeId count: 2];
			[self allocateWallsTo: newWallId count: 2];
			[self allocateVerticesTo: &newVertexId count: 1];
			

			ps_spoke_t* spoke = spokes + event.spoke;
			ps_wall_t* wall0 = walls + spoke->walls[0];
			ps_wall_t* wall1 = walls + spoke->walls[1];
			spoke->active = NO;
			
			ps_wall_t* wall = walls + event.wall;
			wall->active = NO;
			ps_spoke_t* spoke0 = spokes + wall->spokes[0];
			ps_spoke_t* spoke1 = spokes + wall->spokes[1];
			
			vector_t newX = v3Add(vertices[spoke->sourceVertex].position, v3MulScalar(spoke->velocity, event.time - spoke->start));
			assert(!vIsNAN(newX));
		
			vector_t newV0 = bisectorVelocity(wall1->velocity, wall->velocity, edges[wall1->sourceEdge].edge, edges[wall->sourceEdge].edge);
			vector_t newV1 = bisectorVelocity(wall0->velocity, wall->velocity, edges[wall0->sourceEdge].edge, edges[wall->sourceEdge].edge);

			
			
			ps_vertex_t* newVertex = vertices + newVertexId;

			newVertex->position = newX;
			
			ps_spoke_t* newSpoke0 = spokes + newSpokeId[0];
			
			newSpoke0->velocity = newV0;
			newSpoke0->sourceVertex = newVertex->vertexId;
			newSpoke0->walls[0] = newWallId[0];
			newSpoke0->walls[1] = wall1->wallId;
			newSpoke0->active = YES;
			newSpoke0->start = event.time;

			ps_spoke_t* newSpoke1 = spokes + newSpokeId[1];
			
			newSpoke1->velocity = newV1;
			newSpoke1->sourceVertex = newVertex->vertexId;
			newSpoke1->walls[0] = wall0->wallId;
			newSpoke1->walls[1] = newWallId[1];
			newSpoke1->active = YES;
			newSpoke1->start = event.time;
			
			ps_wall_t* newWall0 = walls + newWallId[0];
			newWall0->sourceEdge = wall->sourceEdge;
			newWall0->velocity = wall->velocity;
			newWall0->spokes[0] = wall->spokes[0];
			newWall0->spokes[1] = newSpoke0->spokeId;
			newWall0->active = YES;
			

			ps_wall_t* newWall1 = walls + newWallId[1];
			newWall1->sourceEdge = wall->sourceEdge;
			newWall1->velocity = wall->velocity;
			newWall1->spokes[0] = newSpoke1->spokeId;
			newWall1->spokes[1] = wall->spokes[1];
			newWall1->active = YES;
			
			
			spoke->finalVertex = newVertex->vertexId;
			wall0->spokes[1] = newSpoke1->spokeId;
			wall1->spokes[0] = newSpoke0->spokeId;
			spoke0->walls[1] = newWall0->wallId;
			spoke1->walls[0] = newWall1->wallId;


			[self generateEventsForSplit: *newSpoke0 afterTime: event.time];
			[self generateEventsForSplit: *newSpoke1 afterTime: event.time];
			[self generateEventForWallCollapse: *wall0 afterTime: event.time];
			[self generateEventForWallCollapse: *wall1 afterTime: event.time];
			[self generateEventForWallCollapse: *newWall0 afterTime: event.time];
			[self generateEventForWallCollapse: *newWall1 afterTime: event.time];
 
		}
		else if (walls[event.wall].active) // collapse event
		{
			size_t newSpokeId, newVertexId;
			[self allocateSpokesTo: &newSpokeId count: 1];
			[self allocateVerticesTo: &newVertexId count: 1];
			
			
			ps_wall_t* wall = walls + event.wall;
			ps_spoke_t* spoke0 = spokes + wall->spokes[0];
			ps_spoke_t* spoke1 = spokes + wall->spokes[1];
			ps_vertex_t* vertex0 = vertices + spoke0->sourceVertex;
			ps_vertex_t* vertex1 = vertices + spoke1->sourceVertex;
			wall->active = NO;
			spoke0->active = NO;
			spoke1->active = NO;
		
			ps_wall_t* wall0 = walls  +  spoke0->walls[0];
			ps_wall_t* wall1 = walls  +  spoke1->walls[1];
			
			vector_t newV = bisectorVelocity(wall0->velocity, wall1->velocity, edges[wall0->sourceEdge].edge, edges[wall1->sourceEdge].edge);

			assert(!vIsNAN(newV));
			
			vector_t newX = v3Add(vertex0->position, v3MulScalar(spoke0->velocity, event.time - spoke0->start));

			assert(!vIsNAN(newX));
		
			ps_spoke_t* newSpoke = spokes + newSpokeId;
			
			newSpoke->velocity = newV;
			newSpoke->sourceVertex = newVertexId;
			newSpoke->walls[0] = wall0->wallId;
			newSpoke->walls[1] = wall1->wallId;
			newSpoke->active = YES;
			newSpoke->start = event.time;
			
			ps_vertex_t* newVertex = vertices + newVertexId;

			newVertex->position = newX;
			newVertex->edges[0] = NSNotFound;
			newVertex->edges[1] = NSNotFound;

						
			wall0->spokes[1] = newSpoke->spokeId;
			wall1->spokes[0] = newSpoke->spokeId;
			
			spoke0->finalVertex = newVertex->vertexId;
			spoke1->finalVertex = newVertex->vertexId;
			
			[self generateEventsForSplit: *newSpoke afterTime: event.time];
			[self generateEventForWallCollapse: *wall0 afterTime: event.time];
			[self generateEventForWallCollapse: *wall1 afterTime: event.time];
			 
		}
		
	}
	
	
	for (size_t i = 0; i < numSpokes; ++i)
	{
		ps_spoke_t* spoke = spokes + i;
		
		
		if (spoke->finalVertex == NSNotFound)
		{
			size_t newVertexId;
			[self allocateVerticesTo: &newVertexId count: 1];

			vector_t p = vertices[spoke->sourceVertex].position;
			vector_t v = spoke->velocity;
			vector_t x = v3Add(p, v3MulScalar(v, extensionLimit - spoke->start));
			
			assert(!vIsNAN(x));
			
			ps_vertex_t* newVertex = vertices + newVertexId;
			
			newVertex->position = x;
			newVertex->edges[0] = NSNotFound;
			newVertex->edges[1] = NSNotFound;
			
			spoke->finalVertex = newVertex->vertexId;
			spoke->active = NO;
		}
	}
	
}
#endif

- (NSArray*) offsetMeshes
{
	return outlineMeshes;
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






