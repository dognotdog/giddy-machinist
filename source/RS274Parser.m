//
//  RS274Parser.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 31.08.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import "RS274Parser.h"

#import "FoundationExtensions.h"


@interface RS274TextLine : NSObject
@property(nonatomic) ssize_t lineCount;
@property(nonatomic,strong) NSString* string;
@end


@implementation RS274Parser
{
	NSMutableArray* _currentCommandBlock;
}

static NSString* _removeComments(NSString* inText)
{
	long length = [inText length];
	NSMutableString* outText = [[NSMutableString alloc] initWithCapacity: length];
	
	
	for (long i = 0; i < length; ++i)
	{
		int c = [inText characterAtIndex: i];
		switch (c)
		{
			case '(':
			{
				NSRange commentEnd = [inText rangeOfString: @")" options: NSBackwardsSearch range:NSMakeRange(i, length-i)];
				
				if (commentEnd.location == NSNotFound)
					[NSException raise: @"RS274ParserError" format: @"Missing closing brace in comment"];
								
				i = commentEnd.location;

				break;
			}
			case ';':
				i = LONG_MAX-1;
				break;
			default:
				[outText appendFormat: @"%c", c];
				break;
		}
	}
	return outText;
}

- (void) prepareCommandBlock
{
	_currentCommandBlock = [[NSMutableArray alloc] init];
}

- (void) finishCommandBlock
{
	if ([_currentCommandBlock count])
	{
		if (!self.commandBlocks)
			self.commandBlocks = [NSMutableArray arrayWithObject: _currentCommandBlock];
		else
			[self.commandBlocks addObject: _currentCommandBlock];
	}
	
	_currentCommandBlock = nil;
}

- (NSArray*) parseString: (NSString*) inText named: (NSString*) name
{
	/*
	 Parse steps, per line:
	 1. evaluate numeric expressions in square brackets
	 2. remove comments
	 */
	NSArray* lines = [inText componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];
	
	lines = [lines indexedMap: ^id(id obj, NSInteger index) {
		RS274TextLine* line = [[RS274TextLine alloc] init];
		line.string = obj;
		line.lineCount = index;
		return line;
	}];
	
	
	NSMutableArray* commandLines = [NSMutableArray array];
	
	
	// parameter parsing & expression evaluation should occur before the command words are evaluated...
	// we'll just ignore this for now
	
	for ( RS274TextLine* rawLine in lines)
	{
		@autoreleasepool {
		NSString* text = _removeComments(rawLine.string);
		[self prepareCommandBlock];
		[self parseCString: [text UTF8String] length: strlen([text UTF8String])];
		[self finishCommandBlock];
		
		/*
		NSArray* commands = TokenizeTextLine(rawLine, 0, [rawLine.string length]);
		
		if ([commands count])
			[commandLines addObject: commands];
		 */
		}
	}

	return commandLines;
	
}

- (long) logError: (NSString*) format, ...
{
	va_list args;	
	va_start(args,format);
	NSLogv(format, args);
	va_end(args);
	
	return 0;
}

- (long) parseNumericOperatorString: (const char*) inText length: (long) length object: (id*) objPtr
{
	if (!length)
		return [self logError: @"Zero Length String"];
	
	long i = 0;
	switch (*inText)
	{
		case '+':
		case '-':
		{
			RS274Operator* op = [[RS274Operator alloc] init];
			op.precedenceLevel = 1;
			op.name = [NSString stringWithFormat: @"%c", *inText];
			if (objPtr)
				*objPtr = op;
			
			i += 1;
			break;
		}
		default:
			return [self logError: @"unknown operator"];

	}

	return i;

}
- (long) parseNumericConstantString: (const char*) inText length: (long) length object: (id*) objPtr
{
	if (!length)
		return [self logError: @"Zero Length String"];
	
	long i = 0;
	
	
	long lastDigitIndex = 0;
	while (isdigit(inText[lastDigitIndex]) || (inText[lastDigitIndex] == '.'))
		lastDigitIndex++;
	
	i = lastDigitIndex;
	
	NSString* string = [[NSString alloc] initWithBytes: inText length: lastDigitIndex encoding: NSASCIIStringEncoding];
	
	double val = [string doubleValue];
	
	if (objPtr)
		*objPtr = [NSNumber numberWithDouble: val];
	
	return i;
}

