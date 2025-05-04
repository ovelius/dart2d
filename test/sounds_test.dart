import 'package:dart2d/res/sounds.dart';
import 'package:test/test.dart';
import 'lib/logging_helper.dart';
import 'lib/test_factories.dart';

void main() {

  late Sounds sounds;
  late FakeSoundFactory fakeSoundFactory;

  setUp(() {
    logOutputForTest();
    fakeSoundFactory = FakeSoundFactory();
    fakeSoundFactory.resetPlayedSounds();
    sounds = Sounds(fakeSoundFactory);
  });

  tearDown(() {
    assertNoLoggedWarnings();
  });

  test('preloadSounds_loadsAllSounds', () async {
    sounds.preloadSounds();
    await fakeSoundFactory.loadAllAudio();

    for (Sound s in Sound.values) {
      if (s != Sound.SILENCE) {
        expect(sounds.isLoaded(s), isTrue);
      }
    }
  });

  test('playOneSound_playsSameSound', () async {
    sounds.preloadSounds();
    await fakeSoundFactory.loadAllAudio();

    await sounds.playSound(Sound.BUZZ);
    await sounds.playSound(Sound.BUZZ);

    expect(fakeSoundFactory.getTotalPlayOuts(Sound.BUZZ), 2);
    expect(fakeSoundFactory.getCreatedAudioElements(Sound.BUZZ), 1);
  });


  test('playMultipleSounds_playsDifferentElement', () async {
    sounds.preloadSounds();
    await fakeSoundFactory.loadAllAudio();

    await sounds.playSound(Sound.BUZZ, multiPlay: true);
    await sounds.playSound(Sound.BUZZ, multiPlay: true);
    await sounds.playSound(Sound.BUZZ, multiPlay: true);

    expect(fakeSoundFactory.getTotalPlayOuts(Sound.BUZZ), 3);
    expect(fakeSoundFactory.getCreatedAudioElements(Sound.BUZZ), 3);
  });


  test('playUsingPlayId_canCancelPlay', () async {
    sounds.preloadSounds();
    await fakeSoundFactory.loadAllAudio();

    await sounds.playSound(Sound.BUZZ, playId: "test");
    expect(fakeSoundFactory.getAudioElements(Sound.BUZZ)![0].paused, isFalse);
    sounds.stopPlayId("test");

    // Got paused.
    expect(fakeSoundFactory.getAudioElements(Sound.BUZZ)![0].paused, isTrue);
  });
}