//
//  RS274Interpreter.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 01.09.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RS274Interpreter : NSObject

@property(nonatomic,readonly) NSArray* machineCommands;

- (void) interpretCommandBlocks: (NSArray*) commandBlocks;

- (id) interpretCommandBlock: (NSArray*) commands;

@end


@interface GMachineCommand : NSObject

@end

@interface GMachineCommandMove : GMachineCommand

- (id) initWithSpeed: (double) speed x: (double) x y: (double) y z: (double) z a: (double) a b: (double) b c: (double) c;

@property(nonatomic) double speed;
@property(nonatomic) double xTarget;
@property(nonatomic) double yTarget;
@property(nonatomic) double zTarget;
@property(nonatomic) double aTarget;
@property(nonatomic) double bTarget;
@property(nonatomic) double cTarget;

@end

