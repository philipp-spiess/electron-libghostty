#include <napi.h>

#ifdef __APPLE__
extern "C" int NativeOverlayCreate(unsigned char *buffer,
                                    double x,
                                    double y,
                                    double width,
                                    double height,
                                    double scale);
extern "C" void NativeOverlayUpdate(int overlayId,
                                     double x,
                                     double y,
                                     double width,
                                     double height,
                                     double scale);
extern "C" void NativeOverlayRemove(int overlayId);
#endif

namespace {

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

Napi::Value CreateOverlay(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (info.Length() < 2 || !info[0].IsBuffer() || !info[1].IsObject()) {
    Napi::TypeError::New(env, "Expected (handle:Buffer, frame:{x,y,width,height,scale?})")
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
  double scale = OptionalDouble(frame, "scale", 0.0);

#ifdef __APPLE__
  int id = NativeOverlayCreate(handle.Data(), x, y, width, height, scale);
  return Napi::Number::New(env, id);
#else
  (void)handle;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
  (void)scale;
  return Napi::Number::New(env, -1);
#endif
}

Napi::Value UpdateOverlay(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsObject()) {
    Napi::TypeError::New(env, "Expected (id:number, frame:{x,y,width,height,scale?})")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  int id = info[0].As<Napi::Number>().Int32Value();
  auto frame = info[1].As<Napi::Object>();

  double x = RequireDouble(env, frame, "x");
  double y = RequireDouble(env, frame, "y");
  double width = RequireDouble(env, frame, "width");
  double height = RequireDouble(env, frame, "height");
  if (env.IsExceptionPending()) {
    return env.Null();
  }
  double scale = OptionalDouble(frame, "scale", 0.0);

#ifdef __APPLE__
  NativeOverlayUpdate(id, x, y, width, height, scale);
#endif
  return env.Undefined();
}

Napi::Value RemoveOverlay(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (info.Length() < 1 || !info[0].IsNumber()) {
    Napi::TypeError::New(env, "Expected overlay id number").ThrowAsJavaScriptException();
    return env.Null();
  }

  int id = info[0].As<Napi::Number>().Int32Value();

#ifdef __APPLE__
  NativeOverlayRemove(id);
#else
  (void)id;
#endif
  return env.Undefined();
}

} // namespace

Napi::Object Init(Napi::Env env, Napi::Object exports) {
  exports.Set("createOverlay", Napi::Function::New(env, CreateOverlay));
  exports.Set("updateOverlay", Napi::Function::New(env, UpdateOverlay));
  exports.Set("removeOverlay", Napi::Function::New(env, RemoveOverlay));
  return exports;
}

NODE_API_MODULE(native_overlay, Init)
