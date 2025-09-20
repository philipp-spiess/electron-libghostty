#include <napi.h>

#include <atomic>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <string>

#include "ghostty.h"
#include "ghostty_bridge.h"

extern "C" bool GhosttyEnsureInitialized();
extern "C" int32_t GhosttySurfaceCreate(unsigned char *buffer,
                                         double x,
                                         double y,
                                         double width,
                                         double height,
                                         double scale);
extern "C" bool GhosttySurfaceDestroy(int32_t surface_id);
extern "C" bool GhosttySurfaceResize(int32_t surface_id,
                                      double x,
                                      double y,
                                      double width,
                                      double height,
                                      double scale);
extern "C" bool GhosttySurfaceSetFocus(int32_t surface_id, bool focus);
extern "C" bool GhosttySurfaceSetOccluded(int32_t surface_id, bool occluded);
extern "C" bool GhosttySurfaceSendKey(int32_t surface_id, ghostty_input_key_s key);
extern "C" bool GhosttySurfaceSendText(int32_t surface_id, const char *utf8, size_t len);

bool GhosttyDebugEnabled() {
  static bool enabled = [] {
    const char *env = std::getenv("GHOSTTY_DEBUG");
    if (!env) {
      env = std::getenv("LIBGHOSTTY_DEBUG");
    }
    if (!env) {
      return false;
    }
    return env[0] != '\0' && env[0] != '0';
  }();
  return enabled;
}

void GhosttyDebugLog(const char *fmt, ...) {
  if (!GhosttyDebugEnabled()) {
    return;
  }
  std::va_list args;
  va_start(args, fmt);
  std::fprintf(stderr, "[ghostty-native] ");
  std::vfprintf(stderr, fmt, args);
  std::fprintf(stderr, "\n");
  va_end(args);
}

namespace {

enum class EventType {
  kSetTitle,
  kBell,
  kSurfaceExit,
  kClipboardReadRequest,
  kClipboardWrite,
};

struct EventPayload {
  EventType type;
  int32_t surface_id = -1;
  std::string text;
  bool flag = false;
  uint32_t exit_code = 0;
  uint64_t request_id = 0;
  ghostty_clipboard_e clipboard = GHOSTTY_CLIPBOARD_STANDARD;
};

const char *ClipboardToString(ghostty_clipboard_e clipboard) {
  switch (clipboard) {
    case GHOSTTY_CLIPBOARD_STANDARD:
      return "standard";
    case GHOSTTY_CLIPBOARD_SELECTION:
      return "selection";
    default:
      return "unknown";
  }
}

class GhosttyEventEmitter {
 public:
  static GhosttyEventEmitter &Instance() {
    static GhosttyEventEmitter instance;
    return instance;
  }

  void SetHandler(const Napi::Env &env, const Napi::Function &handler) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (tsfn_) {
      tsfn_.Release();
      tsfn_ = Napi::ThreadSafeFunction();
    }
    tsfn_ = Napi::ThreadSafeFunction::New(env,
                                          handler,
                                          "ghostty-events",
                                          0,
                                          1);
  }

