//
//  MPInteger.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 26.05.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MPInteger : NSObject

- (id) initWithInt64: (int64_t) i;

@property(nonatomic,readonly) size_t numBits;

- (instancetype) add: (MPInteger*) mpi;
- (instancetype) sub: (MPInteger*) mpi;
- (instancetype) mul: (MPInteger*) mpi;
- (instancetype) div: (MPInteger*) mpi;

- (instancetype) sqrt;
- (instancetype) negate;
@property(nonatomic, readonly) NSString* stringValue;;
@property(nonatomic, readonly) long sign;

@end


@interface MPDecimal : MPInteger

- (id) initWithInt64: (int64_t) i shift: (long) shift;

@property(nonatomic) long decimalShift;
@property(nonatomic) long isZero;

- (void) increasePrecisionByBits: (size_t) shift;
- (void) decreasePrecisionByBits: (size_t) shift;

- (int32_t) toInt32WithQ: (size_t) q;
- (int64_t) toInt64WithQ: (size_t) q;

- (long) integerBits;
- (double) toDouble;

@end