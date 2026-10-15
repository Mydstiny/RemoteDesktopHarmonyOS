#pragma once
#include <cstddef>
#include <cstdint>

namespace remotedesk::rdp {
// Offline specification probe only. Intentionally not registered as a DVC plugin.
// A parsed rectangle is not a captured-frame coordinate and never grants input capability.
enum class TextProbeKind { Invalid, ServerVersion, Focus, Geometry, Invocation, RequiresAck, ContentRefused, Unsupported };
struct TextProbeRect { std::uint32_t left = 0, top = 0, right = 0, bottom = 0; };
struct TextProbeResult {
    TextProbeKind kind = TextProbeKind::Invalid;
    std::uint32_t clientId = 0, controlId = 0, versionMajor = 0, versionMinorMask = 0;
    TextProbeRect control, range;
    bool gainingFocus = false, pointerInControl = false, manualInvocation = false;
    // These cannot be promoted by successful parsing; qualification requires real peer evidence.
    bool focusCapability = false, geometryCapability = false, passiveIntegrationQualified = false;
};
TextProbeResult inspectTextInputPdu(const std::uint8_t* data, std::size_t size) noexcept;
}