  void Emit(EventPayload &&payload) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!tsfn_) {
      return;
    }

    auto *heap_payload = new EventPayload(std::move(payload));
    napi_status status = tsfn_.BlockingCall(heap_payload,
                                            [](Napi::Env env,
                                               Napi::Function handler,
                                               EventPayload *payload) {
                                              Napi::Object event = Napi::Object::New(env);
                                              event.Set("surfaceId", Napi::Number::New(env, payload->surface_id));
                                              switch (payload->type) {
                                                case EventType::kSetTitle:
                                                  event.Set("type", Napi::String::New(env, "set-title"));
                                                  event.Set("title", Napi::String::New(env, payload->text));
                                                  break;
                                                case EventType::kBell:
                                                  event.Set("type", Napi::String::New(env, "bell"));
                                                  break;
                                                case EventType::kSurfaceExit:
                                                  event.Set("type", Napi::String::New(env, "surface-exit"));
                                                  event.Set("processAlive",
                                                            Napi::Boolean::New(env, payload->flag));
                                                  event.Set("exitCode", Napi::Number::New(env, payload->exit_code));
                                                  break;
                                                case EventType::kClipboardReadRequest:
                                                  event.Set("type", Napi::String::New(env, "clipboard-read"));
                                                  event.Set("requestId",
                                                            Napi::Number::New(env, static_cast<double>(payload->request_id)));
                                                  event.Set("clipboard",
                                                            Napi::String::New(env, ClipboardToString(payload->clipboard)));
                                                  break;
                                                case EventType::kClipboardWrite:
                                                  event.Set("type", Napi::String::New(env, "clipboard-write"));
                                                  event.Set("text", Napi::String::New(env, payload->text));
                                                  event.Set("clipboard",
                                                            Napi::String::New(env, ClipboardToString(payload->clipboard)));
                                                  event.Set("confirm", Napi::Boolean::New(env, payload->flag));
                                                  break;
                                              }

                                              handler.Call({event});
                                              delete payload;
                                            });
    if (status != napi_ok) {
      delete heap_payload;
    }
  }

  void EmitSetTitle(int32_t surface_id, const std::string &title) {
    EventPayload payload;
    payload.type = EventType::kSetTitle;
    payload.surface_id = surface_id;
    payload.text = title;
    Emit(std::move(payload));
  }

  void EmitBell(int32_t surface_id) {
    EventPayload payload;
    payload.type = EventType::kBell;
    payload.surface_id = surface_id;
    Emit(std::move(payload));
  }

  void EmitSurfaceExit(int32_t surface_id, bool process_alive, uint32_t exit_code) {
    EventPayload payload;
    payload.type = EventType::kSurfaceExit;
    payload.surface_id = surface_id;
    payload.flag = process_alive;
    payload.exit_code = exit_code;
    Emit(std::move(payload));
  }

  void EmitClipboardRead(int32_t surface_id,
                         uint64_t request_id,
                         ghostty_clipboard_e clipboard) {
    EventPayload payload;
    payload.type = EventType::kClipboardReadRequest;
    payload.surface_id = surface_id;
    payload.request_id = request_id;
    payload.clipboard = clipboard;
    Emit(std::move(payload));
  }

  void EmitClipboardWrite(int32_t surface_id,
                          const std::string &text,
                          ghostty_clipboard_e clipboard,
                          bool confirm) {
    EventPayload payload;
    payload.type = EventType::kClipboardWrite;
    payload.surface_id = surface_id;
    payload.text = text;
    payload.clipboard = clipboard;
    payload.flag = confirm;
    Emit(std::move(payload));
  }

 private:
  std::mutex mutex_;
  Napi::ThreadSafeFunction tsfn_;
};

GhosttyEventEmitter &Emitter() {
  return GhosttyEventEmitter::Instance();
}

// Utils ----------------------------------------------------------------------

double RequireDouble(const Napi::Env &env, const Napi::Object &obj, const char *key) {
  if (!obj.Has(key) || !obj.Get(key).IsNumber()) {
    Napi::TypeError::New(env, std::string("Frame is missing numeric property '") + key + "'")
        .ThrowAsJavaScriptException();
    return 0.0;
  }
  return obj.Get(key).As<Napi::Number>().DoubleValue();
}

double OptionalDouble(const Napi::Object &obj, const char *key, double fallback) {
  if (!obj.Has(key)) {
    return fallback;
  }
  Napi::Value value = obj.Get(key);
  if (!value.IsNumber()) {
    return fallback;
  }
  return value.As<Napi::Number>().DoubleValue();
}

Napi::Value EnsureInitialized(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  bool ok = GhosttyEnsureInitialized();
  GhosttyDebugLog("EnsureInitialized -> %s", ok ? "true" : "false");
  return Napi::Boolean::New(env, ok);
}

Napi::Value CreateSurface(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() < 2 || !info[0].IsBuffer() || !info[1].IsObject()) {
    Napi::TypeError::New(env, "Expected (handle:Buffer, frame:Object[, scale:number])")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  auto handle = info[0].As<Napi::Buffer<unsigned char>>();
  auto frame = info[1].As<Napi::Object>();
  double x = RequireDouble(env, frame, "x");
  double y = RequireDouble(env, frame, "y");
  double width = RequireDouble(env, frame, "width");
  double height = RequireDouble(env, frame, "height");
  if (env.IsExceptionPending()) {
    return env.Null();
  }

  double scale = 0.0;
  if (info.Length() > 2 && info[2].IsNumber()) {
    scale = info[2].As<Napi::Number>().DoubleValue();
  } else {
    scale = OptionalDouble(frame, "scale", 0.0);
  }

  int32_t id = GhosttySurfaceCreate(handle.Data(), x, y, width, height, scale);
  GhosttyDebugLog("CreateSurface handle=%p frame=(%.2f, %.2f, %.2f, %.2f) scale=%.2f -> id=%d",
                  handle.Data(),
                  x,
                  y,
                  width,
                  height,
                  scale,
                  id);
  return Napi::Number::New(env, id);
}

