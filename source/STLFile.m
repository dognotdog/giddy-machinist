//
//  STLFile.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 20.05.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "STLFile.h"

#import "gfx.h"

#import "VectorMath_fixp.h"
#import "PriorityQueue.h"


void LoadSTLFileFromDataRaw(NSData* data, size_t* outNumVertices, vector_t** outVertices, vector_t** outNormals, vector_t** outColors, size_t* outNumIndices, uint32_t** outIndices);


@interface STLTriangle : NSObject
@property(nonatomic) uint32_t a,b,c;
@property(nonatomic) v3i_t minp, maxp;
@end


@implementation STLFile
{
	NSArray*	triangles;
	NSArray*	vertices;

	int			scaleShift;
}

@synthesize scaleShift;

static NSArray* _coalesceVertices(NSArray* vertices, uint32_t* indices, size_t numIndices)
{
	
	NSArray* array = [vertices indexedMap:^id(STLVertex* obj, NSInteger index) {
		return @[obj, [NSNumber numberWithInteger: index], [NSNumber numberWithInteger: obj.position.z]];
	}];
	
	
	
	PriorityQueue* zqueue = [[PriorityQueue alloc] initWithCompareBlock:^NSComparisonResult(NSArray* obj0, NSArray* obj1) {
		return i32compare([obj0.lastObject integerValue], [obj1.lastObject integerValue]);
		
	}];
	
	[zqueue addObjectsFromArray: array];
	
	NSArray* sortedObjects = [zqueue allObjects];
	
	NSMutableArray* tmpArray = nil;
	NSMutableArray* slices = [NSMutableArray array];
	for (NSArray* ary in sortedObjects)
	{
		if (!tmpArray)
			tmpArray = [NSMutableArray arrayWithObject: ary];
		else if ([tmpArray.lastObject isEqual: ary.lastObject])
		{
			[tmpArray addObject: ary];
		}
		else
		{
			[slices addObject: tmpArray];
			tmpArray = nil;
		}
	}
	
	NSMutableDictionary* indexMap = [NSMutableDictionary dictionary];
	
	NSMutableArray* outv = [NSMutableArray array];
	for (NSMutableArray* slice in slices)
	{
		for (size_t i = 0; i < slice.count; ++i)
		{
			NSArray* ai = [slice objectAtIndex: i];
			STLVertex* vi = [ai objectAtIndex: 0];
			NSNumber* knum = [NSNumber numberWithInteger: outv.count];
			[indexMap setObject: knum forKey: [ai objectAtIndex: 1]];
			
			[outv addObject: vi];
			
			for (size_t j = i+1; j < slice.count; ++j)
			{
				NSArray* aj = [slice objectAtIndex: j];
				STLVertex* vj = [aj objectAtIndex: 0];

				if (v3iEqual(vi.position, vj.position))
				{
					[indexMap setObject: knum forKey: [aj objectAtIndex: 1]];
					[slice removeObjectAtIndex: j];
					--j;
				}
			}
		}
	}

	for (size_t i = 0; i < numIndices; ++i)
	{
		indices[i] = [[indexMap objectForKey: [NSNumber numberWithInteger: indices[i]]] integerValue];
	}
	
	return outv;
}

/*!
 @param scaleBits number of bits to shift left. 
 */
