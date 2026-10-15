import { DiagnosticOutcome } from './DiagnosticCapturePolicy';
import { recordDiagnosticEvent } from './DiagnosticCaptureRuntime';

/**
 * Remote text input / keyboard avoidance observability (plan 2026-10-13 §13).
 *
 * Only numeric facts leave the page: a fixed reason code, the owner generation,
 * a duration and a bounded count (for example a rounded offset in px). Input
 * text, candidates, window titles, control values and helper tokens are never
 * passed here.
 */
export type RemoteInputDiagnosticEvent =
  'remote_text_capability' | 'remote_text_focus' | 'remote_keyboard_auto_open' |
  'remote_keyboard_suppressed' | 'remote_keyboard_occlusion' | 'remote_input_avoidance' |
  'remote_input_avoidance_presented' | 'remote_text_source_fallback';

export const REMOTE_INPUT_DIAGNOSTIC_EVENTS: RemoteInputDiagnosticEvent[] = [
  'remote_text_capability', 'remote_text_focus', 'remote_keyboard_auto_open',
  'remote_keyboard_suppressed', 'remote_keyboard_occlusion', 'remote_input_avoidance',
  'remote_input_avoidance_presented', 'remote_text_source_fallback'
];

/** Append-only: a code keeps its meaning across releases. 0 is "other". */
const REMOTE_INPUT_REASONS: string[] = [
  'other', 'hidden', 'geometry-unknown', 'outside-surface', 'invalid-target', 'no-room',
  'floating-clear', 'docked', 'floating', 'floating-above', 'floating-below', 'floating-left',
  'floating-right', 'out-of-range', 'verified-focus', 'click', 'not-eligible', 'owner-changed',
  'target-rejected', 'presented', 'helper-source-lost', 'connecting', 'unconfigured',
  'no-editable-focus', 'available', 'unavailable', 'disabled'
];

export function remoteInputReasonCode(reason: string): number {
  const index: number = REMOTE_INPUT_REASONS.indexOf(reason);
  return index < 0 ? 0 : index;
}

export function remoteInputReasonName(code: number): string {
  return code >= 0 && code < REMOTE_INPUT_REASONS.length ? REMOTE_INPUT_REASONS[code] : 'other';
}

/** Bounded, non-negative integer suitable for the event's count field. */
export function remoteInputBoundedCount(value: number): number {
  if (!Number.isFinite(value)) { return 0; }
  return Math.min(100000, Math.max(0, Math.round(Math.abs(value))));
}

export function recordRemoteInputEvent(event: RemoteInputDiagnosticEvent, outcome: DiagnosticOutcome,
  reason: string, generation: number = 0, durationMs: number = 0, count: number = 0): void {
  recordDiagnosticEvent('core.app', event, outcome, 0, Math.max(0, Math.floor(generation)),
    remoteInputReasonCode(reason), Math.max(0, Math.round(durationMs)), remoteInputBoundedCount(count), 0);
}
