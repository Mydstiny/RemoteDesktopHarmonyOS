import { describe, expect, it } from '@ohos/hypium';
import { RemoteTextOwner } from '../main/ets/services/RemoteTextInputPolicy';
import { remoteTextRecord, remoteTextBinding, remoteTextSnapshot, RemoteTextHelperConnection, RemoteTextHelperBinding } from '../main/ets/services/RemoteTextHelperWirePolicy';

export default function remoteTextHelperWireTest(): void {
  describe('RemoteTextHelperWire', (): void => {
    it('binds_identity_frame_and_empty_focus_without_remote_clock_trust', 0, (): void => {
      const connection: RemoteTextHelperConnection = { profileId: 'rdp:fixture', connectionKey: 'a'.repeat(64),
        address: '127.0.0.1', serverName: 'localhost', port: 9446, instance: 'instance', deviceId: 'device',
        ca: '', certificate: '', privateKey: '' };
      const bound: Record<string, Object> = remoteTextRecord(JSON.parse(
        '{"version":1,"runtime":"runtime","instance":"instance","deviceId":"device",' +
        '"lease":"lease","ttlMs":15000,"desktopBinding":"windows:3:Default","bindingId":"capture"}') as Object);
      const binding: RemoteTextHelperBinding = remoteTextBinding(bound, connection);
      const owner: RemoteTextOwner = { protocol: 'rdp', protocolSessionId: 'rdp:3', sessionId: 4, generation: 7, geometryEpoch: 2,
        displayId: 0, desktopBinding: binding.desktopBinding, frameWidth: 1280, frameHeight: 720 };
      const raw: Record<string, Object> = remoteTextRecord(JSON.parse(
        '{"version":1,"runtime":"runtime","bindingId":"capture","desktopBinding":"windows:3:Default",' +
        '"protocolSessionId":"rdp:3","displayId":0,"frameWidth":1280,"frameHeight":720,' +
        '"ownerNonce":"owner","sequence":1,"available":true,"reason":"no-editable-focus",' +
        '"focus":true,"geometry":false,"target":null}') as Object);
      expect(remoteTextSnapshot(raw, binding, owner, 'owner', 0).target === null).assertTrue();
      let rejected: boolean = false;
      raw['ownerNonce'] = 'retired';
      try { remoteTextSnapshot(raw, binding, owner, 'owner', 0); } catch (_error) { rejected = true; }
      expect(rejected).assertTrue();
    });
  });
}
