//
//  GMDocumentWindowController.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 15.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "GMDocumentWindowController.h"

#import "LayerInspectorWindowController.h"
#import "PathView2D.h"
#import "ModelView3D.h"
#import "Slicer.h"

#import "FoundationExtensions.h"

@interface GMDocumentWindowController ()

@end

@implementation GMDocumentWindowController

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
	
}

- (void) windowDidBecomeMain: (NSNotification*) notification
{
	LayerInspectorWindowController* inspector = [LayerInspectorWindowController sharedInspector];
	[self.document addWindowController: inspector];
}

- (void) layerDidLoad: (SlicedLayer*) layer
{
	self.modelView.layers = [self.modelView.layers dictionaryBySettingObject: [layer layerMesh] forKey: [NSNumber numberWithDouble: layer.layerZ]];
	
}

@end
