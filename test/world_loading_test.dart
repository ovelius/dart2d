library dart2d;

import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/worlds/player_world_selector.dart';
import 'package:dart2d/worlds/world_themes.dart';
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
    expectWarningContaining("Received offer from peer that has connection");
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
    FakeImageFactory imageFactoryD = getIt<ImageFactory>() as FakeImageFactory;

    await signalOpen(worldD, ["a", "b", "c"]);

    // Step through CONNECTING_TO_GAME -> LOADING_GAMESTATE (world image chunks).
    for (int i = 0; i < 15; i++) {
      worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldD.frameDraw(KEY_FRAME_DEFAULT / 5);
    }
    expect(loaderD.currentState(), equals(LoaderState.LOADING_GAMESTATE));
    // Must stay connected to commander even though GameState is now 4/4!
    expect(worldD.network().getServerConnection(), isNotNull);
    expect(worldD.network().getServerConnection()!.isClosedConnection(), isFalse);

    // Complete downloaded world image and step through bedrock + entering game.
    await imageFactoryD.completeAllImages();
    for (int i = 0; i < 30; i++) {
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

  test('Map selection tie-breaker within 1s: highest natural ID wins and rolls back loser + updates bystander', () async {
    expectWarningContaining("Duplicate handshake received");
    expectWarningContaining("Got client enter before loading completed");
    expectWarningContaining("Dropping old data");
    expectWarningContaining("Received offer from peer that has connection");

    // Create 3 lobby peers ('a' < 'b' < 'c') in WORLD_SELECT.
    WormWorld worldA = await createTestWorld("a",
        signalPeerOpen: true,
        setPlayer: true,
        setPlayerImage: true,
        selectMap: false,
        completeLoader: false,
        loadImages: true,
        initByteWorld: false);
    FakeImageFactory imageFactoryA = getIt<ImageFactory>() as FakeImageFactory;
    PlayerWorldSelector selectorA = worldA.loader.playerWorldSelector;

    WormWorld worldB = await createTestWorld("b",
        signalPeerOpen: false,
        setPlayer: true,
        setPlayerImage: true,
        selectMap: false,
        completeLoader: false,
        loadImages: true,
        initByteWorld: false);
    FakeImageFactory imageFactoryB = getIt<ImageFactory>() as FakeImageFactory;

    WormWorld worldC = await createTestWorld("c",
        signalPeerOpen: false,
        setPlayer: true,
        setPlayerImage: true,
        selectMap: false,
        completeLoader: false,
        loadImages: true,
        initByteWorld: false);
    FakeImageFactory imageFactoryC = getIt<ImageFactory>() as FakeImageFactory;
    PlayerWorldSelector selectorC = worldC.loader.playerWorldSelector;

    await signalOpen(worldB, ["a"]);
    await signalOpen(worldC, ["a", "b"]);

    for (int i = 0; i < 4; i++) {
      worldA.frameDraw(0.05);
      worldB.frameDraw(0.05);
      worldC.frameDraw(0.05);
    }
    expect(worldA.loader.currentState(), equals(LoaderState.WORLD_SELECT));
    expect(worldB.loader.currentState(), equals(LoaderState.WORLD_SELECT));
    expect(worldC.loader.currentState(), equals(LoaderState.WORLD_SELECT));

    // Buffer C's inbound packets briefly to simulate simultaneous map picks in
    // flight while 'a' selects Villa (index 0) and even finishes startAsServer()!
    for (TestConnection conn in testConnections['c'] ?? const <TestConnection>[]) {
      conn.buffer = true;
    }

    // Ensure 'a' picks index 0 (Villa) and 'c' picks index 5 (Lunar).
    selectorA.setSelectedMapIndexForTest(0);
    selectorC.setSelectedMapIndexForTest(5);

    // t = 0.0s: 'a' selects Villa! Bystander 'b' receives 'a's Villa selection first.
    selectorA.maybeSelectPlayerOrMap();
    final String mapChosenByA = selectorA.selectedWorldName!;
    expect(parseGeneratedMapName(mapChosenByA)!.theme.id, equals(WorldThemeId.villa));

    await imageFactoryA.completeAllImages();
    await imageFactoryB.completeAllImages();
    // Advance 0.35s (< 1.0s tie-break window!): 'a' even completes startAsServer()!
    for (int i = 0; i < 7; i++) {
      worldA.frameDraw(0.05);
      worldB.frameDraw(0.05);
      worldC.frameDraw(0.05);
    }
    expect(worldA.loaderCompleted(), isTrue);
    expect(worldA.isCommander, isTrue);

    // t = 0.35s (< 1.0s!): 'c' (higher natural ID: 'c' > 'a') selects Lunar!
    selectorC.maybeSelectPlayerOrMap();
    final String mapChosenByC = selectorC.selectedWorldName!;
    expect(parseGeneratedMapName(mapChosenByC)!.theme.id, equals(WorldThemeId.lunar));
    expect(mapChosenByC, isNot(equals(mapChosenByA)));

    // Flush packets so 'a's and 'c's selections cross on the wire!
    for (TestConnection conn in testConnections['c'] ?? const <TestConnection>[]) {
      conn.buffer = false;
      conn.flushBuffer();
    }

    await imageFactoryA.completeAllImages();
    await imageFactoryB.completeAllImages();
    await imageFactoryC.completeAllImages();

    for (int i = 0; i < 6; i++) {
      worldC.frameDraw(0.08);
      worldA.frameDraw(0.08);
      worldB.frameDraw(0.08);
      await imageFactoryA.completeAllImages();
      await imageFactoryB.completeAllImages();
      await imageFactoryC.completeAllImages();
    }

    for (int i = 0; i < 20; i++) {
      worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
    }

    // Highest natural ID 'c' won the tie-break; 'a' rolled back its server & Villa
    // map and joined 'c's Lunar game alongside bystander 'b'!
    expect(worldC.isCommander, isTrue);
    expect(worldA.isCommander, isFalse);
    expect(worldB.isCommander, isFalse);
    expect(worldA.loaderCompleted(), isTrue);
    expect(worldB.loaderCompleted(), isTrue);
    expect(worldC.loaderCompleted(), isTrue);

    for (WormWorld w in [worldA, worldB, worldC]) {
      expect(w.network().getGameState().gameStateProto.actingCommanderId, equals('c'));
      expect(w.network().getGameState().gameStateProto.mapName, equals(mapChosenByC));
      expect(w.gravity.y, equals(LUNAR_WORLD_GRAVITY));
      expect(w.network().getGameState().playerInfoList(), hasLength(3));
    }
  });

  test('Map selection tie-breaker does NOT rollback local map after 1 second window expires', () async {
    WormWorld worldA = await createTestWorld("a",
        signalPeerOpen: true,
        setPlayer: true,
        setPlayerImage: true,
        selectMap: false,
        completeLoader: false,
        loadImages: true,
        initByteWorld: false);
    FakeImageFactory imageFactoryA = getIt<ImageFactory>() as FakeImageFactory;
    PlayerWorldSelector selectorA = worldA.loader.playerWorldSelector;

    WormWorld worldZ = await createTestWorld("z",
        signalPeerOpen: false,
        setPlayer: true,
        setPlayerImage: true,
        selectMap: false,
        completeLoader: false,
        loadImages: true,
        initByteWorld: false);
    await signalOpen(worldZ, ["a"]);

    // Buffer 'a' -> 'z' so 'z' hasn't received 'a's pick yet.
    for (TestConnection conn in testConnections['z'] ?? const <TestConnection>[]) {
      conn.buffer = true;
    }

    selectorA.maybeSelectPlayerOrMap();
    final String mapChosenByA = selectorA.selectedWorldName!;
    await imageFactoryA.completeAllImages();

    // Advance 1.3 seconds (> 1.0s tie-break window) on worldA!
    for (int i = 0; i < 13; i++) {
      worldA.frameDraw(0.1);
    }
    expect(worldA.isCommander, isTrue);

    // Even if higher-ID 'z' sends commanderMapSelected after > 1.0s, 'a' keeps its map!
    final String lateRemoteMap = encodeGeneratedMapName(WorldThemeId.spooky, 4242);
    worldZ.network().peer.connections['a']!.sendSingleUpdate(
        StateUpdate()..commanderMapSelected = lateRemoteMap);

    expect(selectorA.selectedWorldName, equals(mapChosenByA));
    expect(worldA.network().getGameState().gameStateProto.mapName, equals(mapChosenByA));
    expect(worldA.isCommander, isTrue);
  });

  test('Commander change mid-join: graceful transferCommander during LOADING_GAMESTATE elects in-game peer and completes join', () async {
    expectWarningContaining("Duplicate handshake received");
    expectWarningContaining("Dropping old data");
    expectWarningContaining("Received offer from peer that has connection");
    expectWarningContaining("from unpinned peer");
    expectWarningContaining("Not parsing gamestate from");

    // Active game with Commander 'b' and in-game Client 'c'.
    // Joiner has ID 'a' ('a' < 'b' < 'c') to also verify a still-loading peer
    // with the lowest ID is NEVER prematurely elected commander over in-game 'c'!
    WormWorld worldB = await createTestWorld("b");
    worldB.startAsServer("nameB");
    WormWorld worldC = await createTestWorld("c");
    worldC.connectTo("b", "nameC");
    worldC.network().getServerConnection()!.sendClientEnter();

    for (int i = 0; i < 12; i++) {
      worldB.frameDraw(0.1);
      worldC.frameDraw(0.1);
    }
    expect(worldC.network().getGameState().playerInfoByConnectionId('c')!.inGame, isTrue);

    // Joiner 'a' starts staged Loader join.
    WormWorld worldA = await createTestWorld("a",
        signalPeerOpen: false,
        setPlayer: true,
        setPlayerImage: true,
        selectMap: false,
        completeLoader: false,
        loadImages: true,
        initByteWorld: false);
    FakeImageFactory imageFactoryA = getIt<ImageFactory>() as FakeImageFactory;

    await signalOpen(worldA, ["b", "c"]);
    for (int i = 0; i < 10; i++) {
      worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
    }
    expect(worldA.loader.currentState(), equals(LoaderState.LOADING_GAMESTATE));
    expect(worldA.loaderCompleted(), isFalse);

    // Commander 'b' transfers command right while 'a' is mid-LOADING_GAMESTATE!
    expect(worldB.network().transferCommander("tab backgrounded"), isTrue);
    // Must elect in-game 'c' (NOT still-loading 'a')!
    expect(worldB.network().pendingCommandTransfer(), equals('c'));
    expect(worldC.isCommander, isTrue);

    for (int i = 0; i < 12; i++) {
      worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
    }
    await imageFactoryA.completeAllImages();

    for (int i = 0; i < 25; i++) {
      worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
    }

    expect(worldA.loader.currentState(), equals(LoaderState.LOADING_AS_CLIENT_COMPLETED));
    expect(worldA.loaderCompleted(), isTrue);
    for (WormWorld w in [worldA, worldB, worldC]) {
      expect(w.network().getGameState().gameStateProto.actingCommanderId, equals('c'));
      expect(w.network().getGameState().playerInfoList(), hasLength(3));
      expect(w.spriteIndex[playerId(0)], isA<LocalPlayerSprite>());
      expect(w.spriteIndex[playerId(1)], isA<LocalPlayerSprite>());
      expect(w.spriteIndex[playerId(2)], isA<LocalPlayerSprite>());
    }
  });

  test('Commander change mid-join: abrupt commander crash during LOADING_ENTERING_GAME and unsynced handshake', () async {
    ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = false;
    expectWarningContaining("Duplicate handshake received");
    expectWarningContaining("Dropping old data");
    expectWarningContaining("Received offer from peer that has connection");

    // Case 1: Commander 'a' crashes right when joiner 'd' reaches LOADING_ENTERING_GAME.
    WormWorld worldA = await createTestWorld("a");
    worldA.startAsServer("nameA");
    WormWorld worldB = await createTestWorld("b");
    worldB.connectTo("a", "nameB");
    worldB.network().getServerConnection()!.sendClientEnter();

    for (int i = 0; i < 12; i++) {
      worldA.frameDraw(0.1);
      worldB.frameDraw(0.1);
    }

    WormWorld worldD = await createTestWorld("d",
        signalPeerOpen: false,
        setPlayer: true,
        setPlayerImage: true,
        selectMap: false,
        completeLoader: false,
        loadImages: true,
        initByteWorld: false);
    FakeImageFactory imageFactoryD = getIt<ImageFactory>() as FakeImageFactory;
    await signalOpen(worldD, ["a", "b"]);

    for (int i = 0; i < 12; i++) {
      worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldD.frameDraw(KEY_FRAME_DEFAULT / 5);
    }
    expect(worldD.loader.currentState(), equals(LoaderState.LOADING_GAMESTATE));

    // Buffer 'a's inbound packets so 'd' finishes computing ByteWorld and enters
    // LOADING_ENTERING_GAME (sending clientEnter to 'a') right as 'a' crashes!
    for (TestConnection conn in testConnections['a'] ?? const <TestConnection>[]) {
      conn.buffer = true;
    }
    await imageFactoryD.completeAllImages();
    for (int i = 0; i < 15; i++) {
      worldD.frameDraw(0.05);
    }
    expect(worldD.loader.currentState(), equals(LoaderState.LOADING_ENTERING_GAME));

    // Abruptly crash Commander 'a'!
    for (TestConnection conn in List.of(testConnections['a']!)) {
      conn.signalClose();
    }

    for (int i = 0; i < 20; i++) {
      worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldD.frameDraw(KEY_FRAME_DEFAULT / 5);
    }

    // 'b' became commander and 'd' re-sent clientEnter to 'b' and completed joining!
    expect(worldB.isCommander, isTrue);
    expect(worldD.loader.currentState(), equals(LoaderState.LOADING_AS_CLIENT_COMPLETED));
    expect(worldD.loaderCompleted(), isTrue);
    expect(worldB.network().getGameState().playerInfoList(), hasLength(2));
    expect(worldD.network().getGameState().playerInfoList(), hasLength(2));
    expect(worldB.network().getGameState().playerInfoByConnectionId('d')!.inGame, isTrue);

    // Case 2: Now 'e' starts joining 'b' (with 'd' in game), gets CommanderGameReply
    // from 'b' BEFORE 'b' syncs 'e' to 'd', and 'b' crashes abruptly!
    for (TestConnection conn in testConnections['d'] ?? const <TestConnection>[]) {
      if (conn.getOtherEnd()?.id == 'b') {
        conn.buffer = true;
      }
    }
    WormWorld worldE = await createTestWorld("e",
        signalPeerOpen: false,
        setPlayer: true,
        setPlayerImage: true,
        selectMap: false,
        completeLoader: false,
        loadImages: true,
        initByteWorld: false);
    FakeImageFactory imageFactoryE = getIt<ImageFactory>() as FakeImageFactory;
    await signalOpen(worldE, ["b"]);

    // Step until 'e' gets CommanderGameReply from 'b' (entering LOADING_GAMESTATE),
    // while 'd' still has NO idea 'e' exists!
    for (int i = 0; i < 8; i++) {
      worldB.frameDraw(0.05);
      worldE.frameDraw(0.05);
    }
    expect(worldE.loader.currentState(), equals(LoaderState.LOADING_GAMESTATE));
    expect(worldD.network().getGameState().isInGame('e'), isFalse);

    // Abruptly crash Commander 'b'!
    for (TestConnection conn in List.of(testConnections['b']!)) {
      conn.signalClose();
    }

    for (int i = 0; i < 15; i++) {
      worldD.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldE.frameDraw(KEY_FRAME_DEFAULT / 5);
    }
    await imageFactoryE.completeAllImages();
    for (int i = 0; i < 25; i++) {
      worldD.frameDraw(KEY_FRAME_DEFAULT / 5);
      worldE.frameDraw(KEY_FRAME_DEFAULT / 5);
    }

    // 'd' became commander, 'e' did NOT close 'd' as "multiple commander connections",
    // re-handshook with 'd', downloaded the world from 'd', and entered the game!
    expect(worldD.isCommander, isTrue);
    expect(worldE.loader.currentState(), equals(LoaderState.LOADING_AS_CLIENT_COMPLETED));
    expect(worldE.loaderCompleted(), isTrue);
    expect(worldD.network().getGameState().playerInfoList(), hasLength(2));
    expect(worldE.network().getGameState().playerInfoList(), hasLength(2));
    expect(worldD.network().getGameState().isInGame('e'), isTrue);
    expect(worldE.network().getGameState().gameStateProto.actingCommanderId, equals('d'));
  });
}