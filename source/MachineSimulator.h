//
//  MachineSimulator.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 30.09.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MachineSimulator : NSObject

- (void) executeCommandsAsync: (NSArray*) commands;

@end
