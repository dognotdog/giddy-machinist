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
	NSMutableArray* openPaths;
	NSArray* motorcyclePaths;
}

@synthesize slice, indexOfSelectedOutline, motorcyclePaths, spokePaths, outlinePaths, thinWallPaths;

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

- (void) removeAllOffsetOutlinePaths
{
	[offsetPaths removeAllObjects];
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
	motorcyclePaths = @[];
	spokePaths = @[];
	thinWallPaths = @[];
	
	for (SlicedOutline* path in slice.outlinePaths)
	{
		NSBezierPath* outline = [NSBezierPath bezierPath];
		NSArray* segments = [path allNestedPaths];
		for (SlicedLineSegment* segment in segments)
		{
			vector_t* vertices = segment.vertices;
			for (size_t i = 0; i < segment.vertexCount; ++i)
			{
				vector_t vertex = vertices[i];
				if (!i)
					[outline moveToPoint: NSMakePoint(vertex.farr[0], vertex.farr[1])];
				else
					[outline lineToPoint: NSMakePoint(vertex.farr[0], vertex.farr[1])];
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
			vector_t* vertices = segment.vertices;
			for (size_t i = 0; i < segment.vertexCount; ++i)
			{
				vector_t vertex = vertices[i];
				if (!i)
					[outline moveToPoint: NSMakePoint(vertex.farr[0], vertex.farr[1])];
				else
					[outline lineToPoint: NSMakePoint(vertex.farr[0], vertex.farr[1])];
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
	
	
	[transform translateXBy: CGRectGetMidX(self.bounds) - scale*CGRectGetMidX(outlineRect) yBy: CGRectGetMidY(self.bounds) - scale*CGRectGetMidY(outlineRect)];
	[transform scaleBy: scale];

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
		for (NSBezierPath* path in offsetPaths)
		{
			[[[NSColor grayColor] colorWithAlphaComponent: 1.0] set];
			
			[path setLineWidth: 1.0/scale];
			[path stroke];
		}
	if (displayThinWalls)
		for (NSBezierPath* path in thinWallPaths)
		{
			[[[NSColor greenColor] colorWithAlphaComponent: 0.8] set];
			
			[path setLineWidth: 1.0/scale];
			[path fill];
			[path stroke];
		}
	
	[[NSColor whiteColor] set];
	
	[NSBezierPath setDefaultLineWidth: 1.0/scale];
	[NSBezierPath strokeLineFromPoint: CGPointAdd(self.cursor, CGPointMake(0.0,-10.0)) toPoint: CGPointAdd(self.cursor,  CGPointMake(0.0, -1.0))];
	[NSBezierPath strokeLineFromPoint: CGPointAdd(self.cursor, CGPointMake(0.0, 10.0)) toPoint: CGPointAdd(self.cursor,  CGPointMake(0.0,  1.0))];
	[NSBezierPath strokeLineFromPoint: CGPointAdd(self.cursor, CGPointMake(-10.0,0.0)) toPoint: CGPointAdd(self.cursor,  CGPointMake(-1.0, 0.0))];
	[NSBezierPath strokeLineFromPoint: CGPointAdd(self.cursor, CGPointMake( 10.0,0.0)) toPoint: CGPointAdd(self.cursor,  CGPointMake(1.0, 0.0))];

	[transform invert];
	[transform concat];
	
	[ctx restoreGraphicsState];

}

- (void) mouseDown:(NSEvent *)theEvent
{
	CGPoint point = [self convertPoint: [theEvent locationInWindow] fromView: nil];
	
	NSAffineTransform* contentTransform = [self contentTransform];
	[contentTransform invert];
	point = [contentTransform transformPoint: point];
	
	self.cursor = point;
	
	NSLog(@"cursor at %f,%f", point.x, point.y);
	
	[self setNeedsDisplay: YES];
}


@end
