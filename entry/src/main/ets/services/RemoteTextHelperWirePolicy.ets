import { boundedRemoteInputRect, copyRemoteTextOwner, RemoteInputRect, RemoteTextOwner, RemoteTextTarget } from './RemoteTextInputPolicy';

export interface RemoteTextHelperProfile { id: string; label: string; protocol: string; connectionKey: string; }
export interface RemoteTextHelperConnection {
  profileId: string; connectionKey: string; address: string; serverName: string; port: number;
  instance: string; deviceId: string; ca: string; certificate: string; privateKey: string;
}
export interface RemoteTextHelperBinding {
  runtime: string; lease: string; ttlMs: number; desktopBinding: string; bindingId: string;
}
export interface RemoteTextHelperSnapshot { available: boolean; reason: string; sequence: number; target: RemoteTextTarget | null; }

export function remoteTextRecord(value: Object): Record<string, Object> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) { throw new Error('TEXT_METADATA_INVALID'); }
  return value as Record<string, Object>;
}
export function remoteTextFields(value: Record<string, Object>, keys: Array<string>): void {
  if (Object.keys(value).some((key: string): boolean => !keys.includes(key))) { throw new Error('TEXT_METADATA_INVALID'); }
}
export function remoteTextString(value: Record<string, Object>, key: string, max: number = 160): string {
  const item: Object = value[key];
  if (typeof item !== 'string' || item.length === 0 || item.length > max || /[\x00-\x1f\x7f]/.test(item)) {
    throw new Error('TEXT_METADATA_INVALID');
  }
  return item;
}
function integer(value: Record<string, Object>, key: string, max: number): number {
  const item: Object = value[key];
  if (typeof item !== 'number' || !Number.isSafeInteger(item) || item < 0 || item > max) { throw new Error('TEXT_METADATA_INVALID'); }
  return item;
}
export function remoteTextBinding(value: Record<string, Object>, connection: RemoteTextHelperConnection): RemoteTextHelperBinding {
  remoteTextFields(value, ['version', 'runtime', 'instance', 'deviceId', 'lease', 'ttlMs', 'desktopBinding', 'bindingId']);
  if (value['version'] !== 1 || value['instance'] !== connection.instance || value['deviceId'] !== connection.deviceId) {
    throw new Error('TEXT_IDENTITY_MISMATCH');
  }
  const ttlMs: number = integer(value, 'ttlMs', 15000);
  if (ttlMs < 1000) { throw new Error('TEXT_METADATA_INVALID'); }
  return { runtime: remoteTextString(value, 'runtime', 100), lease: remoteTextString(value, 'lease', 100), ttlMs,
    desktopBinding: remoteTextString(value, 'desktopBinding'), bindingId: remoteTextString(value, 'bindingId', 100) };
}
function rectangle(value: Object, owner: RemoteTextOwner): RemoteInputRect | null {
  if (value === null) { return null; }
  const record: Record<string, Object> = remoteTextRecord(value);
  remoteTextFields(record, ['x', 'y', 'width', 'height']);
  const rect: RemoteInputRect = { x: record['x'] as number, y: record['y'] as number,
    width: record['width'] as number, height: record['height'] as number };
  if (typeof record['x'] !== 'number' || typeof record['y'] !== 'number' || typeof record['width'] !== 'number' ||
    typeof record['height'] !== 'number' || rect.x < 0 || rect.y < 0 || rect.x + Math.max(1, rect.width) > owner.frameWidth ||
    rect.y + rect.height > owner.frameHeight || boundedRemoteInputRect(rect, owner.frameWidth, owner.frameHeight) === null) {
    throw new Error('TEXT_METADATA_INVALID');
  }
  return boundedRemoteInputRect(rect, owner.frameWidth, owner.frameHeight);
}
export function remoteTextSnapshot(value: Record<string, Object>, binding: RemoteTextHelperBinding,
  owner: RemoteTextOwner, nonce: string, lastSequence: number): RemoteTextHelperSnapshot {
  remoteTextFields(value, ['version', 'runtime', 'bindingId', 'desktopBinding', 'displayId', 'frameWidth', 'frameHeight',
    'protocolSessionId', 'ownerNonce', 'sequence', 'available', 'reason', 'focus', 'geometry', 'target']);
  if (value['version'] !== 1 || value['runtime'] !== binding.runtime || value['bindingId'] !== binding.bindingId ||
    value['desktopBinding'] !== binding.desktopBinding || value['desktopBinding'] !== owner.desktopBinding ||
    (value['protocolSessionId'] ?? '') !== (owner.protocolSessionId ?? '') || value['ownerNonce'] !== nonce || value['displayId'] !== owner.displayId || value['frameWidth'] !== owner.frameWidth ||
    value['frameHeight'] !== owner.frameHeight) { throw new Error('TEXT_OWNER_MISMATCH'); }
  if (typeof value['protocolSessionId'] !== 'string' ||
    (owner.protocol === 'rdp' && !/^rdp:[0-9]{1,10}$/.test(owner.protocolSessionId ?? ''))) { throw new Error('TEXT_OWNER_MISMATCH'); }
  const sequence: number = integer(value, 'sequence', Number.MAX_SAFE_INTEGER);
  if (sequence <= lastSequence || typeof value['available'] !== 'boolean' || typeof value['focus'] !== 'boolean' ||
    typeof value['geometry'] !== 'boolean') { throw new Error('TEXT_METADATA_INVALID'); }
  const reason: string = remoteTextString(value, 'reason', 64);
  if (!['ready', 'no-editable-focus', 'denied', 'unsupported', 'locked', 'unavailable', 'outside-capture',
    'desktop-mismatch', 'display-mismatch', 'capture-mismatch', 'unsupported-control', 'protocol-session-mismatch'].includes(reason)) { throw new Error('TEXT_METADATA_INVALID'); }
  let target: RemoteTextTarget | null = null;
  if (value['target'] !== null) {
    const raw: Record<string, Object> = remoteTextRecord(value['target']);
    remoteTextFields(raw, ['focusToken', 'editable', 'readOnly', 'enabled', 'visible', 'inputKind', 'controlRect', 'caretRect']);
    if (value['available'] !== true || value['focus'] !== true || value['geometry'] !== true || reason !== 'ready' ||
      raw['editable'] !== true || raw['readOnly'] !== false || raw['enabled'] !== true || raw['visible'] !== true ||
      (raw['inputKind'] !== 'text' && raw['inputKind'] !== 'password')) { throw new Error('TEXT_METADATA_INVALID'); }
    const token: string = remoteTextString(raw, 'focusToken', 64);
    if (!/^[a-f0-9]{64}$/.test(token)) { throw new Error('TEXT_METADATA_INVALID'); }
    const controlRect: RemoteInputRect | null = rectangle(raw['controlRect'], owner);
    const caretRect: RemoteInputRect | null = rectangle(raw['caretRect'], owner);
    if (controlRect === null && caretRect === null) { throw new Error('TEXT_METADATA_INVALID'); }
    target = { owner: copyRemoteTextOwner(owner), source: 'hostHelper', focusToken: token, sequence,
      editable: true, readOnly: false, enabled: true, visible: true, verified: true,
      inputKind: raw['inputKind'] as string, controlRect, caretRect };
  } else if (reason === 'ready') { throw new Error('TEXT_METADATA_INVALID'); }
  return { available: value['available'] === true, reason, sequence, target };
}

