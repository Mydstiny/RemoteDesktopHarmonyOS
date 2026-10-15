import { RemoteInputRect } from './RemoteTextInputPolicy';
import { RemoteSurfaceTransform, RemoteSurfacePoint, remotePointToSurface } from './RemoteSurfaceTransformPolicy';
import { CanvasTransform, CanvasViewport } from './RemoteCanvasTransformPolicy';

export function remoteKeyboardBaseSurfaceTransform(viewport: CanvasViewport, canvas: CanvasTransform,
  remoteWidth: number, remoteHeight: number, widthVp: number, heightVp: number,
  flipX: boolean = false, flipY: boolean = false): RemoteSurfaceTransform {
  const rotation: number = canvas.rotation ?? 0;
  const sourceW: number = rotation % 2 === 1 ? viewport.sourceHeight : viewport.sourceWidth;
  const sourceH: number = rotation % 2 === 1 ? viewport.sourceWidth : viewport.sourceHeight;
  const scale: number = Math.min(viewport.surfaceWidth / sourceW, viewport.surfaceHeight / sourceH) * canvas.scale;
  const viewportW: number = Math.max(1, Math.round(sourceW * scale));
  const viewportH: number = Math.max(1, Math.round(sourceH * scale));
  return { remoteWidth, remoteHeight, viewportX: Math.round((viewport.surfaceWidth - viewportW) / 2 + canvas.panX),
    viewportY: Math.round((viewport.surfaceHeight - viewportH) / 2 + canvas.panY), viewportW, viewportH,
    surfaceWidthPx: viewport.surfaceWidth, surfaceHeightPx: viewport.surfaceHeight,
    surfaceWidthVp: widthVp, surfaceHeightVp: heightVp, rotation, flipX, flipY };
}

/** Project all four corners; rotations and independent visual mirrors must not use the control transform. */
export function remoteInputRectOnSurface(rect: RemoteInputRect,
  transform: RemoteSurfaceTransform): RemoteInputRect | null {
  const points: RemoteSurfacePoint[] = [remotePointToSurface(transform, rect.x, rect.y),
    remotePointToSurface(transform, rect.x + rect.width, rect.y),
    remotePointToSurface(transform, rect.x, rect.y + rect.height),
    remotePointToSurface(transform, rect.x + rect.width, rect.y + rect.height)];
  const scaleX: number = transform.surfaceWidthPx / transform.surfaceWidthVp;
  const scaleY: number = transform.surfaceHeightPx / transform.surfaceHeightVp;
  const xs: number[] = points.map((point: RemoteSurfacePoint): number => point.x * scaleX);
  const ys: number[] = points.map((point: RemoteSurfacePoint): number => point.y * scaleY);
  if (xs.some((value: number): boolean => !Number.isFinite(value)) ||
    ys.some((value: number): boolean => !Number.isFinite(value))) { return null; }
  const x: number = Math.min(...xs);
  const y: number = Math.min(...ys);
  return { x, y, width: Math.max(1, Math.max(...xs) - x), height: Math.max(1, Math.max(...ys) - y) };
}

/** Candidate UI uses the displayed rectangle, independent of the control-only transform. */
export function remoteImeAnchorOnSurface(rect: RemoteInputRect | null,
  transform: RemoteSurfaceTransform, originX: number = 0, originY: number = 0): RemoteSurfacePoint {
  const projected: RemoteInputRect | null = rect === null ? null : remoteInputRectOnSurface(rect, transform);
  const width: number = Math.max(1, transform.surfaceWidthVp);
  const height: number = Math.max(1, transform.surfaceHeightVp);
  const x: number = projected === null ? width / 2 : projected.x * width / transform.surfaceWidthPx;
  const y: number = projected === null ? height / 2 : (projected.y + projected.height) * height / transform.surfaceHeightPx;
  return { x: originX + Math.max(0, Math.min(width - 1, x)),
    y: originY + Math.max(0, Math.min(height - 1, y)), inside: projected !== null };
}

/** Both native values must describe the exact submitted tuple after a successful swap. */
export function remoteKeyboardTransformPresented(pending: number, applied: number, presented: number): boolean {
  return Number.isSafeInteger(pending) && pending > 0 && applied === pending && presented === pending;
}