- (instancetype) initWithData: (NSData*) data scale: (int) scaleBits transform: (matrix_t) M
{
	if (!(self = [super init]))
		return nil;
	
	size_t numVertices = 0, numIndices = 0;

	vector_t* floatVertices = NULL;
	vector_t* colors = NULL;
	vector_t* normals = NULL;
	uint32_t* indices = NULL;

	LoadSTLFileFromDataRaw(data, &numVertices, &floatVertices, &normals, &colors, &numIndices, &indices);

		
	scaleShift = scaleBits;
	
	double scale = 1 << scaleShift;
	
	NSMutableArray* vArray = [NSMutableArray arrayWithCapacity: numVertices];
	
	for (size_t i = 0; i < numVertices; ++i)
	{
		vector_t p = mTransformPos(M, floatVertices[i]);
		v3i_t q;
		q.x = p.farr[0]*scale;
		q.y = p.farr[1]*scale;
		q.z = p.farr[2]*scale;
		q.shift = scaleShift;
		
		STLVertex* v = [[STLVertex alloc] init];
		v.position = q;
		[vArray addObject: v];
	}
	
	vertices = vArray;
		
	
	free(floatVertices);
	free(colors);
	free(normals);
	

	// FIXME: coalesce is broken
//	vertices = _coalesceVertices(vertices, indices, numIndices);
	
	NSMutableArray* tris = [NSMutableArray arrayWithCapacity: numIndices/3];
	
	for (size_t i = 0; i < numIndices; i += 3)
	{
		uint32_t a = indices[i];
		uint32_t b = indices[i+1];
		uint32_t c = indices[i+2];
		
		STLTriangle* tri = [[STLTriangle alloc] init];
		tri.a = a;
		tri.b = b;
		tri.c = c;
		v3i_t A = [(STLVertex*)[vertices objectAtIndex: a] position];
		v3i_t B = [(STLVertex*)[vertices objectAtIndex: b] position];
		v3i_t C = [(STLVertex*)[vertices objectAtIndex: c] position];
		
		tri.minp = v3iMin(A, v3iMin(B, C));
		tri.maxp = v3iMax(A, v3iMax(B, C));
		
		[tris addObject: tri];
	}
	
	triangles = tris;

	
	return self;
}

- (NSArray*) trianglesIntersectingZLayer: (vmint_t) h
{
	return [triangles select: ^BOOL(STLTriangle* tri) {
		return (tri.minp.z <= h) && (tri.maxp.z >= h) && (tri.minp.z != tri.maxp.z);
	}];
}

- (NSArray*) lineSegmentsIntersectingZLayer: (v3i_t) zOffset
{
	NSMutableArray* segments = [NSMutableArray array];
	
	NSArray* tris = [self trianglesIntersectingZLayer: zOffset.z];
	for (STLTriangle* tri in tris)
	{
		v3i_t A = v3iSub([(STLVertex*)[vertices objectAtIndex: tri.a] position], zOffset);
		v3i_t B = v3iSub([(STLVertex*)[vertices objectAtIndex: tri.b] position], zOffset);
		v3i_t C = v3iSub([(STLVertex*)[vertices objectAtIndex: tri.c] position], zOffset);
		
		v3i_t rays[3][2] = {{A, B},{B, C},{C, A}};
		
		NSMutableArray* hits = [NSMutableArray array];
		
		for (int i = 0; i < 3; ++i)
		{
			v3i_t a = rays[i][0];
			v3i_t b = rays[i][1];
			
			// if this edge is planar, or not intersecting plane, continue
			if (((a.z <= 0) && (b.z <= 0)) || ((a.z >= 0) && (b.z >= 0)) || (a.z == b.z))
				continue;
			
			v3i_t r = v3iSub(b, a);
			
			// A + AB*d = B + BA - BA*d
			// (AB+BA)*d = B-A + BA
			
			// our t = num/den
			vmint_t num = 0 - a.z;
			vmint_t	den = r.z;
			
			v3i_t rs = v3iScale(r, num, den);
			
			v3i_t x = v3iAdd(a, rs);
			
			// reverse test, because A-B and B-A rays have to result in same X,Y
			{
				v3i_t rrev = v3iSub(a, b);
				
				// our t = num/den
				vmint_t numrev = 0 - b.z;
				vmint_t	denrev = rrev.z;
				
				v3i_t rsrev = v3iScale(rrev, numrev, denrev);
				
				v3i_t xrev = v3iAdd(b, rsrev);
				assert(xrev.x == x.x);
				assert(xrev.y == x.y);
				assert(xrev.z == x.z);
			}
			
			assert(x.z == 0);

			x.z = zOffset.z;
			STLVertex* vx = [[STLVertex alloc] init];
			vx.position = x;
			
			[hits addObject: vx];
			
		}
		
		if (hits.count == 2)
		{
			STLVertex* va = [hits objectAtIndex: 0];
			STLVertex* vb = [hits objectAtIndex: 1];
			if (!v3iEqual(va.position, vb.position))
				[segments addObject: hits];
		}
	}
	
	return segments;
}

