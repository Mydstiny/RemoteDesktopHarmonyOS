export interface SessionTrafficSnapshot {
  available: boolean;
  sessionId: number;
  generation: string;
  scope: string;
  sampleMs: number;
  rxHigh: number;
  rxLow: number;
  txHigh: number;
  txLow: number;
}

export class SessionTrafficPoint {
  atMs: number = 0;
  received: number = 0;
  sent: number = 0;
}

export class SessionTrafficView {
  available: boolean = false;
  rateAvailable: boolean = false;
  receivedPerSecond: number = 0;
  sentPerSecond: number = 0;
  receivedTotal: number = 0;
  sentTotal: number = 0;
  scope: string = '';
  points: Array<SessionTrafficPoint> = [];
}

function trafficWord(value: number): boolean {
  return Number.isInteger(value) && value >= 0 && value <= 4294967295;
}

/** Subtract exact uint64 words before conversion; totals above 2^53 never lose small deltas. */
export function trafficDelta(high: number, low: number, priorHigh: number, priorLow: number): number {
  if (![high, low, priorHigh, priorLow].every((value: number): boolean => trafficWord(value))) { return -1; }
  if (high < priorHigh || (high === priorHigh && low < priorLow)) { return -1; }
  const delta: number = (high - priorHigh) * 4294967296 + low - priorLow;
  return Number.isSafeInteger(delta) ? delta : -1;
}

export class SessionTrafficSampler {
  private previous: SessionTrafficSnapshot | null = null;
  private history: Array<SessionTrafficPoint> = [];
  reset(): void { this.previous = null; this.history = []; }
  sample(snapshot: SessionTrafficSnapshot): SessionTrafficView {
    const view: SessionTrafficView = new SessionTrafficView();
    if (!snapshot.available || snapshot.sessionId <= 0 || snapshot.generation.length === 0 ||
        snapshot.scope.length === 0 || !Number.isFinite(snapshot.sampleMs) ||
        ![snapshot.rxHigh, snapshot.rxLow, snapshot.txHigh, snapshot.txLow]
          .every((value: number): boolean => trafficWord(value))) { this.reset(); return view; }
    view.available = true; view.scope = snapshot.scope;
    view.receivedTotal = snapshot.rxHigh * 4294967296 + snapshot.rxLow;
    view.sentTotal = snapshot.txHigh * 4294967296 + snapshot.txLow;
    const prior: SessionTrafficSnapshot | null = this.previous;
    this.previous = snapshot;
    if (prior === null || prior.sessionId !== snapshot.sessionId || prior.generation !== snapshot.generation ||
        prior.scope !== snapshot.scope) { this.history = []; return view; }
    const elapsed: number = snapshot.sampleMs - prior.sampleMs;
    const received: number = trafficDelta(snapshot.rxHigh, snapshot.rxLow, prior.rxHigh, prior.rxLow);
    const sent: number = trafficDelta(snapshot.txHigh, snapshot.txLow, prior.txHigh, prior.txLow);
    // A hidden HUD or suspended runtime is not a fresh real-time sample.
    if (elapsed <= 0 || elapsed > 5000 || received < 0 || sent < 0) { this.history = []; return view; }
    view.rateAvailable = true;
    view.receivedPerSecond = received * 1000 / elapsed;
    view.sentPerSecond = sent * 1000 / elapsed;
    const point: SessionTrafficPoint = new SessionTrafficPoint();
    point.atMs = snapshot.sampleMs; point.received = view.receivedPerSecond; point.sent = view.sentPerSecond;
    this.history = this.history.filter((item: SessionTrafficPoint): boolean => snapshot.sampleMs - item.atMs <= 60000);
    this.history.push(point);
    if (this.history.length > 120) { this.history.shift(); }
    view.points = this.history.slice(); return view;
  }
}

export function formatTrafficBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) { return '—'; }
  if (bytes >= 1073741824) { return (bytes / 1073741824).toFixed(2) + ' GiB'; }
  if (bytes >= 1048576) { return (bytes / 1048576).toFixed(2) + ' MiB'; }
  if (bytes >= 1024) { return (bytes / 1024).toFixed(1) + ' KiB'; }
  return bytes.toFixed(0) + ' B';
}

export function trafficScopeLabel(scope: string): string {
  if (scope === 'rdp-tcp-payload') { return 'RDP TCP（含 TLS/网关封装）'; }
  if (scope === 'rustdesk-peer-udp-payload') { return '主串流 UDP（含 KCP 重传）'; }
  if (scope === 'rustdesk-peer-tcp-payload') { return '主串流 TCP（含协议加密）'; }
  return '统计不可用';
}
