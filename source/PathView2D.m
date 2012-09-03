//
//  PathView2D.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 03.09.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import "PathView2D.h"

#import "RS274Interpreter.h"

#import "VectorMath.h"
#import "CGGeometryExtensions.h"

@implementation PathView2D
{
	NSMutableArray* paths;
	CGRect pathBounds;
	
	CGPoint _pathCursor;
}

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
	[[NSColor blackColor] set];
	NSRectFill(dirtyRect);

	NSAffineTransform* transform = [NSAffineTransform transform];
	CGRect bounds = self.bounds;
	
	[transform translateXBy: pathBounds.origin.x-bounds.origin.x yBy: pathBounds.origin.y-bounds.origin.y];
	[transform scaleXBy: bounds.size.width/pathBounds.size.width yBy: bounds.size.height/pathBounds.size.height];
	
	//[transform concat];

	[[NSColor whiteColor] set];
	
	for (NSBezierPath* path in paths)
	{
		[[transform transformBezierPath: path] stroke];
	}
	
	//[transform invert];
	//[transform concat];
}

- (void) resetPaths
{
	paths = [NSMutableArray array];
	[self setNeedsDisplay: YES];
}

- (void) generatePathsWithMachineCommands:(NSArray *)commands
{
	
	CGPoint maxp = _pathCursor;
	CGPoint minp = _pathCursor;
	
	for (id command in commands)
	{
		if ([command isKindOfClass: [GMachineCommandMove class]])
		{
			NSBezierPath* path = [NSBezierPath bezierPath];
			[path moveToPoint: _pathCursor];
			CGPoint target = CGPointMake([command xTarget], [command yTarget]);
			_pathCursor = target;
			minp = CGPointMin(minp, _pathCursor);
			maxp = CGPointMax(maxp, _pathCursor);
			[path lineToPoint: _pathCursor];
			[paths addObject: path];
		}
	}
	
	pathBounds = CGRectMake(minp.x, minp.y, maxp.x-minp.x, maxp.y-minp.y);
	[self setNeedsDisplay: YES];
}

@end
