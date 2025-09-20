#include "../include/Common.h"

#ifdef PLATFORM_OSX

#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>

#include <atomic>
#include <cstddef>
#include <cstdlib>
#include <memory>
#include <unordered_map>

#include "ghostty.h"
#include "ghostty_bridge.h"

#define RUN_ON_MAIN(block)                                  \
  if ([NSThread isMainThread]) {                            \
    block();                                                \
  } else {                                                  \
    dispatch_sync(dispatch_get_main_queue(), block);        \
  }

extern bool GhosttyDebugEnabled();
extern void GhosttyDebugLog(const char *fmt, ...);

namespace {

struct SurfaceEntry;
class GhosttyAppController;

static std::atomic<int32_t> g_next_surface_id{1};

}  // namespace

@interface GhosttySurfaceView : NSView
@property(nonatomic, assign) int32_t surfaceId;
@property(nonatomic, assign) CGFloat backingScale;
@property(nonatomic, assign) SurfaceEntry *surfaceEntry;
- (instancetype)initWithFrame:(NSRect)frame controller:(GhosttyAppController *)controller;
- (void)updateDrawableSize;
@end

namespace {

struct SurfaceEntry {
  int32_t id = -1;
  ghostty_surface_t surface = nullptr;
  __weak GhosttySurfaceView *view = nil;
  __weak NSView *container = nil;
  double scale = 1.0;
  bool occluded = false;
};

class GhosttyAppController {
 public:
  static GhosttyAppController &Shared() {
    static GhosttyAppController instance;
    return instance;
  }

  bool Initialized() const { return app_ != nullptr; }

  int32_t CreateSurface(NSView *container, CGRect frame, double scale) {
    if (!Initialized() || container == nil) {
      return -1;
    }

    if (GhosttyDebugEnabled()) {
      const char *containerClass = container ? object_getClassName(container) : "<null>";
      GhosttyDebugLog("CreateSurface(container=%p class=%s) frame=(%.2f, %.2f, %.2f, %.2f) scale=%.2f",
                      container,
                      containerClass,
                      frame.origin.x,
                      frame.origin.y,
                      frame.size.width,
                      frame.size.height,
                      scale);
    }

    if (scale <= 0.0) {
      scale = container.window ? container.window.backingScaleFactor : NSScreen.mainScreen.backingScaleFactor;
    }

    auto entry = std::make_shared<SurfaceEntry>();
    entry->id = g_next_surface_id.fetch_add(1);
    entry->scale = scale;
    entry->container = container;

    GhosttySurfaceView *view = [[GhosttySurfaceView alloc] initWithFrame:frame controller:this];
    if (view == nil) {
      GhosttyDebugLog("CreateSurface -> failed to allocate GhosttySurfaceView");
      return -1;
    }

    entry->view = view;
    view.surfaceId = entry->id;
    view.surfaceEntry = entry.get();
    view.backingScale = scale;
    [container addSubview:view positioned:NSWindowAbove relativeTo:nil];
    [view setNeedsLayout:YES];
    [view layoutSubtreeIfNeeded];
    [view updateDrawableSize];

    ghostty_surface_config_s surface_cfg = ghostty_surface_config_new();
    surface_cfg.platform_tag = GHOSTTY_PLATFORM_MACOS;
    surface_cfg.platform.macos.nsview = (__bridge void *)view;
    surface_cfg.userdata = entry.get();
    surface_cfg.scale_factor = scale;
    surface_cfg.wait_after_command = false;

    ghostty_surface_t surface = ghostty_surface_new(app_, &surface_cfg);
    if (!surface) {
      [view removeFromSuperview];
      GhosttyDebugLog("CreateSurface -> ghostty_surface_new failed");
      return -1;
    }

    entry->surface = surface;
    surfaces_by_id_.emplace(entry->id, entry);
    surfaces_by_handle_[surface] = entry;

    const uint32_t pixel_width = static_cast<uint32_t>(round(frame.size.width * scale));
    const uint32_t pixel_height = static_cast<uint32_t>(round(frame.size.height * scale));

    ghostty_surface_set_content_scale(surface, scale, scale);
    ghostty_surface_set_size(surface, pixel_width, pixel_height);
    ghostty_surface_set_focus(surface, container.window ? container.window.isKeyWindow : true);

    ScheduleTick();
    GhosttyDebugLog("CreateSurface -> id=%d surface=%p view=%p layer=%s",
                    entry->id,
                    surface,
                    view,
                    object_getClassName(view.layer));
    return entry->id;
  }

