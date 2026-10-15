#include "rdp_text_input_probe.h"

namespace remotedesk::rdp {
namespace {
std::uint32_t u32(const std::uint8_t* p) noexcept {
    return static_cast<std::uint32_t>(p[0]) | (static_cast<std::uint32_t>(p[1]) << 8) |
        (static_cast<std::uint32_t>(p[2]) << 16) | (static_cast<std::uint32_t>(p[3]) << 24);
}
TextProbeRect rect(const std::uint8_t* p) noexcept { return {u32(p), u32(p + 4), u32(p + 8), u32(p + 12)}; }
bool valid(const TextProbeRect& r) noexcept { return r.right >= r.left && r.bottom >= r.top; }
}
TextProbeResult inspectTextInputPdu(const std::uint8_t* data, std::size_t size) noexcept {
    TextProbeResult out;
    if (!data || size < 6 || size > 65536) return out;
    const auto declared = u32(data);
    if (declared < 2 || declared > 65532 || static_cast<std::size_t>(declared) + 4 != size) return out;
    const auto id = static_cast<std::uint16_t>(data[4] | (data[5] << 8));
    const auto* p = data + 6;
    const auto body = size - 6;
    switch (id) {
        case 0x031A: // NOTIFY_SERVER_VERSION: GUID + major + minor bitmask
            if (body != 24) return out;
            out.kind = TextProbeKind::ServerVersion;
            out.versionMajor = u32(p + 16); out.versionMinorMask = u32(p + 20);
            return out;
        case 0x0308: // EDIT_CONTROL_FOCUS: bools are packed bytes, not C++ ABI structs
            if (body != 66 || p[56] > 1 || p[65] > 1) return out;
            out.clientId = u32(p); out.control = rect(p + 4); out.gainingFocus = p[56] != 0;
            // ControlBounds is only supplied on focus gain; no synthetic focus-loss rectangle.
            if (out.gainingFocus && !valid(out.control)) return TextProbeResult{};
            out.kind = TextProbeKind::Focus;
            return out;
        case 0x030F: // GEOMETRY_CHANGED: client, control, bounds, selection range, range bounds
            if (body != 48) return out;
            out.clientId = u32(p); out.controlId = u32(p + 4);
            out.control = rect(p + 8); out.range = rect(p + 32);
            if (!valid(out.control) || !valid(out.range)) return TextProbeResult{};
            out.kind = TextProbeKind::Geometry;
            return out;
        case 0x0310: // Invocation is a policy signal, not a trusted local touch receipt.
            if (body != 25) return out;
            for (std::size_t i = 20; i < 25; ++i) if (p[i] > 1) return out;
            out.clientId = u32(p); out.control = rect(p + 4);
            if (!valid(out.control)) return TextProbeResult{};
            out.gainingFocus = p[20] != 0; out.pointerInControl = p[21] != 0; out.manualInvocation = p[22] != 0;
            out.kind = TextProbeKind::Invocation;
            return out;
        case 0x0302: // REGISTER_REMOTE_EDIT_CONTROL has mandatory editClientOperationId ACK.
            out.kind = TextProbeKind::RequiresAck; return out;
        case 0x0200: case 0x0201: case 0x030C: case 0x0319:
            // Do not inspect, decode or retain any text-bearing payload.
            out.kind = TextProbeKind::ContentRefused; return out;
        default: out.kind = TextProbeKind::Unsupported; return out;
    }
}
}
