//
//  ModelView3D.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 20.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import "ModelView3D.h"
#import "GfxShader.h"
#import "GfxStateStack.h"
#import "GfxTexture.h"
#import "gfx.h"
#import "GLString.h"
#import "GLDrawableBuffer.h"

#import <OpenGL/gl3.h>


@implementation ModelView3D
{
	GfxShader* modelShader;
	GfxShader* flatShader;
	GfxTexture* whiteTexture;
	
	vector_t	camLookAt, camPos;
	float		camDistance;
	float		camHeading, camPitch;
	
	range3d_t	printableVolume;
	GfxMesh*	grid;
}

@synthesize models;

- (void) createGrid
{
	grid = [[GfxMesh alloc] init];
	
	size_t numVertices = 8, numIndices = 8*3, kv = 0, ki = 0;
	
	vector_t* vertices = calloc(numVertices, sizeof(*vertices));
	vector_t* colors = calloc(numVertices, sizeof(*colors));
	uint32_t* indices = calloc(numIndices, sizeof(*indices));

	
	vertices[kv++] = vCreatePos(printableVolume.minv.farr[0],printableVolume.minv.farr[1],printableVolume.minv.farr[2]);
	vertices[kv++] = vCreatePos(printableVolume.maxv.farr[0],printableVolume.minv.farr[1],printableVolume.minv.farr[2]);
	vertices[kv++] = vCreatePos(printableVolume.minv.farr[0],printableVolume.maxv.farr[1],printableVolume.minv.farr[2]);
	vertices[kv++] = vCreatePos(printableVolume.maxv.farr[0],printableVolume.maxv.farr[1],printableVolume.minv.farr[2]);
	vertices[kv++] = vCreatePos(printableVolume.minv.farr[0],printableVolume.minv.farr[1],printableVolume.maxv.farr[2]);
	vertices[kv++] = vCreatePos(printableVolume.maxv.farr[0],printableVolume.minv.farr[1],printableVolume.maxv.farr[2]);
	vertices[kv++] = vCreatePos(printableVolume.minv.farr[0],printableVolume.maxv.farr[1],printableVolume.maxv.farr[2]);
	vertices[kv++] = vCreatePos(printableVolume.maxv.farr[0],printableVolume.maxv.farr[1],printableVolume.maxv.farr[2]);

	/*
	indices[ki++] = 0;
	indices[ki++] = 1;
	indices[ki++] = 0;
	indices[ki++] = 2;
	indices[ki++] = 0;
	indices[ki++] = 4;
	*/
	indices[ki++] = 0;
	indices[ki++] = 1;
	indices[ki++] = 2;
	indices[ki++] = 3;
	indices[ki++] = 4;
	indices[ki++] = 5;
	indices[ki++] = 6;
	indices[ki++] = 7;

	indices[ki++] = 0;
	indices[ki++] = 2;
	indices[ki++] = 1;
	indices[ki++] = 3;
	indices[ki++] = 4;
	indices[ki++] = 6;
	indices[ki++] = 5;
	indices[ki++] = 7;

	indices[ki++] = 0;
	indices[ki++] = 4;
	indices[ki++] = 1;
	indices[ki++] = 5;
	indices[ki++] = 2;
	indices[ki++] = 6;
	indices[ki++] = 3;
	indices[ki++] = 7;

	
	for (size_t i = 0; i < numVertices; ++i)
		colors[i] = vCreate(1.0, 1.0, 1.0, 1.0);
	
	
	
	
	
	
	
	[grid setVertices: vertices count: numVertices copy: NO];
	[grid setColors: colors count: numVertices copy: NO];
	[grid addDrawArrayIndices: indices count: numIndices withMode: GL_LINES];
	
	
	free(indices);
	
}

- (void) setupView
{
	glClearColor(0.5,0.25,0.0,1.0);
	glClearDepth(1.0f);
	modelShader = [[GfxShader alloc] initWithVertexShaderFiles: [NSArray arrayWithObjects: @"model.vs", nil] fragmentShaderFiles: [NSArray arrayWithObjects: @"model.fs", nil] prefixString: @""];
	flatShader = [[GfxShader alloc] initWithVertexShaderFiles: [NSArray arrayWithObjects: @"flat.vs", nil] fragmentShaderFiles: [NSArray arrayWithObjects: @"flat.fs", nil] prefixString: @""];
	whiteTexture = [GfxTexture textureNamed: @"white.png"];

	statusString = [[GLString alloc] initWithString: @"test" withAttributes: [GLString defaultStringAttributes] withTextColor: [NSColor whiteColor] withBoxColor: [NSColor blackColor] withBorderColor: [NSColor grayColor]];
	
	if (!models)
		models = [NSArray array];

	camPos = vCreatePos(300.0, 300.0, 300.0);
	printableVolume.maxv = vCreatePos(200.0, 200.0, 200.0);
	
	[self createGrid];
}

- (void) awakeFromNib
{
	[[self window] setAcceptsMouseMovedEvents: YES];
	
}

- (BOOL) acceptsFirstResponder
{
	return YES;
}

- (void) drawHUDWithState: (GfxStateStack*) gfxState
{
	NSSize size = [self bounds].size;
	matrix_t projMatrix = mOrtho(vCreateDir(0.0,0.0,-1.0), vCreateDir(size.width, size.height, 1.0));
	
	gfxState.projectionMatrix = projMatrix;
	gfxState.modelViewMatrix = mIdentity();
	gfxState.color = vCreate(1.0, 1.0, 1.0, 1.0);
	[gfxState setTexture: whiteTexture atIndex: 0];
	gfxState.blendingEnabled = YES;
	gfxState.blendingSrcMode = GL_ONE;
	gfxState.blendingDstMode = GL_ONE_MINUS_SRC_ALPHA;
	gfxState.depthTestEnabled = NO;
	
	[statusString setString: [NSString stringWithFormat: @"foo"]];
	
//	[statusString drawAtPoint: NSMakePoint(1.0,1.0)];
	
}