  bool DestroySurface(int32_t surface_id) {
    auto it = surfaces_by_id_.find(surface_id);
    if (it == surfaces_by_id_.end()) {
      return false;
    }

    GhosttyDebugLog("DestroySurface id=%d", surface_id);

    std::shared_ptr<SurfaceEntry> entry = it->second;
    GhosttySurfaceView *view = entry->view;
    if (view) {
      [view removeFromSuperview];
      view.surfaceEntry = nullptr;
      GhosttyDebugLog("DestroySurface removing view layer=%s", view.layer ? object_getClassName(view.layer) : "<nil>");
    }
    entry->container = nil;

    ghostty_surface_t surface = entry->surface;
    if (surface) {
      ghostty_surface_free(surface);
      surfaces_by_handle_.erase(surface);
    }

    surfaces_by_id_.erase(it);
    return true;
  }

  bool ResizeSurface(int32_t surface_id, CGRect frame, double scale) {
    SurfaceEntry *entry = EntryForSurface(surface_id);
    if (!entry) {
      return false;
    }

    GhosttyDebugLog("ResizeSurface id=%d frame=(%.2f, %.2f, %.2f, %.2f) scale=%.2f",
                    surface_id,
                    frame.origin.x,
                    frame.origin.y,
                    frame.size.width,
                    frame.size.height,
                    scale);

    if (scale <= 0.0) {
      scale = entry->scale;
    }

    entry->scale = scale;
    GhosttySurfaceView *view = entry->view;
    if (view) {
      view.backingScale = scale;
      view.frame = frame;
      [view updateDrawableSize];
    }

    if (entry->surface) {
      const uint32_t pixel_width = static_cast<uint32_t>(round(frame.size.width * scale));
      const uint32_t pixel_height = static_cast<uint32_t>(round(frame.size.height * scale));
      ghostty_surface_set_content_scale(entry->surface, scale, scale);
      ghostty_surface_set_size(entry->surface, pixel_width, pixel_height);
    }

    ScheduleTick();
    return true;
  }

  bool SetFocus(int32_t surface_id, bool focus) {
    SurfaceEntry *entry = EntryForSurface(surface_id);
    if (!entry || !entry->surface) {
      return false;
    }
    GhosttyDebugLog("SetFocus id=%d focus=%s", surface_id, focus ? "true" : "false");
    ghostty_surface_set_focus(entry->surface, focus);
    return true;
  }

  bool SetOcclusion(int32_t surface_id, bool occluded) {
    SurfaceEntry *entry = EntryForSurface(surface_id);
    if (!entry || !entry->surface) {
      return false;
    }
    entry->occluded = occluded;
    GhosttyDebugLog("SetOcclusion id=%d occluded=%s", surface_id, occluded ? "true" : "false");
    ghostty_surface_set_occlusion(entry->surface, occluded);
    return true;
  }

  bool SendKey(int32_t surface_id, const ghostty_input_key_s &key) {
    SurfaceEntry *entry = EntryForSurface(surface_id);
    if (!entry || !entry->surface) {
      return false;
    }
    GhosttyDebugLog("SendKey id=%d", surface_id);
    return ghostty_surface_key(entry->surface, key);
  }

  bool SendText(int32_t surface_id, const char *utf8, size_t len) {
    SurfaceEntry *entry = EntryForSurface(surface_id);
    if (!entry || !entry->surface || utf8 == nullptr) {
      return false;
    }
    GhosttyDebugLog("SendText id=%d len=%zu", surface_id, len);
    ghostty_surface_text(entry->surface, utf8, static_cast<uintptr_t>(len));
    return true;
  }

  SurfaceEntry *EntryForSurface(int32_t surface_id) {
    auto it = surfaces_by_id_.find(surface_id);
    if (it == surfaces_by_id_.end()) {
      return nullptr;
    }
    return it->second.get();
  }

