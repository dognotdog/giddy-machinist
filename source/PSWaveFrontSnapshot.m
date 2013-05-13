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
			segment.time = self.time;
			
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

- (NSBezierPath*) thinWallAreaLessThanWidth: (double) width
{
	NSBezierPath* bpath = [NSBezierPath bezierPath];
	
	for (NSArray* loop in loops)
	{
		NSMutableArray* thinWaveFronts = [NSMutableArray array];
		
		for (PSWaveFrontSegment* segment in loop)
		{
			if (segment.waveFront.terminationTime < self.time+width)
			{
				[thinWaveFronts addObject: segment];
			}
		}
		
		for (PSWaveFrontSegment* segment in thinWaveFronts)
		{
			NSMutableArray* vertices = [NSMutableArray arrayWithObject: segment.rightVertex];
			
			//FIXME: regarding issue #2
			{
				NSArray* spokes = segment.waveFront.retiredLeftSpokes;
				for (size_t i = 0; i+1 < spokes.count; ++i)
				{
					PSSpoke* spoke0 = [spokes objectAtIndex: i];
					PSSpoke* spoke1 = [spokes objectAtIndex: i+1];
					assert(spoke0.terminalVertex == spoke1.sourceVertex);
				}
			}
			{
				NSArray* spokes = segment.waveFront.retiredRightSpokes;
				for (size_t i = 0; i+1 < spokes.count; ++i)
				{
					PSSpoke* spoke0 = [spokes objectAtIndex: i];
					PSSpoke* spoke1 = [spokes objectAtIndex: i+1];
					assert(spoke0.terminalVertex == spoke1.sourceVertex);
				}
			}
			
			
			
			for (PSSpoke* spoke in segment.waveFront.retiredRightSpokes)
			{
				assert(spoke.terminationTime < INFINITY);
				if (spoke.terminationTime > self.time)
					[vertices addObject: spoke.terminalVertex];
			}
			for (PSSpoke* spoke in [segment.waveFront.retiredLeftSpokes reverseObjectEnumerator])
			{
				
				if (spoke.start > self.time)
					[vertices addObject: spoke.sourceVertex];
			}
			[vertices addObject: segment.leftVertex];
			
			for (size_t i = 0; i < vertices.count; ++i)
			{
				vector_t pos = [(PSVertex*)[vertices objectAtIndex: i] position];
				if (i == 0)
					[bpath moveToPoint: CGPointMake(pos.farr[0], pos.farr[1])];
				else
					[bpath lineToPoint: CGPointMake(pos.farr[0], pos.farr[1])];

			}
			
			[bpath closePath];
		}		

	}
	
	return bpath;
}

@end


@implementation PSWaveFrontSegment



@end