- (void) drawModelsWithState: (GfxStateStack*) gfxState
{
	NSSize size = [self bounds].size;
	matrix_t projMatrix = mPerspective(60.0*M_PI/180.0, size.width/size.height, 1.0, 1000.0);
	
	vector_t up = vCreateDir(0.0, 0.0, 1.0);

	vector_t camDelta = vSub3D(camPos, camLookAt);
	vector_t camRight = vCross(up, camDelta);
	vector_t camUp = vCross(camDelta, camRight);
	
	matrix_t R = mCreateFromBases(vSetLength(camRight, 1.0), vSetLength(camUp, 1.0), vSetLength(camDelta, 1.0));
	
	matrix_t viewMatrix = mTransform(mTranspose(R), mTranslationMatrix(vNegate(camPos)));

	
	range3d_t modelsRange = rCreateFromMinMax(vCreatePos(0.0, 0.0, 0.0), vCreatePos(200.0, 200.0, 200.0));
	
	for (GfxMesh* model in models)
	{
		range3d_t r = [model vertexBounds];
		modelsRange = rUnionRange(modelsRange, r);
	}
	
//	matrix_t projMatrix = mOrtho(modelsRange.minv, modelsRange.maxv);
	
	gfxState.projectionMatrix = projMatrix;
	gfxState.modelViewMatrix = viewMatrix;
//	gfxState.modelViewMatrix = mIdentity();
	[gfxState setTexture: whiteTexture atIndex: 0];
	gfxState.depthTestEnabled = YES;
	gfxState.cullingEnabled = NO;
	gfxState.frontFace = GL_CCW;
	gfxState.shader = modelShader;
	
	[gfxState setVectorUniform: mTransformDir(viewMatrix, vCreateDir(1.0, 1.0, -1.0)) named: @"lightPos"];
//	[gfxState setVectorUniform: vSub3D(camLookAt, camPos) named: @"lightPos"];
	
	
	[gfxState submitState];
	
	[[GfxMesh sphereMesh] justDraw];
	
	LogGLError(@"wtf");
	
	gfxState.shader = flatShader;
	
	[gfxState submitState];

	
	for (GfxMesh* model in models)
	{
		[model drawHierarchyWithState: gfxState];
	}
	
	[grid justDraw];
}

- (void) drawWithState: (GfxStateStack*) gfxState
{
	gfxState.depthTestEnabled = YES;
	gfxState.polygonOffsetUnits = 1.0;
	gfxState.polygonOffsetFactor = 1.0;
	gfxState.polygonOffsetEnabled = YES;
	gfxState.cullingEnabled = NO;
	gfxState.polygonMode = GL_FILL;
	glDepthFunc(GL_LEQUAL);
	
	
	glFrontFace(GL_CW);
	glCullFace(GL_BACK);
	//	glEnable(GL_CULL_FACE);
	
//	[self drawWorld: theWorld inFrustum: mIdentity() withState: gfxState];
	
	[self drawModelsWithState: gfxState];
	
	[self drawHUDWithState: gfxState];
	
//	LogGLError(@"what happen");
	
}

- (void) drawForTime: (const CVTimeStamp*) outputTime
{
	NSArray* drawableKeys = [NSArray arrayWithObjects: @"everything", nil];
	
	self.drawableBuffer.drawableKeys = drawableKeys;
	
	[drawableBuffer queueUpdate: ^{
		GLDrawableBlock block = ^(GfxStateStack* gfxState) {
			[self drawWithState: gfxState];
		};
		return (id)block;
		
	} forKey: @"everything"];
	
	
	[super drawForTime: outputTime];

}

- (void) scrollWheel:(NSEvent *) event
{
	NSUInteger flags = [event modifierFlags];
	float dx = [event deltaX];
	float dy = [event deltaY];
	
	vector_t camDelta = vSub3D(camLookAt, camPos);
	vector_t right = vCross(camDelta, vCreateDir(0.0, 0.0, 1.0));
	vector_t up = vCross(right, camDelta);

	if (flags & NSShiftKeyMask)
	{
		matrix_t MX = mRotationMatrixAxisAngle(up, -dx*0.01);
		matrix_t MY = mRotationMatrixAxisAngle(right, -dy*0.01);
		
		vector_t newDelta = mTransformDir(mTransform(MX, MY), camDelta);
		camPos = v3Sub(camLookAt, newDelta);
	}
	else if (flags & NSControlKeyMask)
	{
		vector_t planarForward = v3Sub(camDelta, vProjectAOnB(camDelta, vCreateDir(0.0, 0.0, 1.0)));
		vector_t planarRight = vCross(planarForward, vCreateDir(0.0, 0.0, 1.0));
		vector_t move = v3Add(vSetLength(planarForward, dy*0.1), vSetLength(planarRight, dx*0.1));
		camPos = v3Add(camPos, move);
		camLookAt = v3Add(camLookAt, move);
	}
	else
	{
		camDelta = v3MulScalar(camDelta, 1.0+dy*0.01);
		camPos = v3Sub(camLookAt, camDelta);
	}
	
}

@end