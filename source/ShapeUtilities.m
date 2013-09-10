//
//  ShapeUtilities.m
//
//

#import "ShapeUtilities.h"
#import <AppKit/AppKit.h>


@implementation ShapeUtilities

- (id)init
{
    self = [super init];
    if (self) {
        // No init stuff needed.
    }
    
    return self;
}

+ (NSBezierPath*) createBezierPathFromData: (NSData*) data
{	
	//  Created by Dömötör Gulyás on 2013-08-24. Copyright 2013.

	NSString* dataString = [[NSString alloc] initWithData: data encoding: NSASCIIStringEncoding];
	
	NSRange prologueEndRange = [dataString rangeOfString: @"%%EndProlog"];
	NSRange trailerRange = [dataString rangeOfString: @"%%PageTrailer"];
	NSRange pageSetupEndRange = [dataString rangeOfString: @"%%EndPageSetup"];
	NSRange setupEndRange = [dataString rangeOfString: @"%%EndSetup"];
	
	NSRange endStuffRange = NSMakeRange(0, 0);
	
	if (prologueEndRange.location != NSNotFound)
		endStuffRange = NSUnionRange(prologueEndRange, endStuffRange);
	if (pageSetupEndRange.location != NSNotFound)
		endStuffRange = NSUnionRange(pageSetupEndRange, endStuffRange);
	if (setupEndRange.location != NSNotFound)
		endStuffRange = NSUnionRange(setupEndRange, endStuffRange);
	
	assert(endStuffRange.location != NSNotFound);
	
	
	if (trailerRange.location == NSNotFound)
		trailerRange.location = dataString.length;
	
	NSString* epsString = [[dataString substringToIndex: trailerRange.location] substringFromIndex: endStuffRange.location + endStuffRange.length];
	
	return [self createBezierPathFromEPSPageString: epsString];
}

