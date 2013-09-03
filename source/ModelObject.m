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

#import <AppKit/AppKit.h>

@implementation ModelObject

@synthesize document;

- (instancetype) init
{
	if (!(self = [super init]))
		return nil;
	
	self.objectTransform = mIdentity();
	
	return self;
}

- (NSString*) navLabel
{
	return self.name;
}

- (id) gfx
{
	return [[GfxNode alloc] init];
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
	ModelObjectCreateContourProxy* createContourProxy;
}

@synthesize sourcePolygon, toolpathPolygon, navSelection;

- (instancetype) init
{
	if (!(self = [super init]))
		return nil;
	
	self.objectTransform = mIdentity();
		
	{
		transformProxy = [[ModelObjectTransformProxy alloc] init];
		transformProxy.object = self;
		transformProxy.document = self.document;
	}
	{
		createContourProxy = [[ModelObjectCreateContourProxy alloc] init];
		createContourProxy.object = self;
		createContourProxy.document = self.document;
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


- (NSInteger) navChildCount
{
	// Transform, Source Polygon, Toolpath
	return 2 + !!self.sourcePolygon + !!self.toolpathPolygon;
}

- (NSArray*) navChildren
{
	NSMutableArray* children = [[NSMutableArray alloc] init];
	[children addObject: transformProxy];
	if (self.sourcePolygon)
		[children addObject: self.sourcePolygon];
	if (self.toolpathPolygon)
		[children addObject: self.toolpathPolygon];
	[children addObject: createContourProxy];
	return children;

}



- (id) navChildAtIndex:(NSInteger)idx
{
	NSArray* children = [self navChildren];
	return [children objectAtIndex: idx];
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
}

@synthesize navSelection;

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

- (NSString*) navLabel
{
	return @"Transform";
}

- (NSInteger) navChildCount
{
	return fields.count;
}

- (id) navChildAtIndex:(NSInteger)idx
{
	return [fields objectAtIndex: idx];
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
	[contour generateToolpathWithOffset: toolOffset];

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

