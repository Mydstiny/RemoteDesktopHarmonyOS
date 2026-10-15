import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { RemoteTextHelperProfile } from '../services/RemoteTextHelperWirePolicy';
import { remoteTextHelperProfiles } from '../services/RemoteTextHelperProfiles';
import { RemoteTextHelperAccess } from '../services/RemoteTextHelperAccess';
import { RemoteTextHelperStore } from '../services/RemoteTextHelperStore';
import { pairRemoteTextHelper } from '../services/RemoteTextHelperRuntime';

/** Optional free helper setup inside keyboard settings. Never edits protocol credentials or installs a service. */
@Component
export struct RemoteTextHelperSettings {
  @StorageProp('accentColor') accent: string = '#007DFF';
  @StorageProp('currentTheme') theme: string = 'dark';
  @State private profiles: Array<RemoteTextHelperProfile> = [];
  @State private selectedId: string = '';
  @State private address: string = '';
  @State private serverName: string = '';
  @State private port: string = '9446';
  @State private invite: string = '';
  @State private busy: boolean = false;
  @State private configured: boolean = false;
  @State private status: string = '';
  @State private expanded: boolean = false;
  private epoch: number = 0;
  private live: boolean = false;
  private offAccount: (() => void) | null = null;
  private cancelPair: () => void = (): void => {};
  private text(): string { return this.theme === 'dark' ? '#F5F7FA' : '#101828'; }
  private subtext(): string { return this.theme === 'dark' ? '#98A2B3' : '#667085'; }
  private selected(): RemoteTextHelperProfile | null { return this.profiles.find((value): boolean => value.id === this.selectedId) ?? null; }
  aboutToAppear(): void {
    this.live = true; this.profiles = remoteTextHelperProfiles();
    this.offAccount = RemoteTextHelperAccess.getInstance().subscribe((): void => {
      this.epoch++; this.cancelPair(); this.busy = false; this.configured = false;
      this.invite = ''; this.selectedId = ''; this.profiles = []; this.status = '账号状态已变化，请重新进入此页';
    });
  }
  aboutToDisappear(): void {
    this.live = false; this.epoch++; this.cancelPair(); this.invite = ''; this.offAccount?.(); this.offAccount = null;
  }
  private async select(profile: RemoteTextHelperProfile): Promise<void> {
    const epoch: number = ++this.epoch;
    this.selectedId = profile.id; this.invite = ''; this.configured = false; this.status = '';
    try {
      const access = RemoteTextHelperAccess.getInstance(), lease = access.capture();
      const store = RemoteTextHelperStore.getInstance(); await store.initialize(getContext(this) as common.Context);
      const value = await store.load(lease, profile.id, profile.connectionKey);
      if (!this.live || epoch !== this.epoch || !access.current(lease)) { return; }
      this.configured = value !== null;
      if (value !== null) { this.address = value.address; this.serverName = value.serverName; this.port = value.port.toString(); }
      this.status = value === null ? '尚未配对焦点辅助' : '已配对；输入框能力将在连接对应桌面时验证';
    } catch (_error) { if (this.live && epoch === this.epoch) { this.status = '本地配对存储暂不可用'; } }
  }
  private async pair(): Promise<void> {
    const profile = this.selected(); if (profile === null || this.busy) { return; }
    const port: number = Number(this.port);
    if (!Number.isSafeInteger(port) || port < 1024 || port > 65535) { this.status = '请填写有效端口'; return; }
    const epoch: number = ++this.epoch;
    const address: string = this.address.trim(), name: string = this.serverName.trim() || address.split('%')[0];
    this.busy = true; this.status = '正在验证证书和配对权限…';
    try {
      await pairRemoteTextHelper(getContext(this) as common.Context, profile, address, name, port, this.invite,
        (): boolean => this.live && epoch === this.epoch && this.selectedId === profile.id &&
          remoteTextHelperProfiles().some((value): boolean => value.id === profile.id && value.connectionKey === profile.connectionKey),
        (cancel: () => void): void => { this.cancelPair = cancel; });
      if (!this.live || epoch !== this.epoch) { return; }
      this.invite = ''; this.configured = true; this.status = '已配对；输入框能力将在连接对应桌面时验证';
    } catch (_error) {
      if (this.live && epoch === this.epoch) { this.invite = ''; this.status = '配对未完成，请检查地址并在宿主重新生成邀请'; }
    } finally { if (epoch === this.epoch) { this.busy = false; } }
  }
  private async remove(): Promise<void> {
    const profile = this.selected(); if (profile === null || this.busy) { return; }
    const epoch = ++this.epoch; this.busy = true;
    try {
      const access = RemoteTextHelperAccess.getInstance(), lease = access.capture();
      await RemoteTextHelperStore.getInstance().remove(lease, profile.id);
      if (!this.live || epoch !== this.epoch || !access.current(lease)) { return; }
      this.configured = false; this.status = '本机配对已移除；宿主仍可单独撤销此设备授权';
    } catch (_error) { if (this.live && epoch === this.epoch) { this.status = '移除配对失败，请重试'; } }
    finally { if (epoch === this.epoch) { this.busy = false; } }
  }
  private copyBinding(): void {
    const profile = this.selected(); if (profile === null) { return; }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, profile.connectionKey);
    void pasteboard.getSystemPasteboard().setData(data).then((): void => {
      if (this.live) { promptAction.showToast({ message: '桌面连接标识已复制', duration: 1400 }); }
    }).catch((): void => { if (this.live) { this.status = '复制失败'; } });
  }
  build() {
    Column({ space: 10 }) {
      Button(this.expanded ? '收起焦点辅助设置' : '配置远端焦点辅助（可选）')
        .fontColor(this.accent).backgroundColor(Color.Transparent).padding(0)
        .onClick((): void => { this.expanded = !this.expanded; })
      Text('SSH 直接使用终端光标。RDP、RustDesk、VNC 和 Moonlight 可通过免费宿主辅助提供输入框位置；未配置时仍可手动或使用点击兼容模式。')
        .fontSize(12).fontColor(this.subtext()).width('100%')
      if (this.expanded) {
        Text('在远端实际被捕获的用户桌面启动焦点辅助，授予系统无障碍权限并登记桌面范围。辅助只发送输入框和光标位置，不发送输入正文。')
          .fontSize(12).fontColor(this.subtext()).width('100%')
        if (this.profiles.length === 0) { Text('请先添加一个图形远程主机；Moonlight 需先读取应用目录。').fontColor(this.subtext()).fontSize(12) }
        ForEach(this.profiles, (profile: RemoteTextHelperProfile): void => {
          Button(profile.label + ' · ' + profile.protocol).fontColor(this.selectedId === profile.id ? this.accent : this.text())
            .backgroundColor(Color.Transparent).width('100%').enabled(!this.busy)
            .onClick((): void => { void this.select(profile); })
        }, (profile: RemoteTextHelperProfile): string => profile.id)
        if (this.selectedId.length > 0) {
          Button('复制桌面连接标识供宿主登记').fontColor(this.accent).backgroundColor(Color.Transparent).onClick((): void => this.copyBinding())
          TextInput({ text: this.address, placeholder: '辅助服务地址（IP 或域名）' }).maxLength(253).enabled(!this.busy)
            .onChange((value: string): void => { this.address = value; })
          TextInput({ text: this.serverName, placeholder: '证书中的服务器名（留空使用地址）' }).maxLength(253).enabled(!this.busy)
            .onChange((value: string): void => { this.serverName = value; })
          TextInput({ text: this.port, placeholder: '辅助服务端口' }).type(InputType.Number).maxLength(5).enabled(!this.busy)
            .onChange((value: string): void => { this.port = value; })
          TextArea({ text: this.invite, placeholder: '粘贴宿主生成的完整配对邀请 JSON' }).maxLength(20000).height(88).enabled(!this.busy)
            .onChange((value: string): void => { this.invite = value; })
          Button(this.busy ? '正在处理…' : '配对焦点辅助').enabled(!this.busy && this.invite.length > 0)
            .backgroundColor(this.accent).fontColor(Color.White).onClick((): void => { void this.pair(); })
          if (this.configured) { Button('移除本机配对').enabled(!this.busy).fontColor('#FF6B6B').backgroundColor(Color.Transparent).onClick((): void => { void this.remove(); }) }
          if (this.status.length > 0) { Text(this.status).fontSize(12).fontColor(this.subtext()).width('100%') }
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 12, bottom: 12 })
  }
}