+ (NSBezierPath*)createBezierPathFromEPSPageString:(NSString *)epsString
{
	//  Created by Dömötör Gulyás on 2013-08-24. Copyright 2013.

	/*
	 A full postscript interpreter would be too much effort, so we try to focus on the subset that is common for creating lines in in a page, as you would use for generating contours for machining.
	 */
	
	NSArray* epsLines = [epsString componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];
	
	NSBezierPath* bpath = [[NSBezierPath alloc] init];
	
	NSAffineTransform* pageTransform = nil;
	
	CGPoint currentPoint, controlPoint1, controlPoint2, prevPoint;

	for (NSString* _line in epsLines)
	{
		NSString* line = _line; // re-assign because enumeration pointer can't be changed
		@autoreleasepool {
			
			line = [line stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];

			NSRange commentRange = [line rangeOfString: @"%"];
			if (commentRange.location != NSNotFound)
				line = [line substringToIndex: commentRange.location];
			
			NSRange beforeCmdRange = [line rangeOfCharacterFromSet: [NSCharacterSet whitespaceCharacterSet] options: NSBackwardsSearch];
			if (beforeCmdRange.location == NSNotFound)
			{
				// no whitespace found, so either no command at all, or only a command
				// if the latter, check
				NSCharacterSet* charset = [NSCharacterSet characterSetWithCharactersInString: line];
				if ([[NSCharacterSet letterCharacterSet] isSupersetOfSet: charset])
				{
					// if the string is all letters, we continue parsing it, else dump it
					beforeCmdRange.location = 0;
					beforeCmdRange.length = 0;
				}
				else
					continue;
			}
			
			NSString* cmdString = [line substringFromIndex: beforeCmdRange.location+beforeCmdRange.length];
			
			NSScanner* lineScanner = [NSScanner scannerWithString: [line substringToIndex: beforeCmdRange.location]];
			
			if ([cmdString isEqualToString: @"moveto"] || [cmdString isEqualToString: @"mo"] || [cmdString isEqualToString: @"m"] || [cmdString isEqualToString: @"M"])
			{
				[lineScanner scanDouble: &currentPoint.x];
				[lineScanner scanDouble: &currentPoint.y];
				[bpath moveToPoint: currentPoint];

			}
			else if ([cmdString isEqualToString: @"lineto"] || [cmdString isEqualToString: @"li"] || [cmdString isEqualToString: @"l"] || [cmdString isEqualToString: @"L"])
			{
				[lineScanner scanDouble: &currentPoint.x];
				[lineScanner scanDouble: &currentPoint.y];
				[bpath lineToPoint: currentPoint];
			}
			else if ([cmdString isEqualToString: @"curveto"] || [cmdString isEqualToString: @"cv"] || [cmdString isEqualToString: @"c"] || [cmdString isEqualToString: @"C"])
			{
				[lineScanner scanDouble: &controlPoint1.x];
				[lineScanner scanDouble: &controlPoint1.y];
				[lineScanner scanDouble: &controlPoint2.x];
				[lineScanner scanDouble: &controlPoint2.y];
				[lineScanner scanDouble: &currentPoint.x];
				[lineScanner scanDouble: &currentPoint.y];
				[bpath curveToPoint: currentPoint controlPoint1: controlPoint1 controlPoint2: controlPoint2];
			}
			else if ([cmdString isEqualToString: @"v"] || [cmdString isEqualToString: @"V"])
			{
				[lineScanner scanDouble: &controlPoint1.x];
				[lineScanner scanDouble: &controlPoint1.y];
				[lineScanner scanDouble: &currentPoint.x];
				[lineScanner scanDouble: &currentPoint.y];
				[bpath curveToPoint: currentPoint controlPoint1: prevPoint controlPoint2: controlPoint2];
			}
			else if ([cmdString isEqualToString: @"y"] || [cmdString isEqualToString: @"Y"])
			{
				[lineScanner scanDouble: &controlPoint1.x];
				[lineScanner scanDouble: &controlPoint1.y];
				[lineScanner scanDouble: &currentPoint.x];
				[lineScanner scanDouble: &currentPoint.y];
				[bpath curveToPoint: currentPoint controlPoint1: controlPoint1 controlPoint2: currentPoint];
			}
			else if ([cmdString isEqualToString: @"closepath"] || [cmdString isEqualToString: @"cp"])
			{
				[bpath closePath];
			}
			else if ([cmdString isEqualToString: @"f"] || [cmdString isEqualToString: @"F"])
			{
				[bpath closePath];
			}
			else if ([cmdString isEqualToString: @"clp"])
			{
				// what was setup so far was a clipping path, we ignore it (illustrator)
				bpath = [[NSBezierPath alloc] init];
			}
			else if ([cmdString isEqualToString: @"translate"])
			{
				NSAffineTransformStruct tr = {1.0,0.0,0.0,1.0,0.0,0.0};
				
				[lineScanner scanDouble: &tr.m11];
				[lineScanner scanDouble: &tr.m22];
				
				[lineScanner scanString: @"scale" intoString: NULL];
				
				[lineScanner scanDouble: &tr.tX];
				[lineScanner scanDouble: &tr.tY];
				
				tr.tX *= tr.m11;
				tr.tY *= tr.m22;

				pageTransform = [[NSAffineTransform alloc] init];
				pageTransform.transformStruct = tr;
			}

			
			prevPoint = currentPoint;

		}
	}
	
	if (pageTransform)
		[bpath transformUsingAffineTransform: pageTransform];
	
	return bpath;
}

