import { describe, expect, it } from '@ohos/hypium';
import { RemoteTextInputSession, RemoteTextOwner, RemoteTextTarget, RemoteTextOpenContext,
  defaultRemoteKeyboardBehavior, remoteVirtualKeyboardIntent } from '../main/ets/services/RemoteTextInputPolicy';
import { resolveRemoteKeyboardAvoidance } from '../main/ets/services/RemoteKeyboardAvoidancePolicy';
import { remoteKeyboardTransformPresented } from '../main/ets/services/RemoteKeyboardViewportPolicy';
import { RemoteImeCommand, RemoteImeCommandQueue } from '../main/ets/services/RemoteImeCommandQueue';

export default function remoteTextInputKeyboardTest(): void {
  describe('RemoteTextInputKeyboard', (): void => {
    it('migrates_explicit_compatibility_and_virtual_intent', 0, (): void => {
      expect(defaultRemoteKeyboardBehavior(true).autoOpenPolicy).assertEqual('compatibilityClick');
      expect(defaultRemoteKeyboardBehavior(false).autoOpenPolicy).assertEqual('off');
      expect(remoteVirtualKeyboardIntent('virtual', true, true)).assertTrue();
      expect(remoteVirtualKeyboardIntent('physical', false, false)).assertFalse();
    });
    it('fences_owner_and_preserves_confirmed_static_geometry', 0, (): void => {
      const owner: RemoteTextOwner = { protocol: 'rdp', sessionId: 3, generation: 5, geometryEpoch: 1,
        displayId: 0, desktopBinding: '', frameWidth: 1280, frameHeight: 720 };
      const event: RemoteTextTarget = { owner, source: 'rdpTextChannel', focusToken: 'one', sequence: 1,
        editable: true, readOnly: false, enabled: true, visible: true, verified: true, inputKind: 'text',
        controlRect: { x: 100, y: 600, width: 200, height: 40 }, caretRect: null };
      const context: RemoteTextOpenContext = { policy: 'smart', virtualInput: true, connected: true,
        inputReady: true, foreground: true, modalOwnsInput: false, readOnly: false, keyboardOpen: false };
      const session: RemoteTextInputSession = new RemoteTextInputSession();
      session.setOwner(owner); session.recordUserIntent(0);
      expect(session.acceptTarget(event)).assertTrue();
      expect(session.canAutoOpen(context, 1)).assertTrue();
      expect(session.canAutoOpen(context, 2000)).assertFalse();
      expect(session.targetRect() !== null).assertTrue();
      session.suppressKeyboard(); expect(session.canAutoOpen(context, 1)).assertFalse();
      session.beginFocusMutation(2); expect(session.targetRect() === null).assertTrue();
      owner.geometryEpoch = 2; session.setOwner(owner);
      expect(session.acceptTarget(event)).assertTrue();
      owner.generation = 6;
      expect(session.acceptTarget(event)).assertFalse();
    });
    it('places_target_above_actual_occlusion_and_waits_for_presentation', 0, (): void => {
      const result = resolveRemoteKeyboardAvoidance({ target: { x: 20, y: 600, width: 100, height: 24 },
        occlusion: { visible: true, geometryKnown: true, docked: true,
          rect: { x: 0, y: 500, width: 400, height: 300 } },
        viewport: { x: 0, y: 0, width: 400, height: 800 }, placement: 'nearKeyboard', gap: 16,
        bottomBarHeight: 0, currentX: 0, currentY: 0, initial: true });
      expect(624 + result.y).assertEqual(484);
      expect(remoteKeyboardTransformPresented(3, 3, 2)).assertFalse();
      expect(remoteKeyboardTransformPresented(3, 3, 3)).assertTrue();
    });
    it('drains_committed_input_before_focus_and_retains_failed_command', 0, (): void => {
      const queue: RemoteImeCommandQueue = new RemoteImeCommandQueue();
      queue.enqueueText('text', 7, 'commit');
      expect(queue.drainBeforeFocusChange(7, false, (_command: RemoteImeCommand): boolean => true)).assertFalse();
      expect(queue.size()).assertEqual(1);
      expect(queue.drainBeforeFocusChange(7, true, (_command: RemoteImeCommand): boolean => false)).assertFalse();
      expect(queue.size()).assertEqual(1);
      expect(queue.drainBeforeFocusChange(7, true, (_command: RemoteImeCommand): boolean => true)).assertTrue();
      expect(queue.size()).assertEqual(0);
    });
  });
}
