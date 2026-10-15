import { RemoteInputRect, RemoteKeyboardPlacement } from './RemoteTextInputPolicy';

export interface RemoteKeyboardOcclusion {
  visible: boolean;
  geometryKnown: boolean;
  rect: RemoteInputRect;
  docked: boolean;
}

export interface RemoteKeyboardAvoidanceInput {
  target: RemoteInputRect;
  occlusion: RemoteKeyboardOcclusion;
  viewport: RemoteInputRect;
  placement: RemoteKeyboardPlacement;
  gap: number;
  bottomBarHeight: number;
  currentX: number;
  currentY: number;
  initial: boolean;
}

export interface RemoteKeyboardAvoidanceResult {
  x: number;
  y: number;
  active: boolean;
  reason: string;
}

function validRect(rect: RemoteInputRect): boolean {
  return Number.isFinite(rect.x) && Number.isFinite(rect.y) && Number.isFinite(rect.width) &&
    Number.isFinite(rect.height) && rect.width > 0 && rect.height > 0;
}

interface FloatingAvoidanceCandidate {
  dx: number;
  dy: number;
  rank: number;
  reason: string;
}

/**
 * Floating or split keyboards occlude a bounded rectangle (a split keyboard's
 * centre gap is not treated as usable). Choose the smallest movement that
 * clears it: above first, then below, then to either side. Without room the
 * picture stays put so the user can pan manually.
 */
function resolveFloatingAvoidance(input: RemoteKeyboardAvoidanceInput, shifted: RemoteInputRect,
  keyboard: RemoteInputRect, gap: number, baseX: number, baseY: number): RemoteKeyboardAvoidanceResult {
  const viewport: RemoteInputRect = input.viewport;
  const top: number = viewport.y + gap;
  const bottom: number = viewport.y + viewport.height - gap - Math.max(0, input.bottomBarHeight);
  const left: number = viewport.x + gap;
  const right: number = viewport.x + viewport.width - gap;
  const candidates: FloatingAvoidanceCandidate[] = [];
  const aboveDy: number = keyboard.y - gap - (shifted.y + shifted.height);
  if (shifted.y + aboveDy >= top) { candidates.push({ dx: 0, dy: aboveDy, rank: 0, reason: 'floating-above' }); }
  const belowDy: number = keyboard.y + keyboard.height + gap - shifted.y;
  if (shifted.y + shifted.height + belowDy <= bottom) {
    candidates.push({ dx: 0, dy: belowDy, rank: 1, reason: 'floating-below' });
  }
  const leftDx: number = keyboard.x - gap - (shifted.x + shifted.width);
  if (shifted.x + leftDx >= left) { candidates.push({ dx: leftDx, dy: 0, rank: 2, reason: 'floating-left' }); }
  const rightDx: number = keyboard.x + keyboard.width + gap - shifted.x;
  if (shifted.x + shifted.width + rightDx <= right) {
    candidates.push({ dx: rightDx, dy: 0, rank: 3, reason: 'floating-right' });
  }
  if (candidates.length === 0) {
    return { x: baseX, y: baseY, active: false, reason: 'no-room' };
  }
  candidates.sort((a: FloatingAvoidanceCandidate, b: FloatingAvoidanceCandidate): number => {
    const distance: number = Math.abs(a.dx) + Math.abs(a.dy) - Math.abs(b.dx) - Math.abs(b.dy);
    return Math.abs(distance) >= 1 ? distance : a.rank - b.rank;
  });
  const best: FloatingAvoidanceCandidate = candidates[0];
  const nextX: number = baseX + best.dx;
  const nextY: number = baseY + best.dy;
  const limit: number = Math.max(viewport.height, viewport.width) * 2;
  if (!Number.isFinite(nextX) || !Number.isFinite(nextY) || Math.abs(nextX) > limit || Math.abs(nextY) > limit) {
    return { x: 0, y: 0, active: false, reason: 'out-of-range' };
  }
  return { x: nextX, y: nextY, active: true, reason: best.reason };
}

function rectInsideViewport(rect: RemoteInputRect, input: RemoteKeyboardAvoidanceInput): boolean {
  const viewport: RemoteInputRect = input.viewport;
  return rect.x >= viewport.x && rect.y >= viewport.y && rect.x + rect.width <= viewport.x + viewport.width &&
    rect.y + rect.height <= viewport.y + viewport.height - Math.max(0, input.bottomBarHeight);
}

export function remoteRectsIntersect(a: RemoteInputRect, b: RemoteInputRect): boolean {
  return validRect(a) && validRect(b) && a.x < b.x + b.width && b.x < a.x + a.width &&
    a.y < b.y + b.height && b.y < a.y + a.height;
}

