/**
 * RustDesk frame-rate preference.
 *
 * Official RustDesk clients pair every non-custom quality tier with a 30 FPS
 * cap. The peer sizes its bitrate from the quality tier alone, so a higher cap
 * spreads the same bitrate across more frames. The quality-first tier therefore
 * always streams at 30 FPS; the other tiers follow the user's frame-rate choice
 * (0 = the tier's own default). The native layer applies the same rule.
 */
export const RUSTDESK_FPS_PREF_KEY: string = 'rustdeskFps';
export const RUSTDESK_FPS_AUTO: number = 0;
export const RUSTDESK_BEST_QUALITY_FPS: number = 30;
export const RUSTDESK_FPS_CHOICES: number[] = [RUSTDESK_FPS_AUTO, 30, 60];

export function normalizeRustDeskFps(value: number): number {
  return value === 30 || value === 60 ? value : RUSTDESK_FPS_AUTO;
}

/** The quality-first tier owns the frame rate; the frame-rate choice is inactive. */
export function rustDeskFpsLockedByQuality(quality: number): boolean {
  return quality === 2;
}

export function rustDeskFpsChoiceLabel(fps: number): string {
  const normalized: number = normalizeRustDeskFps(fps);
  return normalized === RUSTDESK_FPS_AUTO ? '自动' : normalized.toString() + ' 帧';
}

/** Short summary of the frame rate the next request will ask the peer for. */
export function rustDeskFpsSummary(quality: number, fps: number): string {
  if (rustDeskFpsLockedByQuality(quality)) {
    return '画质优先固定 ' + RUSTDESK_BEST_QUALITY_FPS.toString() + ' 帧';
  }
  const normalized: number = normalizeRustDeskFps(fps);
  if (normalized === RUSTDESK_FPS_AUTO) {
    return quality === 0 ? '自动 · 30 帧' : '自动 · 随画质档';
  }
  return normalized.toString() + ' 帧';
}
