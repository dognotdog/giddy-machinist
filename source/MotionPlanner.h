//
//  MotionPlanner.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 30.09.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MotionPlanner : NSObject

@property(nonatomic) double autoArcLimitSteps;
@property(nonatomic) long ticksPerSecond;
@property(nonatomic,strong) NSArray* accelerationLimitTable;
@property(nonatomic,strong) NSArray* stepsPerUnitTable;
@property(nonatomic,strong) NSArray* backlashTable;
@property(nonatomic,strong) NSArray* speedLimitTable;

- (void) processMachineCommands: (NSArray*) commands;

@end
