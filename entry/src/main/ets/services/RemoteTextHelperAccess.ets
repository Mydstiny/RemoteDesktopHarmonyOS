import { AccountSessionCoordinator } from './AccountSessionCoordinator';
import { AccountScopeToken } from './AccountScopePolicy';

export interface RemoteTextHelperAccountLease { owner: string; generation: number; epoch: number; }
/** Free local capability; account transitions are the only account gate. */
export class RemoteTextHelperAccess {
  private static instance: RemoteTextHelperAccess;
  private transitioning: boolean = false;
  private epoch: number = 0;
  private listeners: Array<() => void> = [];
  private constructor() {
    const account = AccountSessionCoordinator.getInstance();
    account.onTransitionActivity((active: boolean): void => { this.transitioning = active; if (active) { this.invalidate(); } });
    account.onChange((_scope: AccountScopeToken): void => { this.invalidate(); });
  }
  static getInstance(): RemoteTextHelperAccess {
    if (!RemoteTextHelperAccess.instance) { RemoteTextHelperAccess.instance = new RemoteTextHelperAccess(); }
    return RemoteTextHelperAccess.instance;
  }
  capture(): RemoteTextHelperAccountLease {
    const scope: AccountScopeToken = AccountSessionCoordinator.getInstance().currentScope();
    if (this.transitioning || !['bound', 'ready', 'offline'].includes(scope.sessionState) || scope.ownerScopeId.length === 0) {
      throw new Error('TEXT_ACCOUNT_UNAVAILABLE');
    }
    return { owner: scope.ownerScopeId, generation: scope.generation, epoch: this.epoch };
  }
  current(lease: RemoteTextHelperAccountLease): boolean {
    try { const now = this.capture(); return now.owner === lease.owner && now.generation === lease.generation && now.epoch === lease.epoch; }
    catch (_error) { return false; }
  }
  assertCurrent(lease: RemoteTextHelperAccountLease): void {
    if (!this.current(lease)) { throw new Error('TEXT_ACCOUNT_CHANGED'); }
  }
  subscribe(listener: () => void): () => void {
    this.listeners.push(listener);
    return (): void => { this.listeners = this.listeners.filter((item: () => void): boolean => item !== listener); };
  }
  invalidate(): void {
    this.epoch++;
    this.listeners.slice().forEach((listener: () => void): void => { try { listener(); } catch (_error) {} });
  }
}
