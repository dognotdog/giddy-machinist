//
//  STLFile.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 20.05.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#pragma once

#import <Foundation/Foundation.h>

#import	"gfx.h"
#import "VectorMath_fixp.h"

GfxMesh* LoadSTLFileFromData(NSData* data);

@interface STLVertex : NSObject
@property(nonatomic) v3i_t position;
@end



@interface STLFile : NSObject

@property(nonatomic, readonly) int scaleShift;

- (instancetype) initWithData: (NSData*) data scale: (int) scaleBits transform: (matrix_t) M;

- (NSArray*) lineSegmentsIntersectingZLayer: (v3i_t) zOffset;

@end
