import { common } from '@kit.AbilityKit';
import { systemDateTime } from '@kit.BasicServicesKit';
import { RemoteTextHelperAccess, RemoteTextHelperAccountLease } from './RemoteTextHelperAccess';
import { RemoteTextHelperStore } from './RemoteTextHelperStore';
import { remoteTextRandomId, RemoteTextHelperTransport } from './RemoteTextHelperTransport';
import { copyRemoteTextOwner, sameRemoteTextOwner, RemoteTextOwner } from './RemoteTextInputPolicy';
import { remoteTextBinding, remoteTextFields, remoteTextRecord, remoteTextSnapshot, remoteTextString,
  RemoteTextHelperBinding, RemoteTextHelperConnection, RemoteTextHelperProfile, RemoteTextHelperSnapshot } from './RemoteTextHelperWirePolicy';

export function remoteTextNow(): number { return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false); }
function baseOwner(owner: RemoteTextOwner): RemoteTextOwner { const value = copyRemoteTextOwner(owner); value.desktopBinding = ''; return value; }

export interface RemoteTextHelperInvite { code: string; expires: number; ca: string; serverInstance: string; }
export function remoteTextInvite(text: string): RemoteTextHelperInvite {
  if (text.length > 20000) { throw new Error('TEXT_INVITE_INVALID'); }
  const raw = remoteTextRecord(JSON.parse(text) as Object);
  remoteTextFields(raw, ['code', 'expires', 'ca', 'serverInstance']);
  const value: RemoteTextHelperInvite = { code: remoteTextString(raw, 'code', 100), expires: raw['expires'] as number,
    ca: raw['ca'] as string, serverInstance: remoteTextString(raw, 'serverInstance', 100) };
  if (!/^[A-Za-z0-9_-]{43}$/.test(value.code) || typeof value.expires !== 'number' || !Number.isSafeInteger(value.expires) ||
    value.expires <= Date.now() || value.expires > Date.now() + 180000 || typeof value.ca !== 'string' ||
    value.ca.length > 16000 || !value.ca.includes('-----BEGIN CERTIFICATE-----')) { throw new Error('TEXT_INVITE_INVALID'); }
  return value;
}

export async function pairRemoteTextHelper(context: common.Context, profile: RemoteTextHelperProfile,
  address: string, serverName: string, port: number, invitationText: string, current: () => boolean,
  registerCancel: (cancel: () => void) => void = (_cancel: () => void): void => {}): Promise<void> {
  const account = RemoteTextHelperAccess.getInstance(); const lease = account.capture();
  const invite = remoteTextInvite(invitationText);
  const identity = await RemoteTextHelperTransport.generateIdentity();
  let transport: RemoteTextHelperTransport | null = null;
  let off: (() => void) | null = null;
  registerCancel((): void => { transport?.close(); });
  try {
    account.assertCurrent(lease); if (!current()) { throw new Error('TEXT_OPERATION_CANCELLED'); }
    const connection: RemoteTextHelperConnection = { profileId: profile.id, connectionKey: profile.connectionKey,
      address, serverName, port, instance: invite.serverInstance, deviceId: '', ca: invite.ca,
      certificate: '', privateKey: '' };
    transport = new RemoteTextHelperTransport(connection);
    off = account.subscribe((): void => { transport?.close(); });
    const paired = await transport.post('pair', JSON.stringify({ code: invite.code, csr: identity.csr, name: 'RemoteDesktop text input' }));
    account.assertCurrent(lease); if (!current()) { throw new Error('TEXT_OPERATION_CANCELLED'); }
    remoteTextFields(paired, ['deviceId', 'cert', 'instance']);
    if (paired['instance'] !== invite.serverInstance) { throw new Error('TEXT_IDENTITY_MISMATCH'); }
    connection.deviceId = remoteTextString(paired, 'deviceId', 100);
    connection.certificate = paired['cert'] as string; connection.privateKey = identity.privateKey;
    transport.close(); transport = new RemoteTextHelperTransport(connection);
    const hello = await transport.post('handshake', JSON.stringify({ version: 1, instance: connection.instance, deviceId: connection.deviceId }));
    account.assertCurrent(lease); if (!current()) { throw new Error('TEXT_OPERATION_CANCELLED'); }
    remoteTextFields(hello, ['version', 'instance', 'deviceId', 'capabilities']);
    if (hello['version'] !== 1 || hello['instance'] !== connection.instance || hello['deviceId'] !== connection.deviceId) {
      throw new Error('TEXT_IDENTITY_MISMATCH');
    }
    const capabilities = remoteTextRecord(hello['capabilities']);
    remoteTextFields(capabilities, ['editable', 'geometry', 'coordinates']);
    if (capabilities['editable'] !== true || capabilities['geometry'] !== true || capabilities['coordinates'] !== 'capturePhysicalPx') {
      throw new Error('TEXT_CAPABILITY_UNSUPPORTED');
    }
    const store = RemoteTextHelperStore.getInstance(); await store.initialize(context);
    account.assertCurrent(lease); if (!current()) { throw new Error('TEXT_OPERATION_CANCELLED'); }
    await store.save(lease, connection, current);
    connection.privateKey = '';
    account.assertCurrent(lease); if (!current()) { throw new Error('TEXT_OPERATION_CANCELLED'); }
  } finally { identity.privateKey = ''; transport?.close(); off?.(); }
}

