//
//  RS274Interpreter.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 01.09.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import "RS274Interpreter.h"

#import "RS274Parser.h"

#import "FoundationExtensions.h"

enum
{
	kRS274InputUnitMilliMeter,
	kRS274InputUnitInch,
	kRS274MotionModeRapid,
	kRS274MotionModeFeed,
};




@implementation RS274Interpreter
{
	long			modalInputUnit, modalMotionMode;

	NSMutableArray* machineParameters;
	
	double xAxis, yAxis, zAxis, aAxis, bAxis, cAxis;
	double fastFeedRate, feedRate;
	
	NSMutableArray* machineCommands;
}

@synthesize machineCommands;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	modalInputUnit = kRS274InputUnitMilliMeter;
	modalMotionMode = kRS274MotionModeRapid;
	
	machineParameters = [[NSMutableArray alloc] initWithCapacity: 5400];
	
	for (int i = 0; i < 5400; ++i)
	{
		[machineParameters addObject: @0.0];
	}
	
	[machineParameters replaceObjectAtIndex: 5220 withObject: @1.0];
	
	
	machineCommands = [[NSMutableArray alloc] init];

	return self;
}

- (void) interpretCommandBlocks: (NSArray*) commandBlocks;
{
	for (NSArray* commandBlock in commandBlocks)
		[self interpretCommandBlock: commandBlock];
}

- (NSArray*) interpretComments: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretParameterSets: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretFeedRateModeCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretFeedRateCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretSpindleSpeedCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretSelectToolCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretChangeToolCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretSpindleCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretCoolantCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretOverrideCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretDwellCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretActivePlaneCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretLengthUnitCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretRadiusCompensationCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretLengthCompensationCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretCoordinateSystemSelectionCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretPathControlModeCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretDistanceModeCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretRetractModeCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretHomeCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretCoordinateSystemChangeCommands: (NSArray*) commands
{
	return commands;
}

- (NSArray*) interpretAxisOffsetCommands: (NSArray*) commands
{
	return commands;
}


- (NSArray*) interpretModalMotionCommands: (NSArray*) commands
{
	while (1)
	{
		long i = 0;
		for (id obj in commands)
		{
			if ([obj isKindOfClass: [RS274Command class]])
			{
				RS274Command* cmd = obj;
				if ((cmd.commandLetter == 'G') && ([cmd.value isEqual: @0] || [cmd.value isEqual: @1]))
					break;
			}
			++i;
		}
		
		if (i >= [commands count])
			break;
		
		long cmdIndex = i;
		
		
		long whichCommand = [[[commands objectAtIndex: cmdIndex] value] integerValue];
	
		
		switch (whichCommand) {
			case 0:
				modalMotionMode = kRS274MotionModeRapid;
				break;
			case 1:
				modalMotionMode = kRS274MotionModeFeed;
				break;
				
			default:
				break;
		}
		
		
		commands = [commands arrayByRemovingObjectsAtIndexes: [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(cmdIndex, 1)]];
		
	}
	return commands;

}

- (void) dispatchMotionCommand
{
	double speed = 0.0;
	
	switch (modalMotionMode) {
		case kRS274MotionModeRapid:
			speed = fastFeedRate;
			break;
		case kRS274MotionModeFeed:
			speed = feedRate;
			break;
			
		default:
			break;
	}
	
	GMachineCommandMove* cmd = [[GMachineCommandMove alloc] initWithSpeed: speed x: xAxis y: yAxis z: zAxis a: aAxis b: bAxis c: cAxis];
	[machineCommands addObject: cmd];
	

}


- (NSArray*) interpretMotionTargetCommands: (NSArray*) commands
{
	long i = 0;
	BOOL motionTargetFound = NO;
	while (i < [commands count])
	{
		BOOL removeCommand = YES;
		id obj = [commands objectAtIndex: i];
		if ([obj isKindOfClass: [RS274Command class]])
		{
			int cmdLetter = [obj commandLetter];
			double value = [[obj value] doubleValue];
			switch (cmdLetter)
			{
				case 'A':
					aAxis = value;
					break;
				case 'B':
					bAxis = value;
					break;
				case 'C':
					cAxis = value;
					break;
				case 'X':
					xAxis = value;
					break;
				case 'Y':
					yAxis = value;
					break;
				case 'Z':
					zAxis = value;
					break;
				default:
					removeCommand = NO;
					break;
			}
		}
		else
			removeCommand = NO;
		
		if (removeCommand)
		{
			motionTargetFound = YES;
			commands = [commands arrayByRemovingObjectsAtIndexes: [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(i, 1)]];

		}
		else
			++i;
	}
	
	if (motionTargetFound)
		[self dispatchMotionCommand];
	

	
	return commands;

}

- (NSArray*) interpretMotionCommands: (NSArray*) commands
{
	commands = [self interpretModalMotionCommands: commands];
	commands = [self interpretMotionTargetCommands: commands];
	return commands;
}

- (NSArray*) interpretStopCommands: (NSArray*) commands
{
	return commands;
}



- (id) interpretCommandBlock: (NSArray*) commands
{
	
	commands = [self interpretComments: commands];
	commands = [self interpretParameterSets: commands];
	commands = [self interpretFeedRateModeCommands: commands];
	commands = [self interpretFeedRateCommands: commands];
	commands = [self interpretSpindleSpeedCommands: commands];
	commands = [self interpretSelectToolCommands: commands];
	commands = [self interpretChangeToolCommands: commands];
	commands = [self interpretSpindleCommands: commands];
	commands = [self interpretCoolantCommands: commands];
	commands = [self interpretOverrideCommands: commands];
	commands = [self interpretDwellCommands: commands];
	commands = [self interpretActivePlaneCommands: commands];
	commands = [self interpretLengthUnitCommands: commands];
	commands = [self interpretRadiusCompensationCommands: commands];
	commands = [self interpretLengthCompensationCommands: commands];
	commands = [self interpretCoordinateSystemSelectionCommands: commands];
	commands = [self interpretPathControlModeCommands: commands];
	commands = [self interpretDistanceModeCommands: commands];
	commands = [self interpretRetractModeCommands: commands];
	commands = [self interpretHomeCommands: commands];
	commands = [self interpretCoordinateSystemChangeCommands: commands];
	commands = [self interpretAxisOffsetCommands: commands];
	commands = [self interpretMotionCommands: commands];
	commands = [self interpretStopCommands: commands];

	return nil;
}

@end



@implementation GMachineCommand

@end

@implementation GMachineCommandMove

@synthesize xTarget,yTarget,zTarget,aTarget,bTarget,cTarget,speed;

- (id) initWithSpeed:(double)s x:(double)x y:(double)y z:(double)z a:(double)a b:(double)b c:(double)c
{
	if (!(self = [super init]))
		return nil;
	
	speed = s;
	xTarget = x;
	yTarget = y;
	zTarget = z;
	aTarget = a;
	bTarget = b;
	cTarget = c;
	
	
	return self;
}

@end

