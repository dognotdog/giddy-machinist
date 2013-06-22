//
//  MPInteger.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 26.05.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "MPInteger.h"

#import "tommath.h"

#define PRECISION DBL_MANT_DIG

static double mp_get_double(mp_int *a)
{
    static const int NEED_DIGITS = (PRECISION + 2 * DIGIT_BIT - 2) / DIGIT_BIT;
    static const double DIGIT_MULTI = (mp_digit)1 << DIGIT_BIT;
	
    int i, limit;
    double d = 0.0;
	
    mp_clamp(a);
    i = USED(a);
    limit = i <= NEED_DIGITS ? 0 : i - NEED_DIGITS;
	
    while (i-- > limit) {
        d += DIGIT(a, i);
        d *= DIGIT_MULTI;
    }
	
    if(SIGN(a) == MP_NEG)
        d *= -1.0;
	
    d *= pow(2.0, i * DIGIT_BIT);
    return d;
}


@implementation MPInteger
{
@public
	mp_int	mpint;
}

- (id) initWithMPInt: (mp_int) mpi;
{
	if (!(self = [super init]))
		return nil;
	
	mpint = mpi;

	return self;

}

- (id) initWithInt64: (int64_t) i;
{
	if (!(self = [super init]))
		return nil;
	
	uint64_t ui = i;
	long sign = 1;
	if (i < 0)
	{
		sign = -1;
		ui = (~ui) + 1;
	}
	
	
	uint64_t high = (ui >> 32);
	uint64_t low = ui & 0xFFFFFFFF;
	
	mp_init_set(&mpint, high);
	mp_mul_2d(&mpint, 32, &mpint);
	
	mp_int mplow;
	mp_init_set(&mplow, low);
	
	mp_add(&mpint, &mplow, &mpint);
	
	if (sign < 0)
		mp_neg(&mpint, &mpint);
	
	mp_clear(&mplow);
	
	
	
	
	return self;
}

- (id) init
{
	if (!(self = [super init]))
		return nil;
	
	mp_init(&mpint);
	
	
	return self;
}

- (void) dealloc
{
	mp_clear(&mpint);
}

- (size_t) numBits
{
	return mp_count_bits(&mpint);
}
- (NSString*) stringValue
{
	
	int expectedSize = 0;
	mp_radix_size(&mpint, 10, &expectedSize);
	char* buf = calloc(1, expectedSize);
	
	mp_toradix_n(&mpint, buf, 10, expectedSize);
	
	NSString* str = [NSString stringWithUTF8String: buf];
	free(buf);
	return str;
}



- (MPInteger*) add: (MPInteger *)mpi
{
	mp_int r;
	mp_init(&r);
	
	mp_add(&mpint, &mpi->mpint, &r);
	
	return [[MPInteger alloc] initWithMPInt: r];
}

- (MPInteger*) sub: (MPInteger *)mpi
{
	mp_int r;
	mp_init(&r);
	
	mp_sub(&mpint, &mpi->mpint, &r);
	
	return [[MPInteger alloc] initWithMPInt: r];
}

- (MPInteger*) mul: (MPInteger *)mpi
{
	mp_int r;
	mp_init(&r);
	
	mp_mul(&mpint, &mpi->mpint, &r);
	
	return [[MPInteger alloc] initWithMPInt: r];
}

- (MPInteger*) div: (MPInteger *)mpi
{
	mp_int r;
	mp_init(&r);
	
	mp_div(&mpint, &mpi->mpint, &r, NULL);
	
	return [[MPInteger alloc] initWithMPInt: r];
}

- (MPInteger*) max: (MPInteger *)mpi
{
	assert(mpi);
	
	MPInteger* diff = [self sub: mpi];
	
	return diff.isPositive ? self : mpi;
}

- (MPInteger*) min: (MPInteger *)mpi
{
	assert(mpi);
	
	MPInteger* diff = [self sub: mpi];
	
	return diff.isPositive ? mpi : self;
}

- (NSComparisonResult) compare: (MPInteger *)mpi
{
	assert(mpi);
	
	MPInteger* diff = [self sub: mpi];
	
	return diff.isZero ? NSOrderedSame : (diff.isPositive ? NSOrderedDescending : NSOrderedAscending);
}

- (NSComparisonResult) compareToZero
{
	
	return self.isZero ? NSOrderedSame : (self.isPositive ? NSOrderedDescending : NSOrderedAscending);
}


- (MPInteger*) sqrt
{
	mp_int r;
	mp_init(&r);
	
	mp_sqrt(&mpint, &r);
	
	return [[MPInteger alloc] initWithMPInt: r];

}

- (MPInteger*) negate
{
	mp_int r;
	mp_init(&r);
	
	mp_neg(&mpint, &r);
	
	return [[MPInteger alloc] initWithMPInt: r];
	
}

- (MPInteger*) abs
{
	if (self.isNegative)
		return self.negate;
	else
		return self;
}

- (long) isZero
{
	return mp_iszero(&mpint);
}

- (long) isPositive
{
	return (SIGN(&mpint) == MP_ZPOS) && !mp_iszero(&mpint);
}

