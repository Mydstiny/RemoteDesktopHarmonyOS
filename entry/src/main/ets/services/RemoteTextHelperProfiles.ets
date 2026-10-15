import { VncHostService, VncHostView } from './VncHostService';
import { VncGatewayService } from './VncGatewayService';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { RemoteHost } from '../model/RemoteHost';
import { MoonlightHost } from '../model/MoonlightModels';
import { HostSyncService } from './HostSyncService';
import { CloudStore } from './CloudStore';
import { MoonlightLocalViewService } from './MoonlightLocalViewService';
import { RemoteTextHelperProfile } from './RemoteTextHelperWirePolicy';

function fingerprint(text: string): string {
  const hash = cryptoFramework.createMd('SHA256'); hash.updateSync({ data: new util.TextEncoder().encode(text) });
  let result: string = '';
  for (const byte of hash.digestSync().data) { result += byte.toString(16).padStart(2, '0'); }
  return result;
}
export function remoteTextHostProfile(host: RemoteHost): RemoteTextHelperProfile | null {
  if (!['rdp', 'rustdesk', 'vnc'].includes(host.protocol) || host.id.length === 0 || host.locked) { return null; }
  // Stable local profile identity + endpoint/account/display-routing semantics. Never includes credentials.
  const relay = host.protocol === 'rustdesk' && !host.rustdeskDirectEnabled ?
    HostSyncService.getInstance().getAllRelays().find((value): boolean => value.id === host.rustdeskRelayId) : undefined;
  if (host.protocol === 'rustdesk' && !host.rustdeskDirectEnabled && relay === undefined) { return null; }
  const route: string = relay === undefined ? '' : JSON.stringify([relay.id, relay.idServer, relay.idServerPort,
    relay.relayServer, relay.relayPort, relay.apiServer, relay.controlPlaneProfile, relay.keyMode, relay.updatedAt, relay.syncVersion]);
  const key: string = JSON.stringify([host.protocol, host.id, host.host.trim().toLowerCase(), host.port,
    host.customHostname, host.username, host.gatewayHost, host.gatewayPort, host.rdpGatewayTransport,
    host.rdpEndpointMode, host.rdpGatewayServerName, host.rdpCredentialId, host.rdpAuthMode,
    host.rustdeskDirectEnabled, host.rustdeskDirectHost, host.rustdeskDirectPort, host.rustdeskRelayId,
    host.rustdeskAccountId, host.rustdeskProAccountId, host.rustdeskProPeerId, host.rustdeskProManaged,
    host.lanDiscoveryIdentity, host.rustdeskTargetDevice, route]);
  return { id: host.protocol + ':' + host.id, protocol: host.protocol, label: host.label || host.host, connectionKey: fingerprint(key) };
}
export function remoteTextVncProfile(host: VncHostView): RemoteTextHelperProfile | null {
  if (host.locked || host.id.length === 0) { return null; }
  const gateway = host.gatewayId.length === 0 ? null : VncGatewayService.getInstance().find(host.gatewayId);
  if (host.transport !== 'direct_tcp' && gateway === null) { return null; }
  const route: string = gateway === null ? '' : JSON.stringify([gateway.id, gateway.host, gateway.port,
    gateway.transport, gateway.path, gateway.repeaterMode, gateway.targetId, gateway.tls, gateway.enabled]);
  return { id: 'vnc:' + host.id, protocol: 'vnc', label: host.label,
    connectionKey: fingerprint(JSON.stringify(['vnc', host.id, host.host, host.port, host.username,
      host.transport, host.gatewayId, host.repeaterMode, host.tls, route])) };
}
export function remoteTextMoonlightProfile(host: MoonlightHost, appId: string, label: string): RemoteTextHelperProfile | null {
  if (host.locked === true || host.id.length === 0 || !/^[0-9]+$/.test(appId)) { return null; }
  const addresses = host.addresses.map((value): string => value.host.toLowerCase() + ':' + value.port.toString()).sort();
  return { id: 'moonlight:' + host.id + ':' + appId, protocol: 'moonlight', label: host.displayName + ' · ' + label,
    connectionKey: fingerprint(JSON.stringify(['moonlight', host.id, host.serverUuid, addresses, host.httpsPort, appId])) };
}
export function remoteTextHelperProfiles(): Array<RemoteTextHelperProfile> {
  const profiles: Array<RemoteTextHelperProfile> = [];
  for (const host of HostSyncService.getInstance().getAllHosts()) {
    const profile = remoteTextHostProfile(host); if (profile !== null) { profiles.push(profile); }
  }
  for (const host of VncHostService.getInstance().list()) {
    const profile = remoteTextVncProfile(host); if (profile !== null) { profiles.push(profile); }
  }
  const directory = new MoonlightLocalViewService(CloudStore.getInstance()).loadHosts(Date.now());
  if (directory.ok) {
    for (const view of directory.hosts) {
      if (view.host === null) { continue; }
      for (const item of view.catalogItems) {
        const profile = remoteTextMoonlightProfile(view.host, item.appId, item.title);
        if (profile !== null && !profiles.some((value): boolean => value.id === profile.id)) { profiles.push(profile); }
      }
    }
  }
  return profiles.slice(0, 256);
}
