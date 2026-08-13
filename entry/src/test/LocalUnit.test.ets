import { describe, expect, it } from '@ohos/hypium';
import {
  appendSleepDigit,
  appendSleepMinuteShortcut,
  sleepDigitsToMillis,
  sleepDigitsToParts,
  sleepMillisToDigits,
} from '../main/ets/common/models/SleepTimerInputModels';
import {
  PlaybackHistoryEntry,
  prependPlaybackHistory,
  shouldRecordPlaybackHistory,
  shouldRecordPlaybackStart,
} from '../main/ets/common/models/PlaybackHistoryModels';
import { historyPreview } from '../main/ets/common/models/MoreHomeModels';
import { streamSubmissionMessage } from '../main/ets/common/models/StreamInputModels';

export default function localUnitTest() {
  describe('sleepTimerInputModels', () => {
    it('limitsNumericInputToFourDigits', 0, () => {
      expect(appendSleepDigit('123', '4')).assertEqual('1234');
      expect(appendSleepDigit('1234', '5')).assertEqual('1234');
      expect(appendSleepDigit('12', 'x')).assertEqual('12');
    });

    it('parsesHoursAndMinutes', 0, () => {
      const parts = sleepDigitsToParts('123');
      expect(parts.hours).assertEqual(1);
      expect(parts.minutes).assertEqual(23);
      expect(sleepDigitsToMillis('123')).assertEqual(4980000);
    });

    it('handlesMinuteShortcutsAndRoundTrips', 0, () => {
      expect(appendSleepMinuteShortcut('1', '30')).assertEqual('130');
      expect(appendSleepMinuteShortcut('1234', '30')).assertEqual('1234');
      expect(sleepMillisToDigits(5400000)).assertEqual('130');
      expect(sleepMillisToDigits(0)).assertEqual('');
    });
  });

  describe('playbackHistoryModels', () => {
    it('prependsAndDeduplicatesByUri', 0, () => {
      const oldA = new PlaybackHistoryEntry('a', 'old a', 10, '', 1);
      const oldB = new PlaybackHistoryEntry('b', 'b', 20, '', 2);
      const newA = new PlaybackHistoryEntry('a', 'new a', 30, '', 3);
      const result = prependPlaybackHistory([oldA, oldB], newA);
      expect(result.length).assertEqual(2);
      expect(result[0].title).assertEqual('new a');
      expect(result[1].uri).assertEqual('b');
    });

    it('honorsHistoryAndPlaybackStartGuards', 0, () => {
      expect(shouldRecordPlaybackHistory(false)).assertTrue();
      expect(shouldRecordPlaybackHistory(true)).assertFalse();
      expect(shouldRecordPlaybackStart('playing', '', 'media')).assertTrue();
      expect(shouldRecordPlaybackStart('paused', '', 'media')).assertFalse();
      expect(shouldRecordPlaybackStart('playing', 'media', 'media')).assertFalse();
    });
  });

  describe('homeAndStreamModels', () => {
    it('limitsHistoryPreview', 0, () => {
      expect(historyPreview([1, 2, 3, 4], 2)).assertDeepEquals([1, 2]);
    });

    it('validatesStreamSubmissionFeedback', 0, () => {
      expect(streamSubmissionMessage('   ')).assertEqual('');
      expect(streamSubmissionMessage('https://example.com/live')).assertEqual('暂不支持');
    });
  });
}
