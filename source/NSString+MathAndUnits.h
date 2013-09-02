//
//  NSString+MathAndUnits.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 02.09.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
	MathUnit_none,
	MathUnit_length,
	MathUnit_time,
	MathUnit_last
} MathUnit;


@interface NSString (MathAndUnits)

- (BOOL) isValidNonEmptyMath;
- (double) valueWithUnit: (MathUnit) unit;

@end
