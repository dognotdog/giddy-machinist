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

@end


@implementation ModelObject2D
{
	NSArray* navChildren;
}

- (instancetype) init
{
	if (!(self = [super init]))
		return nil;
	
	self.objectTransform = mIdentity();
	
	NSMutableArray* proxies = [[NSMutableArray alloc] init];
	
	{
		ModelObjectTransformProxy* proxy = [[ModelObjectTransformProxy alloc] init];
		proxy.object = self;
		[proxies addObject: proxy];
	}
	{
		ModelObjectPolygonProxy* proxy = [[ModelObjectPolygonProxy alloc] init];
		proxy.object = self;
		proxy.polygon = self.sourcePolygon;
		proxy.name = @"Source Polygon";
		[proxies addObject: proxy];
	}
	{
		ModelObjectPolygonProxy* proxy = [[ModelObjectPolygonProxy alloc] init];
		proxy.object = self;
		proxy.polygon = self.toolpathPolygon;
		proxy.name = @"Toolpath Polygon";
		[proxies addObject: proxy];
	}
	{
		ModelObjectCreateContourProxy* proxy = [[ModelObjectCreateContourProxy alloc] init];
		proxy.object = self;
		[proxies addObject: proxy];
	}

	
	
	navChildren = proxies;
	
	return self;
}

- (id) gfx
{
	GfxNode* root = [[GfxNode alloc] init];
	id gfx = nil;
	if ((gfx = self.sourcePolygon.gfxMesh))
		[root addChild: gfx];
	if ((gfx = self.toolpathPolygon.gfxMesh))
		[root addChild: gfx];
	
	return root;
}


- (NSInteger) navChildCount
{
	// Transform, Source Polygon, Toolpath
	return navChildren.count;
}



- (id) navChildAtIndex:(NSInteger)idx
{
	return [navChildren objectAtIndex: idx];
}

@end

@implementation ModelObject3D


@end



@implementation ModelObjectProxy

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

@end

@implementation ModelObjectPolygonProxy

- (NSString*) navLabel
{
	return self.name;
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

@synthesize navView;

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

