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

struct ps_edge_s;
typedef struct ps_edge_s ps_edge_t;
struct ps_vertex_s;
typedef struct ps_vertex_s ps_vertex_t;
struct ps_spoke_s;
typedef struct ps_spoke_s ps_spoke_t;
struct ps_wall_s;
typedef struct ps_wall_s ps_wall_t;
struct ps_event_s;
typedef struct ps_event_s ps_event_t;

struct ps_edge_s {
	size_t		edgeId;
	size_t		vertices[2];
	vector_t	normal;
	vector_t	edge;
};

struct ps_vertex_s {
	size_t		vertexId;
	vector_t	position;
	size_t		edges[2];
};
struct ps_spoke_s {
	size_t		spokeId;
	size_t		sourceVertex, finalVertex;
	size_t		walls[2];
	vector_t	velocity;
	double		start;
	BOOL		active;
};
struct ps_wall_s {
	size_t		wallId;
	size_t		sourceEdge;
	size_t		spokes[2];
	vector_t	velocity;
//	double		start;
	BOOL		active;
};

struct ps_event_s {
	double		time;
	vector_t	location;
	size_t		wall, spoke;
};


@implementation PolygonSkeletizer
{
	ps_vertex_t* vertices;
	ps_edge_t* edges;
	ps_spoke_t* spokes;
	ps_wall_t* walls;
	size_t numVertices, numEdges, numSpokes, numWalls;
	
	ps_event_t* events;
	size_t numEvents;
}

@synthesize extensionLimit;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	extensionLimit = 50.0;
	
	return self;
}

- (void) dealloc
{
	if (vertices)
		free(vertices);
	if (edges)
		free(edges);
	if (spokes)
		free(spokes);
	if (walls)
		free(walls);
}

- (void) allocateVerticesTo: (size_t*) dst count: (size_t) n
{
	vertices = realloc(vertices, sizeof(*vertices)*(numVertices+n));
	
	for (size_t i = 0; i < n; ++i)
	{
		size_t k = numVertices+i;
		dst[i] = k;
		vertices[k].vertexId = k;
		vertices[k].position = vCreatePos(NAN, NAN, NAN);
		vertices[k].edges[0] = NSNotFound;
		vertices[k].edges[1] = NSNotFound;
	}
	
	numVertices += n;
}

- (void) allocateEdgesTo: (size_t*) dst count: (size_t) n
{
	edges = realloc(edges, sizeof(*edges)*(numEdges+n));
	
	for (size_t i = 0; i < n; ++i)
	{
		size_t k = numEdges+i;
		dst[i] = k;
		edges[k].edgeId = k;
		edges[k].edge = vCreateDir(NAN, NAN, NAN);
		edges[k].normal = vCreateDir(NAN, NAN, NAN);
		edges[k].vertices[0] = NSNotFound;
		edges[k].vertices[1] = NSNotFound;
	}
	
	numEdges += n;
}



