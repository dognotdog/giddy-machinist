//
//  PolySkelVideoGenerator.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 15.08.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "PolySkelVideoGenerator.h"
#import "LayerInspectorView.h"
#import "PolygonSkeletizer.h"
#import "MPVector2D.h"

@import CoreVideo;
@import AVFoundation;
@import AppKit;

@implementation PolySkelVideoGenerator
{
	NSUInteger currentFrame;
}

- (CVPixelBufferRef) pixelBufferFromCGImage: (CGImageRef) image andSize:(CGSize) size
{
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
							 [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
							 [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
							 nil];
    CVPixelBufferRef pxbuffer = NULL;
	
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, size.width,
										  size.height, kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef) options,
										  &pxbuffer);
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
	
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    NSParameterAssert(pxdata != NULL);
	
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, size.width,
												 size.height, 8, 4*size.width, rgbColorSpace,
												 kCGImageAlphaNoneSkipFirst);
    NSParameterAssert(context);
    CGContextConcatCTM(context, CGAffineTransformMakeRotation(0));
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),
                                           CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
	
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
	
    return pxbuffer;
}


- (NSBitmapImageRep*) generateImageSized: (CGSize) size // generates the texture without drawing texture to current context
{
	NSImage * image = [[NSImage alloc] initWithSize: size];
	
	//	NSGraphicsContext* oldContext = [NSGraphicsContext currentContext];
	
	[image lockFocus];
	[[NSGraphicsContext currentContext] setShouldAntialias: YES];
	CGContextSetShouldSmoothFonts([[NSGraphicsContext currentContext] graphicsPort], YES);
	
	//[self.layerView drawRect: CGRectMake(0.0f, 0.0f, size.width, size.height)];
	
	NSBitmapImageRep * bitmap = [[NSBitmapImageRep alloc] initWithFocusedViewRect: CGRectMake(0.0f, 0.0f, size.width, size.height)];
	[image unlockFocus];
	
	
	return bitmap;
	
}



- (void) recordMovieToURL: (NSURL*) movieUrl withSize: (CGSize) size skeleton: (PolygonSkeletizer*) skeletizer finishedCallback: (void(^)(void)) finishedCallback
{
	NSError *outError;
	NSURL *outputURL = movieUrl;
	AVAssetWriter *assetWriter = [AVAssetWriter assetWriterWithURL:outputURL fileType:AVFileTypeQuickTimeMovie error: &outError];
	assert(assetWriter != nil);
	
	AVAssetWriterInput *assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings: @{AVVideoCodecKey : AVVideoCodecH264, AVVideoWidthKey : [NSNumber numberWithInt: size.width], AVVideoHeightKey : [NSNumber numberWithInt: size.height]}];
	// Add the input to the writer if possible.
	if ([assetWriter canAddInput:assetWriterInput])
		[assetWriter addInput:assetWriterInput];
	
	
	NSDictionary *pixelBufferAttributes = @{
											(__bridge id)kCVPixelBufferCGImageCompatibilityKey : [NSNumber numberWithBool: YES],
											(__bridge id)kCVPixelBufferCGBitmapContextCompatibilityKey : [NSNumber numberWithBool: YES],
											(__bridge id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt: kCVPixelFormatType_32ARGB]
											};
	AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput: assetWriterInput sourcePixelBufferAttributes: pixelBufferAttributes];
	
	[assetWriter startWriting];
	
	[assetWriter startSessionAtSourceTime: kCMTimeZero];
	
	
	__block NSUInteger frameCount = 0;
	
	LayerInspectorView* layerView = [[LayerInspectorView alloc] initWithFrame: CGRectMake(0.0, 0.0, size.width, size.height)];

	
	[assetWriterInput requestMediaDataWhenReadyOnQueue: dispatch_get_main_queue() usingBlock: ^{
		while ([assetWriterInput isReadyForMoreMediaData])
		{
			@autoreleasepool {
				if (frameCount == skeletizer.doneSteps.count)
				{
					[assetWriterInput markAsFinished];
					[assetWriter finishWriting];
					
					finishedCallback();
					break;
				}
				
				PolySkelPhase* phase = [skeletizer.doneSteps objectAtIndex: frameCount];
				layerView.outlinePaths = phase.outlinePaths;
				layerView.motorcyclePaths = phase.motorcyclePaths;
				layerView.activeSpokePaths = phase.activeSpokePaths;
				layerView.terminatedSpokePaths = phase.terminatedSpokePaths;
				[layerView removeAllOffsetOutlinePaths];
				[layerView addOffsetOutlinePaths: phase.waveFrontPaths];
				
				layerView.markerPaths = @[];
				
				if (phase.location)
				{
					vector_t loc = phase.location.toFloatVector;
					CGPoint X = CGPointMake(loc.farr[0], loc.farr[1]);
					
					NSBezierPath* bpath = [NSBezierPath bezierPathWithOvalInRect: CGRectMake(X.x-1.0, X.y-1.0, 2.0, 2.0)];
					
					layerView.markerPaths = @[bpath];
				}

				NSImage * image = [[NSImage alloc] initWithSize: size];
							
				[image lockFocus];
				[[NSGraphicsContext currentContext] setShouldAntialias: YES];
				CGContextSetShouldSmoothFonts([[NSGraphicsContext currentContext] graphicsPort], YES);
				
				[layerView drawRect: CGRectMake(0.0f, 0.0f, size.width, size.height) withOutline: YES withMotorcycles: YES withSpokes: YES withWavefronts: YES withThinWalls: YES];
				
				NSBitmapImageRep * bitmap = [[NSBitmapImageRep alloc] initWithFocusedViewRect: CGRectMake(0.0f, 0.0f, size.width, size.height)];
				[image unlockFocus];
				
				/*
				NSBitmapImageRep* bitmap = [layerView bitmapImageRepForCachingDisplayInRect: CGRectMake(0.0f, 0.0f, size.width, size.height)];
				
				NSImage* image = [[NSImage alloc] initWithSize: size];
				[image addRepresentation: bitmap];

				 */
				
				// Get the next sample buffer.
				CVBufferRef buffer = [self pixelBufferFromCGImage: [bitmap CGImage] andSize: bitmap.size];
				if (buffer)
				{
					CMTime frameTime = CMTimeMake(frameCount*100, 2997);
					// If it exists, append the next sample buffer to the output file.
					[adaptor appendPixelBuffer: buffer withPresentationTime:frameTime];
					
					CVBufferRelease(buffer);
					buffer = nil;
					frameCount++;
				}
			}
		}
	}];
	



}

@end
