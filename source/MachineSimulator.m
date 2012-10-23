//
//  MachineSimulator.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 30.09.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import "MachineSimulator.h"
#import "MotionPlanner.h"

void ResumeStepperInterrupt(void)
{
	
}

void SuspendStepperInterrupt(void)
{
	
}


@implementation MachineSimulator
{
	MotionPlanner* planner;
}

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	planner = [[MotionPlanner alloc] init];
	
	return self;
}

- (void) update:(double)dt
{
	
}

- (void) executeCommandsAsync: (NSArray*) commands
{
	
}
@end
