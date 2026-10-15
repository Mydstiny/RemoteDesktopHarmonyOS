/**
 * RemoteScrollPolicy.ets - linear, precise remote scrolling for RDP, RustDesk and VNC.
 *
 * Every scroll source becomes WHEEL_DELTA units (120 = one mouse notch; positive scrolls up, the
 * sign every protocol here already uses): a mouse notch is 120 units, touchpad motion (virtual
 * two/three-finger swipes and a physical touchpad, both reported in vp) is distance times a fixed
 * gain. The user's speed scales the units, never whole notches, so 150% is exactly one and a half
 * times the distance instead of alternating one and two notches.
 *
 * The protocol's wire then sets the granularity:
 * - units:   RDP and RustDesk-to-Windows carry the units themselves (smooth, like a precision touchpad);
 * - pixels:  RustDesk-to-macOS touchpad scrolling carries pixels, as a Mac trackpad does;
 * - clicks:  VNC carries RFB button-4/5 clicks;
 * - notches: everything else (RustDesk Linux/Android/older peers, a macOS mouse wheel) whole notches.
 * The fraction below one wire step carries to the next sample, so slow motion is not lost and fast
 * motion is not capped into bursts.
 */
export const WHEEL_UNITS_PER_NOTCH: number = 120;
/** Touchpad gain: one notch for every 15 vp of finger travel at 100%. */
export const TOUCHPAD_WHEEL_UNITS_PER_VP: number = 8;
/** One RFB click is a server-defined row; three clicks per notch matches the previous VNC default. */
export const VNC_WHEEL_UNITS_PER_CLICK: number = 40;
/** macOS trackpad pixels: 1.6 px per vp of finger travel at 100%. */
export const MAC_TRACKPAD_UNITS_PER_PIXEL: number = 5;
/** Most one sample may carry (16 notches); a larger jump is bounded instead of queued. */
export const REMOTE_SCROLL_MAX_UNITS_PER_SAMPLE: number = 1920;
/** A touch/touchpad pause longer than this starts a new gesture without the old fraction. */
export const REMOTE_SCROLL_GESTURE_IDLE_MS: number = 400;
/** One touch sample farther than this is a finger landing or lifting, not scrolling. */
export const REMOTE_SCROLL_MAX_TOUCH_STEP_VP: number = 120;

/** RustDesk peer scroll wire reported by the native display snapshot. */
export const RUSTDESK_SCROLL_WIRE_NOTCHES: number = 0;
export const RUSTDESK_SCROLL_WIRE_UNITS: number = 1;
export const RUSTDESK_SCROLL_WIRE_PIXELS: number = 2;

/** ArkUI AxisAction values. */
const AXIS_ACTION_END: number = 3;
const AXIS_ACTION_CANCEL: number = 4;

export type RemoteScrollWire = 'units' | 'pixels' | 'clicks' | 'notches';

export interface RemoteScrollState {
  /** Units not yet sent (always less than one wire step). */
  pending: number;
  lastAtMs: number;
}

export interface RemoteScrollStep {
  /** Whole wire steps to send now (units, pixels, clicks or notches; signed). */
  amount: number;
  state: RemoteScrollState;
}

export function resetRemoteScrollState(): RemoteScrollState {
  return { pending: 0, lastAtMs: 0 };
}

export function remoteScrollWire(protocol: string, rustDeskPeerScrollWire: number,
  touchpadSource: boolean): RemoteScrollWire {
  if (protocol === 'rdp') { return 'units'; }
  if (protocol === 'vnc') { return 'clicks'; }
  if (protocol === 'rustdesk') {
    if (rustDeskPeerScrollWire === RUSTDESK_SCROLL_WIRE_UNITS) { return 'units'; }
    // macOS scrolls a mouse wheel by lines and a trackpad by pixels, as on the Mac itself.
    if (rustDeskPeerScrollWire === RUSTDESK_SCROLL_WIRE_PIXELS && touchpadSource) { return 'pixels'; }
  }
  return 'notches';
}

export function remoteScrollWireStep(wire: RemoteScrollWire): number {
  if (wire === 'units') { return 1; }
  if (wire === 'pixels') { return MAC_TRACKPAD_UNITS_PER_PIXEL; }
  if (wire === 'clicks') { return VNC_WHEEL_UNITS_PER_CLICK; }
  return WHEEL_UNITS_PER_NOTCH;
}

function speedFactor(speedPercent: number): number {
  return Number.isFinite(speedPercent) && speedPercent > 0 ? speedPercent / 100 : 1;
}

/** One mouse-wheel event is one notch in the event's direction, times the user's speed. */
export function mouseWheelUnits(rawDelta: number, speedPercent: number): number {
  if (!Number.isFinite(rawDelta) || rawDelta === 0) { return 0; }
  return (rawDelta > 0 ? 1 : -1) * WHEEL_UNITS_PER_NOTCH * speedFactor(speedPercent);
}

/** Touchpad travel in vp times the touchpad multiplier and the user's wheel speed. */
export function touchpadWheelUnits(distanceVp: number, touchpadMultiplier: number, speedPercent: number): number {
  if (!Number.isFinite(distanceVp) || distanceVp === 0) { return 0; }
  const multiplier: number = Number.isFinite(touchpadMultiplier) && touchpadMultiplier > 0 ? touchpadMultiplier : 1;
  return distanceVp * TOUCHPAD_WHEEL_UNITS_PER_VP * multiplier * speedFactor(speedPercent);
}

/**
 * A mouse wheel's END/CANCEL axis events come from the timer that closes the wheel gesture, not from
 * a new detent; counting them sent an extra notch at the end of every scroll.
 */
export function axisEventCarriesWheelDetent(axisAction: number): boolean {
  return axisAction !== AXIS_ACTION_END && axisAction !== AXIS_ACTION_CANCEL;
}

/** A single touch step this large comes from a finger landing or lifting, not from scrolling. */
export function isTouchScrollDiscontinuity(stepVp: number): boolean {
  return !Number.isFinite(stepVp) || Math.abs(stepVp) > REMOTE_SCROLL_MAX_TOUCH_STEP_VP;
}

/**
 * Add `units` and return the whole wire steps to send now. The fraction carries to the next sample;
 * it is dropped when the direction reverses (a reversal never starts with a stale step the wrong way)
 * and, for gesture sources, after an idle gap (a new swipe does not inherit the last one's fraction).
 */
export function accumulateRemoteScroll(units: number, wire: RemoteScrollWire, previous: RemoteScrollState,
  nowMs: number, gesture: boolean): RemoteScrollStep {
  const pending: number = Number.isFinite(previous.pending) ? previous.pending : 0;
  const lastAtMs: number = Number.isFinite(previous.lastAtMs) ? previous.lastAtMs : 0;
  if (!Number.isFinite(units) || units === 0) {
    return { amount: 0, state: { pending, lastAtMs } };
  }
  const idle: boolean = gesture && lastAtMs > 0 && nowMs - lastAtMs > REMOTE_SCROLL_GESTURE_IDLE_MS;
  const reversed: boolean = pending !== 0 && (pending > 0) !== (units > 0);
  const carry: number = idle || reversed ? 0 : pending;
  const bounded: number = Math.max(-REMOTE_SCROLL_MAX_UNITS_PER_SAMPLE,
    Math.min(REMOTE_SCROLL_MAX_UNITS_PER_SAMPLE, units));
  const total: number = carry + bounded;
  const step: number = remoteScrollWireStep(wire);
  const whole: number = Math.trunc(total / step);
  return { amount: whole, state: { pending: total - whole * step, lastAtMs: nowMs } };
}