  SurfaceEntry *EntryForHandle(ghostty_surface_t handle) {
    auto it = surfaces_by_handle_.find(handle);
    if (it == surfaces_by_handle_.end()) {
      return nullptr;
    }
    std::shared_ptr<SurfaceEntry> entry = it->second.lock();
    return entry ? entry.get() : nullptr;
  }

  void ScheduleTick() {
    if (pending_tick_.test_and_set(std::memory_order_acq_rel)) {
      return;
    }
    GhosttyDebugLog("ScheduleTick queued");
    dispatch_async(dispatch_get_main_queue(), ^{
      pending_tick_.clear(std::memory_order_release);
      if (app_) {
        GhosttyDebugLog("ghostty_app_tick");
        ghostty_app_tick(app_);

        for (auto &pair : surfaces_by_id_) {
          std::shared_ptr<SurfaceEntry> entry = pair.second;
          if (entry && entry->surface) {
            GhosttyDebugLog("ghostty_surface_draw id=%d", entry->id);
            ghostty_surface_draw(entry->surface);
            if (entry->view) {
              [entry->view setNeedsDisplay:YES];
              CALayer *layer = entry->view.layer;
              if (layer) {
                [layer setNeedsDisplay];
              }
            }
          }
        }
      }
    });
  }

  static void RuntimeWakeup(void *userdata) {
    auto *controller = static_cast<GhosttyAppController *>(userdata);
    if (!controller) {
      return;
    }
    GhosttyDebugLog("RuntimeWakeup");
    controller->ScheduleTick();
  }

  static bool RuntimeAction(ghostty_app_t app,
                            ghostty_target_s target,
                            ghostty_action_s action) {
    auto *controller = static_cast<GhosttyAppController *>(ghostty_app_userdata(app));
    if (!controller) {
      return false;
    }

    SurfaceEntry *entry = nullptr;
    if (target.tag == GHOSTTY_TARGET_SURFACE) {
      entry = controller->EntryForHandle(target.target.surface);
    }

    switch (action.tag) {
      case GHOSTTY_ACTION_SET_TITLE:
        if (entry && action.action.set_title.title) {
          GhosttyNativeEmitSetTitle(entry->id, action.action.set_title.title);
          return true;
        }
        break;
      case GHOSTTY_ACTION_RING_BELL:
        if (entry) {
          GhosttyNativeEmitBell(entry->id);
          return true;
        }
        break;
      case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
        if (entry) {
          GhosttyNativeEmitSurfaceExit(entry->id,
                                       false,
                                       action.action.child_exited.exit_code);
          return true;
        }
        break;
      default:
        break;
    }

    return false;
  }

 private:
  GhosttyAppController() {
    int rc = ghostty_init(0, nullptr);
    if (rc != 0) {
      GhosttyDebugLog("ghostty_init failed rc=%d", rc);
      return;
    }

    if (GhosttyDebugEnabled()) {
      const char *resources = std::getenv("GHOSTTY_RESOURCES_DIR");
      const char *config_dir = std::getenv("GHOSTTY_CONFIG_DIR");
      GhosttyDebugLog("GhosttyAppController init resources=%s config_dir=%s",
                      resources ? resources : "<unset>",
                      config_dir ? config_dir : "<unset>");
    }

    config_ = ghostty_config_new();
    if (!config_) {
      GhosttyDebugLog("ghostty_config_new failed");
      return;
    }

#if defined(PLATFORM_OSX)
    ghostty_config_load_default_files(config_);
    ghostty_config_load_recursive_files(config_);
#endif
    ghostty_config_finalize(config_);

    runtime_ = {};
    runtime_.userdata = this;
    runtime_.supports_selection_clipboard = true;
    runtime_.wakeup_cb = &GhosttyAppController::RuntimeWakeup;
    runtime_.action_cb = &GhosttyAppController::RuntimeAction;
    runtime_.read_clipboard_cb = nullptr;
    runtime_.confirm_read_clipboard_cb = nullptr;
    runtime_.write_clipboard_cb = nullptr;
    runtime_.close_surface_cb = nullptr;

    app_ = ghostty_app_new(&runtime_, config_);
    if (!app_) {
      ghostty_config_free(config_);
      config_ = nullptr;
      GhosttyDebugLog("ghostty_app_new failed");
      return;
    }

    GhosttyDebugLog("ghostty_app_new app=%p", app_);
    ghostty_app_set_focus(app_, [NSApp isActive]);
  }

