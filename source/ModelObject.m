//
//  ModelObject.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 28.08.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "ModelObject.h"
#import "NSString+MathAndUnits.h"
#import "PolygonContour.h"
#import "GMDocument.h"
#import "gfx.h"
#import "FixPolygon.h"
#import "FoundationExtensions.h"

#import <AppKit/AppKit.h>

@implementation ModelObject
{
	IBOutlet NSTextField* labelField;
	IBOutlet NSProgressIndicator* progressIndicator;
	
	long progressCounter;
}

@synthesize document, objectTransform, navView;

- (instancetype) init
{
	if (!(self = [super init]))
		return nil;
	
	objectTransform = mIdentity();
	
	return self;
}

- (NSView*) navView
{
	if (!navView)
	{
		NSNib* nib = [[NSNib alloc] initWithNibNamed: @"NavigationModelObjectView" bundle: nil];
		[nib instantiateWithOwner: self topLevelObjects: NULL];
		
		progressIndicator.usesThreadedAnimation = YES;
		
	}
	
	labelField.stringValue = self.navLabel;
		
	assert(navView);
	return navView;
}

- (void) asyncProcessStarted
{
	assert(dispatch_get_current_queue() == dispatch_get_main_queue());
	
	if (!progressCounter)
	{
		[self navView]; // call accessor to make sure view is loaded
		assert(progressIndicator);
		
		progressIndicator.hidden = NO;
		[progressIndicator startAnimation: self];
		progressCounter++;
	}
}

- (void) asyncProcessStopped
{
	assert(dispatch_get_current_queue() == dispatch_get_main_queue());
	progressCounter--;
	
	if (!progressCounter)
	{
		[self navView];
		assert(progressIndicator);
		
		[progressIndicator stopAnimation: self];
		progressIndicator.hidden = YES;
		
	}

}

- (NSString*) navLabel
{
	return self.name;
}

- (id) gfx
{
	return [[GfxNode alloc] init];
}

- (void) setObjectTransform:(matrix_t)m
{
	[self willChangeValueForKey: @"objectTransform"];
	
	objectTransform = m;
	
	[self didChangeValueForKey: @"objectTransform"];
	
	[self.document modelObjectChanged: self];
}

+ (GfxNode*) boundingBoxForIntegerRange: (r3i_t) bounds margin: (vector_t) margin
{
	v3i_t origini = bounds.min;
	v3i_t sizei = v3iSub(bounds.max, bounds.min);
	
	vector_t origin = v3Sub(v3iToFloat(origini), margin);
	vector_t size = v3Add(v3iToFloat(sizei), v3MulScalar(margin, 2.0));
	
	matrix_t MT = mTranslationMatrix(origin);
	matrix_t MS = mScaleMatrix(size);
	
	
	matrix_t bias = mTransform(mScaleMatrix(vCreateDir(0.5, 0.5, 0.5)), mTranslationMatrix(vCreateDir(1.0, 1.0, 1.0)));
	
	GfxNode* root = [[GfxNode alloc] init];
	
	GfxTransformNode* transform = [[GfxTransformNode alloc] initWithMatrix: mTransform(MT, mTransform(MS, bias))];
	
	[root addChild: transform];
	
	[root addChild: [GfxMesh cubeLineMesh]];
	
	return root;
}



@end


@implementation ModelObject2D
{
	ModelObjectTransformProxy* transformProxy;
	ModelObjectContourGenerator* createContourProxy;
	ModelObjectGCodeGenerator* gcodeProxy;
	
	dispatch_source_t editCoalesceSource;
	long toolpathInProgress;
	
}

@synthesize sourcePolygon, toolpathPolygon, navSelection;

- (instancetype) init
{
	if (!(self = [super init]))
		return nil;
	
	[self doesNotRecognizeSelector: _cmd];
		
	return self;
}

