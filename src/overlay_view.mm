#include "../include/Common.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <map>

#ifdef PLATFORM_OSX
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#define RUN_ON_MAIN(block)                                  \
  if ([NSThread isMainThread]) {                            \
    block();                                                \
  } else {                                                  \
    dispatch_sync(dispatch_get_main_queue(), block);        \
  }

@interface NativeOverlayView : NSView
@property(nonatomic, strong) CALayer *backgroundLayer;
@property(nonatomic, strong) NSButton *toggleButton;
@property(nonatomic, strong) NSTextField *inputField;
@property(nonatomic, assign) BOOL useGreen;
- (void)applyCurrentTint;
@end

@implementation NativeOverlayView

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.wantsLayer = YES;
    CALayer *rootLayer = [CALayer layer];
    rootLayer.masksToBounds = NO;
    rootLayer.shadowOpacity = 0.45;
    rootLayer.shadowRadius = 18.0;
    rootLayer.shadowOffset = CGSizeZero;
    rootLayer.shadowColor = [[NSColor colorWithCalibratedRed:0.35
                                                      green:0.0
                                                       blue:0.04
                                                      alpha:0.6] CGColor];

    CALayer *background = [CALayer layer];
    background.masksToBounds = YES;
    background.cornerRadius = 0.0;
    background.backgroundColor = [[NSColor colorWithRed:0.82
                                                  green:0.18
                                                   blue:0.20
                                                  alpha:0.85] CGColor];
    background.borderWidth = 0.0;
    background.borderColor = nil;

    [rootLayer addSublayer:background];
    self.layer = rootLayer;
    self.backgroundLayer = background;

    NSButton *button = [NSButton buttonWithTitle:@"Toggle Color"
                                          target:self
                                          action:@selector(toggleColor:)];
    button.bezelStyle = NSBezelStyleRounded;
    button.translatesAutoresizingMaskIntoConstraints = YES;
    button.wantsLayer = YES;
    button.layer.cornerRadius = 6.0;
    self.toggleButton = button;

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSZeroRect];
    input.placeholderString = @"Type in the native overlay";
    input.translatesAutoresizingMaskIntoConstraints = YES;
    input.bordered = YES;
    input.bezelStyle = NSTextFieldRoundedBezel;
    input.font = [NSFont systemFontOfSize:14.0 weight:NSFontWeightRegular];
    self.inputField = input;

    self.useGreen = NO;
    [self addSubview:input];
    [self addSubview:button];
    [self applyCurrentTint];
  }
  return self;
}

- (void)layout {
  [super layout];
  self.backgroundLayer.frame = self.bounds;
  CGFloat contentWidth = MIN(self.bounds.size.width - 32.0, 320.0);
  CGFloat originX = NSMidX(self.bounds) - contentWidth / 2.0;

  CGFloat textFieldHeight = 28.0;
  self.inputField.frame = NSMakeRect(originX,
                                     NSMidY(self.bounds) - textFieldHeight - 8.0,
                                     contentWidth,
                                     textFieldHeight);

  CGFloat buttonHeight = 32.0;
  self.toggleButton.frame = NSMakeRect(originX,
                                       NSMidY(self.bounds) + 8.0,
                                       contentWidth,
                                       buttonHeight);
}

- (BOOL)isFlipped {
  return YES;
}

