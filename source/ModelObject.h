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

@class FixPolygon, GMDocument, NSView;

@protocol ModelObjectNavigation <NSObject>

@required
- (NSString*) navLabel;

@optional
- (NSImage*) navIcon;
- (NSString*) navValue;
- (void) setNavValue: (NSString*) val;

@property(nonatomic,strong) IBOutlet NSView* navView; // view to use in outline view for item
- (CGFloat) navHeightOfRow; // view to use in outline view for item

- (NSInteger) navChildCount;
- (id) navChildAtIndex: (NSInteger) idx;

@end

@interface ModelObject : NSObject <ModelObjectNavigation>

@property(nonatomic) matrix_t objectTransform;
@property(nonatomic,strong) NSString* name;
@property(nonatomic,weak) GMDocument* document;

@property(nonatomic,strong,readonly) id gfx;

@end


@interface ModelObject2D : ModelObject

@property(nonatomic, strong) NSData* epsData;
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

@end


@interface ModelObjectTransformFieldProxy : ModelObjectProxy

@property(nonatomic, strong) NSString* label;
@property(nonatomic) long fieldnum;


@end


@interface ModelObjectPolygonProxy : ModelObjectProxy

@property(nonatomic,weak) FixPolygon* polygon;
@property(nonatomic,strong) NSString* name;

@end

@interface ModelObjectCreateContourProxy : ModelObjectProxy <NSComboBoxDataSource, NSComboBoxDelegate>

@property(nonatomic, strong) NSView* navView;

@end

