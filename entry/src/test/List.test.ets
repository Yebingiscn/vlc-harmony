import localUnitTest from './LocalUnit.test';
import playerAdvancedOptionsTest from './PlayerAdvancedOptions.test';
import videoPlayerControlsTest from './VideoPlayerControls.test';

export default function testsuite() {
  localUnitTest();
  playerAdvancedOptionsTest();
  videoPlayerControlsTest();
}