- (BOOL)isOpaque {
  return NO;
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (NSView *)hitTest:(NSPoint)point {
  return [super hitTest:point];
}

- (void)applyCurrentTint {
  NSColor *targetColor = self.useGreen
                             ? [NSColor colorWithRed:0.07 green:0.55 blue:0.30 alpha:0.85]
                             : [NSColor colorWithRed:0.82 green:0.18 blue:0.20 alpha:0.85];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.backgroundLayer.backgroundColor = targetColor.CGColor;
  [CATransaction commit];
}

- (void)toggleColor:(id)sender {
  (void)sender;
  self.useGreen = !self.useGreen;
  [self applyCurrentTint];
}

@end

static std::map<int, NativeOverlayView *> g_overlayViews;
static int g_nextOverlayId = 1;
static const void *kOverlayAssociationKey = &kOverlayAssociationKey;

static NativeOverlayView *CreateOrReuseOverlay(NSView *container) {
  NativeOverlayView *existing = objc_getAssociatedObject(container, kOverlayAssociationKey);
  if (existing) {
    return existing;
  }

  NativeOverlayView *overlay = [[NativeOverlayView alloc] initWithFrame:NSZeroRect];
  overlay.translatesAutoresizingMaskIntoConstraints = YES;
  overlay.layer.zPosition = 1000;

  objc_setAssociatedObject(container,
                           kOverlayAssociationKey,
                           overlay,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  return overlay;
}

extern "C" int NativeOverlayCreate(unsigned char *buffer,
                                    double x,
                                    double y,
                                    double width,
                                    double height,
                                    double scale) {
  if (!buffer) {
    return -1;
  }

  __block int overlayId = -1;
  RUN_ON_MAIN(^{
    NSView *rootView = *reinterpret_cast<NSView **>(buffer);
    if (!rootView) {
      return;
    }

    NSView *container = rootView;
    NativeOverlayView *overlay = CreateOrReuseOverlay(container);

    NSRect bounds = container.bounds;
    BOOL containerFlipped = container.isFlipped;
    CGFloat effectiveX = static_cast<CGFloat>(x);
    CGFloat effectiveY = containerFlipped ? static_cast<CGFloat>(y)
                                          : bounds.size.height - static_cast<CGFloat>(y) - static_cast<CGFloat>(height);
    CGFloat effectiveWidth = MAX(static_cast<CGFloat>(width), 1.0);
    CGFloat effectiveHeight = MAX(static_cast<CGFloat>(height), 1.0);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    overlay.frame = NSMakeRect(effectiveX, effectiveY, effectiveWidth, effectiveHeight);
    CGPathRef path = CGPathCreateWithRect(overlay.bounds, NULL);
    overlay.layer.shadowPath = path;
    CGPathRelease(path);

    CGFloat contentsScale = scale > 0.0 ? static_cast<CGFloat>(scale)
                                        : (container.window ? container.window.backingScaleFactor
                                                            : NSScreen.mainScreen.backingScaleFactor);
    overlay.layer.contentsScale = contentsScale;
    overlay.backgroundLayer.contentsScale = contentsScale;

    if (overlay.superview != container) {
      [container addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
    }

    [overlay setNeedsLayout:YES];
    [overlay layoutSubtreeIfNeeded];
    [overlay setNeedsDisplay:YES];

    [CATransaction commit];

    auto it = g_overlayViews.begin();
    for (; it != g_overlayViews.end(); ++it) {
      if (it->second == overlay) {
        overlayId = it->first;
        break;
      }
    }

    if (overlayId == -1) {
      overlayId = g_nextOverlayId++;
      g_overlayViews[overlayId] = overlay;
    }
  });

  return overlayId;
}

extern "C" void NativeOverlayUpdate(int overlayId,
                                     double x,
                                     double y,
                                     double width,
                                     double height,
                                     double scale) {
  RUN_ON_MAIN(^{
    auto it = g_overlayViews.find(overlayId);
    if (it == g_overlayViews.end()) {
      return;
    }

    NativeOverlayView *overlay = it->second;
    NSView *container = overlay.superview;
    if (!container) {
      return;
    }

    NSRect bounds = container.bounds;
    BOOL containerFlipped = container.isFlipped;
    CGFloat effectiveX = static_cast<CGFloat>(x);
    CGFloat effectiveY = containerFlipped ? static_cast<CGFloat>(y)
                                          : bounds.size.height - static_cast<CGFloat>(y) - static_cast<CGFloat>(height);
    CGFloat effectiveWidth = MAX(static_cast<CGFloat>(width), 1.0);
    CGFloat effectiveHeight = MAX(static_cast<CGFloat>(height), 1.0);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    overlay.frame = NSMakeRect(effectiveX, effectiveY, effectiveWidth, effectiveHeight);
    CGPathRef path = CGPathCreateWithRect(overlay.bounds, NULL);
    overlay.layer.shadowPath = path;
    CGPathRelease(path);

    CGFloat contentsScale = scale > 0.0 ? static_cast<CGFloat>(scale)
                                        : (container.window ? container.window.backingScaleFactor
                                                            : NSScreen.mainScreen.backingScaleFactor);
    overlay.layer.contentsScale = contentsScale;
    overlay.backgroundLayer.contentsScale = contentsScale;

    [overlay setNeedsLayout:YES];
    [overlay layoutSubtreeIfNeeded];
    [overlay setNeedsDisplay:YES];

    [CATransaction commit];
  });
}

extern "C" void NativeOverlayRemove(int overlayId) {
  RUN_ON_MAIN(^{
    auto it = g_overlayViews.find(overlayId);
    if (it == g_overlayViews.end()) {
      return;
    }

    NativeOverlayView *overlay = it->second;
    if (overlay.superview) {
      objc_setAssociatedObject(overlay.superview,
                               kOverlayAssociationKey,
                               nil,
                               OBJC_ASSOCIATION_ASSIGN);
    }
    [overlay removeFromSuperview];
    g_overlayViews.erase(it);
  });
}

#endif // PLATFORM_OSX