- (instancetype) initWithBezierPath: (NSBezierPath*) bpath name: (NSString*) name
{
	if (!(self = [super init]))
		return nil;

	editCoalesceSource = dispatch_coalesce_source_create(dispatch_get_main_queue());
	
	self.objectTransform = mIdentity();
	
	self.name = name;
	self.sourceBezierPath = bpath;
	self.sourcePolygon = [FixPolygon polygonFromBezierPath: bpath withTransform: mToAffineTransform(self.objectTransform) flatness: 0.1];
		
	{
		transformProxy = [[ModelObjectTransformProxy alloc] init];
		transformProxy.object = self;
		transformProxy.document = self.document;
	}
	{
		createContourProxy = [[ModelObjectContourGenerator alloc] init];
		createContourProxy.object = self;
		createContourProxy.document = self.document;
	}
	{
		gcodeProxy = [[ModelObjectGCodeGenerator alloc] init];
		gcodeProxy.object = self;
		gcodeProxy.document = self.document;
	}
	
	return self;
}

- (void) setNavSelection:(BOOL)sel
{
	[self willChangeValueForKey: @"navSelection"];
	
	navSelection = sel;
	[self.document modelObjectChanged: self];
	
	[self didChangeValueForKey: @"navSelection"];
}

- (void) cancelToolpathCreation
{
	if (!toolpathInProgress)
		return;
	
	toolpathInProgress = -1;
	while (toolpathInProgress)
		usleep(10);
}

- (void) recreateToolpathAsync
{
	PolygonContour* contour = [[PolygonContour alloc] init];
	contour.polygon = self.sourcePolygon.copy;
	
	for (FixPolygonSegment* segment in contour.polygon.segments)
		[segment cleanupDoubleVertices];
	
	double toolOffset = createContourProxy.toolOffset;

	[self asyncProcessStarted];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		
		[contour generateToolpathWithOffset: toolOffset cancellationCheck: ^BOOL {
			return toolpathInProgress > 0;
		}];
		
		toolpathInProgress = 0;
		
		dispatch_async(dispatch_get_main_queue(), ^{
			
			for (FixPolygonClosedSegment* cseg in contour.toolpath.segments)
			{
				[cseg cleanupDoubleVertices];
				[cseg reverse];
			}
			
			//contour.toolpath.segments = contour.toolpath.segments.reverseObjectEnumerator.allObjects;
			[contour.toolpath reviseWinding];
			self.toolpathPolygon = contour.toolpath;
			[self asyncProcessStopped];
			
		});
		
	});
	
	

}

- (void) parametersForToolpathChanged
{
	self.toolpathPolygon = nil;
	
	dispatch_coalesce(editCoalesceSource, 3.0, ^{
		[self cancelToolpathCreation];
		toolpathInProgress = 1;
		[self recreateToolpathAsync];
	});

}

- (void) setObjectTransform: (matrix_t) m
{
	[super setObjectTransform: m];
	
	self.sourcePolygon = [FixPolygon polygonFromBezierPath: self.sourceBezierPath withTransform: mToAffineTransform(self.objectTransform) flatness: 0.1];
	
	[self parametersForToolpathChanged];
}



- (id) gfx
{
	GfxNode* root = [[GfxNode alloc] init];
	[root addChild: [[GfxTransformNode alloc] initWithMatrix: mIdentity()]];

	id gfx = nil;
	if ((gfx = self.sourcePolygon.gfx))
		[root addChild: gfx];
	if ((gfx = self.toolpathPolygon.gfx))
		[root addChild: gfx];
	if ((gfx = transformProxy.gfx))
		[root addChild: gfx];
	if ((gfx = createContourProxy.gfx))
		[root addChild: gfx];
	
	if (self.navSelection)
	{
		r3i_t bounds = self.sourcePolygon.bounds;
		if (self.toolpathPolygon)
		{
			bounds = riUnionRange(bounds, self.toolpathPolygon.bounds);
			
			
		}
		
		GfxNode* selectRoot = [ModelObject boundingBoxForIntegerRange: bounds margin: vCreatePos(1.0, 1.0, 1.0)];
				
		[root addChild: selectRoot];

	}
	
	return root;
}



- (NSArray*) navChildren
{
	NSMutableArray* children = [[NSMutableArray alloc] init];
	[children addObject: transformProxy];
	if (self.sourcePolygon)
	{
		[children addObject: self.sourcePolygon];
		[children addObject: createContourProxy];
		[children addObject: gcodeProxy];
	}
	if (self.toolpathPolygon)
		[children addObject: self.toolpathPolygon];
	return children;

}



- (void) navSelectChildren:(BOOL)selection
{
	for (id child in self.navChildren)
	{
		if ([child respondsToSelector: @selector(setNavSelection:)])
		{
			[child setNavSelection: selection];
		}
	}
}

