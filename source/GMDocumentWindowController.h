//
//  GMDocumentWindowController.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 15.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PathView2D, ModelView3D;

@interface GMDocumentWindowController : NSWindowController

@property(strong) IBOutlet NSTextView* statusTextView;
@property(strong) IBOutlet PathView2D* pathView;
@property(strong) IBOutlet ModelView3D* modelView;


@end
