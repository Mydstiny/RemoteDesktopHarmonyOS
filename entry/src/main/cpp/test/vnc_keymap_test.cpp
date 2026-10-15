/** Native regression tests for the VNC HarmonyOS -> X11 KeySym contract. */
#include "test_runner.h"
#include "vnc/vnc_rfb_engine.h"

RDP_TEST_CASE(vnc_keymap_covers_extended_function_keys_and_system_controls) {
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2090), 0xFFBEU);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2101), 0xFFC9U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2816), 0xFFCAU);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2827), 0xFFD5U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2079), 0xFF61U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2080), 0xFF13U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2074), 0xFFE5U);
}

RDP_TEST_CASE(vnc_keymap_maps_harmony_consumer_keys_to_xf86_keysyms) {
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(10), 0x1008FF14U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(12), 0x1008FF17U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(13), 0x1008FF16U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(16), 0x1008FF13U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(17), 0x1008FF11U);
}

RDP_TEST_CASE(vnc_keymap_covers_numeric_keypad_controls) {
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2103), 0xFFB0U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2112), 0xFFB9U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2113), 0xFFAFU);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2114), 0xFFAAU);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2115), 0xFFADU);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2116), 0xFFABU);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2117), 0xFFAEU);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2118), 0xFFACU);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2119), 0xFF8DU);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2120), 0xFFBDU);
    // X11 has no keypad-parenthesis keysym; 0xFF9D/0xFF9E are KP_Begin/KP_Insert.
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2121), 0x28U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2122), 0x29U);
}

RDP_TEST_CASE(vnc_keymap_keeps_unknown_and_fn_keys_fail_closed) {
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2078), 0U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(0x20), 0x20U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(0x10039), 0xFFE5U);
    // Unmapped Harmony codes and control characters are never sent as keysyms.
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2633), 0U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2630), 0x1008FF14U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2615), 0x5CU);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(23), 0U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(22), 0x1008FF12U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(2606), 0xFF23U);
    RDP_ASSERT_EQ(VncRfbEngine::keySymForHarmonyCodeForTesting(0x21), 0x21U);
}
