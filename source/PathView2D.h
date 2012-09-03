//
//  PathView2D.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 03.09.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PathView2D : NSView

- (void) resetPaths;
- (void) generatePathsWithMachineCommands: (NSArray*) commands;

@end
