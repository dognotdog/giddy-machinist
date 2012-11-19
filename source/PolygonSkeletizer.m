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

@class PSEdge;

@interface PSVertex : NSObject
@property(nonatomic) vector_t position;
@property(nonatomic, readonly) NSArray* edges;
- (void) addEdge: (PSEdge*) edge;
- (void) removeEdge: (PSEdge*) edge;
- (PSEdge*) nextEdgeFromEdgeCCW: (PSEdge*) edge;
@end

@interface PSEdge : NSObject
@property(nonatomic) PSVertex* startVertex, *endVertex;
@property(nonatomic) vector_t normal, edge;
@end

@interface PSSourceEdge : PSEdge
@property(nonatomic, weak) PSSourceEdge *next, *prev;
@end

@interface PSMotorcycleEdge : PSEdge
@property(nonatomic) double start;
@property(nonatomic) vector_t leftNormal, rightNormal;
@end



@interface PSMotorcycle : NSObject
@property(nonatomic, weak) PSVertex* sourceVertex;
@property(nonatomic, weak) PSVertex* terminalVertex;
@property(nonatomic) vector_t velocity;
@property(nonatomic) vector_t leftNormal, rightNormal;
@property(nonatomic, weak) PSMotorcycle *leftNeighbour, *rightNeighbour;
@property(nonatomic) double start;

@end


@interface PSConvexRegion : NSObject

@property(nonatomic) NSArray* vertices;
@property(nonatomic) NSArray* sourceEdges;
@property(nonatomic) NSArray* railEdges;

- (id) initWithRegionArray: (NSArray*) ary;

@end


@interface PSEvent : NSObject

@property(nonatomic) double time;
@property(nonatomic) vector_t location;
@property(nonatomic) size_t wall, spoke;

@end

@interface PSEventGroup : NSObject

@property(nonatomic,strong) NSArray* events;
@property(nonatomic) double time;
@property(nonatomic) vector_t location;

@end

@implementation PSEvent

@synthesize time, location, wall, spoke;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	time = NAN;
	location = vCreate(NAN, NAN, NAN, NAN);
	wall = NSNotFound;
	spoke = NSNotFound;
	
	return self;
}
@end

@implementation PSEventGroup

@synthesize time, location, events;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	time = NAN;
	location = vCreate(NAN, NAN, NAN, NAN);
	events = [NSArray array];
	
	return self;
}
@end


@implementation PolygonSkeletizer
{
	NSArray* vertices;
	NSArray* edges;
	
	NSArray* terminatedMotorcycles;
}

