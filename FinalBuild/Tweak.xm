/*
 * Tweak.xm
 * CameraInject — rootless jailbreak tweak (iOS 15.x)
 */

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <os/lock.h>
#import <CoreFoundation/CoreFoundation.h>
#import "SampleBufferFactory.h"

// ============================================================================
#pragma mark - Constants & Globals
// ============================================================================

static NSString *const kConfigPath     = @"/var/jb/Library/CameraInject/config.plist";
static NSString *const kDefaultImgPath = @"/var/jb/Library/CameraInject/inject.png";

static UIImage       *gInjectImage = nil;
static BOOL           gEnabled     = YES;
static NSString      *gImagePath   = nil;
static os_unfair_lock gImageLock   = OS_UNFAIR_LOCK_INIT;

// ============================================================================
#pragma mark - Config Loading
// ============================================================================

static void CILoadConfig(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    NSDictionary *cfg = [NSDictionary dictionaryWithContentsOfFile:kConfigPath];
    os_unfair_lock_lock(&gImageLock);

    gEnabled     = cfg[@"enabled"]   ? [cfg[@"enabled"] boolValue] : YES;
    gImagePath   = cfg[@"imagePath"] ?: kDefaultImgPath;
    gInjectImage = gEnabled ? [UIImage imageWithContentsOfFile:gImagePath] : nil;

    if (gEnabled && !gInjectImage) {
        CGSize sz = CGSizeMake(640, 480);
        UIGraphicsBeginImageContextWithOptions(sz, YES, 1.0);
        [[UIColor colorWithRed:0.1 green:0.6 blue:0.9 alpha:1.0] setFill];
        UIRectFill(CGRectMake(0, 0, sz.width, sz.height));
        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont boldSystemFontOfSize:36],
            NSForegroundColorAttributeName: UIColor.whiteColor
        };
        [@"CameraInject" drawAtPoint:CGPointMake(160, 210) withAttributes:attrs];
        gInjectImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }

    os_unfair_lock_unlock(&gImageLock);
    NSLog(@"[CameraInject] Config loaded. enabled=%d imagePath=%@", gEnabled, gImagePath);
}

static void CILoadConfigInitial(void) {
    CILoadConfig(NULL, NULL, NULL, NULL, NULL);
}

static UIImage *CIGetInjectImage(void) {
    os_unfair_lock_lock(&gImageLock);
    UIImage *img = gInjectImage;
    os_unfair_lock_unlock(&gImageLock);
    return img;
}

// ============================================================================
#pragma mark - Proxy Delegate
// ============================================================================

@interface CIProxyDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak)   id<AVCaptureVideoDataOutputSampleBufferDelegate> realDelegate;
@property (nonatomic, strong) dispatch_queue_t realQueue;
@end

@implementation CIProxyDelegate

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    if (!gEnabled) {
        [self.realDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }
    UIImage *img = CIGetInjectImage();
    if (!img) {
        [self.realDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }
    CMSampleBufferRef fakeBuf = CICreateSampleBufferFromImage(img, sampleBuffer);
    if (fakeBuf) {
        [self.realDelegate captureOutput:output didOutputSampleBuffer:fakeBuf fromConnection:connection];
        CFRelease(fakeBuf);
    } else {
        [self.realDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
  didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    if ([self.realDelegate respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)]) {
        [self.realDelegate captureOutput:output didDropSampleBuffer:sampleBuffer fromConnection:connection];
    }
}

- (BOOL)respondsToSelector:(SEL)sel {
    return [super respondsToSelector:sel] || [self.realDelegate respondsToSelector:sel];
}
- (id)forwardingTargetForSelector:(SEL)sel {
    return self.realDelegate;
}

@end

// ============================================================================
#pragma mark - Associated-object key
// ============================================================================

static const void *kProxyDelegateKey = &kProxyDelegateKey;

// ============================================================================
#pragma mark - Hooks
// ============================================================================

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
                          queue:(dispatch_queue_t)sampleBufferCallbackQueue
{
    if (!delegate || !gEnabled) { %orig; return; }

    CIProxyDelegate *proxy = objc_getAssociatedObject(self, kProxyDelegateKey);
    if (!proxy || proxy.realDelegate != delegate) {
        proxy = [[CIProxyDelegate alloc] init];
        proxy.realDelegate = delegate;
        proxy.realQueue    = sampleBufferCallbackQueue;
        objc_setAssociatedObject(self, kProxyDelegateKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig(proxy, sampleBufferCallbackQueue);
}

- (id)sampleBufferDelegate {
    CIProxyDelegate *proxy = objc_getAssociatedObject(self, kProxyDelegateKey);
    return proxy ? proxy.realDelegate : %orig;
}

%end

%hook AVCaptureSession

- (void)startRunning {
    CILoadConfigInitial();
    %orig;
}

- (void)stopRunning {
    %orig;
}

%end

// ============================================================================
#pragma mark - Constructor
// ============================================================================

%ctor {
    CILoadConfigInitial();

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        CILoadConfig,
        CFSTR("com.yourname.camerainject.reload"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );

    NSLog(@"[CameraInject] Loaded. Image path: %@", gImagePath);
}
