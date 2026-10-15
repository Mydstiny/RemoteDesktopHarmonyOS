import { FOCUS_SESSION_WINDOW_PARAM } from './SessionWindowFocusParam';
import { SessionBackgroundCoordinator } from './SessionBackgroundCoordinator';
/**
 * SSH terminal background continuity.
 *
 * SSH owns its member records; the shared Ability coordinator owns the OS task.
 */
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  buildSshBackgroundNotificationContent,
  SshBackgroundNotificationContent
} from './ssh/notification/SshNotificationService';
import { sshDiagnosticErrorCode } from './ssh/observability/SshDiagnosticPolicy';

const TAG = 'SshTerminalBgTask';
const DOMAIN = 0x0016;
const SSH_NOTIFICATION_ID = 606000;
const SSH_NOTIFICATION_SLOT = notificationManager.SlotType.SERVICE_INFORMATION;

interface ActiveSshTask {
  context: common.UIAbilityContext;
  sessionId: number;
  continuousTaskId: number;
  notificationId: number;
  hostId: string;
  hostLabel: string;
  hostAddress: string;
  state: 'running' | 'rejected';
}

export interface SshTerminalBackgroundSnapshot {
  sessionId: number;
  hostId: string;
  hostLabel: string;
  hostAddress: string;
  state: 'running' | 'rejected';
}

export interface SshTerminalBackgroundInfo {
  windowId?: string;
  hostId: string;
  sessionId: number;
  hostLabel: string;
  hostAddress: string;
}

/**
 * Page-local ownership of tasks started from the live Ability background
 * signal. The page can be torn down while the process-wide background service
 * is still draining an async start/stop operation, so this registry must be
 * reset at every page lifecycle boundary. Keeping the identity keyed by the
 * normalized host/session pair also prevents duplicate signal callbacks from
 * growing an unbounded list.
 */
export class SshBackgroundSignalTaskRegistry {
  private readonly tasks: Map<string, SshTerminalBackgroundInfo> =
    new Map<string, SshTerminalBackgroundInfo>();

  private key(info: SshTerminalBackgroundInfo): string {
    const hostId: string = info.hostId.trim();
    if (hostId.length === 0 || info.sessionId <= 0) { return ''; }
    return hostId + '#' + info.sessionId.toString();
  }

  track(info: SshTerminalBackgroundInfo): void {
    const key: string = this.key(info);
    if (key.length === 0) { return; }
    this.tasks.set(key, {
      hostId: info.hostId.trim(),
      sessionId: info.sessionId,
      hostLabel: info.hostLabel,
      hostAddress: info.hostAddress, windowId: info.windowId
    });
  }

  snapshot(): SshTerminalBackgroundInfo[] {
    const result: SshTerminalBackgroundInfo[] = [];
    this.tasks.forEach((info: SshTerminalBackgroundInfo): void => {
      result.push({
        hostId: info.hostId,
        sessionId: info.sessionId,
        hostLabel: info.hostLabel,
        hostAddress: info.hostAddress, windowId: info.windowId
      });
    });
    return result;
  }

  clear(): void { this.tasks.clear(); }

  size(): number { return this.tasks.size; }
}

export enum SshBackgroundSignalAction {
  none = 0,
  start = 1,
  stop = 2
}

/**
 * A normal Home/lock transition keeps the ArkUI page mounted, so
 * aboutToDisappear cannot be the only continuous-task trigger. Page teardown
 * remains the owner while terminalClosing is true; otherwise the live Ability
 * background signal starts the current sessions and the matching foreground
 * signal stops only tasks registered by that page.
 */
export function decideSshBackgroundSignalAction(isBackground: boolean,
  terminalClosing: boolean, activeSessionCount: number,
  pageTrackedTaskCount: number): SshBackgroundSignalAction {
  if (terminalClosing) { return SshBackgroundSignalAction.none; }
  if (isBackground) {
    return activeSessionCount > 0 ? SshBackgroundSignalAction.start :
      SshBackgroundSignalAction.none;
  }
  return pageTrackedTaskCount > 0 ? SshBackgroundSignalAction.stop :
    SshBackgroundSignalAction.none;
}

export class SshTerminalBackgroundTaskService {
  private static instance: SshTerminalBackgroundTaskService | null = null;
  private readonly tasks: Map<string, ActiveSshTask> = new Map<string, ActiveSshTask>();
  private requestSequence: number = 0;
  private notificationTail: Promise<void> = Promise.resolve();
  constructor() {
    SessionBackgroundCoordinator.getInstance().observe((_context: common.UIAbilityContext): void => {
      void this.publishAggregateNotification();
    });
  }

  static getInstance(): SshTerminalBackgroundTaskService {
    if (SshTerminalBackgroundTaskService.instance === null) {
      SshTerminalBackgroundTaskService.instance = new SshTerminalBackgroundTaskService();
    }
    return SshTerminalBackgroundTaskService.instance;
  }

