//
//  Document.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 31.08.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class GMDocumentWindowController,GM3DPrintSettings;

@interface GMDocument : NSDocument

@property(nonatomic, strong) GMDocumentWindowController*  mainWindowController;

@property(nonatomic, strong, readonly) NSArray* slicedLayers;
@property(nonatomic, strong, readonly) NSArray* contourPolygons;

@property(nonatomic, strong) GM3DPrintSettings* printSettings;

- (IBAction) importGCode: (id) sender;

@end
