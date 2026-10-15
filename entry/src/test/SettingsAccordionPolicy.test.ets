import { describe, it, expect } from '@ohos/hypium';
import {
  SETTINGS_SECTION_ABOUT,
  SETTINGS_SECTION_APPEARANCE,
  SETTINGS_SECTION_CONNECTION_LIVE,
  SETTINGS_SECTION_HOME,
  SETTINGS_SECTION_MOONLIGHT,
  SETTINGS_SECTION_NONE,
  SETTINGS_SECTION_RATING,
  SETTINGS_SECTION_TUTORIAL,
  SETTINGS_SECTION_VIRTUAL_KEYBOARD,
  SETTINGS_RDP_SWITCH_ROW_COUNT,
  SETTINGS_SECURITY_ACTION_ROW_COUNT,
  SETTINGS_VNC_ACTION_ROW_COUNT,
  SETTINGS_MOONLIGHT_ACTION_ROW_COUNT,
  SETTINGS_RATING_SUBTITLE,
  SETTINGS_APP_BUNDLE_NAME,
  SETTINGS_APPGALLERY_REVIEW_ACTION,
  SETTINGS_BROWSER_VIEW_ACTION,
  settingsSectionIsAction,
  settingsNextExpandedSection,
  settingsActionKind,
  settingsRatingUriCandidates,
  settingsRatingWantAction,
  settingsMoonlightExpandedMaxHeight,
  settingsRdpExpandedMaxHeight,
  settingsSecurityExpandedMaxHeight,
  settingsVncExpandedMaxHeight,
  SETTINGS_SECTION_VNC
} from '../main/ets/services/SettingsAccordionPolicy';

