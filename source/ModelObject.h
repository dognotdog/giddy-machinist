//
//  ModelObject.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 28.08.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AppKit/NSComboBox.h>

#import "VectorMath.h"
#import "VectorMath_fixp.h"

@class FixPolygon, GMDocument, GfxNode, NSView, NSBezierPath;

@protocol ModelObjectNavigation <NSObject>

@required
- (NSString*) navLabel;
@property(nonatomic,weak) GMDocument* document;

@optional
- (void) setNavLabel: (NSString*) label;
- (NSImage*) navIcon;
- (NSString*) navValue;
- (void) setNavValue: (NSString*) val;

@property(nonatomic) BOOL navSelection;
- (void) navSelectChildren: (BOOL) selection;

- (GfxNode*) gfx;

@property(nonatomic,strong) IBOutlet NSView* navView; // view to use in outline view for item
- (CGFloat) navHeightOfRow; // view to use in outline view for item

- (NSArray*) navChildren;

@end

@interface ModelObject : NSObject <ModelObjectNavigation>

@property(nonatomic) matrix_t objectTransform;
@property(nonatomic,strong) NSString* name;

+ (GfxNode*) boundingBoxForIntegerRange: (r3i_t) bounds margin: (vector_t) margin;

@end


@interface ModelObject2D : ModelObject

- (instancetype) initWithBezierPath: (NSBezierPath*) bpath name: (NSString*) name;

@property(nonatomic, strong) NSBezierPath* sourceBezierPath;
@property(nonatomic, strong) FixPolygon* sourcePolygon;
@property(nonatomic, strong) FixPolygon* toolpathPolygon;

@end


@interface ModelObject3D : ModelObject

@property(nonatomic, strong) NSData* stlData;

@end

@interface ModelObjectProxy : NSObject <ModelObjectNavigation>

@property(nonatomic,weak) id object;

@end

@interface ModelObjectTransformProxy : ModelObjectProxy

@property(nonatomic, strong) NSView* navView;

@end


@interface ModelObjectTransformFieldProxy : ModelObjectProxy

@property(nonatomic, strong) NSString* label;
@property(nonatomic) long fieldnum;


@end

@interface ModelObjectCreateContourProxy : ModelObjectProxy <NSComboBoxDataSource, NSComboBoxDelegate>

@property(nonatomic, strong) NSView* navView;

@end

@interface ModelObjectContourGenerator : ModelObjectProxy <NSComboBoxDataSource, NSComboBoxDelegate>

@property(nonatomic, strong) NSView* navView;

@property(nonatomic) double toolOffset;

@end

@interface ModelObjectGCodeGenerator : ModelObjectProxy

@property(nonatomic, strong) NSView* navView;


@end


