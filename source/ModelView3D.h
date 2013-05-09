//
//  ModelView3D.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 20.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import "GLBaseView.h"


@interface ModelView3D : GLBaseView

@property(strong) NSArray* models;
@property(strong) NSDictionary* layers;

@property(nonatomic,strong) IBOutlet NSSegmentedControl* modelViewScrollModeControl;

- (void) generateMovePathWithMachineCommands:(NSArray *)commands;

@end
