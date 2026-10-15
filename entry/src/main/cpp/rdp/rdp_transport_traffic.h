#pragma once
#include "common/session_traffic.h"
#include <memory>

#ifdef USE_REAL_FREERDP
#include <freerdp/freerdp.h>
#include <freerdp/transport_io.h>
#include <new>

// Observe FreeRDP's public socket layer without replacing TLS, framing, gateway
// or error handling. Layer clones retain counters beyond the adapter lifetime.
namespace RdpTransportTraffic {
struct Hook {
    rdpTransportIo original;
    pContextFree originalFree;
    std::shared_ptr<SessionTrafficCounters> counters;
};
struct Layer {
    rdpTransportLayer* original;
    std::shared_ptr<SessionTrafficCounters> counters;
};
inline int Read(void* context, void* data, int bytes) {
    auto* layer = static_cast<Layer*>(context);
    const int result = layer->original->Read(layer->original->userContext, data, bytes);
    if (result > 0) layer->counters->received.fetch_add(result, std::memory_order_relaxed);
    return result;
}
inline int Write(void* context, const void* data, int bytes) {
    auto* layer = static_cast<Layer*>(context);
    const int result = layer->original->Write(layer->original->userContext, data, bytes);
    if (result > 0) layer->counters->sent.fetch_add(result, std::memory_order_relaxed);
    return result;
}
inline BOOL Wait(void* context, BOOL write, DWORD timeout) {
    auto* layer = static_cast<Layer*>(context);
    return layer->original->Wait(layer->original->userContext, write, timeout);
}
inline HANDLE Event(void* context) {
    auto* layer = static_cast<Layer*>(context);
    return layer->original->GetEvent(layer->original->userContext);
}
inline BOOL Close(void* context) {
    auto* layer = static_cast<Layer*>(context);
    transport_layer_free(layer->original);
    delete layer;
    return TRUE;
}
inline rdpTransportLayer* Connect(rdpTransport* transport, const char* host, int port, DWORD timeout) {
    auto* hook = static_cast<Hook*>(freerdp_get_io_callback_context(transport_get_context(transport)));
    if (!hook) return nullptr;
    auto* original = hook->original.ConnectLayer(transport, host, port, timeout);
    if (!original) return nullptr;
    auto* wrapped = transport_layer_new(transport, 0);
    auto* state = new (std::nothrow) Layer {original, hook->counters};
    if (!wrapped || !state) {
        transport_layer_free(wrapped);
        delete state;
        // Telemetry allocation must not make a connection fail. This generation
        // is unavailable rather than reporting partial totals as complete.
        hook->counters->available.store(false, std::memory_order_release);
        return original;
    }
    wrapped->userContext = state;
    wrapped->Read = Read; wrapped->Write = Write; wrapped->Wait = Wait;
    wrapped->GetEvent = Event; wrapped->Close = Close;
    return wrapped;
}
inline void Free(freerdp* instance, rdpContext* context) {
    auto* hook = static_cast<Hook*>(freerdp_get_io_callback_context(context));
    if (!hook) return;
    const auto original = hook->originalFree;
    const BOOL cleared = freerdp_set_io_callback_context(context, nullptr);
    (void)cleared;
    delete hook;
    if (original) original(instance, context);
}
// The websocket gateway (GatewayUrl, also chosen by AVD/ARM) opens its own
// socket with freerdp_tcp_connect and bypasses io.ConnectLayer. Such a session
// is reported as unavailable instead of as a real zero.
inline bool UsesUncountedGateway(rdpSettings* settings) {
    if (!settings) return false;
    if (freerdp_settings_get_bool(settings, FreeRDP_GatewayArmTransport)) return true;
    if (!freerdp_settings_get_bool(settings, FreeRDP_GatewayEnabled)) return false;
    const char* url = freerdp_settings_get_string(settings, FreeRDP_GatewayUrl);
    return url != nullptr && url[0] != '\0';
}
inline void MarkUncountedGateway(rdpSettings* settings,
                                 const std::shared_ptr<SessionTrafficCounters>& counters) {
    if (counters && UsesUncountedGateway(settings)) {
        counters->available.store(false, std::memory_order_release);
    }
}
inline bool Install(freerdp* instance, const std::shared_ptr<SessionTrafficCounters>& counters) {
    auto* context = instance->context;
    const auto* original = freerdp_get_io_callbacks(context);
    if (!original || !original->ConnectLayer || freerdp_get_io_callback_context(context)) return false;
    auto* hook = new (std::nothrow) Hook {*original, instance->ContextFree, counters};
    if (!hook) return false;
    auto callbacks = *original;
    callbacks.ConnectLayer = Connect;
    if (!freerdp_set_io_callback_context(context, hook)) { delete hook; return false; }
    if (!freerdp_set_io_callbacks(context, &callbacks)) {
        const BOOL cleared = freerdp_set_io_callback_context(context, nullptr);
        (void)cleared; delete hook; return false;
    }
    instance->ContextFree = Free;
    counters->available.store(true, std::memory_order_release);
    return true;
}
}
#endif
