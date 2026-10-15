#include <napi/native_api.h>
#include <multimodalinput/oh_input_manager.h>
#include <atomic>
#include <cstdint>
#include <cmath>
#include <memory>
#include <mutex>

// The interceptor owns no event memory. Copy scalars in the callback; never retain Input_KeyEvent*.
namespace SystemKeyCaptureNapi {
namespace {
struct Event { int32_t code, action, window, display, id; int64_t time; uint64_t token; };
std::mutex mutex;
std::mutex operations;
napi_threadsafe_function sink = nullptr;
napi_env ownerEnv = nullptr;
uint64_t nextToken = 0;
uint64_t activeToken = 0;
bool installed = false;
std::atomic<bool> overflow{false};

void Number(napi_env env, napi_value object, const char* name, double value) {
    napi_value number; napi_create_double(env, value, &number); napi_set_named_property(env, object, name, number);
}
void Deliver(napi_env env, napi_value callback, void*, void* data) {
    std::unique_ptr<Event> event(static_cast<Event*>(data));
    if (!env || !callback || !event) return;
    {
        std::lock_guard<std::mutex> guard(mutex);
        if (event->token != activeToken || env != ownerEnv) return;
    }
    napi_value object, receiver, result;
    napi_create_object(env, &object); napi_get_undefined(env, &receiver);
    Number(env, object, "keyCode", event->code); Number(env, object, "action", event->action);
    Number(env, object, "windowId", event->window); Number(env, object, "displayId", event->display);
    Number(env, object, "eventId", event->id); Number(env, object, "actionTime", event->time);
    Number(env, object, "token", event->token); Number(env, object, "overflow", overflow.load() ? 1 : 0);
    napi_call_function(env, receiver, callback, 1, &object, &result);
}
void OnKey(const Input_KeyEvent* source) {
    if (!source) return;
    napi_threadsafe_function target;
    uint64_t token;
    {
        std::lock_guard<std::mutex> guard(mutex);
        target = sink; token = activeToken;
        if (!target || !token || napi_acquire_threadsafe_function(target) != napi_ok) return;
    }
    int32_t id = -1; OH_Input_GetKeyEventId(source, &id);
    auto* event = new (std::nothrow) Event{OH_Input_GetKeyEventKeyCode(source), OH_Input_GetKeyEventAction(source),
        OH_Input_GetKeyEventWindowId(source), OH_Input_GetKeyEventDisplayId(source), id,
        OH_Input_GetKeyEventActionTime(source), token};
    if (!event || napi_call_threadsafe_function(target, event, napi_tsfn_nonblocking) != napi_ok) {
        delete event; overflow.store(true);
    }
    napi_release_threadsafe_function(target, napi_tsfn_release);
}
int32_t Remove(napi_env env, uint64_t token, bool force) {
    // Register/remove can be requested by different Ability NAPI environments.
    std::lock_guard<std::mutex> operation(operations);
    {
        std::lock_guard<std::mutex> guard(mutex);
        if (env != ownerEnv || token != activeToken) return 0;
    }
    // Do not hold our callback mutex across an OS registration/removal call.
    const int32_t status = installed ? OH_Input_RemoveKeyEventInterceptor() : 0;
    napi_threadsafe_function retired = nullptr;
    {
        std::lock_guard<std::mutex> guard(mutex);
        // A failed removal keeps the interceptor registered, so keep its sink and
        // token: the owner stays the only one that can retry the removal (TS drops
        // the keys while its release is pending). Only environment teardown retires
        // the sink regardless; the process is exiting then.
        if (status == 0 || force) {
            if (status == 0) { installed = false; }
            activeToken = 0; ownerEnv = nullptr;
            retired = sink; sink = nullptr;
        }
    }
    if (retired) napi_release_threadsafe_function(retired, napi_tsfn_abort);
    return status;
}
void Cleanup(void* data) {
    auto env = static_cast<napi_env>(data);
    uint64_t token;
    { std::lock_guard<std::mutex> guard(mutex); token = activeToken; }
    Remove(env, token, true);
}
napi_value Stop(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value argv[1], result; double token = 0;
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc == 1) napi_get_value_double(env, argv[0], &token);
    napi_create_int32(env, std::isfinite(token) && token > 0 && token <= 9007199254740991.0 && std::floor(token) == token ? Remove(env, static_cast<uint64_t>(token), false) : 401, &result); return result;
}
napi_value Start(napi_env env, napi_callback_info info) {
    std::unique_lock<std::mutex> operation(operations);
    size_t argc = 1; napi_value argv[1], result, name; napi_valuetype type = napi_undefined;
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    napi_create_object(env, &result);
    if (argc == 1) napi_typeof(env, argv[0], &type);
    if (type != napi_function) { Number(env, result, "status", 401); Number(env, result, "token", 0); return result; }
    uint64_t token;
    {
        std::lock_guard<std::mutex> guard(mutex);
        if (installed || sink) { Number(env, result, "status", 409); Number(env, result, "token", 0); return result; }
        token = ++nextToken;
        napi_create_string_utf8(env, "RemoteSystemKeys", NAPI_AUTO_LENGTH, &name);
        if (napi_create_threadsafe_function(env, argv[0], nullptr, name, 256, 1, nullptr, nullptr,
            nullptr, Deliver, &sink) != napi_ok) {
            Number(env, result, "status", 500); Number(env, result, "token", 0); return result;
        }
        ownerEnv = env; activeToken = token; overflow.store(false);
    }
    const int32_t status = OH_Input_AddKeyEventInterceptor(OnKey, nullptr);
    if (status == 0) { std::lock_guard<std::mutex> guard(mutex); installed = true; }
    else { operation.unlock(); Remove(env, token, false); }
    Number(env, result, "status", status); Number(env, result, "token", status == 0 ? token : 0);
    return result;
}
} // namespace
void Init(napi_env env, napi_value exports) {
    napi_property_descriptor methods[] = {
        {"startSystemKeyCapture", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopSystemKeyCapture", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(methods) / sizeof(methods[0]), methods);
    napi_add_env_cleanup_hook(env, Cleanup, env);
}
} // namespace SystemKeyCaptureNapi