+ (NSBezierPath*)createBezierPathFromEPSString:(NSString *)epsString
{
	//  Created by Jeff Menter on 4/20/11.
	//  Copyright 2011 Jeff Menter. No rights reserved.

	// this works only for a very restricted subset, use above method instead
	
	// Declare some floats for the incoming point data.
	CGFloat currentPoint_x = 0.0;
	CGFloat currentPoint_y = 0.0;
	CGFloat controlPoint1_x = 0.0;
	CGFloat controlPoint1_y = 0.0;
	CGFloat controlPoint2_x = 0.0;
	CGFloat controlPoint2_y = 0.0;
	CGFloat previousPoint_x = 0.0;
	CGFloat previousPoint_y = 0.0;
	
	// These are the markers used in the EPS chunk. We create a NSCharacterSet to use with the NSScanners.
	NSCharacterSet *pathPointMarkers = [NSCharacterSet characterSetWithCharactersInString:@"mMcCvVlLyYfF"];
	
	// This scanner scans the totality of the incoming string.
	NSScanner *epsStringScanner = [NSScanner scannerWithString:epsString];
	
	// Needed for the marker to marker substrings.
	NSString *pointSubString;
	// Need a NSScanner as well.
	NSScanner *pointSubStringScanner;
	// We need this mutable for now. We'll return this cast as non-mutable.
	NSBezierPath* bpath = [[NSBezierPath alloc] init];
	
	// Go through the string character by character till we reach the end.
	while ([epsStringScanner isAtEnd] == NO) {
		// Scan up to a marker and put that chunk in a substring.
		[epsStringScanner scanUpToCharactersFromSet:pathPointMarkers intoString:&pointSubString];
		// Scanner for the substring.
		pointSubStringScanner = [NSScanner scannerWithString:pointSubString];
		
		if (epsStringScanner.isAtEnd)
			break;
		
		// Check to see what kind of marker we've found.
		// m or M is moveToPoint.
		if ([epsString characterAtIndex:[epsStringScanner scanLocation]] == 'm' ||
			[epsString characterAtIndex:[epsStringScanner scanLocation]] == 'M') {
			// Get the two floats we expect for this marker and assign them.
			[pointSubStringScanner scanDouble:&currentPoint_x];
			[pointSubStringScanner scanDouble:&currentPoint_y];
			// Execute the proper CGPath operation.
			[bpath moveToPoint: CGPointMake(currentPoint_x, currentPoint_y)];
		}
		// c or C is "curve from and to" with a control point from the previous point.
		if ([epsString characterAtIndex:[epsStringScanner scanLocation]] == 'c' ||
			[epsString characterAtIndex:[epsStringScanner scanLocation]] == 'C') {
			// Get the six floats we expect.
			[pointSubStringScanner scanDouble:&controlPoint1_x];
			[pointSubStringScanner scanDouble:&controlPoint1_y];
			[pointSubStringScanner scanDouble:&controlPoint2_x];
			[pointSubStringScanner scanDouble:&controlPoint2_y];
			[pointSubStringScanner scanDouble:&currentPoint_x];
			[pointSubStringScanner scanDouble:&currentPoint_y];
			// Do it up.
			[bpath curveToPoint: CGPointMake(currentPoint_x, currentPoint_y) controlPoint1: CGPointMake(controlPoint1_x, controlPoint1_y) controlPoint2: CGPointMake(controlPoint2_x, controlPoint2_y)];
		}
		// v or V is "curve to only". No handle from the point we came from.
		if ([epsString characterAtIndex:[epsStringScanner scanLocation]] == 'v' ||
			[epsString characterAtIndex:[epsStringScanner scanLocation]] == 'V') {
			// Since there is no handle from the point we came from, we just assign the previous
			// control point's coordinates.
			[pointSubStringScanner scanDouble:&controlPoint1_x];
			[pointSubStringScanner scanDouble:&controlPoint1_y];
			[pointSubStringScanner scanDouble:&currentPoint_x];
			[pointSubStringScanner scanDouble:&currentPoint_y];
			// Make it so.
			[bpath curveToPoint: CGPointMake(currentPoint_x, currentPoint_y) controlPoint1: CGPointMake(previousPoint_x, previousPoint_y) controlPoint2: CGPointMake(controlPoint1_x, controlPoint1_y)];
		}
		// y or Y is "curve from only". No handle on the point we're going to.
		if ([epsString characterAtIndex:[epsStringScanner scanLocation]] == 'y' ||
			[epsString characterAtIndex:[epsStringScanner scanLocation]] == 'Y') {
			[pointSubStringScanner scanDouble:&controlPoint1_x];
			[pointSubStringScanner scanDouble:&controlPoint1_y];
			[pointSubStringScanner scanDouble:&currentPoint_x];
			[pointSubStringScanner scanDouble:&currentPoint_y];
			// Aw yeah.
			[bpath curveToPoint: CGPointMake(currentPoint_x, currentPoint_y) controlPoint1: CGPointMake(controlPoint1_x, controlPoint1_y) controlPoint2: CGPointMake(currentPoint_x, currentPoint_y)];
		}
		// l or L is "line to point". Simple.
		if ([epsString characterAtIndex:[epsStringScanner scanLocation]] == 'l' ||
			[epsString characterAtIndex:[epsStringScanner scanLocation]] == 'L') {
			[pointSubStringScanner scanDouble:&currentPoint_x];
			[pointSubStringScanner scanDouble:&currentPoint_y];
			// Totally appropriate.
			[bpath lineToPoint: CGPointMake(currentPoint_x, currentPoint_y)];
		}
		// f or F is "close this subpath and start a new one." When you're drawing the resulting
		// path, use even-odd fill rules to make compound paths appear as you would expect.
		if ([epsString characterAtIndex:[epsStringScanner scanLocation]] == 'f' ||
			[epsString characterAtIndex:[epsStringScanner scanLocation]] == 'F') {
			[bpath closePath];
		}
		// Assign these in case we get one of those whacky "curve to only" commands next time through.
		previousPoint_x = currentPoint_x;
		previousPoint_y = currentPoint_y;
		// Put the scan location of the scanner one character ahead so it will continue on.
		[epsStringScanner setScanLocation:[epsStringScanner scanLocation] + 1];
	}
	// Return the path as a plain CGPathRef. I don't see why not?
	return bpath;
}

- (void)dealloc
{

}

@end
