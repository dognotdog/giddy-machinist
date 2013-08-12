//
//  PSWavefrontSnapshot.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 28.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "PSWaveFrontSnapshot.h"
#import "PolygonSkeletizerObjects.h"
#import "MPInteger.h"

#import "FoundationExtensions.h"

@implementation PSWaveFrontSnapshot

@synthesize loops;

- (void) setLoops:(NSArray *)inLoops
{
	NSMutableDictionary* vertexDict = [NSMutableDictionary dictionary];
	
	// need to replace all wavefronts with wavefront segments
	loops = [inLoops map: ^id(NSArray* inLoop) {
		return [inLoop map: ^id(PSWaveFront* waveFront) {
			PSWaveFrontSegment* segment = [[PSWaveFrontSegment alloc] init];
			segment.waveFronts = @[waveFront];
			segment.time = self.time;
			
			PSSpoke* leftSpoke = waveFront.leftSpoke;
			PSSpoke* rightSpoke = waveFront.rightSpoke;
			
			PSRealVertex* leftVertex = [vertexDict objectForKey: [NSValue valueWithPointer: (__bridge void*)leftSpoke]];
			PSRealVertex* rightVertex = [vertexDict objectForKey: [NSValue valueWithPointer: (__bridge void*)rightSpoke]];
			
			if (!leftVertex)
			{
				leftVertex = [[PSRealVertex alloc] init];
				leftVertex.position = [leftSpoke positionAtTime: self.time];
				[vertexDict setObject: leftVertex forKey: [NSValue valueWithPointer: (__bridge void*)leftSpoke]];
			}
			if (!rightVertex)
			{
				rightVertex = [[PSRealVertex alloc] init];
				rightVertex.position = [rightSpoke positionAtTime: self.time];
				[vertexDict setObject: rightVertex forKey: [NSValue valueWithPointer: (__bridge void*)rightSpoke]];
			}
			
			segment.leftVertex = leftVertex;
			segment.rightVertex = rightVertex;
			
			
			return segment;
		}];
	}];
	
	// link up segments
	for (NSArray* loop in loops)
	{
		for (size_t i = 0; i < loop.count; ++i)
		{
			PSWaveFrontSegment* s0 = [loop objectAtIndex: i];
			PSWaveFrontSegment* s1 = [loop objectAtIndex: (i+1) % loop.count];
			s0.rightSegment = s1;
			s1.leftSegment = s0;
		}
	}
	
	// merge sections across non-bisecting spokes
/*
	loops = [loops map: ^id(NSMutableArray* inLoop) {
		inLoop = [inLoop mutableCopy];
		for (size_t i = 0; i < inLoop.count; ++i)
		{
			PSWaveFrontSegment* s0 = [inLoop objectAtIndex: i];
			PSWaveFrontSegment* s1 = [inLoop objectAtIndex: (i+1) % inLoop.count];

			assert([[s0.waveFronts lastObject] rightSpoke].rightWaveFront == [s1.waveFronts objectAtIndex: 0]);
			
			if (v3Equal([[s0.waveFronts lastObject] direction], [[s1.waveFronts objectAtIndex: 0] direction]))
			{
				s0.waveFronts = [s0.waveFronts arrayByAddingObjectsFromArray: s1.waveFronts];
				s0.rightSegment = s1.rightSegment;
				s0.rightVertex = s1.rightVertex;
				
				s0.rightSegment.leftSegment = s0;
				
				[inLoop removeObjectAtIndex: (i+1) % inLoop.count];
				i--;
			}
			
		}
		return inLoop;
	}];
*/
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
				[bpath moveToPoint: v3iToCGPoint(segment.leftVertex.position)];
			else
				[bpath lineToPoint: v3iToCGPoint(segment.leftVertex.position)];
			firstSegment = NO;
		}
		[bpath closePath];
	}
	
	return bpath;
}

- (NSBezierPath*) thinWallAreaLessThanWidth: (double) _width
{
	MPDecimal* width = [[MPDecimal alloc] initWithDouble: _width];
	NSBezierPath* bpath = [NSBezierPath bezierPath];
	
	MPDecimal* timeSqr = [self.time mul: self.time];
	
	for (NSArray* loop in loops)
	{
		NSMutableArray* thinWaveFronts = [NSMutableArray array];
		
		for (PSWaveFrontSegment* segment in loop)
		{
			if ([segment.finalTerminationTime compare: [self.time add: width]] < 0)
			{
				[thinWaveFronts addObject: segment];
			}
		}
		
		for (PSWaveFrontSegment* segment in thinWaveFronts)
		{
			NSMutableArray* vertices = [NSMutableArray arrayWithObject: segment.rightVertex];
			
			NSArray* leftSpokes = [[[segment.waveFronts objectAtIndex: 0] retiredLeftSpokes] arrayByAddingObject: [[segment.waveFronts objectAtIndex: 0] leftSpoke]];
			NSArray* rightSpokes = [[[segment.waveFronts lastObject] retiredRightSpokes] arrayByAddingObject: [[segment.waveFronts lastObject] rightSpoke]];
			
			//asserts regarding issue #2
			if (0) {
				NSArray* spokes = leftSpokes;
				for (size_t i = 0; i+1 < spokes.count; ++i)
				{
					PSSpoke* spoke0 = [spokes objectAtIndex: i];
					PSSpoke* spoke1 = [spokes objectAtIndex: i+1];
					assert(v3iEqual(spoke0.endLocation, spoke1.startLocation));
				}
			}
			if (0) {
				NSArray* spokes = rightSpokes;
				for (size_t i = 0; i+1 < spokes.count; ++i)
				{
					PSSpoke* spoke0 = [spokes objectAtIndex: i];
					PSSpoke* spoke1 = [spokes objectAtIndex: i+1];
					assert(v3iEqual(spoke0.endLocation, spoke1.startLocation));
				}
			}
			
			
			
			for (PSSpoke* spoke in rightSpokes)
			{
				assert(spoke.terminationTimeSqr);
				if ([spoke.terminationTimeSqr compare: timeSqr] > 0)
					[vertices addObject: spoke.terminalVertex];
			}
			for (PSSpoke* spoke in [leftSpokes reverseObjectEnumerator])
			{
				assert(spoke.startTimeSqr);
				if ([spoke.startTimeSqr compare: timeSqr] > 0)
					[vertices addObject: [PSRealVertex vertexAtPosition: spoke.startLocation]];
			}
			[vertices addObject: segment.leftVertex];
			
			for (size_t i = 0; i < vertices.count; ++i)
			{
				v3i_t pos = [(PSRealVertex*)[vertices objectAtIndex: i] position];
				if (i == 0)
					[bpath moveToPoint: v3iToCGPoint(pos)];
				else
					[bpath lineToPoint: v3iToCGPoint(pos)];

			}
			
			[bpath closePath];
		}		

	}
	
	return bpath;
}

@end


@implementation PSWaveFrontSegment

@synthesize waveFronts;

- (MPDecimal*) finalTerminationTime
{
	MPDecimal* t = [[MPDecimal alloc] initWithInt64: 0 shift: 0];
	
	for (PSWaveFront* waveFront in waveFronts)
	{
		assert(waveFront.terminationTimeSqr);
		t = [t max: waveFront.terminationTimeSqr.sqrt];
	}
	return t;
}

@end