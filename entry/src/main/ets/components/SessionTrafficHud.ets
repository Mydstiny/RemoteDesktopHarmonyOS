import { SessionTrafficView, formatTrafficBytes, trafficScopeLabel } from '../services/SessionTrafficSampler';

@Component
export struct SessionTrafficHud {
  @Prop traffic: SessionTrafficView = new SessionTrafficView();
  @Prop expanded: boolean = false;

  private rate(received: boolean): string {
    return this.traffic.rateAvailable ? formatTrafficBytes(received ?
      this.traffic.receivedPerSecond : this.traffic.sentPerSecond) + '/s' : '—';
  }
  private points(received: boolean): Array<Array<number>> {
    const history = this.traffic.points;
    if (history.length < 2) { return []; }
    const last: number = history[history.length - 1].atMs;
    let max: number = 1;
    for (const item of history) { max = Math.max(max, item.received, item.sent); }
    return history.map((item): Array<number> => [180 * (1 - (last - item.atMs) / 60000),
      30 - 28 * (received ? item.received : item.sent) / max]);
  }
  build() {
    Column({ space: 3 }) {
      Row() {
        Text('网速 ↓ / ↑').fontSize(10).fontColor('#BAC3D1')
        Blank()
        Text(this.rate(true) + ' / ' + this.rate(false)).fontSize(10).fontColor('#FFFFFF')
      }.width('100%')
      if (this.expanded) {
        Text('累计 ↓ ' + (this.traffic.available ? formatTrafficBytes(this.traffic.receivedTotal) : '—') +
          '  ↑ ' + (this.traffic.available ? formatTrafficBytes(this.traffic.sentTotal) : '—'))
          .fontSize(9).fontColor('#BAC3D1').width('100%')
        if (this.traffic.points.length >= 2) {
          Stack() {
            Polyline().points(this.points(true)).stroke('#66D9EF').strokeWidth(1.5).fill('none')
            Polyline().points(this.points(false)).stroke('#F8C970').strokeWidth(1.5).fill('none')
          }.width(180).height(32)
        }
        Text(trafficScopeLabel(this.traffic.scope) + ' · 60 秒趋势').fontSize(9).fontColor('#BAC3D1').width('100%')
        Text('不含 IP/TCP 头；RustDesk 不含独立文件通道与信令').fontSize(8).fontColor('#8E99AA').width('100%')
      }
    }.width('100%').hitTestBehavior(HitTestMode.Transparent)
  }
}