- (void) setSourcePolygon:(FixPolygon *)poly
{
	[self willChangeValueForKey: @"sourcePolygon"];
	
	[(id)poly setNavLabel: @"Source Polygon"];
	
	sourcePolygon = poly;
	[self.document modelObjectChanged: self];
	
	[self didChangeValueForKey: @"sourcePolygon"];
}

- (void) setToolpathPolygon:(FixPolygon *)poly
{
	[self willChangeValueForKey: @"toolpathPolygon"];
	
	[(id)poly setNavLabel: @"Toolpath Polygon"];
	
	poly.opacity = 1.0;
	toolpathPolygon = poly;
	[self.document modelObjectChanged: self];
	
	[self didChangeValueForKey: @"toolpathPolygon"];
}


@end

@implementation ModelObject3D


@end



@implementation ModelObjectProxy

@synthesize document;

- (NSString*) navLabel
{
	[self doesNotRecognizeSelector: _cmd];
	return nil;
}

@end

@implementation ModelObjectTransformProxy
{
	NSArray* fields;
	
	
	IBOutlet NSTextField* minXField;
	IBOutlet NSTextField* minYField;
	IBOutlet NSTextField* minZField;
	IBOutlet NSTextField* maxXField;
	IBOutlet NSTextField* maxYField;
	IBOutlet NSTextField* maxZField;
	IBOutlet NSTextField* scaleXField;
	IBOutlet NSTextField* scaleYField;
	IBOutlet NSTextField* scaleZField;
	IBOutlet NSTextField* rotXField;
	IBOutlet NSTextField* rotYField;
	IBOutlet NSTextField* rotZField;
	IBOutlet NSButton* linkScaleButton;
}

@synthesize navView, navSelection;

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	
	ModelObjectTransformFieldProxy* field0 = [[ModelObjectTransformFieldProxy alloc] init];
	field0.label = @"Scale X";
	field0.fieldnum = 0;
	
	ModelObjectTransformFieldProxy* field1 = [[ModelObjectTransformFieldProxy alloc] init];
	field1.label = @"Scale Y";
	field1.fieldnum = 5;

	ModelObjectTransformFieldProxy* field2 = [[ModelObjectTransformFieldProxy alloc] init];
	field2.label = @"Scale Z";
	field2.fieldnum = 10;
	
	fields = @[field0, field1, field2];
	
	return self;
}

- (void) setObject:(ModelObject *)object
{
	[super setObject: object];
	
	for (ModelObjectTransformFieldProxy* field in fields)
	{
		field.object = self.object;
	}
	

}

- (IBAction) fieldEndEditAction: (id)sender
{
	
	ModelObject2D* obj = self.object;

	r3i_t srcBoundsi	= obj.sourcePolygon.bounds;
	range3d_t srcBounds = riToFloat(srcBoundsi);

	matrix_t transform = obj.objectTransform;
	vector_t minv = srcBounds.minv;
	vector_t maxv = srcBounds.maxv;
	vector_t delta = vCreatePos(0.0, 0.0, 0.0);
	vector_t scale = vCreateDir(vLength(transform.varr[0]), vLength(transform.varr[1]), vLength(transform.varr[2]));
	double rotZ = atan2(transform.varr[0].farr[1], transform.varr[0].farr[0])*(180.0/M_PI);

	if (sender == minXField)
	{
		minv.farr[0] = minXField.doubleValue;
		
		delta = v3Sub(minv, srcBounds.minv);
	}
	if (sender == minYField)
	{
		minv.farr[1] = minYField.doubleValue;
		
		delta = v3Sub(minv, srcBounds.minv);
	}
	if (sender == minZField)
	{
		minv.farr[2] = minZField.doubleValue;
		
		delta = v3Sub(minv, srcBounds.minv);
	}
	
	if (sender == maxXField)
	{
		maxv.farr[0] = maxXField.doubleValue;
		
		delta = v3Sub(maxv, srcBounds.maxv);
	}
	if (sender == maxYField)
	{
		maxv.farr[1] = maxYField.doubleValue;
		
		delta = v3Sub(maxv, srcBounds.maxv);
	}
	if (sender == maxZField)
	{
		maxv.farr[2] = maxZField.doubleValue;
		
		delta = v3Sub(maxv, srcBounds.maxv);
	}
	
	if (sender == scaleXField)
	{
		scale.farr[0] = scaleXField.doubleValue;
	}
	if (sender == scaleYField)
	{
		scale.farr[1] = scaleYField.doubleValue;
	}
	if (sender == scaleZField)
	{
		scale.farr[2] = scaleZField.doubleValue;
	}
	if (sender == rotZField)
	{
		rotZ = rotZField.doubleValue;
	}

	vector_t newT = v3Add(delta, transform.varr[3]);
		
	
	obj.objectTransform = mTransform(mTranslationMatrix(newT), mTransform(mRotationMatrixAxisAngle(vCreateDir(0.0, 0.0, 1.0), rotZ*(M_PI/180.0)), mScaleMatrix(scale)));
	
	[self updateFields];
	
}