  async start(context: common.UIAbilityContext, info: SshTerminalBackgroundInfo): Promise<boolean> {
    const hostId: string = info.hostId.trim();
    if (hostId.length === 0 || info.sessionId <= 0) { return false; }
    const key: string = this.taskKey(hostId, info.sessionId);
    const task: ActiveSshTask = { context, sessionId: info.sessionId, hostId,
      hostLabel: info.hostLabel, hostAddress: info.hostAddress, continuousTaskId: -1,
      notificationId: SSH_NOTIFICATION_ID, state: 'rejected' };
    this.tasks.set(key, task);
    const coordinator: SessionBackgroundCoordinator = SessionBackgroundCoordinator.getInstance();
    const started: boolean = await coordinator.acquire(context, 'ssh:' + key, ['multiDeviceConnection'],
      async (): Promise<WantAgent> => {
        const parameters: Record<string, Object> = {};
        parameters['hostId'] = hostId; parameters['sessionId'] = info.sessionId;
        parameters['resumeSshSession'] = true; parameters['protocol'] = 'ssh';
        if (info.windowId !== undefined && info.windowId.length > 0) { parameters[FOCUS_SESSION_WINDOW_PARAM] = info.windowId; }
        return wantAgent.getWantAgent({ wants: [{ bundleName: context.abilityInfo.bundleName,
          abilityName: 'EntryAbility', parameters }], actionType: wantAgent.OperationType.START_ABILITY,
          requestCode: this.nextRequestCode(), wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] });
      });
    if (this.tasks.get(key) !== task) { return false; }
    task.state = started ? 'running' : 'rejected'; task.continuousTaskId = coordinator.taskId(context);
    await this.publishAggregateNotification(); return started;
  }
  async stopAllSessionTasks(): Promise<void> {
    const tasks: Array<ActiveSshTask> = Array.from(this.tasks.values());
    // Retire metadata synchronously so late start completions and observer
    // notifications cannot resurrect the previous account's sessions.
    this.tasks.clear();
    const coordinator: SessionBackgroundCoordinator = SessionBackgroundCoordinator.getInstance();
    await Promise.all(tasks.map((task: ActiveSshTask): Promise<void> =>
      coordinator.release(task.context, 'ssh:' + this.taskKey(task.hostId, task.sessionId))));
    await this.publishAggregateNotification();
  }
  async stop(context: common.UIAbilityContext): Promise<void> {
    const tasks: Array<ActiveSshTask> = Array.from(this.tasks.values());
    for (const task of tasks) {
      if (task.context === context) { await this.stopSession(context, task.sessionId, task.hostId); }
    }
  }
  async stopSession(context: common.UIAbilityContext, sessionId: number, hostId: string = ''): Promise<void> {
    const tasks: Array<ActiveSshTask> = Array.from(this.tasks.values());
    const coordinator: SessionBackgroundCoordinator = SessionBackgroundCoordinator.getInstance();
    for (const task of tasks) {
      if (task.context !== context || task.sessionId !== sessionId ||
        (hostId.length > 0 && task.hostId !== hostId.trim())) { continue; }
      const key: string = this.taskKey(task.hostId, sessionId);
      this.tasks.delete(key); await coordinator.release(context, 'ssh:' + key);
    }
    await this.publishAggregateNotification();
  }
  private taskRunning(task: ActiveSshTask): boolean {
    return SessionBackgroundCoordinator.getInstance().running(task.context, 'ssh:' + this.taskKey(task.hostId, task.sessionId));
  }

  isRunning(): boolean {
    let running: boolean = false;
    this.tasks.forEach((task: ActiveSshTask): void => {
      if (this.taskRunning(task)) { running = true; }
    });
    return running;
  }

  activeCount(): number {
    let count: number = 0;
    this.tasks.forEach((task: ActiveSshTask): void => {
      if (this.taskRunning(task)) { count++; }
    });
    return count;
  }

  isBackgroundLimited(sessionId: number, hostId: string = ''): boolean {
    const normalizedHostId: string = hostId.trim();
    let limited: boolean = false;
    this.tasks.forEach((task: ActiveSshTask): void => {
      if (task.sessionId === sessionId &&
        (normalizedHostId.length === 0 || task.hostId === normalizedHostId) &&
        !this.taskRunning(task)) {
        limited = true;
      }
    });
    return limited;
  }

  snapshot(): SshTerminalBackgroundSnapshot[] {
    const result: SshTerminalBackgroundSnapshot[] = [];
    this.tasks.forEach((task: ActiveSshTask): void => {
      result.push({
        sessionId: task.sessionId,
        hostId: task.hostId,
        hostLabel: task.hostLabel,
        hostAddress: task.hostAddress,
        state: this.taskRunning(task) ? 'running' : 'rejected'
      });
    });
    return result;
  }

  private publishAggregateNotification(): Promise<void> {
    const pending: Promise<void> = this.notificationTail.then((): Promise<void> => this.publishLatestNotification());
    this.notificationTail = pending.catch((): void => {}); return pending;
  }
  private async publishLatestNotification(): Promise<void> {
    const snapshots: SshTerminalBackgroundSnapshot[] = this.snapshot();
    if (snapshots.length === 0) {
      try { await notificationManager.cancel(SSH_NOTIFICATION_ID); } catch (_err) { /* best effort */ }
      return;
    }
    const runningCount: number = snapshots.filter(
      (snapshot: SshTerminalBackgroundSnapshot): boolean => snapshot.state === 'running').length;
    const limitedCount: number = snapshots.length - runningCount;
    const content: SshBackgroundNotificationContent =
      buildSshBackgroundNotificationContent(runningCount, limitedCount);
    const request: notificationManager.NotificationRequest = {
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: content.title,
          text: content.text
        }
      },
      id: SSH_NOTIFICATION_ID,
      notificationSlotType: SSH_NOTIFICATION_SLOT,
      tapDismissed: false,
      isAlertOnce: true
    };
    try {
      await notificationManager.publish(request);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'SSH notification publish failed code=' +
        sshDiagnosticErrorCode(err));
    }
  }

  private taskKey(hostId: string, sessionId: number): string {
    return hostId + '#' + sessionId.toString();
  }

  private nextRequestCode(): number {
    this.requestSequence = (this.requestSequence + 1) % 10000;
    return SSH_NOTIFICATION_ID + this.requestSequence;
  }

}
