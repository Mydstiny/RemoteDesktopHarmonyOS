export type RemotePreferenceScalar = string | number | boolean;
export interface RemotePreferenceWrite { key: string; value: RemotePreferenceScalar; }
export interface RemotePreferenceSnapshot extends RemotePreferenceWrite { present: boolean; }
export interface RemotePreferencePort {
  has(key: string): boolean;
  get(key: string): RemotePreferenceScalar;
  put(key: string, value: RemotePreferenceScalar): void;
  delete(key: string): void;
  flush(): void;
}
export interface RemotePreferenceWriteResult { ok: boolean; rollbackSucceeded: boolean; }

/** Publish only after durable flush. On failure restore the entire saved prefix, including absent keys. */
export function writeRemoteKeyboardPreferences(port: RemotePreferencePort,
  writes: Array<RemotePreferenceWrite>): RemotePreferenceWriteResult {
  const saved: Array<RemotePreferenceSnapshot> = [];
  try {
    for (const item of writes) {
      const present: boolean = port.has(item.key);
      saved.push({ key: item.key, value: present ? port.get(item.key) : '', present });
    }
  } catch (_error) { return { ok: false, rollbackSucceeded: true }; }
  try {
    for (const item of writes) { port.put(item.key, item.value); }
    port.flush();
    return { ok: true, rollbackSucceeded: true };
  } catch (_error) {
    let restored: boolean = true;
    for (const item of saved) {
      try { if (item.present) { port.put(item.key, item.value); } else { port.delete(item.key); } }
      catch (_rollbackError) { restored = false; }
    }
    try { port.flush(); } catch (_flushError) { restored = false; }
    return { ok: false, rollbackSucceeded: restored };
  }
}
