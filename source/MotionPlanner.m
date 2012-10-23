//
//  MotionPlanner.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 30.09.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import "MotionPlanner.h"

@implementation MotionPlanner
{
	
}

@synthesize accelerationLimitTable, stepsPerUnitTable, backlashTable, speedLimitTable, autoArcLimitSteps, ticksPerSecond;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	accelerationLimitTable = [NSArray arrayWithObjects:
						 @1.0,
						 @1.0,
						 @1.0,
						 @1.0,
						 @1.0,
						 @1.0,
						 nil];
	speedLimitTable = [NSArray arrayWithObjects:
						 @50.0,
						 @50.0,
						 @1.0,
						 @1.0,
						 @1.0,
						 @1.0,
						 nil];
	stepsPerUnitTable = [NSArray arrayWithObjects:
						 @76.5,
						 @76.5,
						 @2560.0,
						 @169.0,
						 @1.0,
						 @1.0,
						 nil];
	backlashTable = [NSArray arrayWithObjects:
						 @0.1,
						 @0.2,
						 @0,
						 @0,
						 @0,
						 @0,
						 nil];

	ticksPerSecond = 10000;
	autoArcLimitSteps = 16;
	
	return self;
}

- (void) processMachineCommands: (NSArray*) commands
{
	
}

@end
