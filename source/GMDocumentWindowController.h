//
//  GMDocumentWindowController.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 15.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PathView2D, ModelView3D, LayerInspectorView, GMDocument, GfxNode;

@interface GMDocumentWindowController : NSWindowController <NSSplitViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate>

@property(nonatomic,strong) IBOutlet id tmpNavOutlineRowView;


@property(nonatomic,strong) IBOutlet NSTextView* statusTextView;
@property(nonatomic,strong) IBOutlet PathView2D* pathView;
@property(nonatomic,strong) IBOutlet ModelView3D* modelView;

@property(nonatomic,strong) IBOutlet NSPopUpButton* layerSelector;
@property(nonatomic,strong) IBOutlet NSPopUpButton* outlineSelector;
@property(nonatomic,strong) IBOutlet LayerInspectorView* layerView;
@property(nonatomic,strong) IBOutlet NSButton* resetButton;
@property(nonatomic,strong) IBOutlet NSButton* stepButton;
@property(nonatomic,strong) IBOutlet NSSegmentedControl* displayOptionsControl;
@property(nonatomic,strong) IBOutlet NSTextField* extensionLimitField;
@property(nonatomic,strong) IBOutlet NSTextField* wavePhaseNumberField;
@property(nonatomic,strong) IBOutlet NSSlider* wavePhaseNumberSlider;

@property(nonatomic) NSUInteger displayWaveFrontPhaseNumber;
@property(nonatomic, readonly) NSUInteger waveFrontPhaseCount;

@property(nonatomic,strong) IBOutlet NSProgressIndicator* progressIndicator;

@property(nonatomic,strong) IBOutlet NSSplitView* mainSplitView;
@property(nonatomic,strong) IBOutlet NSOutlineView* navigationView;

@property(nonatomic) GMDocument* document;

- (IBAction) layerSelected: (id) sender;
- (IBAction) outlineSelected: (id) sender;
- (IBAction) displayOptionsChanged: (id) sender;
- (IBAction) runSlicing: (id) sender;

@end
