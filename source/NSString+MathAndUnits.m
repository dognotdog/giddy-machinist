//
//  NSString+MathAndUnits.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 02.09.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "NSString+MathAndUnits.h"



@interface MAUExpression : NSObject

+ (instancetype) expressionWithString: (NSString*) text;



@property(nonatomic, strong) NSString* stringValue;

@end

@implementation NSString (MathAndUnits)

- (BOOL) isValidNonEmptyMath
{
	
}

- (double) valueWithUnit: (MathUnit) unit
{
	return NAN;
}

@end

@interface MAUEUnityOperator : MAUExpression

@property(nonatomic,strong) id operand;

@end

@interface MAUEBinaryOperator : MAUExpression

@property(nonatomic,strong) id firstOperand;
@property(nonatomic,strong) id secondOperand;

@end

@interface MAUENumberLiteral : MAUExpression

@property(nonatomic,strong) id value;

@end

@interface MAUEUnitExpression : MAUExpression

@property(nonatomic,strong) NSString* unit;
@property(nonatomic,strong) MAUExpression* operand;

@end

@implementation MAUExpression

+ (id) nextTokenFromScanner: (NSScanner*) scanner
{
	
	NSArray* nonNumberTokenStrings = @[@"(", @"[", @"{", @")", @"]", @"}",
									   @"*", @"/", @"+", @"-", @"^", @",",
									   @"mm", @"cm", @"m", @"inch", @"foot", @"degree", @"°", @"rad",
									   @"pi", @"e"];

	for (NSString* tokenString in nonNumberTokenStrings)
	{
		if ([scanner scanString: tokenString intoString: NULL])
		{
			return tokenString;
		}
	}
	
	NSDecimal decimal;
	if ([scanner scanDecimal: &decimal])
	{
		return [NSDecimalNumber decimalNumberWithDecimal: decimal];
	}

	return nil;
}


+ (NSArray*) tokensFromScanner: (NSScanner*) scanner
{
	
	NSMutableArray* tokens = [NSMutableArray array];
	
	while (!scanner.isAtEnd)
	{
		[tokens addObject: [self nextTokenFromScanner: scanner]];
	}
			
	
	return tokens;
}

+ (instancetype) expressionFromTokens: (NSArray*) tokens
{
	NSArray* validUnits = @[@"mm", @"cm", @"m", @"inch", @"foot", @"degree", @"°", @"rad"];
	NSArray* groupBeginMarkers = @[@"(", @"[", @"{"];
	NSArray* groupEndMarkers = @[@")", @"]", @"}"];
	NSDictionary* opPrecedences = @{@",":@0, @"+":@1, @"-":@1, @"*":@2, @"/":@2, @"^":@3};

	id lastExpression = nil;
	
	for (id token in tokens)
	{
		if (lastExpression)
		{
			if ([token isKindOfClass: [NSNumber class]])
			{
				
			}

		}
		if ([token isKindOfClass: [NSNumber class]])
		{
			if (lastExpression)
				[NSException raise: @"com.elmonkey.math.invalid-expression" format: @"No number expected."];
			
			MAUENumberLiteral* exp = [[MAUENumberLiteral alloc] init];
			exp.value = token;
			
			lastExpression = exp;
		}
		else
		{
			if ([validUnits containsObject: token])
			{
				if (!lastExpression)
					[NSException raise: @"com.elmonkey.math.invalid-expression" format: @"Number for unit not found."];

				MAUEUnitExpression* exp = [[MAUEUnitExpression alloc] init];
				exp.stringValue = token;
				exp.operand = lastExpression;
				lastExpression = exp;
			}
			else if ([opPrecedences objectForKey: token])
			{
				MAUEBinaryOperator* op = [[MAUEBinaryOperator alloc] init];
				op.stringValue = token;
				
				if (!lastExpression && [@"-" isEqualToString: token])
				{
					lastExpression = op;
				}
				else
				{
					if (!lastExpression)
						[NSException raise: @"com.elmonkey.math.invalid-expression" format: @"Number for operator not found."];
					
					if ([lastExpression isKindOfClass: [MAUEBinaryOperator class]])
					{
						NSInteger lastPrecedence = [[opPrecedences objectForKey: [lastExpression stringValue]] integerValue];
						NSInteger opPrecedence = [[opPrecedences objectForKey: op.stringValue] integerValue];
						
						if (opPrecedence < lastPrecedence)
						{
							op.firstOperand = lastExpression;
						}
					}
					else
					{
						op.firstOperand = lastExpression;
					
						lastExpression = op;
					}
				}
			}
		}
	}
	
}


+ (instancetype) expressionWithString: (NSString*) text
{
	
	NSScanner* scanner = [NSScanner scannerWithString: text];
	
	[scanner setCharactersToBeSkipped: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	NSMutableArray* stack = [[NSMutableArray alloc] init];
	
	[stack addObject: [[MAUEUnityOperator alloc] init]];
	
	return nil;
	
	//return [self expressionWithScanner: scanner stack: stack];
}


@end


@implementation MAUEUnityOperator

@end

@implementation MAUEBinaryOperator

@end


@implementation MAUENumberLiteral

@end

@implementation MAUEUnitExpression

@end

