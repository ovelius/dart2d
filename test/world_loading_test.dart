library dart2d;

import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/worlds/player_world_selector.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/net.dart';

import 'lib/test_mocks.mocks.dart';

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


  test('Buffers byteworld data while loading', () async {
    expectWarningContaining("Dropping old data");
    WormWorld w = await createTestWorld("w");
    w.startAsServer("w");
    // Step through each phase of world loading.
    frameDraws(w);

    WormWorld w2 = await createTestWorld("w2", signalPeerOpen: false,
        setPlayer:true, setPlayerImage: true, selectMap: false, completeLoader:false, loadImages:
        true, initByteWorld: false);
    Loader loader2 = getIt<Loader>();

    await signalOpen(w2, ["w"]);
    frameDraws(w2, 4);

    expect(loader2.currentState(), LoaderState.LOADING_GAMESTATE);

    // Thing happen while loading.
    w.explosionAt(location: Vec2(1, 1), damage: 0, radius: 2);
    w.fillRectAt(Vec2(2,2), Vec2(1,2), "#00FF00");

    // It got buffered in the loader.
    expect(w2.loader.bufferDestruction, hasLength(1));
    expect(w2.loader.bufferDraws, hasLength(1));
  });

  test('E2E_FourthPlayerCompletesFullLoaderJoinWithoutFullGameDisconnect', () async {
    expectWarningContaining("Duplicate handshake received");
    expectWarningContaining("Dropping old data");
    // NOTE: We intentionally do NOT expect "Commander data update for missing"
    // so this test also verifies that warning is silenced while loading!

    WormWorld worldA = await createTestWorld("a");
    worldA.startAsServer("nameA");
    WormWorld worldB = await createTestWorld("b");
    WormWorld worldC = await createTestWorld("c");

    worldB.connectTo("a", "nameB");
    worldC.connectTo("a", "nameC");

    for (int i = 0; i < 8; i++) {
      worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
    }

    // 4th player goes through the real staged Loader (including autoConnectToPeers
    // to a, b, and c and multi-frame map/bedrock loading after joining 4/4 GameState).
    WormWorld worldD = await createTestWorld("d",
        signalPeerOpen: false,
        setPlayer: true,
        setPlayerImage: true,
        selectMap: false,
        completeLoader: false,
        loadImages: true,
        initByteWorld: false);
    Loader loaderD = worldD.loader;

    await signalOpen(worldD, ["a", "b", "c"]);

    // Step all 4 worlds through loading + bedrock computation + entering game.
    for (int i = 0; i < 40; i++) {
      worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldD.frameDraw(KEY_FRAME_DEFAULT / 5);
    }

    // 4th player must NOT have closed its commander connection as "Full game connection!".
    expect(loaderD.currentState(), equals(LoaderState.LOADING_AS_CLIENT_COMPLETED));
    expect(worldD.network().getServerConnection(), isNotNull);
    expect(worldD.network().getServerConnection()!.isClosedConnection(), isFalse);
    expect(worldA.network().gameState.playerInfoList(), hasLength(4));
    expect(worldD.network().gameState.playerInfoList(), hasLength(4));

    // Early auto-connections from d to b and c must be promoted to valid game connections.
    expect(worldD.network().peer.connections['b']?.isValidGameConnection(), isTrue);
    expect(worldD.network().peer.connections['c']?.isValidGameConnection(), isTrue);

    // Every world (commander and all 3 non-commanders) must have all 4 player sprites.
    for (WormWorld w in [worldA, worldB, worldC, worldD]) {
      expect(w.spriteIndex[playerId(0)], isA<LocalPlayerSprite>(),
          reason: "World ${w.network().peer.id} missing player 0 sprite");
      expect(w.spriteIndex[playerId(1)], isA<LocalPlayerSprite>(),
          reason: "World ${w.network().peer.id} missing player 1 sprite");
      expect(w.spriteIndex[playerId(2)], isA<LocalPlayerSprite>(),
          reason: "World ${w.network().peer.id} missing player 2 sprite");
      expect(w.spriteIndex[playerId(3)], isA<LocalPlayerSprite>(),
          reason: "World ${w.network().peer.id} missing player 3 sprite");
    }
  });
}