/** One bounded snapshot request at a time; no event backlog and no source lifetime based on caret movement. */
export class RemoteTextHelperRuntime {
  private closed: boolean = false;
  private timer: number = -1;
  private transport: RemoteTextHelperTransport | null = null;
  private offAccount: (() => void) | null = null;
  private offStore: (() => void) | null = null;
  private lease: RemoteTextHelperAccountLease;
  private owner: RemoteTextOwner;
  private profile: RemoteTextHelperProfile;
  private nonce: string = remoteTextRandomId();
  private binding: RemoteTextHelperBinding | null = null;
  private connection: RemoteTextHelperConnection | null = null;
  private boundAt: number = 0;
  private wireSequence: number = 0;
  private adapterSequence: number = 0;
  private currentOwner: () => RemoteTextOwner | null;
  private currentProfile: () => RemoteTextHelperProfile | null;
  private onBinding: (binding: string) => void;
  private onSnapshot: (snapshot: RemoteTextHelperSnapshot) => void;
  private onUnavailable: (reason: string) => void;
  private intentGeneration: () => number;

  constructor(owner: RemoteTextOwner, profile: RemoteTextHelperProfile,
    currentOwner: () => RemoteTextOwner | null, currentProfile: () => RemoteTextHelperProfile | null,
    onBinding: (binding: string) => void, onSnapshot: (snapshot: RemoteTextHelperSnapshot) => void,
    onUnavailable: (reason: string) => void, intentGeneration: () => number) {
    this.owner = baseOwner(owner); this.profile = { id: profile.id, label: profile.label, protocol: profile.protocol, connectionKey: profile.connectionKey };
    this.currentOwner = currentOwner; this.currentProfile = currentProfile; this.onBinding = onBinding;
    this.onSnapshot = onSnapshot; this.onUnavailable = onUnavailable; this.intentGeneration = intentGeneration;
    const access = RemoteTextHelperAccess.getInstance(); this.lease = access.capture();
    this.offAccount = access.subscribe((): void => { this.fail('account-changed'); });
    this.offStore = RemoteTextHelperStore.getInstance().subscribe((): void => { this.fail('configuration-changed'); });
  }
  active(): boolean { return !this.closed && this.current(); }
  private current(): boolean {
    const owner = this.currentOwner(), profile = this.currentProfile();
    return !this.closed && RemoteTextHelperAccess.getInstance().current(this.lease) && owner !== null &&
      sameRemoteTextOwner(baseOwner(owner), this.owner) && profile !== null && profile.id === this.profile.id &&
      profile.connectionKey === this.profile.connectionKey;
  }
  async start(context: common.Context): Promise<void> {
    try {
      const store = RemoteTextHelperStore.getInstance(); await store.initialize(context);
      if (!this.current()) { this.close(); return; }
      this.connection = await store.load(this.lease, this.profile.id, this.profile.connectionKey);
      if (!this.current()) { this.close(); return; }
      if (this.connection === null) { this.fail('unconfigured'); return; }
      this.transport = new RemoteTextHelperTransport(this.connection);
      await this.poll();
    } catch (_error) { this.fail('unavailable'); }
  }
  private async poll(): Promise<void> {
    if (!this.current() || this.transport === null || this.connection === null) { this.close(); return; }
    try {
      const now: number = remoteTextNow();
      if (this.binding === null || now < this.boundAt || now - this.boundAt >= Math.min(8000, this.binding.ttlMs - 2000)) {
        const started: number = remoteTextNow();
        const raw = await this.transport.post('bind', JSON.stringify({ version: 1, protocol: this.owner.protocol,
          connectionKey: this.profile.connectionKey, ownerNonce: this.nonce, displayId: this.owner.displayId,
          frameWidth: this.owner.frameWidth, frameHeight: this.owner.frameHeight, protocolSessionId: this.owner.protocolSessionId ?? '' }));
        if (!this.current()) { this.close(); return; }
        this.binding = remoteTextBinding(raw, this.connection); this.boundAt = started; this.wireSequence = 0;
        if (remoteTextNow() - started >= this.binding.ttlMs) { throw new Error('TEXT_LEASE_EXPIRED'); }
        this.onBinding(this.binding.desktopBinding);
      }
      const bound = this.binding;
      if (bound === null || !this.current()) { this.close(); return; }
      const intentGeneration: number = this.intentGeneration();
      const raw = await this.transport.post('snapshot', JSON.stringify({ version: 1, lease: bound.lease, ownerNonce: this.nonce }));
      if (!this.current() || remoteTextNow() < this.boundAt || remoteTextNow() - this.boundAt >= bound.ttlMs) { this.fail('unavailable'); return; }
      const owner = copyRemoteTextOwner(this.owner); owner.desktopBinding = bound.desktopBinding;
      const value = remoteTextSnapshot(raw, bound, owner, this.nonce, this.wireSequence);
      this.wireSequence = value.sequence;
      if (value.target !== null) { value.target.sequence = ++this.adapterSequence; }
      if (intentGeneration === this.intentGeneration()) { this.onSnapshot(value); }
      if (!this.current()) { this.close(); return; }
      this.timer = setTimeout((): void => { this.timer = -1; void this.poll(); }, 120);
    } catch (error) {
      const code: string = (error as Error).message;
      this.fail(code === 'CAPTURE_BINDING_MISMATCH' ? 'binding-mismatch' : 'unavailable');
    }
  }
  private fail(reason: string): void {
    if (this.closed) { return; }
    this.close(); this.onUnavailable(reason);
  }
  close(): void {
    this.closed = true;
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    this.transport?.close(); this.transport = null; this.connection = null; this.binding = null;
    this.offAccount?.(); this.offStore?.(); this.offAccount = null; this.offStore = null;
  }
}