export default function settingsAccordionPolicyTest() {
  describe('SettingsAccordionPolicy', (): void => {
    it('settings_page_starts_with_all_accordion_sections_collapsed', 0, (): void => {
      expect(SETTINGS_SECTION_NONE).assertEqual('');
    });

    it('accordion_sections_expand_one_at_a_time_and_collapse_when_reselected', 0, (): void => {
      expect(settingsNextExpandedSection(SETTINGS_SECTION_NONE, SETTINGS_SECTION_APPEARANCE))
        .assertEqual(SETTINGS_SECTION_APPEARANCE);
      expect(settingsNextExpandedSection(SETTINGS_SECTION_APPEARANCE, SETTINGS_SECTION_HOME))
        .assertEqual(SETTINGS_SECTION_HOME);
      expect(settingsNextExpandedSection(SETTINGS_SECTION_HOME, SETTINGS_SECTION_CONNECTION_LIVE))
        .assertEqual(SETTINGS_SECTION_CONNECTION_LIVE);
      expect(settingsNextExpandedSection(SETTINGS_SECTION_CONNECTION_LIVE, SETTINGS_SECTION_TUTORIAL))
        .assertEqual(SETTINGS_SECTION_TUTORIAL);
      expect(settingsNextExpandedSection(SETTINGS_SECTION_TUTORIAL, SETTINGS_SECTION_VIRTUAL_KEYBOARD))
        .assertEqual(SETTINGS_SECTION_VIRTUAL_KEYBOARD);
      expect(settingsNextExpandedSection(SETTINGS_SECTION_CONNECTION_LIVE, SETTINGS_SECTION_CONNECTION_LIVE))
        .assertEqual('');
    });

    it('vnc_accordion_height_contains_every_action_row', 0, (): void => {
      expect(SETTINGS_VNC_ACTION_ROW_COUNT).assertEqual(11);
      expect(settingsVncExpandedMaxHeight()).assertEqual(760);
      expect(settingsVncExpandedMaxHeight(12) > settingsVncExpandedMaxHeight()).assertTrue();
    });

    it('moonlight_accordion_is_independent_and_contains_all_leaf_routes', 0, (): void => {
      expect(SETTINGS_SECTION_MOONLIGHT).assertEqual('moonlight');
      expect(SETTINGS_MOONLIGHT_ACTION_ROW_COUNT).assertEqual(7);
      expect(settingsMoonlightExpandedMaxHeight()).assertEqual(510);
      expect(settingsMoonlightExpandedMaxHeight(10) > settingsMoonlightExpandedMaxHeight()).assertTrue();
      expect(settingsNextExpandedSection(SETTINGS_SECTION_VNC, SETTINGS_SECTION_MOONLIGHT))
        .assertEqual(SETTINGS_SECTION_MOONLIGHT);
      expect(settingsNextExpandedSection(SETTINGS_SECTION_MOONLIGHT, SETTINGS_SECTION_MOONLIGHT))
        .assertEqual(SETTINGS_SECTION_NONE);
    });

    it('rdp_accordion_height_contains_stacked_phone_rows_and_bottom_spacing', 0, (): void => {
      expect(SETTINGS_RDP_SWITCH_ROW_COUNT).assertEqual(6);
      // Free: desktop-size chips plus four selector rows.
      expect(settingsRdpExpandedMaxHeight('sm')).assertEqual(1069);
      expect(settingsRdpExpandedMaxHeight('md')).assertEqual(957);
      expect(settingsRdpExpandedMaxHeight('lg')).assertEqual(957);
      expect(settingsRdpExpandedMaxHeight('xl')).assertEqual(1069);
      expect(settingsRdpExpandedMaxHeight('sm', 7) > settingsRdpExpandedMaxHeight('sm')).assertTrue();
      // 远端显示方案: one entry replaces the size chips and the remote-scale selector.
      expect(settingsRdpExpandedMaxHeight('sm', 6, true)).assertEqual(931);
      expect(settingsRdpExpandedMaxHeight('md', 6, true)).assertEqual(847);
    });

    it('security_accordion_height_tracks_the_secret_visibility_action_row', 0, (): void => {
      expect(SETTINGS_SECURITY_ACTION_ROW_COUNT).assertEqual(5);
      expect(settingsSecurityExpandedMaxHeight()).assertEqual(615);
      expect(settingsSecurityExpandedMaxHeight(6) > settingsSecurityExpandedMaxHeight()).assertTrue();
    });

    it('rating_is_a_direct_action_row_not_an_expandable_section', 0, (): void => {
      expect(settingsSectionIsAction(SETTINGS_SECTION_RATING)).assertTrue();
      expect(settingsSectionIsAction(SETTINGS_SECTION_TUTORIAL)).assertFalse();
      expect(settingsSectionIsAction(SETTINGS_SECTION_ABOUT)).assertFalse();
      expect(settingsNextExpandedSection(SETTINGS_SECTION_APPEARANCE, SETTINGS_SECTION_RATING))
        .assertEqual(SETTINGS_SECTION_APPEARANCE);
      expect(settingsActionKind(SETTINGS_SECTION_RATING)).assertEqual('rating');
    });

    it('app_bundle_name_matches_the_store_listing', 0, (): void => {
      expect(SETTINGS_APP_BUNDLE_NAME).assertEqual('com.example.remotedesktop');
    });

    it('rating_candidates_try_score_before_detail_with_current_bundle', 0, (): void => {
      const candidates: string[] = settingsRatingUriCandidates();
      expect(SETTINGS_RATING_SUBTITLE).assertEqual('前往应用市场为 RemoteDesktop 评分');
      expect(candidates.length >= 2).assertTrue();
      expect(candidates[0].indexOf('com.example.remotedesktop') >= 0).assertTrue();
      expect(candidates[1].indexOf('com.example.remotedesktop') >= 0).assertTrue();
      expect(candidates[0].indexOf('store://appgallery.huawei.com/app/detail') === 0).assertTrue();
      expect(candidates[0].indexOf('action=write-review') >= 0).assertTrue();
      expect(candidates[1].indexOf('comment') >= 0 || candidates[1].indexOf('score') >= 0 ||
        candidates[1].indexOf('rate') >= 0).assertTrue();
      expect(settingsRatingWantAction(candidates[0])).assertEqual(SETTINGS_APPGALLERY_REVIEW_ACTION);
      expect(settingsRatingWantAction(candidates[1])).assertEqual(SETTINGS_BROWSER_VIEW_ACTION);
    });
  });
}