@synthesize extensionLimit, mergeThreshold;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	extensionLimit = 50.0;
	mergeThreshold = 0.001;
	
	vertices = [NSArray array];
	edges = [NSArray array];
	terminatedMotorcycles = [NSArray array];
	
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

}
static inline vector_t bisectorVelocity(vector_t v0, vector_t v1, vector_t e0, vector_t e1)
{
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
		vector_t motorv = cycle.velocity;
		vector_t motorp = cycle.sourceVertex.position;
		// crash against edges
		for (PSEdge* edge in edges)
		{
			// skip edges motorcycle started from
			if ((edge.startVertex == cycle.sourceVertex) || (edge.endVertex == cycle.sourceVertex))
				continue;
			
			
			vector_t delta = v3Sub(motorp, edge.startVertex.position);
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
			
			if ((ta > cycle.start) && (ta < extensionLimit) && (tb > 0.0) && (tb < 1.0))
			{
				double hitTime = ta;
				
				
				id crash = @[[NSNumber numberWithDouble: hitTime], cycle, cycle1, [NSNumber numberWithDouble: tx.farr[0]], [NSNumber numberWithDouble: tx.farr[1]], [NSNumber numberWithBool: NO]];
				[crashes addObject: crash];
			}
			
			
		}
		
		++k;
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

- (void) splitEdge: (PSEdge*) edge atVertex: (PSVertex*) vertex
{
	PSEdge* newEdge = [[[edge class] alloc] init];
	
	newEdge.startVertex = vertex;
	newEdge.endVertex = edge.endVertex;
	
	[edge.endVertex removeEdge: edge];
	edge.endVertex = vertex;
	[newEdge.endVertex addEdge: newEdge];
	
	[vertex addEdge: newEdge];
	[vertex addEdge: edge];
	
	edges = [edges arrayByAddingObject: newEdge];
	
	if ([edge isKindOfClass: [PSSourceEdge class]])
	{
		[(PSSourceEdge*)newEdge setNext: [(PSSourceEdge*)edge next]];
		[(PSSourceEdge*)newEdge setPrev: (PSSourceEdge*)edge];
		[(PSSourceEdge*)edge setNext: (PSSourceEdge*)newEdge];
		[[(PSSourceEdge*)newEdge next] setPrev: (PSSourceEdge*)edge];
	}
}

static void _locateExternalCycles(NSArray* crashes, NSArray** internalCyclesPtr, NSArray** externalCyclesPtr)
{
	
	NSMutableSet* crashedCycles = [NSMutableSet set];
	
	for (NSArray* crashInfo in crashes)
	{
		PSMotorcycle* cycle0 = [crashInfo objectAtIndex: 1];
		PSMotorcycle* cycle1 = [crashInfo objectAtIndex: 2];
		[crashedCycles addObjectsFromArray: @[cycle0, cycle1]];
	}
	
	NSMutableSet* leftNeighbours = [NSMutableSet set];
	NSMutableSet* rightNeighbours = [NSMutableSet set];

	for (PSMotorcycle* cycle in crashedCycles)
	{
		if ([crashedCycles containsObject: cycle.leftNeighbour])
			[leftNeighbours addObject: cycle.leftNeighbour];
		if ([crashedCycles containsObject: cycle.rightNeighbour])
			[rightNeighbours addObject: cycle.rightNeighbour];
	}
	
	NSSet* difference = [leftNeighbours xorSetWithSet: rightNeighbours];
	NSMutableSet* internals = [crashedCycles mutableCopy];
	[internals minusSet: difference];
	
	assert((difference.count == 2) || (difference.count == 0));
	
	*externalCyclesPtr = [difference allObjects];
	*internalCyclesPtr = [internals allObjects];
}

- (void) runMotorcycles
{
	
	assert([edges count] == [vertices count]);
	
	
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
			
			[motorcycles addObject: cycle];
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
			
			vector_t x = _crashLocation(initialCrashInfo);

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
				
				// if we hit a vertex, we take it
				if (crashVertices.count)
				{
					PSVertex* vertex = [crashVertices anyObject];
					// terminate each motorcycle and insert an edge
					for (PSMotorcycle* cycle in cycles)
					{
						cycle.terminalVertex = vertex;
						cycle.leftNeighbour.rightNeighbour = cycle.rightNeighbour;
						cycle.rightNeighbour.leftNeighbour = cycle.leftNeighbour;

						/*
						PSMotorcycleEdge* edge = [[PSMotorcycleEdge alloc] init];
						edge.startVertex = cycle.sourceVertex;
						edge.endVertex = vertex;
						edge.edge = v3Sub(edge.endVertex.position, edge.startVertex.position);
						[edge.startVertex addEdge: edge];
						[edge.endVertex addEdge: edge];
						
						edge.leftNormal = cycle.leftNormal;
						edge.rightNormal = cycle.rightNormal;
						edge.start = cycle.start;

						edges = [edges arrayByAddingObject: edge];
						*/
					}
					
					[motorcycles removeObjectsInArray: [cycles allObjects]];
					terminatedMotorcycles = [terminatedMotorcycles arrayByAddingObjectsFromArray:[cycles allObjects]];
				}
				else
				{
					PSVertex* vertex = [[PSVertex alloc] init];
					vertex.position = x;
					vertices = [vertices arrayByAddingObject: vertex];
					
					PSEdge* edge = [crashWalls anyObject];
					
					[self splitEdge: edge atVertex: vertex];
					
				}
				
			}
			else if (traceCrash)
			{
				PSVertex* vertex = [[PSVertex alloc] init];
				vertex.position = x;
				vertices = [vertices arrayByAddingObject: vertex];
				
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
				
				assert(survivor);
				[crashedCycles removeObject: survivor];
				
				
				
				// terminate each motorcycle and insert an edge
				for (PSMotorcycle* cycle in crashedCycles)
				{
					cycle.terminalVertex = vertex;
					cycle.leftNeighbour.rightNeighbour = cycle.rightNeighbour;
					cycle.rightNeighbour.leftNeighbour = cycle.leftNeighbour;
					
					/*
					PSMotorcycleEdge* edge = [[PSMotorcycleEdge alloc] init];
					edge.startVertex = cycle.sourceVertex;
					edge.endVertex = vertex;
					edge.edge = v3Sub(edge.endVertex.position, edge.startVertex.position);
					[edge.startVertex addEdge: edge];
					[edge.endVertex addEdge: edge];
					
					edge.leftNormal = cycle.leftNormal;
					edge.rightNormal = cycle.rightNormal;
					edge.start = cycle.start;
					
					edges = [edges arrayByAddingObject: edge];
					 */
				}
				
				[motorcycles removeObjectsInArray: [crashedCycles allObjects]];
				terminatedMotorcycles = [terminatedMotorcycles arrayByAddingObjectsFromArray: [crashedCycles allObjects]];
				
				/*
				// aaaaaand... create a new motorcycle for the survivor
				PSMotorcycle* survivor = [survivorCycles anyObject];
				PSMotorcycle* newCycle = [[PSMotorcycle alloc] init];
				newCycle.sourceVertex = vertex;
				newCycle.start = tmin;
				newCycle.velocity = survivor.velocity;
				newCycle.leftNormal = survivor.leftNormal;
				newCycle.rightNormal = survivor.rightNormal;
				
				[motorcycles addObject: newCycle];
				 */
			}
			else if (mergeCrash)
			{
				NSArray* externalCycles = nil;
				NSArray* internalCycles = nil;
				_locateExternalCycles(simultaneousCrashes, &internalCycles, &externalCycles);
				
				//assert(simultaneousCrashes.count < 2); // TODO: allow star merge
				
				PSVertex* vertex = [[PSVertex alloc] init];
				vertex.position = x;
				vertices = [vertices arrayByAddingObject: vertex];
				
				for (PSMotorcycle* cycle in internalCycles)
				{
					cycle.terminalVertex = vertex;
					cycle.leftNeighbour.rightNeighbour = cycle.rightNeighbour;
					cycle.rightNeighbour.leftNeighbour = cycle.leftNeighbour;
				}
				
				if (externalCycles.count)
				{
					PSMotorcycle* cycle0 = [externalCycles objectAtIndex: 0];
					PSMotorcycle* cycle1 = [externalCycles objectAtIndex: 1];
					
					assert((cycle0.leftNeighbour == cycle1) || (cycle1.leftNeighbour == cycle0));
					
					PSMotorcycle* leftCycle = ( (cycle0.leftNeighbour == cycle1) ? cycle1 : cycle0);
					PSMotorcycle* rightCycle = ( (cycle0.leftNeighbour == cycle1) ? cycle0 : cycle1);
					PSMotorcycle* leftNeighbour = leftCycle.leftNeighbour;
					PSMotorcycle* rightNeighbour = rightCycle.rightNeighbour;

					for (PSMotorcycle* cycle in externalCycles)
					{
						cycle.terminalVertex = vertex;
						cycle.leftNeighbour.rightNeighbour = cycle.rightNeighbour;
						cycle.rightNeighbour.leftNeighbour = cycle.leftNeighbour;
	/*
						PSMotorcycleEdge* edge = [[PSMotorcycleEdge alloc] init];
						edge.startVertex = cycle.sourceVertex;
						edge.endVertex = vertex;
						edge.edge = v3Sub(edge.endVertex.position, edge.startVertex.position);
						[edge.startVertex addEdge: edge];
						[edge.endVertex addEdge: edge];
						
						edge.leftNormal = cycle.leftNormal;
						edge.rightNormal = cycle.rightNormal;
						edge.start = cycle.start;

						edges = [edges arrayByAddingObject: edge];
	 */
					}

					
					PSMotorcycle* newCycle = [[PSMotorcycle alloc] init];
					newCycle.sourceVertex = vertex;
					newCycle.start = tmin;
					newCycle.velocity = bisectorVelocity(leftCycle.leftNormal, rightCycle.rightNormal, _normalToEdge(leftCycle.leftNormal), _normalToEdge(rightCycle.rightNormal));
					newCycle.leftNeighbour = leftNeighbour;
					newCycle.rightNeighbour = rightNeighbour;

					[motorcycles addObject: newCycle];
				}
				
				[motorcycles removeObjectsInArray: internalCycles];
				[motorcycles removeObjectsInArray: externalCycles];
				terminatedMotorcycles = [terminatedMotorcycles arrayByAddingObjectsFromArray: internalCycles];
				terminatedMotorcycles = [terminatedMotorcycles arrayByAddingObjectsFromArray: externalCycles];
				
			}
		}
		
		
		
		
		
		crashes = [self crashMotorcycles: motorcycles];
	}
	
	/*
	 so we crashed everything, and now have a spaghetti of edges leftover, from which we need to extract the convex sub-regions
	 we do this by starting at a random source edge, and walking a loop. each edge will be walked forward and backwards exactly once, then we have all regions
	 TODO: holes need to be treated specially, best by removing the respective source edges from the walk lists appropriately (source edges may only be walked forward)
	 */
	
		
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