- (CGFloat) navHeightOfRow
{
	return self.navView.frame.size.height;
}

- (void) updateFields
{
	
	NSString* formatString = @"%.2f";
	
	
	if ([self.object isKindOfClass: [ModelObject2D class]])
	{
		ModelObject2D* obj = self.object;
		r3i_t srcBoundsi	= obj.sourcePolygon.bounds;
		matrix_t transform = obj.objectTransform;
		
		range3d_t srcBounds = riToFloat(srcBoundsi);
		
		minXField.stringValue = [NSString stringWithFormat: formatString, srcBounds.minv.farr[0]];
		minYField.stringValue = [NSString stringWithFormat: formatString, srcBounds.minv.farr[1]];
		minZField.stringValue = [NSString stringWithFormat: formatString, srcBounds.minv.farr[2]];
		maxXField.stringValue = [NSString stringWithFormat: formatString, srcBounds.maxv.farr[0]];
		maxYField.stringValue = [NSString stringWithFormat: formatString, srcBounds.maxv.farr[1]];
		maxZField.stringValue = [NSString stringWithFormat: formatString, srcBounds.maxv.farr[2]];
		
		scaleXField.stringValue = [NSString stringWithFormat: formatString, vLength(transform.varr[0])];
		scaleYField.stringValue = [NSString stringWithFormat: formatString, vLength(transform.varr[1])];
		scaleZField.stringValue = [NSString stringWithFormat: formatString, vLength(transform.varr[2])];
		
		rotXField.stringValue = [NSString stringWithFormat: formatString, 0.0];
		rotYField.stringValue = [NSString stringWithFormat: formatString, 0.0];
		rotZField.stringValue = [NSString stringWithFormat: formatString, atan2(transform.varr[0].farr[1], transform.varr[0].farr[0])*(180.0/M_PI)];

		rotXField.enabled = NO;
		rotXField.editable = NO;
		rotYField.enabled = NO;
		rotYField.editable = NO;
		
	}
}

- (NSView*) navView
{
	if (!navView)
	{
		NSNib* nib = [[NSNib alloc] initWithNibNamed: @"NavigationObjectTransformView" bundle: nil];
		[nib instantiateWithOwner: self topLevelObjects: NULL];
		
	}
	
	[self updateFields];
	
	assert(navView);
	return navView;
}

- (NSString*) navLabel
{
	return @"Transform";
}

- (id) gfx
{
	GfxNode* root = [[GfxNode alloc] init];
	[root addChild: [[GfxTransformNode alloc] initWithMatrix: mIdentity()]];
		
	if (self.navSelection)
	{
		r3i_t bounds = [self.object sourcePolygon].bounds;

		GfxNode* selectRoot = [ModelObject boundingBoxForIntegerRange: bounds margin: vCreatePos(1.0, 1.0, 1.0)];
		
		[root addChild: selectRoot];
		
	}
	
	return root;
}

@end


@implementation ModelObjectTransformFieldProxy

- (NSString*) navLabel
{
	return self.label;
}

- (NSString*) navValue
{
	matrix_t m = [self.object objectTransform];
	
	NSInteger fieldnum = self.fieldnum;
	
	NSInteger vnum = fieldnum / 4;
	NSInteger anum = fieldnum % 4;
	
	return [NSString stringWithFormat: @"%f", m.varr[vnum].farr[anum]];
}

@end


@implementation ModelObjectCreateContourProxy
{
	NSArray* navChildren;
	
	IBOutlet NSWindow*		createContourSheet;
	IBOutlet NSTextField*	toolDiameterField;
	IBOutlet NSComboBox*	toolOffsetField;
}

