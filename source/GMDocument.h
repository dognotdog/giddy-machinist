//
//  Document.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 31.08.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PathView2D, ModelView3D;

@interface GMDocument : NSDocument

@property(strong) IBOutlet NSTextView* statusTextView;
@property(strong) IBOutlet PathView2D* pathView;
@property(strong) IBOutlet ModelView3D* modelView;

- (IBAction) importGCode: (id) sender;

@end
