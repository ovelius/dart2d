library dart2d;

import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/worlds/player_world_selector.dart';
import 'package:test/test.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/net.dart';

void main() {
  setUpAll(() {
    configureDependencies();
  });
  setUp(() {
    ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = true;
    logOutputForTest();
    clearEnvironment();
    logConnectionData = false;
    Logger.root.level = Level.INFO;
  });

  void frameDraws(WormWorld w) {
    for (int i = 0; i < 10; i++) {
      w.frameDraw(KEY_FRAME_DEFAULT / 5);
    }
  }

  test('Test world staged loading', () async {
    WormWorld w = await createTestWorld("w", signalPeerOpen: false,
          setPlayer:false, setPlayerImage: false, selectMap: false, completeLoader:false, loadImages:
        false, initByteWorld: false);

    // Step through each phase of world loading.
    frameDraws(w);
    Loader loader = getIt<Loader>();

    // Set the name.
    expect(loader.currentState(), LoaderState.WAITING_FOR_NAME);
    setPlayerName("fake");
    frameDraws(w);

    // PeerId assigned.
    expect(loader.currentState(), LoaderState.WEB_RTC_INIT);
    signalOpen(w);
    frameDraws(w);

    // Load images.
    FakeImageFactory imageFactory = getIt<ImageFactory>() as FakeImageFactory;
    expect(loader.currentState(), LoaderState.LOADING_SERVER);
    imageFactory.completeAllImages();
    frameDraws(w);

    // Set player.
    expect(loader.currentState(), LoaderState.PLAYER_SELECT);
    KeyState localKeyState = w.localKeyState;
    // Key down selects it.
    localKeyState.onKeyDown(KeyCodeDart.ENTER);
    frameDraws(w);

    // Select playable sprite.
    expect(loader.currentState(), LoaderState.WORLD_SELECT);
    localKeyState.onKeyDown(KeyCodeDart.ENTER);
    frameDraws(w);

    // Key must go up before we can select again...
    localKeyState.onKeyUp(KeyCodeDart.ENTER);
    localKeyState.onKeyDown(KeyCodeDart.ENTER);
    frameDraws(w);
    expect(loader.currentState(), LoaderState.WORLD_LOADING);
    imageFactory.completeAllImages();
    frameDraws(w);

    // Doing the byteworld.
    expect(loader.currentState(), LoaderState.COMPUTING_BYTE_WORLD);

    while(loader.currentState() == LoaderState.COMPUTING_BYTE_WORLD) {
      w.frameDraw(0.1);
    }
    // Completed.
    expect(loader.currentState(), LoaderState.LOADED_AS_SERVER);
  });


}