@end

@implementation STLVertex

@end


@implementation STLTriangle


- (NSString*) description
{
	return [NSString stringWithFormat: @"tri: %d %d %d", self.a, self.b, self.c];
}


@end



void LoadSTLFileFromDataRaw(NSData* data, size_t* outNumVertices, vector_t** outVertices, vector_t** outNormals, vector_t** outColors, size_t* outNumIndices, uint32_t** outIndices)
{
	
	const size_t headerLength = 80;
	const size_t trianglesStart = 84;
	const size_t triangleLength = 50;
	
	const void* buf = [data bytes];
	assert([data length] > trianglesStart);
	
	size_t numTris = CFSwapInt32LittleToHost(*(uint32_t*)(buf+headerLength));
	size_t datalen = [data length];
	assert(datalen == trianglesStart+numTris*triangleLength);
	
	vector_t* vertices = calloc(numTris*3, sizeof(*vertices));
	vector_t* colors = calloc(numTris*3, sizeof(*colors));
	vector_t* normals = calloc(numTris*3, sizeof(*normals));
	
	for (size_t i = 0; i < numTris; ++i)
	{
		size_t vertexOffset = trianglesStart+triangleLength*i;
		float n[3];
		memcpy(n, buf+vertexOffset, 12);
		for (size_t j = 0; j < 3; ++j)
		{
			normals[3*i+j] = vCreatePos(n[0], n[1], n[2]);
		}
		
		
		for (size_t j = 0; j < 3; ++j)
		{
			float x[3];
			memcpy(x, buf+vertexOffset+12+j*12, 12);
			vertices[3*i+j] = vCreatePos(x[0], x[1], x[2]);
		}
		uint16_t color = CFSwapInt16LittleToHost(*(uint16_t*)(buf+vertexOffset+4*12));
		for (size_t j = 0; j < 3; ++j)
		{
			colors[3*i+j] = vCreatePos(((color & 0x001F)*255)/15L, (((color & 0x03E0) >> 5)*255)/15L, (((color & 0x7C0) >> 10)*255)/15L);
		}
		
	}
	
	uint32_t* indices = calloc(sizeof(*indices), numTris*3);
	
	for (size_t i = 0; i < numTris*3; ++i)
		indices[i]=i;
	
	*outNumVertices = numTris*3;
	*outNumIndices = numTris*3;
	*outVertices = vertices;
	*outNormals = normals;
	*outColors = colors;
	*outIndices = indices;

	
}

GfxMesh* LoadSTLFileFromData(NSData* data)
{
	vector_t* vertices = NULL;
	vector_t* colors = NULL;
	vector_t* normals = NULL;
	uint32_t* indices = NULL;
	size_t numVertices = 0, numIndices = 0;
	
	LoadSTLFileFromDataRaw(data, &numVertices, &vertices, &normals, &colors, &numIndices, &indices);
		
	GfxMesh* mesh = [[GfxMesh alloc] init];
	[mesh addVertices: vertices count: numVertices];
	//	[mesh addColors: colors count: numVertices];
	[mesh addNormals: normals count: numVertices];
	
	[mesh addDrawArrayIndices: indices count: numIndices withMode: GL_TRIANGLES];

	free(vertices);
	free(colors);
	free(normals);
	
	free(indices);
	
	//FIXME: removed as really slows down loading large models without any benefit
	//mesh = [mesh meshWithCoalescedVertices];
	//mesh = [mesh meshWithoutDegenerateTriangles];
	
	return mesh;

}



GfxMesh* LoadSTLFileAtPath(NSString* path)
{
	NSData* data = [NSData dataWithContentsOfFile: path];
	if (!data)
		return nil;
	
	return LoadSTLFileFromData(data);
}
