import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { RemoteTextHelperAccess, RemoteTextHelperAccountLease } from './RemoteTextHelperAccess';
import { remoteTextConnectionValid, RemoteTextHelperConnection } from './RemoteTextHelperWirePolicy';

/** Separate encrypted S4 database. Excluded from host cloud tables, and backups. */
export class RemoteTextHelperStore {
  private static instance: RemoteTextHelperStore;
  private db: relationalStore.RdbStore | null = null;
  private opening: Promise<void> | null = null;
  private queue: Promise<void> = Promise.resolve();
  private listeners: Array<() => void> = [];
  static getInstance(): RemoteTextHelperStore {
    if (!RemoteTextHelperStore.instance) { RemoteTextHelperStore.instance = new RemoteTextHelperStore(); }
    return RemoteTextHelperStore.instance;
  }
  initialize(context: common.Context): Promise<void> {
    if (this.db !== null) { return Promise.resolve(); }
    if (this.opening !== null) { return this.opening; }
    this.opening = this.open(context).finally((): void => { this.opening = null; });
    return this.opening;
  }
  private async open(context: common.Context): Promise<void> {
    const db = await relationalStore.getRdbStore(context, { name: 'remotedesk_text_input_private_v1.db',
      securityLevel: relationalStore.SecurityLevel.S4, encrypt: true });
    try {
      if (db.version !== 0 && db.version !== 1) { throw new Error('TEXT_STORE_VERSION_UNSUPPORTED'); }
      if (db.version === 0) {
        await db.executeSql('CREATE TABLE IF NOT EXISTS text_helpers(owner TEXT NOT NULL,profile TEXT NOT NULL,data TEXT NOT NULL,PRIMARY KEY(owner,profile))');
        db.version = 1;
      }
      this.db = db;
    } catch (_error) { await db.close(); throw new Error('TEXT_STORE_UNAVAILABLE'); }
  }
  private run<T>(lease: RemoteTextHelperAccountLease, action: (db: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    const operation = this.queue.then(async (): Promise<T> => {
      if (this.opening !== null) { await this.opening; }
      RemoteTextHelperAccess.getInstance().assertCurrent(lease);
      const db = this.db;
      if (db === null) { throw new Error('TEXT_STORE_UNAVAILABLE'); }
      const result = await action(db);
      RemoteTextHelperAccess.getInstance().assertCurrent(lease);
      return result;
    });
    this.queue = operation.then((): void => {}, (): void => {});
    return operation;
  }
  load(lease: RemoteTextHelperAccountLease, profile: string, connectionKey: string): Promise<RemoteTextHelperConnection | null> {
    return this.run(lease, async (db: relationalStore.RdbStore): Promise<RemoteTextHelperConnection | null> => {
      const rows = await db.querySql('SELECT data FROM text_helpers WHERE owner=? AND profile=?', [lease.owner, profile]);
      try {
        if (!rows.goToFirstRow()) { return null; }
        const encoded: string = rows.getString(0);
        if (encoded.length > 52000) { throw new Error('TEXT_STORE_RECORD_INVALID'); }
        const value = JSON.parse(encoded) as RemoteTextHelperConnection;
        if (!remoteTextConnectionValid(value) || value.profileId !== profile) { throw new Error('TEXT_STORE_RECORD_INVALID'); }
        return value.connectionKey === connectionKey ? value : null;
      } finally { rows.close(); }
    });
  }
  save(lease: RemoteTextHelperAccountLease, connection: RemoteTextHelperConnection, current: () => boolean): Promise<void> {
    if (!remoteTextConnectionValid(connection)) { return Promise.reject(new Error('TEXT_CONNECTION_INVALID')); }
    const frozen: string = JSON.stringify(connection);
    return this.run(lease, async (db: relationalStore.RdbStore): Promise<void> => {
      db.beginTransaction();
      try {
        const count = await db.querySql('SELECT COUNT(*) FROM text_helpers WHERE owner=? AND profile<>?', [lease.owner, connection.profileId]);
        try { if (!count.goToFirstRow() || count.getLong(0) >= 256) { throw new Error('TEXT_STORE_LIMIT'); } }
        finally { count.close(); }
        RemoteTextHelperAccess.getInstance().assertCurrent(lease);
        if (!current()) { throw new Error('TEXT_OPERATION_CANCELLED'); }
        await db.executeSql('INSERT OR REPLACE INTO text_helpers VALUES (?,?,?)', [lease.owner, connection.profileId, frozen]);
        RemoteTextHelperAccess.getInstance().assertCurrent(lease);
        if (!current()) { throw new Error('TEXT_OPERATION_CANCELLED'); }
        db.commit();
      } catch (_error) { db.rollBack(); throw new Error('TEXT_STORE_WRITE_FAILED'); }
      this.publish();
    });
  }
  remove(lease: RemoteTextHelperAccountLease, profile: string): Promise<void> {
    return this.run(lease, async (db: relationalStore.RdbStore): Promise<void> => {
      db.beginTransaction();
      try {
        await db.executeSql('DELETE FROM text_helpers WHERE owner=? AND profile=?', [lease.owner, profile]);
        RemoteTextHelperAccess.getInstance().assertCurrent(lease); db.commit();
      } catch (_error) { db.rollBack(); throw new Error('TEXT_STORE_WRITE_FAILED'); }
      this.publish();
    });
  }
  subscribe(listener: () => void): () => void {
    this.listeners.push(listener);
    return (): void => { this.listeners = this.listeners.filter((item: () => void): boolean => item !== listener); };
  }
  private publish(): void { this.listeners.slice().forEach((listener: () => void): void => { try { listener(); } catch (_error) {} }); }
}
