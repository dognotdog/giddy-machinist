//
//  MPVector2D.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 28.05.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath_fixp.h"

@class MPDecimal;

@interface MPVector2D : NSObject

@property(nonatomic,strong) MPDecimal* x;
@property(nonatomic,strong) MPDecimal* y;

+ (instancetype) vectorWith3i: (v3i_t) v;

- (MPDecimal*) dot: (MPVector2D*) b;
- (MPDecimal*) cross: (MPVector2D*) b;
- (MPVector2D*) sub: (MPVector2D*) b;
- (MPVector2D*) add: (MPVector2D*) b;
- (MPVector2D*) scale: (MPDecimal*) b;
- (MPVector2D*) scaleNum: (MPDecimal*) num den: (MPDecimal*) den;
- (MPDecimal*) length;
- (MPVector2D*) negate;

- (long) minIntegerBits;


- (v3i_t) toVectorWithShift: (long) shift;
- (vector_t) toFloatVector;

@end