Napi::Value ResizeSurface(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsObject()) {
    Napi::TypeError::New(env, "Expected (id:number, frame:Object[, scale:number])")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  int32_t id = info[0].As<Napi::Number>().Int32Value();
  auto frame = info[1].As<Napi::Object>();
  double x = RequireDouble(env, frame, "x");
  double y = RequireDouble(env, frame, "y");
  double width = RequireDouble(env, frame, "width");
  double height = RequireDouble(env, frame, "height");
  if (env.IsExceptionPending()) {
    return env.Null();
  }

  double scale = 0.0;
  if (info.Length() > 2 && info[2].IsNumber()) {
    scale = info[2].As<Napi::Number>().DoubleValue();
  } else {
    scale = OptionalDouble(frame, "scale", 0.0);
  }

  bool ok = GhosttySurfaceResize(id, x, y, width, height, scale);
  GhosttyDebugLog("ResizeSurface id=%d frame=(%.2f, %.2f, %.2f, %.2f) scale=%.2f -> %s",
                  id,
                  x,
                  y,
                  width,
                  height,
                  scale,
                  ok ? "true" : "false");
  return Napi::Boolean::New(env, ok);
}

Napi::Value DestroySurface(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() < 1 || !info[0].IsNumber()) {
    Napi::TypeError::New(env, "Expected surface id").ThrowAsJavaScriptException();
    return env.Null();
  }

  int32_t id = info[0].As<Napi::Number>().Int32Value();
  bool ok = GhosttySurfaceDestroy(id);
  GhosttyDebugLog("DestroySurface id=%d -> %s", id, ok ? "true" : "false");
  return Napi::Boolean::New(env, ok);
}

Napi::Value SetFocus(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsBoolean()) {
    Napi::TypeError::New(env, "Expected (id:number, focus:boolean)").ThrowAsJavaScriptException();
    return env.Null();
  }
  int32_t id = info[0].As<Napi::Number>().Int32Value();
  bool focus = info[1].As<Napi::Boolean>().Value();
  bool ok = GhosttySurfaceSetFocus(id, focus);
  GhosttyDebugLog("SetFocus id=%d focus=%s -> %s", id, focus ? "true" : "false", ok ? "true" : "false");
  return Napi::Boolean::New(env, ok);
}

Napi::Value SetOccluded(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsBoolean()) {
    Napi::TypeError::New(env, "Expected (id:number, occluded:boolean)").ThrowAsJavaScriptException();
    return env.Null();
  }
  int32_t id = info[0].As<Napi::Number>().Int32Value();
  bool occluded = info[1].As<Napi::Boolean>().Value();
  bool ok = GhosttySurfaceSetOccluded(id, occluded);
  GhosttyDebugLog("SetOccluded id=%d occluded=%s -> %s",
                  id,
                  occluded ? "true" : "false",
                  ok ? "true" : "false");
  return Napi::Boolean::New(env, ok);
}