- (void) generateSkeleton
{
	[self runMotorcycles];
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



@interface PSSpoke : NSObject
@property(nonatomic) NSArray* trajectory;
@property(nonatomic) PSEdge* sourceEdge;
@property(nonatomic) PSVertex* sourceVertex;
@property(nonatomic) PSVertex* destinationVertex;

@end

@implementation PSConvexRegion

@synthesize vertices, railEdges, sourceEdges;

- (void) addVertex: (PSVertex*) src
{
	PSVertex* dst = [[PSVertex alloc] init];
	dst.position = src.position;
	
	vertices = [vertices arrayByAddingObject: dst];
}

- (void) addSourceChain: (NSArray*) chain
{
	if (!vertices.count)
	{
		[self addVertex: [[[chain objectAtIndex: 0] objectAtIndex: 0] startVertex]];
	}
	
	NSMutableArray* newChain = [NSMutableArray array];
	
	for (id entry in chain)
	{
		BOOL reverse = [[entry objectAtIndex: 0] boolValue];
		assert(!reverse);
		
		PSSourceEdge* src = [entry objectAtIndex: 0];
		
		PSSourceEdge* dst = [[PSSourceEdge alloc] init];
		dst.startVertex = [vertices lastObject];
		[self addVertex: src.endVertex];
		dst.endVertex = [vertices lastObject];
		
		[dst.startVertex addEdge: dst];
		[dst.endVertex addEdge: dst];
		
		[newChain addObject: dst];
	}
	sourceEdges = [sourceEdges arrayByAddingObject: newChain];
}

- (void) addRailChain: (NSArray*) chain
{
	if (!vertices.count)
	{
		BOOL reverse = [[[chain objectAtIndex: 0] objectAtIndex: 1] boolValue];
		if (reverse)
			[self addVertex: [[[chain objectAtIndex: 0] objectAtIndex: 0] endVertex]];
		else
			[self addVertex: [[[chain objectAtIndex: 0] objectAtIndex: 0] startVertex]];
	}

	NSMutableArray* newChain = [NSMutableArray array];

	for (id entry in chain)
	{
		BOOL reverse = [[entry objectAtIndex: 0] boolValue];
		
		PSSourceEdge* src = [entry objectAtIndex: 0];
		
		PSSourceEdge* dst = [[PSSourceEdge alloc] init];
		dst.startVertex = [vertices lastObject];
		[self addVertex: (reverse ? src.startVertex : src.endVertex)];
		dst.endVertex = [vertices lastObject];
		
		[dst.startVertex addEdge: dst];
		[dst.endVertex addEdge: dst];
		[newChain addObject: dst];
	}
	railEdges = [railEdges arrayByAddingObject: newChain];

}

- (void) closeChains
{
	assert(vertices.count > 1);
	
	PSVertex* v0 = [vertices objectAtIndex: 0];
	PSVertex* v1 = [vertices lastObject];
	
	vector_t p0 = v0.position;
	vector_t p1 = v1.position;
	
	assert(v3Equal(p0, p1));
	
	assert(v0.edges.count == 1);
	assert(v1.edges.count == 1);
	
	for (PSEdge* edge in v1.edges)
	{
		assert(edge.endVertex == v1);
		
		edge.endVertex = v0;
		[edge.endVertex addEdge: edge];
	}
	
	vertices = [vertices arrayByRemovingLastObject];
}


- (id) initWithRegionArray:(NSArray *)ary
{
	if (!(self = [super init]))
		return nil;
	
	vertices = [NSArray array];
	sourceEdges = [NSArray array];
	railEdges = [NSArray array];
	
	NSArray* chains = [ary continuousSubarraysWithCommonProperty: ^BOOL(id referenceObject, id obj) {
		return [[[referenceObject objectAtIndex: 0] class] isEqual: [[obj objectAtIndex: 0] class]];
	}];
	
	for (NSArray* chain in chains)
	{
		BOOL sourceChain = [[[[chain objectAtIndex: 0] objectAtIndex: 0] class] isEqual: [PSSourceEdge class]];
		
		if (sourceChain)
		{
			[self addSourceChain: chain];
		}
		else
		{
			[self addRailChain: chain];
		}
	}
	
	[self closeChains];
	
	return self;
}

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

- (void) runSpokesWithThreshold: (double) mergeThreshold
{
	NSMutableArray* spokes = [NSMutableArray array];
	
	double maxTime = _maxBoundsDimension(vertices);
	
	NSMutableArray* events = [NSMutableArray array];
	
	for (NSArray* chain in sourceEdges)
	{
		
	}

}

@end

@implementation PSEdge



@end

@implementation PSMotorcycle


@end

@implementation PSMotorcycleEdge


@end

@implementation PSSourceEdge


@end

@implementation PSVertex

@synthesize edges;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	edges = [NSArray array];
	
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

@end