- (void) addClosedPolygonWithVertices: (vector_t*) vv count: (size_t) vcount
{
	size_t* vertexIds = calloc(sizeof(*vertexIds), vcount);
	[self allocateVerticesTo: vertexIds count: vcount];
	size_t* edgeIds = calloc(sizeof(*vertexIds), vcount);
	[self allocateEdgesTo: edgeIds count: vcount];

	edges = realloc(edges, sizeof(*edges)*(numEdges + vcount));
	
	for (long i = 0; i < vcount; ++i)
	{
		size_t ii = vertexIds[i];
		vertices[ii].position = vv[i];
		vertices[ii].edges[0] = edgeIds[(vcount+i-1) % vcount];
		vertices[ii].edges[1] = edgeIds[i];
		
		edges[ii].edgeId = ii;
		edges[ii].vertices[0] = ii;
		edges[ii].vertices[1] = vertexIds[(i+1) % vcount];
	}
	for (long i = 0; i < vcount; ++i)
	{
		size_t ii = edgeIds[i];
		vector_t a = vertices[edges[ii].vertices[0]].position;
		vector_t b = vertices[edges[ii].vertices[1]].position;
		vector_t e = v3Sub(b, a);
		edges[ii].normal = vSetLength(vCreate(-e.farr[1], e.farr[0], 0.0, 0.0), 1.0);
		edges[ii].edge = e;
		
	}

	free(vertexIds);
	free(edgeIds);
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

- (void) generateWalls
{
	assert(numVertices == numEdges);
	
	size_t* spokeIds = calloc(sizeof(*spokeIds), numVertices);
	[self allocateSpokesTo: spokeIds count: numVertices];
	size_t* wallIds = calloc(sizeof(*wallIds), numEdges);
	[self allocateWallsTo: wallIds count: numEdges];
	
	
	
	
	for (size_t i = 0; i < numEdges; ++i)
	{
		ps_edge_t* edge1 = edges+i;
		ps_edge_t* edge0 = edges+((numEdges+i-1) % numEdges);
		
		vector_t r0 = v3Sub(vertices[edge0->vertices[1]].position, vertices[edge0->vertices[0]].position);
		vector_t r1 = v3Sub(vertices[edge1->vertices[1]].position, vertices[edge1->vertices[0]].position);
		vector_t n0 = edge0->normal;
		vector_t n1 = edge1->normal;
		
		vector_t spokeN = bisectorVelocity(n0, n1, r0, r1);
		
		ps_spoke_t* spoke = spokes + spokeIds[i];
		spoke->start = 0.0;
		spoke->velocity = spokeN;
		spoke->sourceVertex = edge0->vertices[1];
		spoke->finalVertex = NSNotFound;
		spoke->walls[0] = (numEdges+i-1) % numEdges;
		spoke->walls[1] = i;
		spoke->active = YES;
		
		ps_wall_t* wall = walls+wallIds[i];

		wall->velocity = n1;
		wall->sourceEdge = i;
		wall->spokes[0] = i;
		wall->spokes[1] = (i+1) % numEdges;
		wall->active = YES;
	}
}

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

- (void) insertEvent: (ps_event_t) event
{
	events = realloc(events, sizeof(*events)*(numEvents+1));
	
/*
	size_t insertionPoint = _findBigger(events, 0, numEvents, event.time);
	
	memcpy(events + insertionPoint+1, events + insertionPoint, sizeof(*events)*(numEvents-insertionPoint));
	events[insertionPoint] = event;
*/
	events[numEvents] = event;
	numEvents++;
	
}


- (void) generateEventForWallCollapse: (ps_wall_t) wall afterTime: (double) minTime
{
	ps_spoke_t spoke0 = spokes[wall.spokes[0]];
	ps_spoke_t spoke1 = spokes[wall.spokes[1]];
	
	vector_t v0 = spoke0.velocity;
	vector_t v1 = spoke1.velocity;
	
	
	vector_t p0 = vertices[spoke0.sourceVertex].position; // v3MulScalar(v0, spoke0.start));
	vector_t p1 = vertices[spoke1.sourceVertex].position; // v3MulScalar(v0, spoke0.start));

	vector_t tx = xRays2D(p0, v0, p1, v1);
	
	double t = tx.farr[0] + spoke0.start;
	
	if (t > minTime)
	{
		if (t < extensionLimit)
		{
			assert(wall.wallId != NSNotFound);
			assert(!isnan(t));
			ps_event_t event;
			event.time = t;
			event.location = v3Add(p0, v3MulScalar(v0, tx.farr[0]));
			event.wall = wall.wallId;
			event.spoke = NSNotFound;
			[self insertEvent: event];
		}
	}
	
}

- (void) generateEventsForSplit: (ps_spoke_t) spoke afterTime: (double) minTime
{

	vector_t sv = spoke.velocity;
	vector_t sp = vertices[spoke.sourceVertex].position;
	
	vector_t e0 = edges[walls[spoke.walls[0]].sourceEdge].edge;
	vector_t e1 = edges[walls[spoke.walls[1]].sourceEdge].edge;
	
	double winding = vCross(e0, e1).farr[2];
	
	if (winding <= 0.0)
		return;
	
	for (size_t j = 0; j < numWalls; ++j)
	{
		// magic to skip the two walls adjacent to the spoke
		if ((j == spoke.walls[0]) || (j == spoke.walls[1]))
			continue;
		
		ps_wall_t wall = walls[j]; 
		vector_t e = edges[wall.sourceEdge].edge;
		vector_t ev = wall.velocity;
		vector_t ep = vertices[edges[wall.sourceEdge].vertices[0]].position;
		
		vector_t v = v3Sub(sv, ev);
		
//		vector_t tx = xRays2D(sp, v, ep, e);
//		double t = tx.farr[0] + spoke.start;
		double approachSpeed = -vDot(ev, v);
		double distance = vDot(ev, v3Sub(sp,ep));
		double t = distance/approachSpeed + spoke.start;
		
		if ((t > minTime) && (t < extensionLimit))
		{
			assert(!isnan(t));
//			assert(t > 0.001);
			vector_t x0 = _spokeVertexAtTime(spokes[wall.spokes[0]], vertices, t);
			vector_t x1 = _spokeVertexAtTime(spokes[wall.spokes[1]], vertices, t);
			vector_t w = v3Sub(x1, x0);
			vector_t ux = xRays2D(sp, sv, x0, w);
			double u = ux.farr[1];
			
			if ((u >= 0.0) && ( u < 1.0))
			{
				ps_event_t event;
				assert(wall.wallId != NSNotFound);
				event.time = t;
				event.location = v3Add(sp, v3MulScalar(sv, t - spoke.start));
				event.wall = wall.wallId;
				event.spoke = spoke.spokeId;
				[self insertEvent: event];
			}
		}
	}

}

- (void) initializeEvents
{
	events = realloc(events, sizeof(*events)*(numSpokes*numWalls+numWalls));
	numEvents = 0;
	
	for (size_t i = 0; i < numWalls; ++i)
	{
		ps_wall_t wall = walls[i];
		[self generateEventForWallCollapse: wall afterTime: 0.0];
	}
	for (size_t i = 0; i < numSpokes; ++i)
	{
		ps_spoke_t spoke = spokes[i];
		[self generateEventsForSplit: spoke afterTime: 0.0];
	}
	
}

- (void) allocateSpokesTo: (size_t*) dst count: (size_t) n
{
	spokes = realloc(spokes, sizeof(*spokes)*(numSpokes+n));
	
	for (size_t i = 0; i < n; ++i)
	{
		size_t k = numSpokes+i;
		dst[i] = k;
		spokes[k].spokeId = k;
		spokes[k].sourceVertex = NSNotFound;
		spokes[k].finalVertex = NSNotFound;
		spokes[k].walls[0] = NSNotFound;
		spokes[k].walls[1] = NSNotFound;
		spokes[k].velocity = vCreateDir(NAN, NAN, NAN);
		spokes[k].start = NAN;
		spokes[k].active = NO;
	}
	
	numSpokes += n;
}

- (void) allocateWallsTo: (size_t*) dst count: (size_t) n
{
	walls = realloc(walls, sizeof(*walls)*(numWalls+n));
	
	for (size_t i = 0; i < n; ++i)
	{
		size_t k = numWalls+i;
		dst[i] = k;
		walls[k].wallId = k;
		walls[k].sourceEdge = NSNotFound;
		walls[k].spokes[0] = NSNotFound;
		walls[k].spokes[1] = NSNotFound;
		walls[k].velocity = vCreateDir(NAN, NAN, NAN);
		walls[k].active = NO;
	}
	
	numWalls += n;
}


- (void) generateSkeleton
{
	// start by generating the spokes for each edge
	assert(numEdges == numVertices);
	
	[self generateWalls];
	[self initializeEvents];
	
	
	while (numEvents)
	{
		
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

- (GfxMesh*) skeletonMesh
{
	uint32_t* indices = calloc(sizeof(*spokes), numSpokes*2);
	vector_t* positions = calloc(sizeof(*positions), numVertices*2);
	vector_t* colors = calloc(sizeof(*colors), numVertices*2);
	
	for (size_t i = 0; i < numVertices; ++i)
	{
		positions[i] = vertices[i].position;
		colors[i] = vCreate(0.0, 0.5, 1.0, 1.0);
	}

	size_t ni = 0;
	
	for (size_t i = 0; i < numSpokes; ++i)
	{
		if (spokes[i].finalVertex == NSNotFound)
			continue;
		indices[ni++] = spokes[i].sourceVertex;
		indices[ni++] = spokes[i].finalVertex;
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



