//
//  PolygonContour.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 24.08.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

@class FixPolygon;

@interface PolygonContour : NSObject

- (void) generateToolpathWithOffset: (double) floatOffset cancellationCheck: (BOOL(^)(void)) checkBlock;

@property(strong, nonatomic) FixPolygon* polygon;
@property(strong, nonatomic) FixPolygon* toolpath;

@property(strong, nonatomic) NSArray* gfxMeshes;

@end