- (long) parseNumericObjectString: (const char*) inText length: (long) length object: (id*) objPtr
{
	if (!length)
		return [self logError: @"Zero Length String"];

	long i = 0;
	long k = 0;
	
	switch (*inText)
	{
		case ' ':
		case '\t':
			i += 1;
			k = [self parseNumericString: inText+1 length: length-1 object: objPtr];
			break;
			
		case '.':
		case '0':
		case '1':
		case '2':
		case '3':
		case '4':
		case '5':
		case '6':
		case '7':
		case '8':
		case '9':
		{
			k = [self parseNumericConstantString: inText length: length object: objPtr];
			break;
		}
		case '+':
		case '-':
		case '*':
		case '/':
		{
			k = [self parseNumericOperatorString: inText length: length object: objPtr];
			break;
		}

		default:
			return [self logError: @"Invalid Character '%c' in numeric object", *inText];
			break;
	}
	
	i += k;

	return i;
}

- (id) buildExpressionTree: (NSArray*) flatTokens
{
	long opIndex = 0;
	
	// operators and numbers are at this point just a flat list, when no parenthesis were used
	// so operators need to be assigned operands
	// this happens by repetitevly finding the highest precedence operator and assigning it its operands
	while ((opIndex != NSNotFound) && ([flatTokens count] > 1) )
	{
		long highestPrecedence = 0;
		for (long i = 0; i < [flatTokens count]; ++i)
		{
			id obj = [flatTokens objectAtIndex: i];
			if ([obj isKindOfClass: [RS274Operator class]])
				highestPrecedence = MAX(highestPrecedence, [obj precedenceLevel]);
		}
		opIndex = NSNotFound;

		for (long i = 0; i < [flatTokens count]; ++i)
		{
			id obj = [flatTokens objectAtIndex: i];
			if ([obj isKindOfClass: [RS274Operator class]] && ([obj precedenceLevel] == highestPrecedence))
			{
				opIndex = i;
				break;
			}
		}
		
		if (opIndex != NSNotFound)
		{
			RS274Operator* op = [flatTokens objectAtIndex: opIndex];
			if ([op.name isEqual: @"-"])
			{
				if (opIndex+1 >= [flatTokens count])
				{
					[self logError: @"Missing right operand"];
				}
				else if (opIndex > 0)
				{
					op.operands = [NSArray arrayWithObjects: [flatTokens objectAtIndex: opIndex-1],[flatTokens objectAtIndex: opIndex+1], nil];
					flatTokens = [flatTokens arrayByRemovingObjectsAtIndexes: [NSIndexSet indexSetWithIndex: opIndex+1]];
					flatTokens = [flatTokens arrayByRemovingObjectsAtIndexes: [NSIndexSet indexSetWithIndex: opIndex-1]];
				}
				else
				{
					op.operands = [NSArray arrayWithObjects: [flatTokens objectAtIndex: opIndex+1], nil];
					flatTokens = [flatTokens arrayByRemovingObjectsAtIndexes: [NSIndexSet indexSetWithIndex: opIndex+1]];
				}
			}
			else
				[self logError: @"Unsopported Operator: %@", op.name];
		}

	}
	
	if ([flatTokens count] != 1)
		[self logError: @"Invalid expression tree, more than one root token remaining"];
	
	return [flatTokens objectAtIndex: 0];
}

- (id) foldConstantsInExpression: (id) inExpr
{
	if ([inExpr isKindOfClass: [RS274Operator class]])
	{
		RS274Operator* op = inExpr;
		if ([op.name isEqual: @"-"])
		{
			if ([op.operands count] == 1)
			{
				id operand = [self foldConstantsInExpression: [op.operands objectAtIndex: 0]];
				if ([operand isKindOfClass: [NSNumber class]])
					return [NSNumber numberWithDouble: -[operand doubleValue]];
			}
			else if ([op.operands count] == 2)
			{
				id operand0 = [self foldConstantsInExpression: [op.operands objectAtIndex: 0]];
				id operand1 = [self foldConstantsInExpression: [op.operands objectAtIndex: 1]];
				if ([operand0 isKindOfClass: [NSNumber class]] && [operand1 isKindOfClass: [NSNumber class]])
					return [NSNumber numberWithDouble: [operand0 doubleValue]-[operand1 doubleValue]];
				
			}
		}
	}
	else if (([inExpr isKindOfClass: [NSNumber class]]))
	{
		return inExpr;
	}
	return inExpr;
}