- (long) isNegative
{
	return !self.isZero && !self.isPositive;
}

- (double) toDouble
{
	
	mp_int r;
	mp_init_copy(&r, &mpint);
	
	long finalShift = 0;
	
	long bitCount = mp_count_bits(&r);
	
	if (bitCount > DBL_MANT_DIG)
	{
		long reducingShift = bitCount - DBL_DIG;
		mp_div_2d(&r, reducingShift, &r, NULL);
		
		finalShift = - reducingShift;
	}
	
	
	
	double x = mp_get_double(&r);
	
	x = x*pow(2.0, -finalShift);
	
	mp_clear(&r);
	
	return x;
}


- (id)copyWithZone:(NSZone *)zone;
{
	mp_int ri;
	mp_init_copy(&ri, &mpint);
	MPInteger* r = [[[self class] allocWithZone: zone] initWithMPInt: ri];
	
	return r;
}


@end

@implementation MPDecimal

- (id)copyWithZone:(NSZone *)zone;
{
	MPDecimal* r = [super copyWithZone: zone];
	r.decimalShift = self.decimalShift;
	return r;
}

@synthesize decimalShift;

- (id) initWithInt64: (int64_t)i shift: (long)shift;
{
	if (!(self = [super initWithInt64: i]))
		return nil;
	
	decimalShift = shift;
	
	return self;
	
}


#if	FLT_RADIX != 2
#error FLT_RADIX must be 2 for float/mp conversion
#endif

- (id) initWithDouble: (double) f;
{
	int exp = 0;
	double mantissa = frexp(f, &exp);
	double m = ldexp(mantissa, DBL_MANT_DIG);
	int64_t i = trunc(m);
	
	
	

	if (!(self = [self initWithInt64: i shift: DBL_MANT_DIG - exp]))
		return nil;
	
	assert(self.toDouble == f);
	
	
	return self;

}
- (id) initWithMPInt: (mp_int) mpi shift: (long) shift;
{
	if (!(self = [super initWithMPInt: mpi]))
		return nil;
	
	decimalShift = shift;
	
	return self;
	
}

+ (id) decimalWithDouble:(double)f
{
	return [[MPDecimal alloc] initWithDouble: f];
}

+ (id) decimalWithInt64:(int64_t)i shift:(long)shift
{
	return [[MPDecimal alloc] initWithInt64: i shift: shift];
}

+ (id) one
{
	static MPDecimal* one = nil;
	if (!one)
		one = [[MPDecimal alloc] initWithInt64: 1 shift: 0];
	return one;
}

+ (id) oneHalf
{
	return [[MPDecimal alloc] initWithInt64: 1 shift: 1];
}

+ (id) zero
{
	return [[MPDecimal alloc] initWithInt64: 0 shift: 0];
}


- (void) increasePrecisionByBits:(size_t)shift
{
	mp_mul_2d(&mpint, shift, &mpint);
	decimalShift+= shift;
}

- (void) decreasePrecisionByBits:(size_t)shift
{
	mp_div_2d(&mpint, shift, &mpint, NULL);
	decimalShift -= shift;
}

- (NSString*) stringValue
{
	mp_int a;
	mp_init_copy(&a, &mpint);
	
	if (decimalShift > 0)
		mp_div_2d(&a, decimalShift, &a, NULL);
	else if (decimalShift < 0)
		mp_mul_2d(&a, -decimalShift, &a);
	
	int expectedSize = 0;
	mp_radix_size(&a, 10, &expectedSize);
	
	

	mp_clear(&a);
	return [super stringValue];
}

- (int32_t) toInt32WithQ: (size_t) q
{
	mp_int r;
	mp_init_copy(&r, &mpint);
	
	long s = mp_count_bits(&r);
	long ibits = s - decimalShift;
	long fbits = s - ibits;

	// how many bits to chop off
	long k = fbits - q;
	
	if (ibits > (long)32-(long)q)
		[NSException raise: @"MPDecimal.rangeException" format: @"Value: %@", self.stringValue];
		
	if (k > 0)
		mp_div_2d(&r, k, &r, NULL);
	else if (k < 0)
		mp_mul_2d(&r, -k, &r);
	
	unsigned long bs = mp_signed_bin_size(&r);
	unsigned long us = bs-1;
	uint8_t* buf = calloc(bs,1);
	mp_to_signed_bin_n(&r, buf, &bs);
	
	assert(bs < 6);
	
	uint32_t rbuf = 0;
	
	long offset = 4-(us);
	
	memmove(((void*)&rbuf)+offset, buf+1, us);
	
	rbuf = CFSwapInt32BigToHost(rbuf);
	
	if (buf[0]) // negative
		rbuf = (~rbuf)+1;
	
	mp_clear(&r);
	
	free(buf);
	return rbuf;
}

