//
//  LayerInspectorView.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 15.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "LayerInspectorView.h"
#import "GMDocumentWindowController.h"

#import "Slicer.h"
#import "SlicedOutline.h"

#import "CGGeometryExtensions.h"

@implementation LayerInspectorView
{
	NSArray* outlinePaths;
	NSMutableArray* offsetPaths;
	NSMutableArray* offsetBoundaryPaths;
	NSMutableArray* openPaths;
	NSArray* motorcyclePaths;
	
//	CGPoint mouseDownLocationInLayer, mouseDragLocationInLayer, mouseUpLocationInSlice;
}

@synthesize slice, indexOfSelectedOutline, motorcyclePaths, spokePaths, outlinePaths, overfillPaths, underfillPaths, mouseDownLocationInSlice, mouseDragLocationInSlice, mouseUpLocationInSlice, clippingOutline;

- (id)initWithFrame:(NSRect)frame
{
    if (!(self = [super initWithFrame:frame]))
		return nil;
    
    return self;
}

- (void) addOffsetOutlinePath: (NSBezierPath*) bpath
{
	[offsetPaths addObject: bpath];
	[self setNeedsDisplay: YES];
}

- (void) addOffsetBoundaryPath: (NSBezierPath*) bpath
{
	[offsetBoundaryPaths addObject: bpath];
	[self setNeedsDisplay: YES];
}

- (void) removeAllOffsetOutlinePaths
{
	[offsetPaths removeAllObjects];
	[self setNeedsDisplay: YES];
}
- (void) removeAllOffsetBoundaryPaths
{
	[offsetBoundaryPaths removeAllObjects];
	[self setNeedsDisplay: YES];
}
- (void) setIndexOfSelectedOutline:(NSInteger)index
{
	indexOfSelectedOutline = index;
	
	[self setNeedsDisplay: YES];
}

- (void) setSlice:(SlicedLayer *)s
{
	slice = s;

	NSMutableArray* outlines = [NSMutableArray array];
	openPaths = [NSMutableArray array];
	offsetPaths = [NSMutableArray array];
	offsetBoundaryPaths = [NSMutableArray array];
	motorcyclePaths = @[];
	spokePaths = @[];
	overfillPaths = @[];
	underfillPaths = @[];
	
	for (SlicedOutline* path in slice.outlinePaths)
	{
		NSBezierPath* outline = [NSBezierPath bezierPath];
		NSArray* segments = [path allNestedPaths];
		for (SlicedLineSegment* segment in segments)
		{
			v3i_t* vertices = segment.vertices;
			for (size_t i = 0; i < segment.vertexCount; ++i)
			{
				v3i_t vertex = vertices[i];
				if (!i)
					[outline moveToPoint: v3iToCGPoint(vertex)];
				else
					[outline lineToPoint: v3iToCGPoint(vertex)];
			}
			[outline closePath];
		}
		
		[outlines addObject: outline];
		
	}
	outlinePaths = outlines;
	
	for (SlicedLineSegment* segment in slice.openPaths)
	{
		NSBezierPath* outline = [NSBezierPath bezierPath];
		{
			v3i_t* vertices = segment.vertices;
			for (size_t i = 0; i < segment.vertexCount; ++i)
			{
				v3i_t vertex = vertices[i];
				if (!i)
					[outline moveToPoint: v3iToCGPoint(vertex)];
				else
					[outline lineToPoint: v3iToCGPoint(vertex)];
			}
		}
		
		[openPaths addObject: outline];
		
	}

	
	
	[self setNeedsDisplay: YES];
}

- (BOOL) becomeFirstResponder
{
	return YES;
}

- (BOOL) acceptsFirstResponder
{
	return YES;
}

- (CGRect) contentRect
{
	NSRect outlineRect = NSMakeRect(INFINITY, INFINITY, -INFINITY, -INFINITY);
	for (NSBezierPath* outlinePath in outlinePaths)
	{
		NSRect bounds = outlinePath.bounds;
		outlineRect = CGRectUnion(outlineRect, bounds);
	}
	
	for (NSBezierPath* outlinePath in openPaths)
	{
		NSRect bounds = outlinePath.bounds;
		outlineRect = CGRectUnion(outlineRect, bounds);
	}
	
	return outlineRect;
}

