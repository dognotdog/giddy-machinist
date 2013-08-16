//
//  GMDocumentWindowController.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 15.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PathView2D, ModelView3D, LayerInspectorView;

@interface GMDocumentWindowController : NSWindowController

@property(strong) IBOutlet NSTextView* statusTextView;
@property(strong) IBOutlet PathView2D* pathView;
@property(strong) IBOutlet ModelView3D* modelView;

@property(nonatomic,strong) IBOutlet NSPopUpButton* layerSelector;
@property(nonatomic,strong) IBOutlet NSPopUpButton* outlineSelector;
@property(nonatomic,strong) IBOutlet LayerInspectorView* layerView;
@property(nonatomic,strong) IBOutlet NSButton* resetButton;
@property(nonatomic,strong) IBOutlet NSButton* stepButton;
@property(nonatomic,strong) IBOutlet NSSegmentedControl* displayOptionsControl;
@property(nonatomic,strong) IBOutlet NSTextField* extensionLimitField;
@property(nonatomic,strong) IBOutlet NSTextField* wavePhaseNumberField;
@property(nonatomic,strong) IBOutlet NSSlider* wavePhaseNumberSlider;

@property(nonatomic,strong) IBOutlet NSProgressIndicator* progressIndicator;

@property(nonatomic) NSUInteger displayWaveFrontPhaseNumber;
@property(nonatomic, readonly) NSUInteger waveFrontPhaseCount;


- (IBAction) layerSelected: (id) sender;
- (IBAction) outlineSelected: (id) sender;
- (IBAction) displayOptionsChanged: (id) sender;
- (IBAction) runSlicing: (id) sender;

@end
