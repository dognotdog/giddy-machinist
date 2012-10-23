//
//  Slicer.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 22.10.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"

@class GfxMesh;


@interface SlicedLayer : NSObject
@property(nonatomic, strong) NSArray* outlinePaths;
@property(nonatomic, strong) NSArray* openPaths;

@end




@interface Slicer : NSObject

- (NSArray*) sliceModel: (GfxMesh*) model intoLayers: (NSArray*) layers;

@property(nonatomic) double mergeThreshold;

@end
