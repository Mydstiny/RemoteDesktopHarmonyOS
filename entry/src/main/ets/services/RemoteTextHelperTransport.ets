import { systemDateTime } from '@kit.BasicServicesKit';
import rdpnapi, { AiTlsRequestOptions, AiTlsResponse, AiGeneratedIdentity } from 'librdpnapi.so';
import { connection } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { parseEndpointHost } from './EndpointAddressPolicy';
import { remoteTextRecord, RemoteTextHelperConnection } from './RemoteTextHelperWirePolicy';

export function remoteTextRandomId(): string {
  const bytes: Uint8Array = cryptoFramework.createRandom().generateRandomSync(24).data;
  let id: string = '';
  for (const byte of bytes) { id += byte.toString(16).padStart(2, '0'); }
  return id;
}
/** Reuses only the native TLS primitive. Own cancellation registry; no shared store or RPC. */
export class RemoteTextHelperTransport {
  private static pending: Map<string, Promise<void>> = new Map();
  private static cancels: Map<string, () => void> = new Map();
  private requests: Set<string> = new Set();
  private closed: boolean = false;
  private identity: RemoteTextHelperConnection | null;
  constructor(identity: RemoteTextHelperConnection) { this.identity = JSON.parse(JSON.stringify(identity)) as RemoteTextHelperConnection; }
  static async generateIdentity(): Promise<AiGeneratedIdentity> {
    const id: string = remoteTextRandomId();
    const operation = rdpnapi.aiGenerateIdentity({ id });
    RemoteTextHelperTransport.pending.set(id, operation.then((): void => {}, (): void => {}));
    RemoteTextHelperTransport.cancels.set(id, (): void => { rdpnapi.aiCancelRequest({ id }); });
    try { return await operation; } finally { RemoteTextHelperTransport.pending.delete(id); RemoteTextHelperTransport.cancels.delete(id); }
  }
  static async drain(): Promise<boolean> {
    Array.from(RemoteTextHelperTransport.cancels.values()).forEach((cancel: () => void): void => cancel());
    let timer: number = -1;
    const complete = Promise.all(Array.from(RemoteTextHelperTransport.pending.values())).then((): boolean => true);
    const expired = new Promise<boolean>((resolve): void => { timer = setTimeout((): void => resolve(false), 5000); });
    try { return await Promise.race([complete, expired]); } finally { if (timer >= 0) { clearTimeout(timer); } }
  }
  close(): void {
    this.closed = true; this.identity = null;
    this.requests.forEach((id: string): void => { RemoteTextHelperTransport.cancels.get(id)?.(); });
  }
  async post(path: string, body: string): Promise<Record<string, Object>> {
    const identity: RemoteTextHelperConnection | null = this.identity;
    if (this.closed || identity === null || !['pair', 'handshake', 'bind', 'snapshot'].includes(path) || body.length > 20000) {
      throw new Error('TEXT_CONNECTION_CLOSED');
    }
    const id: string = remoteTextRandomId();
    this.requests.add(id);
    let wasCancelled: boolean = false;
    let rejectCancel: (error: Error) => void = (_error: Error): void => {};
    const cancelled = new Promise<AiTlsResponse>((_resolve, reject): void => { rejectCancel = reject; });
    const options: AiTlsRequestOptions = { id, address: identity.address, serverName: identity.serverName,
      port: identity.port, ca: identity.ca, certificate: identity.certificate, privateKey: identity.privateKey,
      path: '/v1/text-input/' + path, body, timeoutMs: 5000 };
    RemoteTextHelperTransport.cancels.set(id, (): void => { wasCancelled = true; rejectCancel(new Error('TEXT_OPERATION_CANCELLED')); rdpnapi.aiCancelRequest({ id }); });
    const started: number = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false);
    const operation = (async (): Promise<AiTlsResponse> => {
      let candidates: Array<string> = [options.address];
      const parsed = parseEndpointHost(options.address, 'runtime');
      if (!parsed.ok) { throw new Error('TEXT_ENDPOINT_INVALID'); }
      if (parsed.endpoint.family === 'hostname') {
        let timer: number = -1;
        const expired = new Promise<connection.NetAddress[]>((_resolve, reject): void => {
          timer = setTimeout((): void => reject(new Error('TEXT_DNS_TIMEOUT')), 5000);
        });
        try {
          const addresses = await Promise.race([connection.getAddressesByName(options.address), expired]);
          if (this.closed) { throw new Error('TEXT_OPERATION_CANCELLED'); }
          candidates = [];
          for (const item of addresses) {
            const value = parseEndpointHost(item.address, 'runtime');
            if (value.ok && value.endpoint.family !== 'hostname' && !candidates.includes(item.address)) { candidates.push(item.address); }
            if (candidates.length >= 8) { break; }
          }
          if (candidates.length === 0) { throw new Error('TEXT_HOST_NOT_FOUND'); }
        } finally { if (timer >= 0) { clearTimeout(timer); } }
      }
      for (let index: number = 0; index < candidates.length; index++) {
        if (this.closed || wasCancelled || !this.requests.has(id)) { throw new Error('TEXT_OPERATION_CANCELLED'); }
        const remaining: number = 5000 - (systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false) - started);
        if (remaining < 100 || remaining > 5000) { throw new Error('TEXT_REQUEST_TIMEOUT'); }
        options.timeoutMs = remaining; options.address = candidates[index];
        try { return await rdpnapi.aiTlsRequest(options); }
        catch (error) {
          const code: string = (error as Error).message;
          if (index + 1 >= candidates.length || !['AI_CONNECTION_FAILED', 'AI_HOST_NOT_FOUND'].includes(code)) { throw new Error(code); }
        }
      }
      throw new Error('TEXT_HOST_NOT_FOUND');
    })();
    // Includes DNS continuations so account transitions cannot admit an old-scope native request later.
    const terminal = Promise.race([operation, cancelled]);
    RemoteTextHelperTransport.pending.set(id, operation.then((): void => {}, (): void => {}));
    try {
      const result = await terminal;
      if (this.closed || result.body.byteLength > 32768) { throw new Error('TEXT_METADATA_INVALID'); }
      const value = remoteTextRecord(JSON.parse(util.TextDecoder.create('utf-8', { fatal: true })
        .decodeToString(new Uint8Array(result.body))) as Object);
      if (result.status !== 200 || typeof value['error'] === 'string') {
        const code: Object = value['error'];
        throw new Error(typeof code === 'string' && /^[A-Z0-9_]{1,64}$/.test(code) ? code : 'TEXT_REQUEST_FAILED');
      }
      return value;
    } finally {
      this.requests.delete(id); options.privateKey = '';
      void operation.finally((): void => { RemoteTextHelperTransport.pending.delete(id); RemoteTextHelperTransport.cancels.delete(id); }).catch((): void => {});
    }
  }
}