@synthesize navView, navSelection;

- (NSString*) navLabel
{
	return @"Create Contour…";
}

- (NSInteger) navChildCount
{
	return navChildren.count;
}

- (IBAction) cancelCreateContourAction:(id)sender
{
	[createContourSheet.sheetParent endSheet: createContourSheet returnCode: NSModalResponseCancel];
}

- (IBAction) okCreateContourAction:(id)sender
{
	
	NSString* toolDiameterString = toolDiameterField.stringValue;
	NSString* toolOffsetString = toolOffsetField.stringValue;
	
	if (!toolDiameterString.length)
	{
		NSAlert* alert = [NSAlert alertWithMessageText: @"Invalid Tool Diameter" defaultButton: @"Go Back…" alternateButton: nil otherButton: nil informativeTextWithFormat: @"Tool Diameter Invalid: \"%@\"", toolDiameterString];
		
		[alert beginSheetModalForWindow: createContourSheet completionHandler: ^(NSModalResponse returnCode) {}];
		
		return;
	}
	
	if (!toolOffsetString.length)
	{
		NSAlert* alert = [NSAlert alertWithMessageText: @"Invalid Tool Offset" defaultButton: @"Go Back…" alternateButton: nil otherButton: nil informativeTextWithFormat: @"Tool Offset Invalid: \"%@\"", toolOffsetString];
		
		[alert beginSheetModalForWindow: createContourSheet completionHandler: ^(NSModalResponse returnCode) {}];
		
		return;
	}
	
	double toolOffset = 0.0;
	
	if ([@"inside" isEqualToString: toolOffsetString])
	{
		toolOffset = -0.5*toolDiameterString.doubleValue;
	}
	else if ([@"outside" isEqualToString: toolOffsetString])
	{
		toolOffset = 0.5*toolDiameterString.doubleValue;
	}
	else if ([@"none" isEqualToString: toolOffsetString])
	{
		toolOffset = 0.0;
	}
	else
		toolOffset = toolOffsetString.doubleValue;
	
	
	PolygonContour* contour = [[PolygonContour alloc] init];
	contour.polygon = [self.object sourcePolygon];
	[contour generateToolpathWithOffset: toolOffset cancellationCheck:^BOOL{
		return NO;
	}];

	ModelObject2D* obj = self.object;
	obj.toolpathPolygon = contour.toolpath;
		
	[createContourSheet.sheetParent endSheet: createContourSheet returnCode: NSModalResponseOK];

}


- (IBAction) createContourAction:(id)sender
{
	NSNib* nib = [[NSNib alloc] initWithNibNamed: @"CreateContour2DSheet" bundle: nil];
	
	[nib instantiateWithOwner: self topLevelObjects: NULL];
	
	assert(navView.window);
	[navView.window beginSheet: createContourSheet completionHandler: ^(NSModalResponse returnCode) {}];

}

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox
{
	return 4;
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	
	NSString* lastUsed = [defaults objectForKey: @"lastUsedContour2DToolOffset"];
	if (!lastUsed)
		lastUsed = @"";
	
	NSArray* objects = @[@"inside", @"outside", @"none", lastUsed];
	
	return [objects objectAtIndex: index];
}

- (id) gfx
{
	GfxNode* root = [[GfxNode alloc] init];
	[root addChild: [[GfxTransformNode alloc] initWithMatrix: mIdentity()]];
	
	if (self.navSelection)
	{
		r3i_t bounds = [self.object sourcePolygon].bounds;
		
		GfxNode* selectRoot = [ModelObject boundingBoxForIntegerRange: bounds margin: vCreatePos(1.0, 1.0, 1.0)];
		
		[root addChild: selectRoot];
		
	}
	
	return root;
}

- (NSView*) navView
{
	if (!navView)
	{
		NSNib* nib = [[NSNib alloc] initWithNibNamed: @"NavigationButtonView" bundle: nil];
		[nib instantiateWithOwner: self topLevelObjects: NULL];
		
		NSButton* button = (id)navView;
		
		[button setTarget: self];
		[button setAction: @selector(createContourAction:)];

	}
	assert(navView);
	return navView;
}


- (CGFloat) navHeightOfRow
{
	return self.navView.frame.size.height;
}

@end