- (int64_t) toInt64WithQ: (size_t) q
{
	long s = mp_count_bits(&mpint);
	long k = q-decimalShift;
	long fs = s+k;
	
	if (fs > 64)
		[NSException raise: @"MPDecimal.rangeException" format: @"Value: %@", self.stringValue];
	
	mp_int a;
	mp_init_copy(&a, &mpint);
	
	if (k > 0)
		mp_mul_2d(&a, k, &a);
	else if (fs < 0)
		mp_div_2d(&a, -k, &a, NULL);
	
	int64_t buf = 0;
	unsigned long bs = 8;
	mp_to_signed_bin_n(&a, (void*)&buf, &bs);
	assert(bs);
	buf = CFSwapInt32BigToHost(buf);
	
	mp_clear(&a);
	
	return buf;
}

- (long) integerBits
{
	return mp_count_bits(&mpint) - decimalShift;
}

double mp_get_double2(mp_int *a) {
    double d = 0.0;
    if (USED(a) == 0)
        return d;
    if (USED(a) == 1)
        return SIGN(a) == MP_NEG ? (double) -mp_get_int(a) : (double) mp_get_int(a);
	
    int i;
    for (i = USED(a) - 1; DIGIT(a, i) == 0 && i > 0; i--) {
        /* do nothing */
    }
    d = (double) DIGIT(a, i);
    if (SIGN(a) == MP_NEG)
        d *= -1;
    i--;
    if (i == -1) {
        return d;
    }
    d *= pow(2.0, DIGIT_BIT);
    d += (double) DIGIT(a, i);
	
    d *= pow(2.0, DIGIT_BIT * i);
    return d;
}

- (double) toDouble
{
	
	mp_int r;
	mp_init_copy(&r, &mpint);
	
	long finalShift = decimalShift;
	
	long bitCount = mp_count_bits(&r);
	
	if (bitCount > DBL_MANT_DIG)
	{
		long reducingShift = bitCount - DBL_DIG;
		mp_div_2d(&r, reducingShift, &r, NULL);
		
		finalShift = decimalShift - reducingShift;
	}
	
	
	
	double x = mp_get_double(&r);
	
	x = x*pow(2.0, -finalShift);
	
	mp_clear(&r);

	return x;
}

- (MPDecimal*) add: (MPDecimal *)mpi
{
	mp_int a,b,r;
	mp_init(&r);
	mp_init_copy(&a, &mpint);
	mp_init_copy(&b, &mpi->mpint);

	if (decimalShift > mpi->decimalShift)
		mp_mul_2d(&b, decimalShift - mpi->decimalShift, &b);
	else
		mp_mul_2d(&a, mpi->decimalShift-decimalShift, &a);
	
	mp_add(&a, &b, &r);
	
	mp_clear(&a);
	mp_clear(&b);

	return [[MPDecimal alloc] initWithMPInt: r shift: MAX(decimalShift, mpi->decimalShift)];
}

- (MPDecimal*) sub: (MPDecimal *)mpi
{
	assert(mpi);
	mp_int a,b,r;
	mp_init(&r);
	mp_init_copy(&a, &mpint);
	mp_init_copy(&b, &mpi->mpint);
	
	if (decimalShift > mpi->decimalShift)
		mp_mul_2d(&b, decimalShift - mpi->decimalShift, &b);
	else
		mp_mul_2d(&a, mpi->decimalShift-decimalShift, &a);
	
	mp_sub(&a, &b, &r);
	mp_clear(&a);
	mp_clear(&b);

	
	return [[MPDecimal alloc] initWithMPInt: r shift: MAX(decimalShift, mpi->decimalShift)];
}

- (MPDecimal*) mul: (MPDecimal *)mpi
{
	mp_int a,b,r;
	mp_init(&r);
	mp_init_copy(&a, &mpint);
	mp_init_copy(&b, &mpi->mpint);
		
	mp_mul(&a, &b, &r);
	
	mp_clear(&a);
	mp_clear(&b);
	
	return [[MPDecimal alloc] initWithMPInt: r shift: decimalShift + mpi->decimalShift];
}

- (MPDecimal*) div2: (MPDecimal *)mpi
{
	// following algorithm preserves number of decimal digits in result
	mp_int a,b,r;
	mp_init(&r);
	mp_init_copy(&a, &mpint);
	mp_init_copy(&b, &mpi->mpint);
	
	long shift = mpi->decimalShift;
	
	mp_mul_2d(&a, shift, &a);
	
	mp_div(&a, &b, &r, NULL);
	
	mp_clear(&a);
	mp_clear(&b);

	return [[MPDecimal alloc] initWithMPInt: r shift: decimalShift];
}

- (MPDecimal*) div: (MPDecimal *)mpi
{
	mp_int r;
	mp_init(&r);
	
	long shift = mpi->decimalShift;
		
	mp_div(&mpint, &mpi->mpint, &r, NULL);
		
	return [[MPDecimal alloc] initWithMPInt: r shift: decimalShift-shift];
}

- (MPInteger*) sqrt
{
	mp_int r;
	mp_init_copy(&r, &mpint);
	
	mp_mul_2d(&r, decimalShift, &r);
	mp_sqrt(&r, &r);
	
	return [[MPDecimal alloc] initWithMPInt: r shift: decimalShift];
	
}

- (MPInteger*) negate
{
	mp_int r;
	mp_init(&r);
	
	mp_neg(&mpint, &r);
	
	return [[MPDecimal alloc] initWithMPInt: r shift: decimalShift];
	
}

@end
