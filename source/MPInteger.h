//
//  MPInteger.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 26.05.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MPInteger : NSObject <NSCopying>

- (instancetype) initWithInt64: (int64_t) i;

@property(nonatomic,readonly) size_t numBits;

- (instancetype) add: (MPInteger*) mpi;
- (instancetype) sub: (MPInteger*) mpi;
- (instancetype) mul: (MPInteger*) mpi;
- (instancetype) div: (MPInteger*) mpi;

- (instancetype) min: (MPInteger*) mpi;
- (instancetype) max: (MPInteger*) mpi;

- (NSComparisonResult) compare: (MPInteger *)mpi;
- (NSComparisonResult) compareToZero;

- (instancetype) sqrt;
- (instancetype) negate;
- (instancetype) abs;
- (NSString*) stringValue;;
//- (long) sign;

- (long) isZero;
- (long) isPositive;
- (long) isNegative;

- (double) toDouble;


@end


@interface MPDecimal : MPInteger

+ (instancetype) decimalWithDouble: (double) f;
+ (instancetype) decimalWithInt64: (int64_t) i shift: (long) shift;

+ (instancetype) zero;
+ (instancetype) one;
+ (instancetype) oneHalf;

- (instancetype) initWithInt64: (int64_t) i shift: (long) shift;
- (instancetype) initWithDouble: (double) f;

@property(nonatomic) long decimalShift;

- (void) increasePrecisionByBits: (size_t) shift;
- (void) decreasePrecisionByBits: (size_t) shift;

- (int32_t) toInt32WithQ: (size_t) q;
- (int64_t) toInt64WithQ: (size_t) q;

- (long) integerBits;
- (double) toDouble;

@end