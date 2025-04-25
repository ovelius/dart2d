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

  void frameDraws(WormWorld w,[int count = 10]) {
    for (int i = 0; i < count; i++) {
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
    await signalOpen(w);
    frameDraws(w);

    // Load images.
    FakeImageFactory imageFactory = getIt<ImageFactory>() as FakeImageFactory;
    expect(loader.currentState(), LoaderState.LOADING_SERVER);
    await imageFactory.completeAllImages();
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
    await imageFactory.completeAllImages();
    frameDraws(w);

    while(loader.currentState() == LoaderState.COMPUTING_BYTE_WORLD) {
      w.frameDraw(0.1);
    }
    // Completed.
    expect(loader.currentState(), LoaderState.LOADED_AS_SERVER);
  });

  test('Test worlds loads together', () async {
    expectWarningContaining("Duplicate handshake received");
    expectWarningContaining("Got client enter before loading completed");
    expectWarningContaining("Commander data update for missing");
    expectWarningContaining("Dropping old data");

    WormWorld w = await createTestWorld("w", signalPeerOpen: true,
        setPlayer:true, setPlayerImage: true, selectMap: false, completeLoader:false, loadImages:
        true, initByteWorld: false);
    FakeImageFactory imageFactory1 = getIt<ImageFactory>() as FakeImageFactory;

    // Step through each phase of world loading.
    frameDraws(w);
    Loader loader = getIt<Loader>();

    // Set the name.
    expect(loader.currentState(), LoaderState.WORLD_SELECT);


    WormWorld w2 = await createTestWorld("w2", signalPeerOpen: false,
        setPlayer:true, setPlayerImage: true, selectMap: false, completeLoader:false, loadImages:
        true, initByteWorld: false);
    Loader loader2 = getIt<Loader>();
    FakeImageFactory imageFactory2 = getIt<ImageFactory>() as FakeImageFactory;

    await signalOpen(w2, ["w"]);
    frameDraws(w2);

    expect(loader2.currentState(), LoaderState.WORLD_SELECT);

    w.localKeyState.onKeyDown(KeyCodeDart.ENTER);
    frameDraws(w, 2);
    frameDraws(w2, 2);
    expect(loader.currentState(), LoaderState.WORLD_LOADING);
    expect(loader2.currentState(), LoaderState.WORLD_LOADING);

    // GameState recognized.
    expect(w2.network().getServerConnection(), isNotNull);

    // Complete all images.
    await imageFactory1.completeAllImages();
    await imageFactory2.completeAllImages();

    frameDraws(w);
    expect(loader.currentState(), LoaderState.LOADED_AS_SERVER);

    // A bit more back and forth.
    for (int i = 0; i < 10; i++) {
      w.frameDraw(KEY_FRAME_DEFAULT / 5);
      w2.frameDraw(KEY_FRAME_DEFAULT / 5);
    }

    expect(loader2.currentState(), LoaderState.LOADING_AS_CLIENT_COMPLETED);
  });


}