import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';

const DOMAIN = 0x4748;
const TAG = 'GuardianHub.Share';

export interface ShareIntent {
  uris: string[];
  utd: string;
  text: string;
}

type PickerRecord = Record<string, string | number>;
type PickerRecords = Record<string, PickerRecord[]>;

export const SHARE_INTENT_KEY = 'guardianhub.shareIntent';
const SHARE_INTENT_CHANGE_EVENT_ID = 'guardianhub.shareIntentChange';

export function parseShareIntent(want: Want): ShareIntent {
  const uris: string[] = [];
  const platformStream = want.parameters?.['ability.params.stream'];
  const stream = platformStream !== undefined ?
    platformStream : want.parameters?.['ability.want.params.stream'];
  if (typeof stream === 'string' && stream.length > 0) {
    uris.push(stream);
  } else if (Array.isArray(stream)) {
    (stream as Array<string>).forEach((uri: string) => {
      if (typeof uri === 'string' && uri.length > 0) {
        uris.push(uri);
      }
    });
  }
  if (uris.length === 0 && typeof want.uri === 'string' && want.uri.length > 0) {
    uris.push(want.uri);
  }

  let recordsUtd = '';
  let recordsText = '';
  const pickerRecordsValue = want.parameters?.['ability.picker.records'];
  if (pickerRecordsValue !== null && typeof pickerRecordsValue === 'object') {
    const pickerRecords = pickerRecordsValue as PickerRecords;
    const recordTypes = Object.keys(pickerRecords);
    if (recordTypes.length > 0) {
      recordsUtd = recordTypes[0];
      const records = pickerRecords[recordsUtd];
      if (Array.isArray(records) && records.length > 0) {
        const firstRecord = records[0];
        const sharedValue = firstRecord['5'] ?? firstRecord['2'];
        if (typeof sharedValue === 'string') {
          recordsText = sharedValue;
        }
      }
    }
  }

  let text = '';
  const pickerText = want.parameters?.['ability.picker.text'];
  if (typeof pickerText === 'string') {
    text = pickerText;
  } else if (typeof want.parameters?.['ability.want.params.text'] === 'string') {
    text = want.parameters?.['ability.want.params.text'] as string;
  } else if (recordsText.length > 0) {
    text = recordsText;
  }

  let utd = '';
  const utdValue = want.parameters?.['ability.want.params.utd'];
  if (typeof utdValue === 'string') {
    utd = utdValue;
  } else if (typeof want.parameters?.['std.utd'] === 'string') {
    utd = want.parameters?.['std.utd'] as string;
  } else if (typeof want.type === 'string' && want.type.length > 0) {
    utd = want.type;
  }
  if (utd.length === 0) {
    const mimeType = want.parameters?.['mime-type'];
    if (typeof mimeType === 'string') {
      utd = mimeType;
    }
  }
  if (utd.length === 0) {
    utd = recordsUtd;
  }

  return { uris, utd, text };
}

export default class ShareCheckAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate want: %{public}s', JSON.stringify(want));
    this.publishIntent(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onNewWant want: %{public}s', JSON.stringify(want));
    this.publishIntent(want);
    emitter.emit(SHARE_INTENT_CHANGE_EVENT_ID);
  }

  private publishIntent(want: Want): void {
    const intent = parseShareIntent(want);
    hilog.info(DOMAIN, TAG,
      'parsed share intent: uris=%{public}s utd=%{public}s text=%{public}s',
      JSON.stringify(intent.uris), intent.utd, intent.text.slice(0, 100));
    AppStorage.setOrCreate<ShareIntent>(SHARE_INTENT_KEY, intent);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/ShareCheckPage', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content: %{public}s', JSON.stringify(error));
      }
    });
  }
}