- (NSAffineTransform*) contentTransform
{
	NSAffineTransform* transform = [NSAffineTransform transform];
	
	CGSize boundsSize = self.bounds.size;
	boundsSize.width -= 5.0f;
	boundsSize.height -= 5.0f;
	
	CGRect outlineRect = [self contentRect];
	
	float scale = CGSizeFitScaleFactor(outlineRect.size, boundsSize);
	if (scale != 0.0)
	{
		assert(scale);
		
		[transform translateXBy: CGRectGetMidX(self.bounds) - scale*CGRectGetMidX(outlineRect) yBy: CGRectGetMidY(self.bounds) - scale*CGRectGetMidY(outlineRect)];
		[transform scaleBy: scale];
	}
	return transform;
}

- (void)drawRect:(NSRect)dirtyRect
{
	[[NSColor blackColor] set];
	NSRectFill(dirtyRect);
	
	if (!outlinePaths.count && !openPaths.count)
		return;

	NSAffineTransform* transform = [self contentTransform];
	
	NSGraphicsContext* ctx = [NSGraphicsContext currentContext];
	[ctx saveGraphicsState];
		
	float scale = transform.transformStruct.m11;
	assert(scale);

	BOOL displayOutline = [[self.window.windowController displayOptionsControl] isSelectedForSegment: 0];
	BOOL displayMotorcycles = [[self.window.windowController displayOptionsControl] isSelectedForSegment: 1];
	BOOL displaySpokes = [[self.window.windowController displayOptionsControl] isSelectedForSegment: 2];
	BOOL displayWavefronts = [[self.window.windowController displayOptionsControl] isSelectedForSegment: 3];
	BOOL displayThinWalls = [[self.window.windowController displayOptionsControl] isSelectedForSegment: 4];

	[transform concat];
	
	if (displayOutline)
	{
		NSInteger k = 0;
		for (NSBezierPath* outlinePath in outlinePaths)
		{
			if (k++ == self.indexOfSelectedOutline)
				[[[NSColor yellowColor] colorWithAlphaComponent: 1.0] set];
			else
				[[[NSColor yellowColor] colorWithAlphaComponent: 0.2] set];
			
			[outlinePath setLineWidth: 1.0/scale];
			[outlinePath stroke];
		}
		for (NSBezierPath* path in openPaths)
		{
			[[[NSColor redColor] colorWithAlphaComponent: 0.5] set];
			
			[path setLineWidth: 1.0/scale];
			[path stroke];
		}
	}
	if (displayMotorcycles)
		for (NSBezierPath* path in motorcyclePaths)
		{
			[[[NSColor blueColor] colorWithAlphaComponent: 1.0] set];
			
			[path setLineWidth: 1.0/scale];
			[path stroke];
		}
	if (displaySpokes)
		for (NSBezierPath* path in spokePaths)
		{
			[[[NSColor redColor] colorWithAlphaComponent: 1.0] set];
			
			[path setLineWidth: 1.0/scale];
			[path stroke];
		}
	
	if (displayWavefronts)
	{
		for (NSBezierPath* path in offsetPaths)
		{
			[[[NSColor grayColor] colorWithAlphaComponent: 1.0] set];
			
			[path setLineWidth: 1.0/scale];
			[path stroke];
		}
		for (NSBezierPath* path in offsetBoundaryPaths)
		{
			[[[NSColor grayColor] colorWithAlphaComponent: 0.5] set];
			
			[path setLineWidth: 1.0/scale];
			[path stroke];
		}
	}
	if (displayThinWalls)
	{
		for (NSBezierPath* path in underfillPaths)
		{
			[[[NSColor greenColor] colorWithAlphaComponent: 0.4] set];
			
			[path setLineWidth: 0.5/scale];
			[path fill];
			[path stroke];
		}
		for (NSBezierPath* path in overfillPaths)
		{
			[[[NSColor orangeColor] colorWithAlphaComponent: 0.4] set];
			
			[path setLineWidth: 0.5/scale];
			[path fill];
			[path stroke];
		}
	}
	[[NSColor whiteColor] set];
	
	[NSBezierPath setDefaultLineWidth: 1.0/scale];
	[NSBezierPath strokeLineFromPoint: CGPointAdd(self.cursor, CGPointMake(0.0,-10.0)) toPoint: CGPointAdd(self.cursor,  CGPointMake(0.0, -1.0))];
	[NSBezierPath strokeLineFromPoint: CGPointAdd(self.cursor, CGPointMake(0.0, 10.0)) toPoint: CGPointAdd(self.cursor,  CGPointMake(0.0,  1.0))];
	[NSBezierPath strokeLineFromPoint: CGPointAdd(self.cursor, CGPointMake(-10.0,0.0)) toPoint: CGPointAdd(self.cursor,  CGPointMake(-1.0, 0.0))];
	[NSBezierPath strokeLineFromPoint: CGPointAdd(self.cursor, CGPointMake( 10.0,0.0)) toPoint: CGPointAdd(self.cursor,  CGPointMake(1.0, 0.0))];

	
	if (clippingOutline)
	{
		NSBezierPath* path = [clippingOutline.outline bezierPath];
		[[[NSColor whiteColor] colorWithAlphaComponent: 1.0] set];
		
		[path setLineWidth: 1.0/scale];
		[path stroke];
	}
	
	
	
	[transform invert];
	[transform concat];
	
	[ctx restoreGraphicsState];

}