/** All values are in one surface-pixel space. This offset is never persisted as user pan. */
export function resolveRemoteKeyboardAvoidance(input: RemoteKeyboardAvoidanceInput): RemoteKeyboardAvoidanceResult {
  if (!input.occlusion.visible) { return { x: 0, y: 0, active: false, reason: 'hidden' }; }
  if (!input.occlusion.geometryKnown) {
    return { x: input.currentX, y: input.currentY, active: false, reason: 'geometry-unknown' };
  }
  if (!validRect(input.occlusion.rect)) {
    return { x: 0, y: 0, active: false, reason: 'outside-surface' };
  }
  if (!validRect(input.target) || !validRect(input.viewport) ||
    !Number.isFinite(input.currentX) || !Number.isFinite(input.currentY) ||
    !Number.isFinite(input.gap) || !Number.isFinite(input.bottomBarHeight)) {
    return { x: 0, y: 0, active: false, reason: 'invalid-target' };
  }
  const gap: number = Math.max(0, input.gap);
  const shifted: RemoteInputRect = { x: input.target.x + input.currentX,
    y: input.target.y + input.currentY, width: input.target.width, height: input.target.height };
  const keyboard: RemoteInputRect = input.occlusion.rect;
  if (!input.occlusion.docked) {
    const padded: RemoteInputRect = { x: keyboard.x - gap, y: keyboard.y - gap,
      width: keyboard.width + gap * 2, height: keyboard.height + gap * 2 };
    // Keep a current shift only while it still clears the keyboard on screen (stable typing);
    // a new focus target starts from its natural position.
    if (!input.initial && !remoteRectsIntersect(shifted, padded) && rectInsideViewport(shifted, input)) {
      return { x: input.currentX, y: input.currentY, active: true, reason: 'floating-clear' };
    }
    if (!remoteRectsIntersect(input.target, padded) && rectInsideViewport(input.target, input)) {
      return { x: 0, y: 0, active: true, reason: 'floating-clear' };
    }
    // The smallest necessary move is measured from the natural position.
    return resolveFloatingAvoidance(input, input.target, keyboard, gap, 0, 0);
  }
  const safeTop: number = input.viewport.y + gap;
  const keyboardTop: number = Math.max(input.viewport.y,
    Math.min(input.viewport.y + input.viewport.height, keyboard.y));
  const safeBottom: number = keyboardTop - gap - Math.max(0, input.bottomBarHeight);
  const available: number = safeBottom - safeTop;
  if (available <= 0) { return { x: 0, y: 0, active: false, reason: 'no-room' }; }
  // Oversized controls protect their bottom input line. A caret/line from the source takes precedence upstream.
  const protectedHeight: number = Math.min(input.target.height, available);
  let nextY: number = input.currentY;
  const bottom: number = shifted.y + shifted.height;
  if ((input.initial && input.placement === 'nearKeyboard') || bottom > safeBottom ||
    shifted.y < safeTop) {
    nextY += safeBottom - bottom;
  }
  // Use a small hysteresis during stationary typing; keyboard changes outside it still move immediately.
  if (!input.initial && Math.abs(nextY - input.currentY) < 2) { nextY = input.currentY; }
  const minY: number = safeTop - (input.target.y + input.target.height - protectedHeight);
  const maxY: number = safeBottom - input.target.y - input.target.height;
  nextY = Math.max(minY, Math.min(maxY, nextY));
  const limit: number = Math.max(input.viewport.height, input.viewport.width) * 2;
  if (!Number.isFinite(nextY) || Math.abs(nextY) > limit) {
    return { x: 0, y: 0, active: false, reason: 'out-of-range' };
  }
  // A docked keyboard only needs vertical room; drop any side shift a floating keyboard needed.
  return { x: 0, y: nextY, active: true, reason: 'docked' };
}

/** Translate a window-local keyboard rectangle into the canvas; no height-only floating-keyboard inference. */
export function remoteKeyboardOcclusionForSurface(visible: boolean, keyboard: RemoteInputRect,
  canvasInWindow: RemoteInputRect): RemoteKeyboardOcclusion {
  const empty: RemoteKeyboardOcclusion = { visible, geometryKnown: false,
    rect: { x: 0, y: 0, width: 0, height: 0 }, docked: false };
  if (!visible || !validRect(keyboard) || !validRect(canvasInWindow)) { return empty; }
  const left: number = Math.max(keyboard.x, canvasInWindow.x);
  const top: number = Math.max(keyboard.y, canvasInWindow.y);
  const right: number = Math.min(keyboard.x + keyboard.width, canvasInWindow.x + canvasInWindow.width);
  const bottom: number = Math.min(keyboard.y + keyboard.height, canvasInWindow.y + canvasInWindow.height);
  if (right <= left || bottom <= top) {
    return { visible, geometryKnown: true, rect: { x: 0, y: 0, width: 0, height: 0 }, docked: false };
  }
  return { visible, geometryKnown: true, rect: { x: left - canvasInWindow.x, y: top - canvasInWindow.y,
    width: right - left, height: bottom - top },
    docked: bottom >= canvasInWindow.y + canvasInWindow.height - 2 &&
      right - left >= canvasInWindow.width * 0.8 };
}
