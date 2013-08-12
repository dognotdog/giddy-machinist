//
//  MPVector2D.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 28.05.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "MPVector2D.h"

#import "MPInteger.h"
#import "tommath.h"

@implementation MPVector2D

@synthesize x,y;

+ (instancetype) vectorWith3i: (v3i_t) v
{
	MPVector2D* r = [[MPVector2D alloc] init];
	r.x = [[MPDecimal alloc] initWithInt64: v.x shift: v.shift];
	r.y = [[MPDecimal alloc] initWithInt64: v.y shift: v.shift];
	
	return r;
}

- (id)copyWithZone:(NSZone *)zone;
{
	MPVector2D* r = [[MPVector2D allocWithZone: zone] init];
	r.x = self.x.copy;
	r.y = self.y.copy;
	return r;
}

- (MPDecimal*) dot: (MPVector2D*) b
{
	return [[self.x mul: b.x] add: [self.y mul: b.y]];
}

- (MPDecimal*) cross: (MPVector2D*) b
{
	return [[self.x mul: b.y] sub: [self.y mul: b.x]];
}

- (MPVector2D*) add: (MPVector2D*) b
{
	MPVector2D* v = [[MPVector2D alloc] init];
	v.x = [self.x add: b.x];
	v.y = [self.y add: b.y];
	return v;
}

- (MPVector2D*) sub: (MPVector2D*) b
{
	MPVector2D* v = [[MPVector2D alloc] init];
	v.x = [self.x sub: b.x];
	v.y = [self.y sub: b.y];
	return v;
}

- (MPVector2D*) min: (MPVector2D*) b
{
	MPVector2D* v = [[MPVector2D alloc] init];
	v.x = [self.x min: b.x];
	v.y = [self.y min: b.y];
	return v;
}

- (MPVector2D*) max: (MPVector2D*) b
{
	MPVector2D* v = [[MPVector2D alloc] init];
	v.x = [self.x max: b.x];
	v.y = [self.y max: b.y];
	return v;
}


- (MPVector2D*) scale: (MPDecimal*) b
{
	MPVector2D* v = [[MPVector2D alloc] init];
	v.x = [self.x mul: b];
	v.y = [self.y mul: b];
	return v;
}

- (MPVector2D*) div: (MPDecimal*) b
{
	MPVector2D* v = [[MPVector2D alloc] init];
	v.x = [self.x div: b];
	v.y = [self.y div: b];
	return v;
}


- (MPVector2D*) scaleNum:(MPDecimal *)num den:(MPDecimal *)den
{
	MPVector2D* v = [[MPVector2D alloc] init];
	v.x = [[self.x mul: num] div: den];
	v.y = [[self.y mul: num] div: den];
	return v;
}

- (MPVector2D*) negate
{
	MPVector2D* v = [[MPVector2D alloc] init];
	v.x = self.x.negate;
	v.y = self.y.negate;
	return v;
}

- (MPVector2D*) rotateCCW
{
	MPVector2D* v = [[MPVector2D alloc] init];
	v.x = self.y.negate;
	v.y = self.x;
	return v;
}


- (MPDecimal*) length
{
	
	MPDecimal* v = [self dot: self];
	return v.sqrt;
}

- (v3i_t) toVectorWithShift: (long) shift
{
	v3i_t r = {[self.x toInt32WithQ: shift], [self.y toInt32WithQ: shift], 0, shift};
	return r;
}

- (vector_t) toFloatVector
{
	vector_t r = {[self.x toDouble], [self.y toDouble], 0.0, 0.0};
	return r;
}

- (long) minIntegerBits
{
	return MAX(self.x.integerBits, self.y.integerBits);
}

- (double) angleTo: (MPVector2D*) b
{
	MPDecimal* abc = [self cross: b];
	MPDecimal* abd = [self dot: b];
	
	double angle = atan2(abc.toDouble, abd.toDouble);
	return angle;
}

- (double) floatAngle
{
	return atan2(self.y.toDouble, self.x.toDouble);
}

- (BOOL) isEqual:(MPVector2D*)object
{
	if (![object isMemberOfClass: [self class]])
		return NO;
	
	return ([self.x compare: object.x] == 0) && ([self.y compare: object.y] == 0);
	
}
- (BOOL) isEqualToVector: (MPVector2D*) object
{
	return ([self.x compare: object.x] == 0) && ([self.y compare: object.y] == 0);
}

@end
