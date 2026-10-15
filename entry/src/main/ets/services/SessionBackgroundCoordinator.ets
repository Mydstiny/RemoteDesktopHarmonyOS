import { common, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const STOP_RETRY_MAX_MS: number = 30000;
/** After this many failed stops the task is presumed gone (for example a missed cancel event). */
const STOP_MAX_ATTEMPTS: number = 6;

class BackgroundMember {
  key: string = '';
  modes: Array<string> = [];
  /** The task covering this member was dismissed by the user or revoked by the system. */
  revoked: boolean = false;
  agent: () => Promise<WantAgent> = (): Promise<WantAgent> => Promise.reject(new Error('missing-agent'));
}
class BackgroundLane {
  members: Map<string, BackgroundMember> = new Map<string, BackgroundMember>();
  tail: Promise<void> = Promise.resolve();
  taskId: number = -1;
  modes: string = '';
  primaryKey: string = '';
  state: string = 'idle';
  revision: number = 0;
  retryTimer: number = -1;
  stopAttempts: number = 0;
  stoppingId: number = -1;
  rejectedSignature: string = '';
}

/** One serial, API21 task-ID lane per Ability, shared by all protocols and real file transfers. */
export class SessionBackgroundCoordinator {
  private static shared: SessionBackgroundCoordinator = new SessionBackgroundCoordinator();
  private lanes: Map<common.UIAbilityContext, BackgroundLane> = new Map<common.UIAbilityContext, BackgroundLane>();
  private listening: boolean = false;
  private cancelled: Array<number> = [];
  private observers: Array<(context: common.UIAbilityContext) => void> = [];
  observe(observer: (context: common.UIAbilityContext) => void): void { this.observers.push(observer); }
  private changed(context: common.UIAbilityContext): void {
    for (const observer of this.observers) { try { observer(context); } catch (_) {} }
  }
  static getInstance(): SessionBackgroundCoordinator { return SessionBackgroundCoordinator.shared; }

  private listen(): void {
    if (this.listening) { return; }
    try {
      backgroundTaskManager.on('continuousTaskCancel', (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
        this.cancelled.push(info.id); if (this.cancelled.length > 128) { this.cancelled.shift(); }
        this.lanes.forEach((lane: BackgroundLane, context: common.UIAbilityContext): void => {
          if (lane.taskId !== info.id) { return; }
          if (lane.stoppingId === info.id) { lane.taskId = -1; lane.modes = ''; return; }
          lane.taskId = -1; lane.modes = ''; this.revokeMembers(lane); lane.state = 'revoked'; lane.revision++; this.changed(context);
          hilog.warn(0x0014, 'SessionBackground', 'task revoked id=' + info.id.toString() + ' reason=' + info.reason.toString());
        });
      });
      this.listening = true;
    } catch (_error) { hilog.warn(0x0014, 'SessionBackground', 'cancellation observer unavailable'); }
  }

  acquire(context: common.UIAbilityContext, key: string, modes: Array<string>,
    agent: () => Promise<WantAgent>): Promise<boolean> {
    if (key.length === 0 || modes.length === 0 || modes.some((mode: string): boolean =>
        ['multiDeviceConnection', 'audioPlayback', 'dataTransfer'].indexOf(mode) < 0)) { return Promise.resolve(false); }
    this.listen();
    let lane: BackgroundLane | undefined = this.lanes.get(context);
    if (lane === undefined) { lane = new BackgroundLane(); this.lanes.set(context, lane); }
    const member: BackgroundMember = new BackgroundMember(); member.key = key; member.modes = modes.slice(); member.agent = agent;
    // Revocation belongs to the members the dismissed task covered. A new member (a new connection
    // or transfer) is a fresh request for itself only; an existing member re-acquiring (background
    // entry, media-mode update) keeps its revocation, so a dismissed task is not requested again.
    const previous: BackgroundMember | undefined = lane.members.get(key);
    if (previous === undefined) { lane.rejectedSignature = ''; } else { member.revoked = previous.revoked; }
    lane.members.set(key, member); lane.revision++;
    const current: BackgroundLane = lane;
    return this.enqueue(context, current).then((): boolean =>
      current.members.get(key) === member && this.running(context, key));
  }
  release(context: common.UIAbilityContext, key: string): Promise<void> {
    const lane: BackgroundLane | undefined = this.lanes.get(context);
    if (lane === undefined) { return Promise.resolve(); }
    lane.members.delete(key); lane.revision++;
    if (lane.members.size === 0) { lane.rejectedSignature = ''; }
    return this.enqueue(context, lane);
  }
  async stopAll(): Promise<void> {
    const pending: Array<Promise<void>> = [];
    this.lanes.forEach((lane: BackgroundLane, context: common.UIAbilityContext): void => {
      lane.members.clear(); lane.rejectedSignature = ''; lane.revision++;
      pending.push(this.enqueue(context, lane));
    });
    await Promise.all(pending);
  }
  running(context: common.UIAbilityContext, key: string): boolean {
    const lane: BackgroundLane | undefined = this.lanes.get(context);
    const member: BackgroundMember | undefined = lane?.members.get(key);
    return lane !== undefined && member !== undefined && lane.taskId >= 0 && !member.revoked &&
      member.modes.every((mode: string): boolean => lane!.modes.split(',').indexOf(mode) >= 0);
  }
  state(context: common.UIAbilityContext): string { return this.lanes.get(context)?.state ?? 'idle'; }
  taskId(context: common.UIAbilityContext): number { return this.lanes.get(context)?.taskId ?? -1; }

  private enqueue(context: common.UIAbilityContext, lane: BackgroundLane): Promise<void> {
    const queued: Promise<void> = lane.tail.then((): Promise<void> => this.reconcile(context, lane)).then((): void => {
      this.changed(context);
      if (lane.members.size === 0 && lane.taskId < 0 && this.lanes.get(context) === lane) { this.lanes.delete(context); }
    });
    lane.tail = queued.catch((): void => {}); return queued;
  }
  private revokeMembers(lane: BackgroundLane): void {
    lane.members.forEach((member: BackgroundMember): void => { member.revoked = true; });
  }
  private activeMembers(lane: BackgroundLane): Array<BackgroundMember> {
    return Array.from(lane.members.values()).filter((member: BackgroundMember): boolean => !member.revoked);
  }
  private async reconcile(context: common.UIAbilityContext, lane: BackgroundLane): Promise<void> {
    const active: Array<BackgroundMember> = this.activeMembers(lane);
    if (active.length === 0) {
      if (lane.taskId < 0) { lane.state = lane.members.size > 0 ? 'revoked' : 'idle'; return; }
      const taskId: number = lane.taskId;
      try {
        lane.stoppingId = taskId;
        await backgroundTaskManager.stopBackgroundRunning(context, taskId);
        if (lane.taskId === taskId) { lane.taskId = -1; lane.modes = ''; }
        lane.state = 'idle'; lane.stopAttempts = 0;
      } catch (_error) {
        lane.state = 'stop-failed';
        if (lane.stopAttempts >= STOP_MAX_ATTEMPTS) {
          // Presume the task is gone so new members can start a fresh task instead of
          // updating a dead ID forever; the lane can then be dropped.
          hilog.warn(0x0014, 'SessionBackground', 'stop abandoned id=' + taskId.toString());
          if (lane.taskId === taskId) { lane.taskId = -1; lane.modes = ''; }
          lane.state = 'stop-abandoned'; lane.stopAttempts = 0;
          return;
        }
        // Retry with a capped backoff: a leftover task keeps the notification.
        if (lane.retryTimer < 0) {
          const delay: number = Math.min(STOP_RETRY_MAX_MS, 1000 * Math.pow(2, Math.min(lane.stopAttempts, 5)));
          lane.stopAttempts++;
          lane.retryTimer = setTimeout((): void => {
            lane.retryTimer = -1; void this.enqueue(context, lane);
          }, delay);
        }
      } finally { lane.stoppingId = -1; }
      return;
    }
    const modes: Array<string> = [];
    active.forEach((member: BackgroundMember): void => {
      for (const mode of member.modes) { if (modes.indexOf(mode) < 0) { modes.push(mode); } }
    });
    modes.sort(); const signature: string = modes.join(',');
    if (signature === lane.rejectedSignature) { return; }
    const first: BackgroundMember = active[0];
    if (lane.taskId >= 0 && lane.modes === signature && lane.primaryKey === first.key) { lane.state = 'running'; return; }
    const revision: number = lane.revision;
    try {
      lane.state = lane.taskId < 0 ? 'requesting' : 'updating';
      const agent: WantAgent = await first.agent();
      if (this.activeMembers(lane).length === 0 || revision !== lane.revision) { return; }
      const request: backgroundTaskManager.ContinuousTaskRequest = new backgroundTaskManager.ContinuousTaskRequest();
      request.backgroundTaskModes = modes.map((mode: string): backgroundTaskManager.BackgroundTaskMode =>
        mode === 'dataTransfer' ? backgroundTaskManager.BackgroundTaskMode.MODE_DATA_TRANSFER :
          (mode === 'audioPlayback' ? backgroundTaskManager.BackgroundTaskMode.MODE_AUDIO_PLAYBACK :
            backgroundTaskManager.BackgroundTaskMode.MODE_MULTI_DEVICE_CONNECTION));
      request.wantAgent = agent; request.combinedTaskNotification = false;
      const updating: boolean = lane.taskId >= 0;
      if (updating) { request.continuousTaskId = lane.taskId; }
      const result: backgroundTaskManager.ContinuousTaskNotification = updating ?
        await backgroundTaskManager.updateBackgroundRunning(context, request) :
        await backgroundTaskManager.startBackgroundRunning(context, request);
      const taskId: number = result.continuousTaskId ?? (updating ? lane.taskId : -1);
      if (taskId < 0) { lane.state = 'rejected'; return; }
      if (this.cancelled.indexOf(taskId) >= 0) {
        lane.taskId = -1; lane.modes = ''; this.revokeMembers(lane); lane.state = 'revoked'; return;
      }
      lane.taskId = taskId; lane.modes = signature; lane.primaryKey = first.key; lane.state = 'running';
      // A late start is still owned by this lane. The queued stop/update reconciles the latest membership.
      if (revision !== lane.revision) { await this.reconcile(context, lane); }
    } catch (_error) { lane.state = 'rejected'; lane.rejectedSignature = signature; }
  }
}
