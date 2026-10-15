/**
 * PC session window sizing for a manually chosen remote resolution.
 *
 * 'default' keeps the current behaviour (the window keeps its size and the
 * picture is scaled to it). The two fit modes resize the floating session
 * window so its picture area matches the remote desktop: 'fitScaled' uses the
 * system display scale (remote pixels as vp, the size other apps appear at),
 * 'fitPixels' maps one remote pixel to one physical pixel. All geometry here
 * is in physical px.
 */
export type RemoteWindowSizingMode = 'default' | 'fitScaled' | 'fitPixels';

export const REMOTE_WINDOW_SIZING_KEY: string = 'remoteWindowSizingMode';
export const REMOTE_WINDOW_SIZING_MODES: RemoteWindowSizingMode[] = ['default', 'fitScaled', 'fitPixels'];

export function normalizeRemoteWindowSizingMode(value: string | undefined | null): RemoteWindowSizingMode {
  return value === 'fitScaled' || value === 'fitPixels' ? value : 'default';
}

export function remoteWindowSizingLabel(mode: string): string {
  const normalized: RemoteWindowSizingMode = normalizeRemoteWindowSizingMode(mode);
  if (normalized === 'fitScaled') { return '适配远端（系统缩放）'; }
  if (normalized === 'fitPixels') { return '适配远端（1:1 像素）'; }
  return '默认';
}

export function remoteWindowSizingDescription(mode: string): string {
  const normalized: RemoteWindowSizingMode = normalizeRemoteWindowSizingMode(mode);
  if (normalized === 'fitScaled') { return '窗口按远端分辨率与系统缩放调整大小，和本机应用同等大小'; }
  if (normalized === 'fitPixels') { return '窗口按远端分辨率逐像素显示，最清晰；高分屏上会偏小'; }
  return '窗口保持当前大小，画面缩放适应窗口';
}

export interface RemoteWindowSizingInput {
  mode: RemoteWindowSizingMode;
  remoteWidth: number;
  remoteHeight: number;
  densityPixels: number;
  /** Current window rectangle (includes title bar and session controls). */
  windowLeft: number;
  windowTop: number;
  windowWidth: number;
  windowHeight: number;
  /** Current picture area inside the window. */
  canvasWidth: number;
  canvasHeight: number;
  /** Usable screen area (excludes dock/status areas when the system reports them). */
  areaLeft: number;
  areaTop: number;
  areaWidth: number;
  areaHeight: number;
  minWindowWidth: number;
  minWindowHeight: number;
}

export interface RemoteWindowSizingPlan {
  apply: boolean;
  left: number;
  top: number;
  width: number;
  height: number;
  /** The remote desktop did not fit the screen; the window keeps its aspect at a smaller size. */
  scaledDown: boolean;
  /** The remote desktop is smaller than the minimum window; the picture is letterboxed. */
  clampedToMinimum: boolean;
  reason: string;
}

function positiveFinite(value: number): boolean {
  return Number.isFinite(value) && value > 0;
}

function noPlan(input: RemoteWindowSizingInput, reason: string): RemoteWindowSizingPlan {
  return { apply: false, left: input.windowLeft, top: input.windowTop, width: input.windowWidth,
    height: input.windowHeight, scaledDown: false, clampedToMinimum: false, reason };
}

export function planRemoteWindowSizing(input: RemoteWindowSizingInput): RemoteWindowSizingPlan {
  if (input.mode === 'default') { return noPlan(input, 'default'); }
  if (!positiveFinite(input.remoteWidth) || !positiveFinite(input.remoteHeight) ||
    !positiveFinite(input.windowWidth) || !positiveFinite(input.windowHeight) ||
    !positiveFinite(input.canvasWidth) || !positiveFinite(input.canvasHeight) ||
    !positiveFinite(input.areaWidth) || !positiveFinite(input.areaHeight)) {
    return noPlan(input, 'geometry-unknown');
  }
  const density: number = positiveFinite(input.densityPixels) ? input.densityPixels : 1;
  let targetWidth: number = input.mode === 'fitScaled' ? input.remoteWidth * density : input.remoteWidth;
  let targetHeight: number = input.mode === 'fitScaled' ? input.remoteHeight * density : input.remoteHeight;
  // Title bar, session rails and bars stay the same size; only the picture area follows the remote.
  const chromeWidth: number = Math.max(0, input.windowWidth - input.canvasWidth);
  const chromeHeight: number = Math.max(0, input.windowHeight - input.canvasHeight);
  const maxCanvasWidth: number = input.areaWidth - chromeWidth;
  const maxCanvasHeight: number = input.areaHeight - chromeHeight;
  if (maxCanvasWidth <= 0 || maxCanvasHeight <= 0) { return noPlan(input, 'no-room'); }
  let scaledDown: boolean = false;
  if (targetWidth > maxCanvasWidth || targetHeight > maxCanvasHeight) {
    const factor: number = Math.min(maxCanvasWidth / targetWidth, maxCanvasHeight / targetHeight);
    targetWidth *= factor;
    targetHeight *= factor;
    scaledDown = true;
  }
  let width: number = Math.round(targetWidth + chromeWidth);
  let height: number = Math.round(targetHeight + chromeHeight);
  let clampedToMinimum: boolean = false;
  if (width < input.minWindowWidth || height < input.minWindowHeight) {
    width = Math.max(width, Math.round(input.minWindowWidth));
    height = Math.max(height, Math.round(input.minWindowHeight));
    clampedToMinimum = true;
  }
  width = Math.min(width, Math.round(input.areaWidth));
  height = Math.min(height, Math.round(input.areaHeight));
  // Keep the window where it is unless the new size would leave the usable area.
  const left: number = Math.round(Math.min(Math.max(input.windowLeft, input.areaLeft),
    input.areaLeft + input.areaWidth - width));
  const top: number = Math.round(Math.min(Math.max(input.windowTop, input.areaTop),
    input.areaTop + input.areaHeight - height));
  const unchanged: boolean = Math.abs(width - input.windowWidth) < 2 && Math.abs(height - input.windowHeight) < 2 &&
    left === Math.round(input.windowLeft) && top === Math.round(input.windowTop);
  return { apply: !unchanged, left, top, width, height, scaledDown, clampedToMinimum,
    reason: unchanged ? 'already-fitted' : (scaledDown ? 'scaled-down' : 'fitted') };
}