@implementation ModelObjectContourGenerator
{
	IBOutlet NSTextField* toolDiameterField;
}

@synthesize navView, navSelection;

- (NSView*) navView
{
	if (!navView)
	{
		NSNib* nib = [[NSNib alloc] initWithNibNamed: @"NavigationContourGeneratorView" bundle: nil];
		[nib instantiateWithOwner: self topLevelObjects: NULL];
		
		
	}
	assert(navView);
	return navView;
}

- (CGFloat) navHeightOfRow
{
	return self.navView.frame.size.height;
}

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox
{
	return 4;
}

- (double) toolOffset
{
	[self navView];
	
	double toolDiameter = toolDiameterField.doubleValue;
	
	return toolDiameter/2.0; //FIXME: this is a hack
	
}

- (IBAction) doneEditingAction:(id)sender
{
	ModelObject2D* obj = self.object;
	[obj parametersForToolpathChanged];
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	
	NSString* lastUsed = [defaults objectForKey: @"LastUsedContour2DToolOffset"];
	if (!lastUsed)
		lastUsed = @"";
	
	NSArray* objects = @[@"inside", @"outside", @"none", lastUsed];
	
	return [objects objectAtIndex: index];
}

- (id) gfx
{
	return [[GfxNode alloc] init];
}

@end


@implementation ModelObjectGCodeGenerator
{
	IBOutlet NSTextField* cutDepthField;
}

@synthesize navView, navSelection;


- (NSView*) navView
{
	if (!navView)
	{
		NSNib* nib = [[NSNib alloc] initWithNibNamed: @"NavigationGCodeGeneratorView" bundle: nil];
		[nib instantiateWithOwner: self topLevelObjects: NULL];
		
		
	}
	assert(navView);
	return navView;
}
- (CGFloat) navHeightOfRow
{
	return self.navView.frame.size.height;
}


- (NSString*) generateGCode
{
	NSString* preamble = [NSString stringWithContentsOfFile: [[NSBundle mainBundle] pathForResource: @"preamble" ofType: @"gcode"] encoding: NSASCIIStringEncoding error: NULL];
	
	double cutDepth = -cutDepthField.doubleValue;
	double safeDepth = 0.0;
	
	NSString* tool = @"T1";
	
	NSString* spindleOn = @"M3";
	NSString* spindleOff = @"M5";
	
	NSMutableArray* toolpathStrings = @[preamble, tool, @"G0 Z0", spindleOn, @"G4 P3000"].mutableCopy;
	
	ModelObject2D* obj = self.object;
	assert(obj);
	
	
	for (FixPolygonSegment* segment in obj.toolpathPolygon.segments)
	{
		v3i_t* vertices = segment.vertices;
		
		vector_t start = v3iToFloat(vertices[0]);
		
		[toolpathStrings addObject: [NSString stringWithFormat: @"G0 X%.3f Y%.3f", start.farr[0], start.farr[1]]];
		[toolpathStrings addObject: [NSString stringWithFormat: @"G1 Z%.3f", cutDepth]];

		
		for (size_t i = 0; i < segment.vertexCount; ++i)
		{
			vector_t v = v3iToFloat(vertices[i]);
			{
				[toolpathStrings addObject: [NSString stringWithFormat: @"G1 X%.3f Y%.3f", v.farr[0], v.farr[1]]];
			}
		}
		
		if (segment.isClosed)
		{
			[toolpathStrings addObject: [NSString stringWithFormat: @"G1 X%.3f Y%.3f", start.farr[0], start.farr[1]]];
		
		}

		[toolpathStrings addObject: [NSString stringWithFormat: @"G1 Z%.3f", safeDepth]];
	}
	
	
	[toolpathStrings addObject: spindleOff];

	
	return [toolpathStrings componentsJoinedByString:@"\n"];
}

- (IBAction) exportGCodeAction: (id) sender
{
	int result = 0;
	
	NSSavePanel*	panel = [NSSavePanel savePanel];
	[panel setTitle: @"Export G-Code"];
	[panel setAllowedFileTypes: @[@"gcode"]];
	
	
	result = [panel runModal];
	if (result == NSOKButton)
	{
		NSString* gcode = [self generateGCode];
		
		[gcode writeToURL: panel.URL atomically: YES encoding: NSASCIIStringEncoding error: NULL];
		
	}
	

}

@end







