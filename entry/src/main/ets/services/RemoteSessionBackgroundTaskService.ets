import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { SessionBackgroundCoordinator } from './SessionBackgroundCoordinator';
import { FOCUS_SESSION_WINDOW_PARAM } from './SessionWindowFocusParam';

export interface RemoteSessionBgInfo {
  hostId: string;
  sessionId: number;
  resumeRemoteSession: boolean;
  protocolLabel: string;
  hostAddress: string;
  hasAudio: boolean;
  hasVideo: boolean;
  /** The session window (empty for the main window); a tap on the notification brings it forward. */
  windowId?: string;
  /** True only after the active AVSession is established for the actual playback. */
  mediaSessionActive?: boolean;
}

/** Connection tasks are independent from the page's presentation/notification preferences. */
export class RemoteSessionBackgroundTaskService {
  private static shared: RemoteSessionBackgroundTaskService = new RemoteSessionBackgroundTaskService();
  private members: Map<common.UIAbilityContext, Map<string, RemoteSessionBgInfo>> =
    new Map<common.UIAbilityContext, Map<string, RemoteSessionBgInfo>>();
  private coordinator: SessionBackgroundCoordinator = SessionBackgroundCoordinator.getInstance();
  private requestCode: number = 605000;
  static getInstance(): RemoteSessionBackgroundTaskService { return RemoteSessionBackgroundTaskService.shared; }
  private key(info: RemoteSessionBgInfo): string {
    return 'remote:' + info.protocolLabel.toLowerCase() + ':' + info.sessionId.toString();
  }
  async startSessionTask(context: common.UIAbilityContext, info: RemoteSessionBgInfo): Promise<boolean> {
    if (info.sessionId <= 0 || info.hostId.length === 0) { return false; }
    let members: Map<string, RemoteSessionBgInfo> | undefined = this.members.get(context);
    if (members === undefined) { members = new Map<string, RemoteSessionBgInfo>(); this.members.set(context, members); }
    const key: string = this.key(info); members.set(key, info);
    const modes: Array<string> = ['multiDeviceConnection'];
    if (info.mediaSessionActive === true && (info.hasAudio || info.hasVideo)) { modes.push('audioPlayback'); }
    const requestCode: number = ++this.requestCode;
    return this.coordinator.acquire(context, key, modes, async (): Promise<WantAgent> => {
      const parameters: Record<string, Object> = {};
      parameters['hostId'] = info.hostId; parameters['sessionId'] = info.sessionId;
      parameters['resumeRemoteSession'] = info.resumeRemoteSession;
      if (info.windowId !== undefined && info.windowId.length > 0) { parameters[FOCUS_SESSION_WINDOW_PARAM] = info.windowId; }
      return wantAgent.getWantAgent({ wants: [{ bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility', parameters }], actionType: wantAgent.OperationType.START_ABILITY,
        requestCode, wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] });
    });
  }
  async startAudioPlaybackTask(context: common.UIAbilityContext, info: RemoteSessionBgInfo): Promise<void> {
    await this.updateAudioPlaybackMode(context, info);
  }
  async updateAudioPlaybackMode(context: common.UIAbilityContext, info: RemoteSessionBgInfo): Promise<void> {
    if (!this.members.get(context)?.has(this.key(info))) { return; }
    await this.startSessionTask(context, info);
  }
  async stopSessionTask(context: common.UIAbilityContext, sessionId: number,
    protocol: string): Promise<void> {
    const members: Map<string, RemoteSessionBgInfo> | undefined = this.members.get(context);
    if (members === undefined) { return; }
    const keys: Array<string> = [];
    members.forEach((info: RemoteSessionBgInfo, key: string): void => {
      if (info.sessionId === sessionId && info.protocolLabel.toLowerCase() === protocol.toLowerCase()) { keys.push(key); }
    });
    for (const key of keys) { members.delete(key); await this.coordinator.release(context, key); }
    if (members.size === 0) { this.members.delete(context); }
  }
  async stopAllSessionTasks(): Promise<void> {
    this.members.clear(); await this.coordinator.stopAll();
  }
  isRunning(): boolean {
    let running: boolean = false;
    this.members.forEach((members: Map<string, RemoteSessionBgInfo>, context: common.UIAbilityContext): void => {
      members.forEach((_info: RemoteSessionBgInfo, key: string): void => { if (this.coordinator.running(context, key)) { running = true; } });
    });
    return running;
  }
  wasRejected(): boolean {
    let rejected: boolean = false;
    this.members.forEach((_members: Map<string, RemoteSessionBgInfo>, context: common.UIAbilityContext): void => {
      const state: string = this.coordinator.state(context);
      if (state === 'rejected' || state === 'revoked' || state === 'stop-failed') { rejected = true; }
    });
    return rejected;
  }
}
