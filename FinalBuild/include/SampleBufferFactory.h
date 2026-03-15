#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#import <CoreMedia/CoreMedia.h>
#import <UIKit/UIKit.h>

/// Converts a UIImage into a CMSampleBuffer that AVFoundation delegates expect.
/// The returned buffer is retained — caller must CFRelease when done.
CMSampleBufferRef CICreateSampleBufferFromImage(UIImage *image, CMSampleBufferRef referenceBuf);

/// Creates a CVPixelBuffer from a UIImage, matching the given size.
CVPixelBufferRef CICreatePixelBufferFromImage(UIImage *image, CGSize targetSize);

#ifdef __cplusplus
}
#endif