export function remoteTextConnectionValid(value: RemoteTextHelperConnection): boolean {
  return value !== null && typeof value.profileId === 'string' && value.profileId.length > 0 && value.profileId.length <= 200 &&
    typeof value.connectionKey === 'string' && /^[a-f0-9]{64}$/.test(value.connectionKey) &&
    typeof value.address === 'string' && /^[A-Za-z0-9:._%-]+$/.test(value.address) && value.address.length <= 253 &&
    typeof value.serverName === 'string' && /^[A-Za-z0-9:._-]+$/.test(value.serverName) && value.serverName.length <= 253 &&
    Number.isSafeInteger(value.port) && value.port >= 1024 && value.port <= 65535 &&
    typeof value.instance === 'string' && /^[A-Za-z0-9_-]{1,100}$/.test(value.instance) &&
    typeof value.deviceId === 'string' && /^[A-Za-z0-9_-]{1,100}$/.test(value.deviceId) &&
    typeof value.ca === 'string' && value.ca.length <= 16000 && value.ca.includes('-----BEGIN CERTIFICATE-----') &&
    typeof value.certificate === 'string' && value.certificate.length <= 16000 && value.certificate.includes('-----BEGIN CERTIFICATE-----') &&
    typeof value.privateKey === 'string' && value.privateKey.length <= 16000 && value.privateKey.includes('PRIVATE KEY');
}
