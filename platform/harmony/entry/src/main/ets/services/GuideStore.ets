/**
 * First-run onboarding state.
 *
 * The guide appears once automatically and afterwards only on demand from the
 * home page. Reads fail *closed*: if storage cannot be read we report "already
 * seen", because showing an explanation the user has dismissed is a worse
 * failure than never showing it again automatically — the home page keeps a
 * permanent entry either way.
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'guardianhub_guide';
const ONBOARDING_SEEN_KEY: string = 'onboarding_seen';

export class GuideStore {
  /** Whether the automatic first-run guide has already been shown. */
  static async hasSeenOnboarding(context: common.Context): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      return (await store.get(ONBOARDING_SEEN_KEY, false)) as boolean;
    } catch (_) {
      return true;
    }
  }

  /**
   * Record that the guide has been shown. Called when the page opens rather
   * than when it is finished, so a back gesture does not make it reappear on
   * every launch.
   */
  static async markOnboardingSeen(context: common.Context): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, STORE_NAME);
      await store.put(ONBOARDING_SEEN_KEY, true);
      await store.flush();
    } catch (_) {
      // Losing the flag only costs one extra showing.
    }
  }
}