- (CGPoint) convertPointToSlice: (CGPoint) aPoint
{
	CGPoint point = [self convertPoint: aPoint fromView: nil];

	NSAffineTransform* contentTransform = [self contentTransform];
	[contentTransform invert];
	return [contentTransform transformPoint: point];

}

- (void) mouseDown: (NSEvent *)theEvent
{
	CGPoint point = [self convertPointToSlice: [theEvent locationInWindow]];
		
	self.cursor = point;
	
	mouseDownLocationInSlice = point;
	mouseDragLocationInSlice = point;
	mouseUpLocationInSlice = point;
	
	NSLog(@"cursor at %f,%f", point.x, point.y);
	
	[self setNeedsDisplay: YES];
}

- (SlicedOutline*) generateClippingOutline
{
	SlicedLineSegment* segment = [self clippingSegment];
	if (!segment)
		return nil;
	SlicedOutline* outline = [[SlicedOutline alloc] init];
	outline.outline = segment;
	return outline;
}

- (SlicedLineSegment*) clippingSegment
{
	v3i_t a = v3iCreateFromFloat(mouseDownLocationInSlice.x, mouseDownLocationInSlice.y, 0.0, 16);
	v3i_t b = v3iCreateFromFloat(mouseDragLocationInSlice.x, mouseDragLocationInSlice.y, 0.0, 16);
	
	if (v3iEqual(a, b))
		return nil;
	if ((a.x == b.x) || (a.y == b.y))
		return nil;

	v3i_t min = v3iMin(a, b);
	v3i_t max = v3iMax(a, b);
	
	v3i_t delta = v3iSub(max, min);
	v3i_t dx = delta;
	v3i_t dy = delta;
	dx.y = 0;
	dy.x = 0;
	
	v3i_t p[4] = {min, v3iAdd(min, dx), max, v3iAdd(min, dy)};
	
	
	SlicedLineSegment* segment = [[SlicedLineSegment alloc] init];
	
	[segment addVertices: p count: 4];
	
	[segment closePolygonWithoutMergingEndpoints];
	
	[segment analyzeSegment];
	
	
	return segment;
}

- (void) mouseDragged: (NSEvent *)theEvent
{
	CGPoint point = [self convertPointToSlice: [theEvent locationInWindow]];
	
	mouseDragLocationInSlice = point;
	
	
	clippingOutline = [self generateClippingOutline];
	
	[self setNeedsDisplay: YES];
}

- (void) mouseUp: (NSEvent *)theEvent
{
	CGPoint point = [self convertPointToSlice: [theEvent locationInWindow]];
	
	mouseUpLocationInSlice = point;
	
	clippingOutline = [self generateClippingOutline];
	
	[self setNeedsDisplay: YES];
}


@end
