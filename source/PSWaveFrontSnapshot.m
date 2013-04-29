//
//  PSWavefrontSnapshot.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 28.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "PSWaveFrontSnapshot.h"
#import "PolygonSkeletizerObjects.h"

@implementation PSWaveFrontSnapshot

@synthesize loops;

- (void) setLoops:(NSArray *)inLoops
{
	NSMutableDictionary* vertexDict = [NSMutableDictionary dictionary];
	
	// need to replace all wavefronts with wavefront segments
	loops = [inLoops map: ^id(NSArray* inLoop) {
		return [inLoop map: ^id(PSWaveFront* waveFront) {
			PSWaveFrontSegment* segment = [[PSWaveFrontSegment alloc] init];
			segment.waveFront = waveFront;
			
			PSSpoke* leftSpoke = waveFront.leftSpoke;
			PSSpoke* rightSpoke = waveFront.rightSpoke;
			
			PSVertex* leftVertex = [vertexDict objectForKey: [NSValue valueWithPointer: (__bridge void*)leftSpoke]];
			PSVertex* rightVertex = [vertexDict objectForKey: [NSValue valueWithPointer: (__bridge void*)rightSpoke]];
			
			if (!leftVertex)
			{
				leftVertex = [[PSVertex alloc] init];
				leftVertex.time = self.time;
				leftVertex.position = [leftSpoke positionAtTime: self.time];
				[vertexDict setObject: leftVertex forKey: [NSValue valueWithPointer: (__bridge void*)leftSpoke]];
			}
			if (!rightVertex)
			{
				rightVertex = [[PSVertex alloc] init];
				rightVertex.time = self.time;
				rightVertex.position = [rightSpoke positionAtTime: self.time];
				[vertexDict setObject: rightVertex forKey: [NSValue valueWithPointer: (__bridge void*)rightSpoke]];
			}
			
			segment.leftVertex = leftVertex;
			segment.rightVertex = rightVertex;
			
			
			return segment;
		}];
	}];
	
}

- (NSBezierPath*) waveFrontPath
{
	NSBezierPath* bpath = [NSBezierPath bezierPath];
	
	for (NSArray* loop in loops)
	{
		BOOL firstSegment = YES;
		for (PSWaveFrontSegment* segment in loop)
		{
			if (firstSegment)
				[bpath moveToPoint: CGPointMake(segment.leftVertex.position.farr[0], segment.leftVertex.position.farr[1])];
			else
				[bpath lineToPoint: CGPointMake(segment.leftVertex.position.farr[0], segment.leftVertex.position.farr[1])];
			firstSegment = NO;
		}
		[bpath closePath];
	}
	
	return bpath;
}

@end


@implementation PSWaveFrontSegment



@end