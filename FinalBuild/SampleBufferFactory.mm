/*
 * SampleBufferFactory.mm
 * CameraInject
 *
 * Converts a UIImage into a CMSampleBuffer that can be forwarded to
 * AVCaptureVideoDataOutputSampleBufferDelegate receivers.
 *
 * Rootless path: /var/jb/Library/CameraInject/inject.png
 */

#include "SampleBufferFactory.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <UIKit/UIKit.h>

// ---------------------------------------------------------------------------
// CVPixelBuffer from UIImage
// ---------------------------------------------------------------------------
CVPixelBufferRef CICreatePixelBufferFromImage(UIImage *image, CGSize targetSize) {
    if (!image) return NULL;

    CGFloat w = targetSize.width  > 0 ? targetSize.width  : image.size.width;
    CGFloat h = targetSize.height > 0 ? targetSize.height : image.size.height;

    NSDictionary *options = @{
        (NSString *)kCVPixelBufferCGImageCompatibilityKey    : @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey     : @{}
    };

    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        (size_t)w, (size_t)h,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)options,
        &pixelBuffer
    );

    if (status != kCVReturnSuccess || !pixelBuffer) return NULL;

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        baseAddr,
        (size_t)w, (size_t)h,
        8,
        CVPixelBufferGetBytesPerRow(pixelBuffer),
        colorSpace,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
    );

    if (ctx) {
        // Flip coordinate system (UIKit vs CoreGraphics)
        CGContextTranslateCTM(ctx, 0, h);
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image.CGImage);
        CGContextRelease(ctx);
    }

    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    return pixelBuffer;
}

// ---------------------------------------------------------------------------
// CMSampleBuffer from UIImage, optionally cloned from a reference buffer
// ---------------------------------------------------------------------------
CMSampleBufferRef CICreateSampleBufferFromImage(UIImage *image, CMSampleBufferRef referenceBuf) {
    // Determine output size from reference buffer or fall back to image size
    CGSize targetSize = image.size;
    if (referenceBuf) {
        CVImageBufferRef refImg = CMSampleBufferGetImageBuffer(referenceBuf);
        if (refImg) {
            targetSize = CGSizeMake(
                CVPixelBufferGetWidth(refImg),
                CVPixelBufferGetHeight(refImg)
            );
        }
    }

    CVPixelBufferRef pixelBuffer = CICreatePixelBufferFromImage(image, targetSize);
    if (!pixelBuffer) return NULL;

    // -----------------------------------------------------------------------
    // Build timing info — reuse from reference buffer when available so the
    // host app sees monotonically increasing presentation timestamps.
    // -----------------------------------------------------------------------
    CMSampleTimingInfo timingInfo = kCMTimingInfoInvalid;
    if (referenceBuf) {
        CMSampleTimingInfo refTiming;
        if (CMSampleBufferGetSampleTimingInfo(referenceBuf, 0, &refTiming) == noErr) {
            timingInfo = refTiming;
        }
    } else {
        timingInfo.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock());
        timingInfo.duration              = CMTimeMake(1, 30); // 30 fps placeholder
        timingInfo.decodeTimeStamp       = kCMTimeInvalid;
    }

    // -----------------------------------------------------------------------
    // Build video format description from the pixel buffer
    // -----------------------------------------------------------------------
    CMVideoFormatDescriptionRef fmtDesc = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &fmtDesc);
    if (!fmtDesc) {
        CVPixelBufferRelease(pixelBuffer);
        return NULL;
    }

    // -----------------------------------------------------------------------
    // Create the sample buffer
    // -----------------------------------------------------------------------
    CMSampleBufferRef sampleBuffer = NULL;
    CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        fmtDesc,
        &timingInfo,
        &sampleBuffer
    );

    CFRelease(fmtDesc);
    CVPixelBufferRelease(pixelBuffer);

    // Propagate attachments from reference (e.g. orientation, display layer hints)
    if (sampleBuffer && referenceBuf) {
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(referenceBuf, false);
        if (attachments && CFArrayGetCount(attachments) > 0) {
            CFDictionaryRef srcDict = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
            CFArrayRef dstAttachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
            if (dstAttachments && CFArrayGetCount(dstAttachments) > 0) {
                CFMutableDictionaryRef dstDict =
                    (CFMutableDictionaryRef)CFArrayGetValueAtIndex(dstAttachments, 0);
                CFDictionaryApplyFunction(srcDict, [](const void *k, const void *v, void *ctx){
                    CFDictionarySetValue((CFMutableDictionaryRef)ctx, k, v);
                }, dstDict);
            }
        }
    }

    return sampleBuffer; // caller must CFRelease
}