  ~GhosttyAppController() {
    for (auto &pair : surfaces_by_id_) {
      if (pair.second->surface) {
        ghostty_surface_free(pair.second->surface);
      }
    }
    surfaces_by_id_.clear();
    surfaces_by_handle_.clear();

    if (app_) {
      ghostty_app_free(app_);
      app_ = nullptr;
    }
    if (config_) {
      ghostty_config_free(config_);
      config_ = nullptr;
    }
  }

  ghostty_app_t app_ = nullptr;
  ghostty_config_t config_ = nullptr;
  ghostty_runtime_config_s runtime_{};
  std::unordered_map<int32_t, std::shared_ptr<SurfaceEntry>> surfaces_by_id_;
  std::unordered_map<void *, std::weak_ptr<SurfaceEntry>> surfaces_by_handle_;
  std::atomic_flag pending_tick_ = ATOMIC_FLAG_INIT;
};

CGRect FrameForContainer(NSView *container,
                         double x,
                         double y,
                         double width,
                         double height) {
  NSRect bounds = container.bounds;
  BOOL flipped = container.isFlipped;
  CGFloat effectiveY = flipped ? static_cast<CGFloat>(y)
                                : bounds.size.height - static_cast<CGFloat>(y) - static_cast<CGFloat>(height);
  return CGRectMake(static_cast<CGFloat>(x),
                    effectiveY,
                    static_cast<CGFloat>(width),
                    static_cast<CGFloat>(height));
}

}  // namespace

@implementation GhosttySurfaceView {
  GhosttyAppController *_controller;
}

- (instancetype)initWithFrame:(NSRect)frame controller:(GhosttyAppController *)controller {
  self = [super initWithFrame:frame];
  if (self) {
    _controller = controller;
    self.wantsLayer = YES;
    self.layer = [self makeBackingLayer];
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
    self.translatesAutoresizingMaskIntoConstraints = YES;
    self.autoresizingMask = NSViewNotSizable;

    CAMetalLayer *metalLayer = (CAMetalLayer *)self.layer;
    metalLayer.device = MTLCreateSystemDefaultDevice();
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    metalLayer.framebufferOnly = YES;
    metalLayer.presentsWithTransaction = NO;
    metalLayer.contentsScale = NSScreen.mainScreen.backingScaleFactor;
    GhosttyDebugLog("GhosttySurfaceView init layer=%s", object_getClassName(self.layer));
  }
  return self;
}

- (CALayer *)makeBackingLayer {
  GhosttyDebugLog("makeBackingLayer -> CAMetalLayer");
  return [CAMetalLayer layer];
}

- (BOOL)isFlipped {
  return YES;
}

- (void)setBackingScale:(CGFloat)backingScale {
  _backingScale = backingScale;
  GhosttyDebugLog("setBackingScale %.2f", backingScale);
  [self updateDrawableSize];
}

- (void)updateDrawableSize {
  CALayer *layer = self.layer;
  if (!layer) {
    return;
  }

  CGSize size = self.bounds.size;
  CGFloat scale = self.backingScale > 0.0 ? self.backingScale : NSScreen.mainScreen.backingScaleFactor;
  if ([layer respondsToSelector:@selector(setContentsScale:)]) {
    layer.contentsScale = scale;
  }

  if ([layer isKindOfClass:[CAMetalLayer class]]) {
    CAMetalLayer *metalLayer = (CAMetalLayer *)layer;
    metalLayer.drawableSize = CGSizeMake(size.width * scale, size.height * scale);
  }
  GhosttyDebugLog("updateDrawableSize layer=%s bounds=(%.2f, %.2f) scale=%.2f",
                  object_getClassName(layer),
                  size.width,
                  size.height,
                  scale);
}

- (void)setFrame:(NSRect)frameRect {
  [super setFrame:frameRect];
  GhosttyDebugLog("setFrame -> updateDrawableSize");
  [self updateDrawableSize];
}