Napi::Value SendKey(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsObject()) {
    Napi::TypeError::New(env, "Expected (id:number, event:Object)").ThrowAsJavaScriptException();
    return env.Null();
  }
  int32_t id = info[0].As<Napi::Number>().Int32Value();
  Napi::Object obj = info[1].As<Napi::Object>();

  ghostty_input_key_s key{};
  key.action = static_cast<ghostty_input_action_e>(obj.Get("action").As<Napi::Number>().Int32Value());
  key.mods = static_cast<ghostty_input_mods_e>(obj.Get("mods").As<Napi::Number>().Uint32Value());
  key.consumed_mods = static_cast<ghostty_input_mods_e>(obj.Get("consumedMods").As<Napi::Number>().Uint32Value());
  key.keycode = obj.Get("keycode").As<Napi::Number>().Uint32Value();
  key.unshifted_codepoint = obj.Has("codepoint") && obj.Get("codepoint").IsNumber()
                               ? obj.Get("codepoint").As<Napi::Number>().Uint32Value()
                               : 0;
  key.composing = obj.Has("composing") && obj.Get("composing").IsBoolean()
                      ? obj.Get("composing").As<Napi::Boolean>().Value()
                      : false;

  std::string textStorage;
  if (obj.Has("text") && obj.Get("text").IsString()) {
    textStorage = obj.Get("text").As<Napi::String>().Utf8Value();
    key.text = textStorage.c_str();
  } else {
    key.text = nullptr;
  }

  bool ok = GhosttySurfaceSendKey(id, key);
  GhosttyDebugLog("SendKey id=%d action=%d mods=%u -> %s",
                  id,
                  static_cast<int>(key.action),
                  static_cast<unsigned>(key.mods),
                  ok ? "true" : "false");
  return Napi::Boolean::New(env, ok);
}

Napi::Value SendText(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsString()) {
    Napi::TypeError::New(env, "Expected (id:number, text:string)").ThrowAsJavaScriptException();
    return env.Null();
  }
  int32_t id = info[0].As<Napi::Number>().Int32Value();
  std::string text = info[1].As<Napi::String>().Utf8Value();
  bool ok = GhosttySurfaceSendText(id, text.c_str(), text.size());
  GhosttyDebugLog("SendText id=%d bytes=%zu -> %s", id, text.size(), ok ? "true" : "false");
  return Napi::Boolean::New(env, ok);
}

Napi::Value SetEventHandler(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  if (info.Length() < 1 || !info[0].IsFunction()) {
    Napi::TypeError::New(env, "Expected function argument").ThrowAsJavaScriptException();
    return env.Null();
  }
  Napi::Function handler = info[0].As<Napi::Function>();
  Emitter().SetHandler(env, handler);
  GhosttyDebugLog("Registered event handler");
  return env.Null();
}

}  // namespace

// Native event emitters -------------------------------------------------------

void GhosttyNativeEmitSetTitle(int32_t surface_id, const char *title) {
  std::string value = title ? std::string(title) : std::string();
  Emitter().EmitSetTitle(surface_id, value);
}

void GhosttyNativeEmitBell(int32_t surface_id) {
  Emitter().EmitBell(surface_id);
}

void GhosttyNativeEmitSurfaceExit(int32_t surface_id, bool process_alive, uint32_t exit_code) {
  Emitter().EmitSurfaceExit(surface_id, process_alive, exit_code);
}

void GhosttyNativeEmitClipboardReadRequest(int32_t surface_id,
                                           uint64_t request_id,
                                           ghostty_clipboard_e clipboard) {
  Emitter().EmitClipboardRead(surface_id, request_id, clipboard);
}

void GhosttyNativeEmitClipboardWrite(int32_t surface_id,
                                     const char *text,
                                     ghostty_clipboard_e clipboard,
                                     bool confirm) {
  std::string value = text ? std::string(text) : std::string();
  Emitter().EmitClipboardWrite(surface_id, value, clipboard, confirm);
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
  exports.Set("ensureInitialized", Napi::Function::New(env, EnsureInitialized));
  exports.Set("createSurface", Napi::Function::New(env, CreateSurface));
  exports.Set("resizeSurface", Napi::Function::New(env, ResizeSurface));
  exports.Set("destroySurface", Napi::Function::New(env, DestroySurface));
  exports.Set("setFocus", Napi::Function::New(env, SetFocus));
  exports.Set("setOccluded", Napi::Function::New(env, SetOccluded));
  exports.Set("sendKey", Napi::Function::New(env, SendKey));
  exports.Set("sendText", Napi::Function::New(env, SendText));
  exports.Set("setEventHandler", Napi::Function::New(env, SetEventHandler));

  // Backwards compatibility aliases
  exports.Set("createOverlay", Napi::Function::New(env, CreateSurface));
  exports.Set("updateOverlay", Napi::Function::New(env, ResizeSurface));
  exports.Set("removeOverlay", Napi::Function::New(env, DestroySurface));

  return exports;
}

NODE_API_MODULE(native_overlay, Init)