- (long) parseNumericString: (const char*) inText length: (long) length object: (id*) objectPtr
{
	if (!length)
		return [self logError: @"Zero Length String"];
	
	long i = 0;
	long k = 0;
	
	NSMutableArray* numericObjects = [[NSMutableArray alloc] init];
	
	while (i < length)
	{
		id obj = nil;
		k = [self parseNumericObjectString: inText+i length: length-i object: &obj];
		
		if (!k)
			return [self logError: @"Unknown error parsing numeric string"];
		[numericObjects addObject: obj];
		
		i += k;
		if (![obj isKindOfClass: [RS274Operator class]])
			break;
	}
	
	id expressionTree = [self buildExpressionTree: numericObjects];
	
	id foldedExpression = [self foldConstantsInExpression: expressionTree];
	
	if (objectPtr)
		*objectPtr = foldedExpression;
	

	
	return i;
}



- (void) attachCommand: (id) command
{
//	NSLog(@"Command Received: %@", command);
	
	[_currentCommandBlock addObject: command];
	
}

- (long) parseCommandString: (const char*) inText length: (long) length
{
	if (!length)
		return [self logError: @"Zero Length String"];
	
	long i = 1;
	long k = 0;
	
	int cmdChar = *inText;
	
	id cmdValue = nil;
	
	k = [self parseNumericString: inText+i length: length-i object: &cmdValue];
	
	if (!k)
		return [self logError: @"Invalid command number"];
	i += k;
	
	RS274Command* command = [[RS274Command alloc] init];
	command.commandLetter = cmdChar;
	command.value = cmdValue;
	
	[self attachCommand: command];
	
	
	return i;
	
	
	
}

- (long) parseAssignmentString: (const char*) inText length: (long) length
{
	if (!length)
		return [self logError: @"Zero Length String"];
	return 0;
}

/*
static long _ignoreWhitespace(const char* txt, long length)
{
	for (long i = 0; i < length; ++i)
		if ((txt[i] != ' ') && (txt[i] != '\t'))
			return i;
	return length;
}
 */
- (long) parseParameterSetString: (const char*) inText length: (long) length
{
	if (!length)
		return [self logError: @"Zero Length Parameter Set String"];

	id parameterIndex = nil;
	id parameterValue = nil;
	
	if (*inText == '#')
		return [self logError: @"Parameter Assignment not starting with '#'"];
	
	long i = 1;
	long k = 0;
	
	k = [self parseNumericString: inText+i length: length-i object: &parameterIndex];
	
	if (!k)
		return [self logError: @"Invalid parameter index"];
	
	i += k;
	
	k = [self parseAssignmentString: inText+i length: length-i];
	
	if (!k)
		return [self logError: @"Missing assignment operator"];
	
	i += k;
	
	k = [self parseNumericString: inText+i length: length-i object: &parameterValue];
	
	if (!k)
		return [self logError: @"Invalid parameter value"];
	
	i += k;
	
	return i;
}

- (long) parseWordString: (const char*) inText length: (long) length
{
	if (!length)
		return 0;
	
	switch (toupper(*inText))
	{
		case ' ':
		case '\t':
		{
			return 1;
		}
		case '#':
		{
			long k = [self parseParameterSetString: inText length: length];
			if (!k)
				return [self logError: @"Unexpected error in parsing parameter set"];
			else
				return k;
		}
		case 'A':
		case 'B':
		case 'C':
		case 'D':
		case 'E':
		case 'F':
		case 'G':
		case 'H':
		case 'I':
		case 'J':
		case 'K':
		case 'L':
		case 'M':
		case 'N':
		case 'P':
		case 'Q':
		case 'R':
		case 'S':
		case 'T':
		case 'X':
		case 'Y':
		case 'Z':
		{
			long k = [self parseCommandString: inText length: length];
			if (!k)
				return 0;
			else
				return k;
		}
		default:
			return [self logError: @"Unexpected Character '%c'", *inText];
	}
}

- (void) parseCString: (const char*) inText length: (long) length
{
	if (!length)
		return;
	long i = 0;
	
	while (i < length)
	{
		long k = [self parseWordString: inText+i length: length-i];
		if (!k)
			break;
		i+= k;
	}
	
}

- (void) parseString: (NSString*) inText
{
	const char* inBuf = [inText UTF8String];
	size_t inSize = strlen(inBuf);
	
	
	[self parseCString: inBuf length: inSize];
}

@end

@implementation RS274TextLine

@synthesize lineCount, string;

@end


@implementation RS274Command

@synthesize commandLetter, value;

- (NSString*) description
{
	return [NSString stringWithFormat: @"%c:%@", commandLetter, self.value];
}

@end

@implementation RS274Operator

@synthesize precedenceLevel, name;

- (NSString*) description
{
	return self.name;
}

@end