@end

extern "C" bool GhosttyEnsureInitialized() {
  bool ok = GhosttyAppController::Shared().Initialized();
  GhosttyDebugLog("GhosttyEnsureInitialized -> %s", ok ? "true" : "false");
  return ok;
}

extern "C" int32_t GhosttySurfaceCreate(unsigned char *buffer,
                                         double x,
                                         double y,
                                         double width,
                                         double height,
                                         double scale) {
  if (!buffer) {
    return -1;
  }

  __block int32_t surfaceId = -1;
  RUN_ON_MAIN(^{
    __unsafe_unretained NSView **rootViewPtr =
        reinterpret_cast<__unsafe_unretained NSView **>(buffer);
    NSView *rootView = rootViewPtr ? *rootViewPtr : nil;
    if (!rootView) {
      GhosttyDebugLog("GhosttySurfaceCreate -> missing root view");
      return;
    }

    CGRect frame = FrameForContainer(rootView, x, y, width, height);
    surfaceId = GhosttyAppController::Shared().CreateSurface(rootView, frame, scale);
  });

  GhosttyDebugLog("GhosttySurfaceCreate buffer=%p -> id=%d", buffer, surfaceId);
  return surfaceId;
}

extern "C" bool GhosttySurfaceDestroy(int32_t surface_id) {
  __block bool result = false;
  RUN_ON_MAIN(^{ result = GhosttyAppController::Shared().DestroySurface(surface_id); });
  GhosttyDebugLog("GhosttySurfaceDestroy id=%d -> %s", surface_id, result ? "true" : "false");
  return result;
}

extern "C" bool GhosttySurfaceResize(int32_t surface_id,
                                      double x,
                                      double y,
                                      double width,
                                      double height,
                                      double scale) {
  __block bool result = false;
  RUN_ON_MAIN(^{
    GhosttyAppController &controller = GhosttyAppController::Shared();
    SurfaceEntry *entry = controller.EntryForSurface(surface_id);
    if (!entry) {
      return;
    }
    NSView *container = entry->container;
    if (!container) {
      return;
    }
    CGRect frame = FrameForContainer(container, x, y, width, height);
    result = controller.ResizeSurface(surface_id, frame, scale);
  });
  GhosttyDebugLog("GhosttySurfaceResize id=%d -> %s", surface_id, result ? "true" : "false");
  return result;
}

extern "C" bool GhosttySurfaceSetFocus(int32_t surface_id, bool focus) {
  __block bool result = false;
  RUN_ON_MAIN(^{ result = GhosttyAppController::Shared().SetFocus(surface_id, focus); });
  GhosttyDebugLog("GhosttySurfaceSetFocus id=%d focus=%s -> %s",
                  surface_id,
                  focus ? "true" : "false",
                  result ? "true" : "false");
  return result;
}

extern "C" bool GhosttySurfaceSetOccluded(int32_t surface_id, bool occluded) {
  __block bool result = false;
  RUN_ON_MAIN(^{ result = GhosttyAppController::Shared().SetOcclusion(surface_id, occluded); });
  GhosttyDebugLog("GhosttySurfaceSetOccluded id=%d occluded=%s -> %s",
                  surface_id,
                  occluded ? "true" : "false",
                  result ? "true" : "false");
  return result;
}

extern "C" bool GhosttySurfaceSendKey(int32_t surface_id, ghostty_input_key_s key) {
  __block bool result = false;
  RUN_ON_MAIN(^{ result = GhosttyAppController::Shared().SendKey(surface_id, key); });
  GhosttyDebugLog("GhosttySurfaceSendKey id=%d -> %s", surface_id, result ? "true" : "false");
  return result;
}

extern "C" bool GhosttySurfaceSendText(int32_t surface_id, const char *utf8, size_t len) {
  __block bool result = false;
  RUN_ON_MAIN(^{ result = GhosttyAppController::Shared().SendText(surface_id, utf8, len); });
  GhosttyDebugLog("GhosttySurfaceSendText id=%d len=%zu -> %s",
                  surface_id,
                  len,
                  result ? "true" : "false");
  return result;
}

#endif  // PLATFORM_OSX
