library dart2d;

import 'dart:math';

import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/weapons/weapon_state.dart';
import 'package:test/test.dart';
import 'lib/test_factories.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/world_util.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/util/util.dart';
import 'package:web/web.dart';

void main() {
  setUpAll((){
    configureDependencies();
    ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = true;
    // TODO make this true.
    throwIfLoggingUnexpected = false;
    logConnectionData = true;
  });
  setUp(() {
    logOutputForTest();
    clearEnvironment();
    logConnectionData = false;
    Logger.root.level = Level.INFO;
  });

  group('World 2 world network tests', () {
    test('TestBasicSmokeConnection', () async {
      WormWorld worldA = await createTestWorld("c");
      WormWorld worldB = await createTestWorld("b");
      expect(worldA.network().getPeer().connectedToServer(), isTrue);
      expect(worldB.network().getPeer().connectedToServer(), isTrue);

      // A framedraw will start worldB as server.
      worldB.startAsServer("nameB");
      worldB.frameDraw();
      expect(worldB, hasSpriteWithNetworkId(playerId(0)));
      // Locally controlled player.
      expect(
          worldB,
          controlsMatching(playerId(0))
              .withActiveMethod(PlayerControlMethods.FIRE_KEY)
              .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
              .withActiveMethod(PlayerControlMethods.RESPAWN)
              .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
              .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      worldA.connectTo("b", "nameC", true);
      // A framedraw twill start worldA as client.
      worldA.frameDraw();
      // Make worldB add the player to the world.
      worldB.frameDraw(0.1);

      // Simulate a keyframe from A and verify that it is received.
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(recentReceviedDataFrom("c").keyFrame, 1);

      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(recentReceviedDataFrom("b").keyFrame, 1);

      // Run frames again to make sure sprites are added to world.
      worldA.frameDraw(0.01);
      worldB.frameDraw(0.01);

      expect(worldA, hasSpriteWithNetworkId(playerId(0)));
      expect(worldA, hasSpriteWithNetworkId(playerId(1)));
      expect(worldB, hasSpriteWithNetworkId(playerId(0)));
      expect(worldB, hasSpriteWithNetworkId(playerId(1)));

      // Assert server control.
      expect(
          worldB,
          controlsMatching(playerId(0))
              .withActiveMethod(PlayerControlMethods.FIRE_KEY)
              .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
              .withActiveMethod(PlayerControlMethods.RESPAWN)
              .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
              .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      // Comander takes control of weapon change and fire of weapon, and respawn
      expect(
          worldB,
          controlsMatching(playerId(1))
              .withActiveMethod(PlayerControlMethods.FIRE_KEY)
              .withActiveMethod(PlayerControlMethods.RESPAWN)
              .withActiveMethod(PlayerControlMethods.SERVER_TO_OWNER_DATA)
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      // Assert client control.
      expect(
          worldA,
          controlsMatching(playerId(1))
              .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
              // Client also switches weapon.
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH)
              .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
              .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR));
      // Client has no active methods for server.
      // But listens for weapon switch in case of command transfer.
      expect(
          worldA,
          controlsMatching(playerId(0))
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      // Both worlds are in the same gamestate.
      expect(worldB.network().gameState,
          isGameStateOf({playerId(0): "nameB", playerId(1): "nameC"})
            .withCommanderId('b'));
      expect(worldA.network().gameState,
          isGameStateOf({playerId(0): "nameB", playerId(1): "nameC"})
              .withCommanderId('b'));
    });

    test('Connection dies becomes two commanders', () async {
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      expect(worldA.network().getPeer().connectedToServer(), isTrue);
      expect(worldB.network().getPeer().connectedToServer(), isTrue);

      // A framedraw will start worldB as server.
      worldA.startAsServer("nameA");
      worldA.frameDraw();
      worldB.connectTo("a", "nameB", true);

      for (int i = 0; i < 10; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 3);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 3);
      }

      expect(
          worldA,
          hasExactSprites([
            hasSpriteWithNetworkId(playerId(0))
                .andNetworkType(NetworkType.LOCAL),
            hasSpriteWithNetworkId(playerId(1))
                .andNetworkType(NetworkType.REMOTE_FORWARD)
                .andOwnerId("b"),
          ]));

      expect(
          worldB,
          hasExactSprites([
            hasSpriteWithNetworkId(playerId(0))
                .andNetworkType(NetworkType.REMOTE)
                .andOwnerId("a"),
            hasSpriteWithNetworkId(playerId(1))
                .andNetworkType(NetworkType.LOCAL),
          ]));

      // Assert server control.
      expect(
          worldA,
          controlsMatching(playerId(0))
              .withActiveControlMethods([PlayerControlMethods.FIRE_KEY, PlayerControlMethods.CONTROL_KEYS,
          PlayerControlMethods.RESPAWN, PlayerControlMethods.DRAW_HEALTH_BAR, PlayerControlMethods.DRAW_WEAPON_HELPER,
          PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH]));
      // Commander takes control of weapon change and fire of weapon, and respawn
      expect(
          worldA,
          controlsMatching(playerId(1))
              .withActiveControlMethods([PlayerControlMethods.FIRE_KEY,
            PlayerControlMethods.RESPAWN, PlayerControlMethods.SERVER_TO_OWNER_DATA,PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH]
          ));

      // Assert client control.
      expect(
          worldB,
          controlsMatching(playerId(1))
              .withActiveControlMethods([PlayerControlMethods.CONTROL_KEYS,
          // Client also switches weapon.
              PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH,
              PlayerControlMethods.DRAW_WEAPON_HELPER,
              PlayerControlMethods.DRAW_HEALTH_BAR]));
      // Client has no active methods for server.
      // But listens for weapon switch in case of command transfer.
      expect(
          worldB,
          controlsMatching(playerId(0))
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      // Both worlds are in the same gamestate.
      expect(worldB.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"})
              .withCommanderId('a'));
      expect(worldA.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"})
              .withCommanderId('a'));

      // Kill connections.
      testConnections['a']!.forEach((e) {
        e.signalClose();
      });

      for (int i = 0; i < 10; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 3);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 3);
      }

      expect(worldA.network().gameState,
          isGameStateOf({playerId(0): "nameA"})
              .withCommanderId('a'));
      expect(worldB.network().gameState,
          isGameStateOf({playerId(1): "nameB"})
              .withCommanderId('b'));


      expect(
          worldA,
          hasExactSprites([
            hasSpriteWithNetworkId(playerId(0))
                .andNetworkType(NetworkType.LOCAL),
          ]));

      expect(
          worldB,
          hasExactSprites([
            hasSpriteWithNetworkId(playerId(1))
                .andNetworkType(NetworkType.LOCAL),
          ]));
      expect(
          worldA,
          controlsMatching(playerId(0))
              .withActiveControlMethods([PlayerControlMethods.FIRE_KEY, PlayerControlMethods.CONTROL_KEYS,
            PlayerControlMethods.RESPAWN, PlayerControlMethods.DRAW_HEALTH_BAR, PlayerControlMethods.DRAW_WEAPON_HELPER,
            PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH]));
      expect(
          worldB,
          controlsMatching(playerId(1))
              .withActiveControlMethods([PlayerControlMethods.FIRE_KEY, PlayerControlMethods.CONTROL_KEYS,
            PlayerControlMethods.RESPAWN, PlayerControlMethods.DRAW_HEALTH_BAR, PlayerControlMethods.DRAW_WEAPON_HELPER,
            PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH]));
    });


    test('TestThreeWorlds', () async {
      print("Testing connecting with three players");
      WormWorld worldA = await createTestWorld("a");
      worldA.startAsServer("nameA");
      worldA.frameDraw();

      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");

      // b connects to a.
      worldB.connectTo("a", "nameB");
      worldA.frameDraw(0.1);
      expect(
          worldA,
          hasSpriteWithNetworkId(playerId(0))
              .andNetworkType(NetworkType.LOCAL));
      expect(
          worldA,
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.REMOTE_FORWARD));
      expect(
          worldA, isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"})
              .withCommanderId('a'));
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      // After worldAs keyframe worldB has the entire state of the game.
      worldB.frameDraw(0.1);
      expect(
          worldB,
          hasSpriteWithNetworkId(playerId(0))
              .andNetworkType(NetworkType.REMOTE));
      expect(
          worldB,
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.LOCAL));
      expect(
          worldB, isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"})
            .withCommanderId("a"));

      // now c connects to a.
      worldC.connectTo("a", "nameC");
      // run a frame in a to make sure the sprite is processed.
      worldA.frameDraw(0.1);
      worldA.frameDraw(0.1);
      expect(
          worldA,
          hasSpriteWithNetworkId(playerId(0))
              .andNetworkType(NetworkType.LOCAL));
      expect(
          worldA,
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.REMOTE_FORWARD));
      expect(
          worldA,
          hasSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.REMOTE_FORWARD));
      expect(
          worldA,
          isGameStateOf({
            playerId(0): "nameA",
            playerId(1): "nameB",
            playerId(2): "nameC"
          }).withCommanderId("a"));
      // Now C runs a keyframe. This will make a forward the local player sprite in c to b.
      logConnectionData = true;
      worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldC.frameDraw(0.1);
      worldB.frameDraw(0.1);
      expect(
          worldB,
          hasSpriteWithNetworkId(playerId(0))
              .andNetworkType(NetworkType.REMOTE));
      expect(
          worldB,
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.LOCAL));
      expect(
          worldB,
          hasSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.REMOTE));
      // Make server a run a keyframe to ensure gamestate if propagated.
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(
          worldB,
          isGameStateOf({
            playerId(0): "nameA",
            playerId(1): "nameB",
            playerId(2): "nameC"
          }).withCommanderId("a"));
      // This also sets up CLIENT_TO_CLIENT connections.
      expect(
          worldB, hasSpecifiedConnections(['c', 'a']).isValidGameConnections());
      expect(
          worldC, hasSpecifiedConnections(['b', 'a']).isValidGameConnections());
      // And of course the server to client connections from A.
      expect(
          worldA, hasSpecifiedConnections(['b', 'c']).isValidGameConnections());
      // Make sure a doesn't deliver things in sync to c from b.
      // Run a keyframe in B.
      // TODO(Erik): Make c be smart enough to determine the real source of the sprite.
      // c should disregard the sprite from a since a direct connection exists to b.
      testConnections["a"]![0].buffer = true;
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldC.frameDraw(
          0.1); // This adds the sprite from the client to client connection.
      expect(
          worldC,
          hasSpriteWithNetworkId(playerId(0))
              .andNetworkType(NetworkType.REMOTE));
      expect(
          worldC,
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.REMOTE));
      expect(
          worldC,
          hasSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.LOCAL));

      testConnections["a"]![0].buffer = false;
      testConnections["a"]![0].flushBuffer();

      worldA.frameDraw(0.01);
      worldB.frameDraw(0.01);
      worldC.frameDraw(0.01);

      // Final GameState should be consitent.
      expect(
          worldA,
          isGameStateOf({
            playerId(0): "nameA",
            playerId(1): "nameB",
            playerId(2): "nameC"
          }).withCommanderId('a'));
      expect(
          worldB,
          isGameStateOf({
            playerId(0): "nameA",
            playerId(1): "nameB",
            playerId(2): "nameC"
          }).withCommanderId('a'));
      expect(
          worldC,
          isGameStateOf({
            playerId(0): "nameA",
            playerId(1): "nameB",
            playerId(2): "nameC"
          }).withCommanderId('a'));

      // Assert sprite control.
      expect(
          worldA,
          controlsMatching(playerId(0))
              .withActiveMethod(PlayerControlMethods.FIRE_KEY)
              .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
              .withActiveMethod(PlayerControlMethods.RESPAWN)
              .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
              .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      expect(
          worldA,
          controlsMatching(playerId(1))
              .withActiveMethod(PlayerControlMethods.RESPAWN)
              .withActiveMethod(PlayerControlMethods.FIRE_KEY)
              .withActiveMethod(PlayerControlMethods.SERVER_TO_OWNER_DATA)
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      expect(
          worldA,
          controlsMatching(playerId(2))
              .withActiveMethod(PlayerControlMethods.RESPAWN)
              .withActiveMethod(PlayerControlMethods.FIRE_KEY)
              .withActiveMethod(PlayerControlMethods.SERVER_TO_OWNER_DATA)
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      expect(
          worldB,
          controlsMatching(playerId(0))
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      expect(
          worldB,
          controlsMatching(playerId(1))
              .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
              .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
              .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      expect(
          worldB,
          controlsMatching(playerId(2))
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      expect(
          worldC,
          controlsMatching(playerId(0))
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      expect(
          worldC,
          controlsMatching(playerId(1))
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
      expect(
          worldC,
          controlsMatching(playerId(2))
              .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
              .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
              .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
    });

    test('TestThreeWorlds connectsOverCommanderConnection', () async {
      print("Testing connecting with three players");
      WormWorld worldA = await createTestWorld("a");
      worldA.startAsServer("nameA");
      worldA.frameDraw();

      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");

      // b connects to a.
      worldC.connectTo("a", "nameC");

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      // Disconnect signaling channel of C.
      worldC.network().peer.disconnect();

      /// World B connects.
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }
      // This also sets up CLIENT_TO_CLIENT connections.
      expect(
          worldB, hasSpecifiedConnections(['c', 'a']).isValidGameConnections());
      expect(
          worldC, hasSpecifiedConnections(['b', 'a']).isValidGameConnections());
      // We could create a client to client connection even with signaling
      // server disconnected.
      expect(
          worldA, hasSpecifiedConnections(['b', 'c']).isValidGameConnections());

      worldA.frameDraw(0.01);
      worldB.frameDraw(0.01);
      worldC.frameDraw(0.01);

      // Final GameState should be consitent.
      expect(
          worldA,
          isGameStateOf({
            playerId(0): "nameA",
            playerId(1): "nameC",
            playerId(2): "nameB"
          }).withCommanderId('a'));
      expect(
          worldB,
          isGameStateOf({
            playerId(0): "nameA",
            playerId(1): "nameC",
            playerId(2): "nameB"
          }).withCommanderId('a'));
      expect(
          worldC,
          isGameStateOf({
            playerId(0): "nameA",
            playerId(1): "nameC",
            playerId(2): "nameB"
          }).withCommanderId('a'));

    });

    test('FourWorldsCommanderDies elects new commander', () async {
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");
      worldA.startAsServer("nameA");

      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");
      WormWorld worldD = await createTestWorld("d");

      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");
      worldD.connectTo("a", "nameD");


      for (int i = 0; i < 20; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldD.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      expect(
          worldA,
          controlsMatching(playerId(0))
              .withActiveMethod(PlayerControlMethods.FIRE_KEY)
              .withActiveMethod(PlayerControlMethods.RESPAWN)
              .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
              .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
              .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      expect(worldA,
          hasSpecifiedConnections(['b', 'c', 'd']).isValidGameConnections());
      expect(worldB,
          hasSpecifiedConnections(['a', 'c', 'd']).isValidGameConnections());
      expect(worldC,
          hasSpecifiedConnections(['a', 'b', 'd']).isValidGameConnections());
      expect(worldD,
          hasSpecifiedConnections(['a', 'b', 'c']).isValidGameConnections());

      expect(worldA.spriteIndex.count(), equals(4));
      expect(worldB.spriteIndex.count(), equals(4));
      expect(worldC.spriteIndex.count(), equals(4));
      expect(worldD.spriteIndex.count(), equals(4));

      Map<int, String>  gameState = {
        playerId(0): "nameA",
        playerId(1): "nameB",
        playerId(2): "nameC",
        playerId(3): "nameD"
      };
      expect(worldA, isGameStateOf(gameState).withCommanderId('a'));
      expect(worldB, isGameStateOf(gameState).withCommanderId('a'));
      expect(worldC, isGameStateOf(gameState).withCommanderId('a'));
      expect(worldD, isGameStateOf(gameState).withCommanderId('a'));
      expect(worldD.spriteIndex.count(), equals(4));

      // All worlds should be disconnected from the server.
      expect(worldA, isConnectedToServer(false));
      expect(worldB, isConnectedToServer(false));
      expect(worldC, isConnectedToServer(false));
      expect(worldD, isConnectedToServer(false));

      // Now make a drop away.
      testConnections['a']!.forEach((e) {
        e.signalClose();
      });


      for (int i = 0; i < 20; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldD.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      expect(
          worldB,
          controlsMatching(playerId(1))
              .withActiveMethod(PlayerControlMethods.FIRE_KEY)
              .withActiveMethod(PlayerControlMethods.RESPAWN)
              .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
              .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
              .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      gameState.remove(playerId(0));
      expect(worldB, isGameStateOf(gameState).withCommanderId('b'));
      expect(worldC, isGameStateOf(gameState).withCommanderId('b'));
      expect(worldD, isGameStateOf(gameState).withCommanderId('b'));
      expect(worldB.spriteIndex.count(), equals(3));
      expect(worldC.spriteIndex.count(), equals(3));
      expect(worldD.spriteIndex.count(), equals(3));

      // All worlds should be connected to server again.
      expect(worldB, isConnectedToServer(true));
      expect(worldC, isConnectedToServer(true));
      expect(worldD, isConnectedToServer(true));

      // TODO bring back!
      // expect(worldB.spriteIndex[playerId(1)].frames,
      // equals(PLAYER_TWO_SPRITE_FRAMES));
      // TODO: Check type of playerId(1).

      // Now b is having issues.
      testConnections['b']!.forEach((e) {
        e..signalClose();
      });
      for (int i = 0; i < 18; i++) {
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldD.frameDraw(KEY_FRAME_DEFAULT / 5);
      }
      expect(worldC.spriteIndex.count(), equals(2));
      expect(worldD.spriteIndex.count(), equals(2));

      gameState.remove(playerId(1));
      expect(worldC, isGameStateOf(gameState).withCommanderId('c'));
      expect(worldD, isGameStateOf(gameState).withCommanderId('c'));

      expect(
          worldC,
          controlsMatching(playerId(2))
              .withActiveMethod(PlayerControlMethods.FIRE_KEY)
              .withActiveMethod(PlayerControlMethods.RESPAWN)
              .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
              .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
              .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));

      // Finally C is having issues.
      testConnections['c']!.forEach((e) {
        e.signalClose();
      });
      for (int i = 0; i < 18; i++) {
        worldD.frameDraw(KEY_FRAME_DEFAULT / 5 );
      }
      // WorldD is all alone.
      expect(worldD, hasSpecifiedConnections([]));
      expect(worldD.spriteIndex.count(), equals(1));

      gameState.remove(playerId(2));
      expect(worldD, isGameStateOf(gameState).withCommanderId('d'));

      expect(
          worldD,
          controlsMatching(playerId(3))
              .withActiveMethod(PlayerControlMethods.FIRE_KEY)
              .withActiveMethod(PlayerControlMethods.RESPAWN)
              .withActiveMethod(PlayerControlMethods.CONTROL_KEYS)
              .withActiveMethod(PlayerControlMethods.DRAW_HEALTH_BAR)
              .withActiveMethod(PlayerControlMethods.DRAW_WEAPON_HELPER)
              .withActiveMethod(PlayerControlMethods.LISTEN_FOR_WEAPON_SWITCH));
    });

    test('TestBadCommanderConnection', () async {
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      worldB.startAsServer("nameB");
      worldB.frameDraw();
      worldA.connectTo("b", "nameA");
      expect(
          worldB.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('b'));

      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);

      for (int i = 0; i < 13; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5 + 0.01);
      }

      // B hasn't responded in a long time.
      expect(worldA.network().hasNetworkProblem(), equals(true));

      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);

      // B now responded and we're back.
      expect(worldA.network().hasNetworkProblem(), equals(false));

      expect(
          worldB.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('b'));
      expect(worldB.spriteIndex.count(), equals(2));

      // Now B is having framerate issues.
      worldB.drawFps().setFpsForTest(2.1);

      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      expect(worldB.network().slowCommandingFrames(), equals(2));

      while (worldB.network().slowCommandingFrames() > 0) {
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }

      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);

      // Commander is now a.
      expect(
          worldB.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('a'));
      expect(
          worldB,
          hasExactSprites([
            hasSpriteWithNetworkId(playerId(0))
                .andNetworkType(NetworkType.LOCAL),
            hasSpriteWithNetworkId(playerId(1))
                .andNetworkType(NetworkType.REMOTE)
                .andOwnerId("a"),
          ]));
      expect(
          worldA.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('a'));
      expect(
          worldA,
          hasExactSprites([
            hasSpriteWithNetworkId(playerId(0))
                .andNetworkType(NetworkType.REMOTE_FORWARD)
                  .andOwnerId('b'),
            hasSpriteWithNetworkId(playerId(1))
                .andNetworkType(NetworkType.LOCAL),
          ]));

      // Because worldB is only doing 2 Fps!
      expect(worldB.network().getGameState().playerInfoByConnectionId('b')!.fps,
          lessThan(2.2));
      expect(worldA.network().getGameState().playerInfoByConnectionId('b')!.fps,
          lessThan(2.2));

      worldB.drawFps().setFpsForTest(25.0);
      worldA.drawFps().setFpsForTest(25.1);

      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT /5);
        worldB.frameDraw(KEY_FRAME_DEFAULT /5);
      }

      // Commander is still a.
      expect(
          worldB.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('a'));
      expect(
          worldA.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('a'));

      // And the FPS increased.
      expect(worldB.network().getGameState().playerInfoByConnectionId('b')!.fps,
          equals(25));
      expect(worldA.network().getGameState().playerInfoByConnectionId('b')!.fps,
          equals(25));

      // But now a is having trouble.
      worldA.drawFps().setFpsForTest(3.1);

      // Pas some time.
      for (int i = 0; i < 12; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01, true);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01, true);
      }

      // Commander is now b.
      expect(
          worldB.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('b'));
      expect(
          worldA.network().gameState,
          isGameStateOf({playerId(1): "nameA", playerId(0): "nameB"})
              .withCommanderId('b'));
    });

    test('CommanderForwardsSpriteData', () async  {
      ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = false;
      WormWorld worldA = await createTestWorld("client1");
      WormWorld worldB = await createTestWorld("commander");
      WormWorld worldC = await createTestWorld("client2");

      TestConnectionFactory connectionFactory = getIt<ConnectionFactory>() as TestConnectionFactory;
      worldB.startAsServer("nameB");
      worldB.frameDraw();
      connectionFactory
          .failConnection('client1', 'client2')
          .failConnection('client2', 'client1');

      worldA.connectTo('commander');
      worldA.network().getServerConnection()!.sendClientEnter();
      worldC.connectTo('commander');
      worldC.network().getServerConnection()!.sendClientEnter();

      for (int i = 0; i < 8; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT /5);
        worldB.frameDraw(KEY_FRAME_DEFAULT/5);
        worldC.frameDraw(KEY_FRAME_DEFAULT/5);
      }

      expect(
          worldB,
          hasExactSprites([
            hasSpriteWithNetworkId(playerId(0))
                .andNetworkType(NetworkType.LOCAL),
            hasSpriteWithNetworkId(playerId(1))
                .andNetworkType(NetworkType.REMOTE_FORWARD),
            hasSpriteWithNetworkId(playerId(2))
                .andNetworkType(NetworkType.REMOTE_FORWARD),
          ]));

      LocalPlayerSprite spriteA = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(spriteA.networkType, NetworkType.LOCAL);
      spriteA.position.x = 33.0;
      spriteA.velocity = Vec2();

      LocalPlayerSprite spriteA2 = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(spriteA2.position.x, 33.0);

      LocalPlayerSprite spriteC = worldC.spriteIndex[playerId(1)] as LocalPlayerSprite;
      logConnectionData = true;
      for (int i = 0; i < 2; i++) {
        print("${spriteA.networkId} -${spriteA.networkType} - ${spriteA.position} - ${spriteA.velocity}");
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      expect(worldB,
          hasSpecifiedConnections(['client1', 'client2'])
              .isValidGameConnections());
      expect(worldA.network().safeActiveConnections().containsKey("client1"), isFalse);
      expect(worldA.network().safeActiveConnections().containsKey("client2"), isFalse);
      expect(worldC.network().safeActiveConnections().containsKey("client1"), isFalse);
      expect(worldC.network().safeActiveConnections().containsKey("client2"), isFalse);

      // C received the data from A through B.
      expect(spriteA.position.x, equals(spriteC.position.x));
    });

    test('SecondaryCommander_OtherJoinsLater', () async {
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");

      logConnectionData = false;
      for (int i = 0; i < 100; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      }
      worldB.network().safeActiveConnections().values.first.close("test closure!");

      for (int i = 0; i < 10; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      expect(
          worldB.network().gameState,
          isGameStateOf({
            playerId(1): "nameB",
          }).withCommanderId("b"));


      WormWorld worldC = await createTestWorld("c");
      // 20 keyframes later another player joins.
      worldC.connectTo("b", "nameC");
      for (int i = 0; i < 15; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5 );
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }
      expect(worldB,
          hasSpecifiedConnections(['c']).isValidGameConnections());
      expect(worldC,
          hasSpecifiedConnections(['b']).isValidGameConnections());
      // Should work just fine.
      expect(
          worldB.network().gameState,
          isGameStateOf({
            playerId(1): "nameB",
            playerId(2): "nameC"
          }).withCommanderId("b"));
      // Should work just fine.
      expect(
          worldC.network().gameState,
          isGameStateOf({
            playerId(1): "nameB",
            playerId(2): "nameC"
          }).withCommanderId("b"));
    });


    test('TestThreePlayerOneJoinsLater', () async {
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");

      logConnectionData = false;
      for (int i = 0; i < 100; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      }
      expect(worldA.network().gameState.isConnected("b", "a"), isTrue);
      expect(worldA.network().gameState.isConnected("a", "b"), isTrue);
      expect(worldB.network().gameState.isConnected("b", "a"), isTrue);
      expect(worldB.network().gameState.isConnected("a", "b"), isTrue);

      WormWorld worldC = await createTestWorld("c");
      // 20 keyframes later another player joins.
      worldC.connectTo("a", "nameC");
      for (int i = 0; i < 15; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5 );
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }
      expect(worldA,
          hasSpecifiedConnections(['b', 'c']).isValidGameConnections());
      expect(worldB,
          hasSpecifiedConnections(['a', 'c']).isValidGameConnections());
      expect(worldC,
          hasSpecifiedConnections(['a', 'b']).isValidGameConnections());
      // Should work just fine.
      expect(
          worldA.network().gameState,
          isGameStateOf({
            playerId(0): "nameA",
            playerId(1): "nameB",
            playerId(2): "nameC"
          }).withCommanderId("a"));

      // Verify Gamestate has mapped connections.
      for (WormWorld w in [worldA, worldB, worldC]) {
        for (WormWorld w2 in [worldA, worldB, worldC]) {
          GameState gameState = w.network().getGameState();
          String id1 = w.network().getPeer().getId();
          String id2 = w2.network().getPeer().getId();
          if (id1 == id2) {
            continue;
          }
          print("verify ${id1} connected to ${id2}");
          expect(gameState.isConnected(id1, id2), isTrue, reason: "$id1 is not connected to $id2!");
        }
      }
    });

    test('ThreeWorlds oneCommanderConnectionDies ElectsNewCommander', () async {
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");
      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");

      logConnectionData = false;
      for (int i = 0; i < 10; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }
      expect(worldA,
          hasSpecifiedConnections(['b', 'c']).isValidGameConnections());
      expect(worldB,
          hasSpecifiedConnections(['a', 'c']).isValidGameConnections());
      expect(worldC,
          hasSpecifiedConnections(['a', 'b']).isValidGameConnections());

      // Kill 'c's commander connection.
      testConnections['a']!.forEach((e) {
         if (e.getOtherEnd()?.id == 'c') {
          e.signalClose();
        }
      });

      for (int i = 0; i < 10; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      //  We manage to save the gameState by converting 'b' to commander.
      expect(worldA, isGameStateOf(
          {playerId(0): "nameA", playerId(1): "nameB", playerId(2):"nameC"}).withCommanderId('b'));
      expect(worldB, isGameStateOf(
          {playerId(0): "nameA", playerId(1): "nameB", playerId(2):"nameC"}).withCommanderId('b'));
      expect(worldC, isGameStateOf(
          {playerId(0): "nameA", playerId(1): "nameB", playerId(2):"nameC"}).withCommanderId('b'));

      expect(
          worldC,
          hasSpriteWithNetworkId(playerId(0))
              .andNetworkType(NetworkType.REMOTE));
      expect(
          worldC,
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.REMOTE));
      expect(
          worldC,
          hasSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.LOCAL));

      expect(
          worldB,
          hasSpriteWithNetworkId(playerId(0))
              .andNetworkType(NetworkType.REMOTE_FORWARD));
      expect(
          worldB,
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.LOCAL));
      expect(
          worldB,
          hasSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.REMOTE_FORWARD));

      expect(
          worldA,
          hasSpriteWithNetworkId(playerId(0))
              .andNetworkType(NetworkType.LOCAL));
      expect(
          worldA,
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.REMOTE));
      expect(
          worldA,
          hasSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.REMOTE));

    });

    test('TestMaxPlayers', () async {
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");

      worldA.startAsServer("nameA");

      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");
      WormWorld worldD = await createTestWorld("d");
      WormWorld worldE = await createTestWorld("e");

      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");
      worldD.connectTo("a", "nameD");
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);

      // The 4th player is now in a full (4/4) GameState; calling
      // findActiveGameConnection() during loading must NOT close its own
      // commander connection as "Full game connection!".
      expect(worldD.network().gameState.isAtMaxPlayers(), isTrue);
      expect(worldD.network().findActiveGameConnection(), isTrue);
      expect(worldD.network().getServerConnection()!.isClosedConnection(), isFalse);

      // At max players signaling server is disconnected.
      expect(worldA.network().peer.connectedToServer(), isFalse);
      // Explicitly reconnect.
      worldA.network().peer.reconnect();

      worldE.connectTo("a", "nameE", false);
      logConnectionData = true;
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);

      expect(worldE.network().getServerConnection(), isNotNull);

      worldE.network().getServerConnection()!.connectToGame('nameE', 2);

      expect(recentSentDataTo("e").stateUpdate[0].commanderGameReply,
          CommanderGameReply()
            ..challengeReply = CommanderGameReply_ChallengeReply.REJECT_FULL);

      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      worldE.frameDraw(KEY_FRAME_DEFAULT + 0.01);

      // Gamestate got reset.
      expect(worldE.network().gameState.playerInfoList(), hasLength(0));
      expect(worldE.network().gameState.gameStateProto.actingCommanderId, isEmpty);

      expect(worldA,
          hasSpecifiedConnections(['b', 'c', 'd']).isValidGameConnections());
    });

    test('TwoConnectionsDropped_findsNewStableGameState', () async {
      ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = false;
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");
      worldA.startAsServer("nameA");

      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");
      WormWorld worldD = await createTestWorld("d");

      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");
      worldD.connectTo("a", "nameD");

      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);
      worldC.frameDraw(KEY_FRAME_DEFAULT);
      worldD.frameDraw(KEY_FRAME_DEFAULT);

      testConnections['a']?.forEach((TestConnection c) {c.close();});
      testConnections['b']?.forEach((TestConnection c) {c.close();});

      ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = false;

      // During the first < 2 seconds of send failures, connections are not
      // dropped prematurely.
      for (int i = 0; i < 10; i++) {
        worldC.frameDraw(0.1);
        worldD.frameDraw(0.1);
      }
      expect(worldC.network().peer.hasConnectionTo('a'), isTrue);

      // Advance past the 2-second send failure grace period plus re-election.
      for (int i = 0; i < 30; i++) {
        worldC.frameDraw(0.1);
        worldD.frameDraw(0.1);
      }

      // The two worlds still survived, and connected to each other. Yay!
      expect(worldC, isGameStateOf(
          {playerId(2): "nameC", playerId(3): "nameD"}).withCommanderId('c'));
      expect(worldD, isGameStateOf(
          {playerId(2): "nameC", playerId(3): "nameD"}).withCommanderId('c'));
    });

    test('TestMultipleCommanders_keepsOneCommander', () async {
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");
      worldA.startAsServer("nameA");
      WormWorld worldB = await createTestWorld("b");
      worldB.startAsServer("nameB");

      WormWorld worldC = await createTestWorld("c");
      worldC.network().peer.connectTo("a");
      worldC.network().peer.connectTo("b");

      expect(worldA, hasSpecifiedConnections(['c']));
      expect(worldB, hasSpecifiedConnections(['c']));
      expect(worldC, hasSpecifiedConnections(['a', 'b']));

      // Poor worldC is confused about who is in charge :(
      expect(worldC, isGameStateOf({}));
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.1);
      expect(worldC, isGameStateOf({playerId(0): "nameA"}).withCommanderId("a"));
      expect(worldC.network().getServerConnection()!.id, "a");
      worldB.frameDraw(KEY_FRAME_DEFAULT + 0.1);
      expect(worldC.network().getServerConnection()!.id, "b");
      expect(worldC, isGameStateOf({playerId(0): "nameB"}).withCommanderId("b"));

      // Now connect.
      worldC.network().getServerConnection()!.connectToGame("nameC", 2);
      // We got gamestate and all.
      expect(
          worldC, isGameStateOf({playerId(0): "nameB", playerId(1): "nameC"}).withCommanderId("b"));

      // Now A tries to update.
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.1);
      worldA.frameDraw(KEY_FRAME_DEFAULT + 0.1);
      // We keep our gamestate.
      expect(
          worldC, isGameStateOf({playerId(0): "nameB", playerId(1): "nameC"}).withCommanderId("b"));
      // And we even dropped connection to the other commander.
      worldC.frameDraw();
      expect(worldC, hasSpecifiedConnections(['b']).isValidGameConnections());
    });

    test('TestCloseCommanderToCommanderConnection', () async {
      ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = false;
      logConnectionData = false;
      ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = false;
      WormWorld worldA = await createTestWorld("a");
      worldA.startAsServer("nameA");
      WormWorld worldB = await createTestWorld("b");
      worldB.startAsServer("nameB");

      worldA.network().peer.connectTo('b');
      expect(worldA, hasSpecifiedConnections(['b']));
      expect(worldB, hasSpecifiedConnections(['a']));

      // logConnectionData = true;
      for (int i = 0; i < 15; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.1);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.1);
      }

      // The connection didn't make sense, so we closed it.
      expect(worldA, hasSpecifiedConnections([]));
      expect(worldB, hasSpecifiedConnections([]));
    });

    test('TransferCommander immediately transfers command on close or background', () async {
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");
      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");

      for (int i = 0; i < 10; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      expect(worldA.network().isCommander(), isTrue);
      expect(worldB.network().isCommander(), isFalse);
      expect(worldC.network().isCommander(), isFalse);

      // Non-commander closing/backgrounding does not trigger a command transfer.
      expect(worldB.network().transferCommander("tab backgrounded"), isFalse);
      expect(worldA.network().isCommander(), isTrue);

      // Commander tab closing/backgrounding immediately initiates transfer.
      expect(worldA.network().transferCommander("tab backgrounded"), isTrue);
      // Subsequent event firing while transfer is pending is idempotent.
      expect(worldA.network().transferCommander("tab closing"), isFalse);

      String newCommanderId = worldA.network().pendingCommandTransfer()!;
      expect(newCommanderId, anyOf(equals('b'), equals('c')));

      // New commander immediately took over on receiving transferCommand.
      WormWorld newCommander = newCommanderId == 'b' ? worldB : worldC;
      WormWorld otherClient = newCommanderId == 'b' ? worldC : worldB;
      expect(newCommander.network().isCommander(), isTrue);

      // Advance one keyframe on the remaining peers so the other client updates.
      newCommander.frameDraw(KEY_FRAME_DEFAULT);
      otherClient.frameDraw(KEY_FRAME_DEFAULT);

      expect(newCommander.network().gameState.gameStateProto.actingCommanderId,
          equals(newCommanderId));
      expect(otherClient.network().gameState.gameStateProto.actingCommanderId,
          equals(newCommanderId));
    });

    test('SpriteId allocation wraps within local range and avoids player collisions', () async {
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      // worldB's playerSprite has id 2000; spawning >1000 local sprites must wrap
      // within [2001, 3000) and never collide with 2000 or 3000.
      expect(worldB.playerSprite!.networkId, equals(playerId(1)));
      for (int i = 0; i < 1100; i++) {
        MovingSprite s = MovingSprite.imageBasedSprite(Vec2(), 0, worldB.imageIndex());
        worldB.spriteIndex.addSprite(s);
        worldB.spriteIndex.putPendingSpritesInWorld();
        expect(s.networkId, greaterThan(playerId(1)));
        expect(s.networkId, lessThan(playerId(2)));
        worldB.spriteIndex.removeSprite(s.networkId!);
        worldB.spriteIndex.removePending();
      }

      // getNextUsablePlayerSpriteId must skip IDs already present in GameState
      // even if their sprite is not currently in SpriteIndex.
      worldA.network().gameState.addPlayerInfo(PlayerInfoProto()
        ..connectionId = "ghost"
        ..name = "ghost"
        ..spriteId = playerId(2));
      expect(worldA.network().gameState.getNextUsablePlayerSpriteId(worldA),
          equals(playerId(3)));

      // removeByConnectionId must never mutate worldA's own playerSprite.networkType.
      worldA.network().gameState.addPlayerInfo(PlayerInfoProto()
        ..connectionId = "colliding"
        ..name = "colliding"
        ..spriteId = worldA.playerSprite!.networkId!);
      worldA.network().gameState.removeByConnectionId(worldA, "colliding");
      expect(worldA.playerSprite!.networkType, equals(NetworkType.LOCAL));
    });

    test('GracefulGoodbye_printsPlayerDisconnectedAndRemovesPlayer', () async {
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");
      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");

      for (int i = 0; i < 10; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      // Client B disconnects gracefully (e.g. closing tab).
      worldB.network().sendGoodbye("tab closing");

      // Both remaining peers immediately receive goodbye and show "<name> disconnected".
      expect(
          worldA.hudMessages.messages.where((m) => m.message == "nameB disconnected").length,
          equals(1));
      expect(
          worldC.hudMessages.messages.where((m) => m.message == "nameB disconnected").length,
          equals(1));

      // Advance a few frames so closed connections and sprites are cleaned up.
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      expect(worldA, isGameStateOf({playerId(0): "nameA", playerId(2): "nameC"}).withCommanderId('a'));
      expect(worldC, isGameStateOf({playerId(0): "nameA", playerId(2): "nameC"}).withCommanderId('a'));
      // Commander broadcast must not create a duplicate disconnect banner on C.
      expect(
          worldC.hudMessages.messages.where((m) => m.message == "nameB disconnected").length,
          equals(1));

      // Now Commander A transfers command and sends goodbye.
      worldA.network().transferCommander("tab closing");
      worldA.network().sendGoodbye("tab closing");
      expect(
          worldC.hudMessages.messages.where((m) => m.message == "nameA disconnected").length,
          equals(1));

      for (int i = 0; i < 5; i++) {
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }
      expect(worldC, isGameStateOf({playerId(2): "nameC"}).withCommanderId('c'));
      expect(worldC, hasSpecifiedConnections([]));
    });

    test('NonCommanderReceivesPlayerSprite_OverCommanderKeyframeWhenAsymmetric', () async {
      ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = false;
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("commander");
      WormWorld worldB = await createTestWorld("client1");
      WormWorld worldC = await createTestWorld("client2");

      TestConnectionFactory connectionFactory =
          getIt<ConnectionFactory>() as TestConnectionFactory;
      worldA.startAsServer("nameA");
      worldA.frameDraw();

      // Block direct client1 <-> client2 connections so sprites must traverse
      // commander.
      connectionFactory
          .failConnection('client1', 'client2')
          .failConnection('client2', 'client1');

      worldB.connectTo('commander', "nameB");
      worldC.connectTo('commander', "nameC");

      // Simulate asymmetric/stale connectionInfo where commander thinks client1
      // is connected to client2, even though client2 has no connection to client1.
      worldA.network().gameState.playerInfoByConnectionId('client1')!
          .connectionInfo.add(ConnectionInfoProto()
            ..id = 'client2'
            ..latencyMillis = 20);

      // Step ONLY commander's keyframes (even without client1 sending updates,
      // e.g. while client1 is still loading) and client2's frameDraw.
      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 2);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 2);
      }

      // client2 MUST have received client1's LocalPlayerSprite via commander's
      // keyframe despite the one-sided connectionInfo.
      expect(worldC.spriteIndex[playerId(1)], isA<LocalPlayerSprite>());
      // And drawPlayerStats must safely render even if a player sprite is missing.
      worldC.spriteIndex.removeSprite(playerId(1));
      worldC.spriteIndex.removePending();
      expect(worldC.spriteIndex[playerId(1)], isNull);
      expect(() => drawPlayerStats(
          worldC.byteWorld.canvas!.context2D, worldC, 800, 600,
          worldC.spriteIndex, worldC.imageIndex(), false, false),
          returnsNormally);
    });

    test('E2E_TransientSendFailuresSurviveAndRecoverWithinTwoSeconds', () async {
      ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = false;
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      }
      expect(worldA, hasSpecifiedConnections(['b']).isValidGameConnections());
      expect(worldB, hasSpecifiedConnections(['a']).isValidGameConnections());

      // Manually trigger transient send errors on b -> a for 1.5 seconds (< 2s).
      // Note: testConnections[remoteId] holds TestConnections pointing TO remoteId.
      final TestConnection connBtoA = testConnections['a']!
          .firstWhere((c) => c.getOtherEnd()?.id == 'b');
      connBtoA.throwOnSend = true;

      for (int i = 0; i < 15; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }
      // Connection must survive < 2s of send failures.
      expect(worldB.network().peer.hasConnectionTo('a'), isTrue);
      expect(worldB.network().getServerConnection()!.isClosedConnection(), isFalse);

      // Recover transport; movement updates should flow again.
      connBtoA.throwOnSend = false;
      final LocalPlayerSprite spriteB = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      spriteB.position = Vec2(33.0, 22.0);
      spriteB.velocity = Vec2();
      for (int i = 0; i < 6; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
      }
      expect(worldA.spriteIndex[playerId(1)]!.position.x, closeTo(33.0, 2.0));

      // Now sustain send errors for > 2 seconds: connection must close cleanly.
      connBtoA.throwOnSend = true;
      for (int i = 0; i < 25; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }
      expect(worldB.network().peer.hasConnectionTo('a'), isFalse);
    });

    test('E2E_ClientToClientConnectionDroppedMidGame_CommanderFallbackKeepsSpritesSynced', () async {
      ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = false;
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");
      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");

      for (int i = 0; i < 12; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }
      expect(worldB, hasSpecifiedConnections(['a', 'c']).isValidGameConnections());
      expect(worldC, hasSpecifiedConnections(['a', 'b']).isValidGameConnections());

      // Manually kill ONLY the direct client-to-client (b <-> c) transport mid-game.
      for (TestConnection c in testConnections['b']!) {
        if (c.getOtherEnd()?.id == 'c') {
          c.close();
        }
      }

      // Drop b's sprite on c to verify full re-creation via commander fallback.
      worldC.spriteIndex.removeSprite(playerId(1));
      worldC.spriteIndex.removePending();
      expect(worldC.spriteIndex[playerId(1)], isNull);

      final LocalPlayerSprite spriteB = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      spriteB.position = Vec2(41.0, 25.0);
      spriteB.velocity = Vec2();

      // Advance past the 2-second send-failure timeout on b <-> c plus keyframes
      // so ClientStatusData updates and Commander A resumes forwarding b -> c.
      for (int i = 0; i < 35; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
        worldC.frameDraw(0.1);
      }

      // Direct b <-> c link is closed, while commander links stay alive.
      expect(worldB.network().peer.hasConnectionTo('c'), isFalse);
      expect(worldC.network().peer.hasConnectionTo('b'), isFalse);
      expect(worldB.network().peer.hasConnectionTo('a'), isTrue);
      expect(worldC.network().peer.hasConnectionTo('a'), isTrue);

      // c must have re-created b's sprite and received its new position via commander A!
      expect(worldC.spriteIndex[playerId(1)], isA<LocalPlayerSprite>());
      expect(worldC.spriteIndex[playerId(1)]!.position.x, closeTo(41.0, 2.0));
    });

    test('E2E_EarlyAutoConnectBeforeJoin_PromotesClientToClientAndTransfersSprites', () async {
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");
      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 8; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      // Reproduce autoConnectToPeers(): c connects directly to non-commander b
      // BEFORE c has joined a's GameState (neither end marks client-to-client).
      worldC.network().peer.connectTo("b");
      expect(worldB.network().peer.connections['c']!.isValidGameConnection(), isFalse);
      expect(worldC.network().peer.connections['b']!.isValidGameConnection(), isFalse);

      // Now c joins Commander A.
      worldC.connectTo("a", "nameC");
      for (int i = 0; i < 12; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      // Both sides of the early b <-> c connection must be promoted to valid
      // game connections and all 3 worlds must have all 3 player sprites.
      expect(worldB.network().peer.connections['c']!.isValidGameConnection(), isTrue);
      expect(worldC.network().peer.connections['b']!.isValidGameConnection(), isTrue);
      for (WormWorld w in [worldA, worldB, worldC]) {
        expect(w.spriteIndex[playerId(0)], isA<LocalPlayerSprite>());
        expect(w.spriteIndex[playerId(1)], isA<LocalPlayerSprite>());
        expect(w.spriteIndex[playerId(2)], isA<LocalPlayerSprite>());
      }
    });

    test('E2E_CommanderMigrationWithMissingSprite_NewCommanderForwardsPlayerSpriteToOtherClients', () async {
      ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = false;
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");
      WormWorld worldD = await createTestWorld("d");

      TestConnectionFactory connectionFactory =
          getIt<ConnectionFactory>() as TestConnectionFactory;
      // Block direct c <-> d so d's sprite MUST be forwarded through the commander.
      connectionFactory
          .failConnection('c', 'd')
          .failConnection('d', 'c');

      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();
      worldC.connectTo("a", "nameC");
      worldC.network().getServerConnection()!.sendClientEnter();
      worldD.connectTo("a", "nameD");
      worldD.network().getServerConnection()!.sendClientEnter();

      for (int i = 0; i < 12; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldD.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      // Remove d's sprite from BOTH b (the soon-to-be commander) and c right
      // before commander a dies, reproducing a commander migration where the
      // new commander creates d's sprite via CreateSpriteFromNetwork.
      worldB.spriteIndex.removeSprite(playerId(3));
      worldB.spriteIndex.removePending();
      worldC.spriteIndex.removeSprite(playerId(3));
      worldC.spriteIndex.removePending();
      expect(worldB.spriteIndex[playerId(3)], isNull);
      expect(worldC.spriteIndex[playerId(3)], isNull);

      // Kill Commander A cleanly.
      for (TestConnection conn in List.of(testConnections['a']!)) {
        conn.signalClose();
      }

      for (int i = 0; i < 18; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldD.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      // b is elected new commander, recreates d's sprite as REMOTE_FORWARD, and
      // forwards it to c despite c <-> d having no direct link.
      expect(worldB.network().isCommander(), isTrue);
      expect(worldB.spriteIndex[playerId(3)], isA<LocalPlayerSprite>());
      expect(worldB.spriteIndex[playerId(3)]!.networkType, equals(NetworkType.REMOTE_FORWARD));
      expect(worldC.spriteIndex[playerId(3)], isA<LocalPlayerSprite>());

      // Verify drawWinView also handles a missing winner sprite without throwing.
      worldC.network().gameState.gameStateProto.winnerPlayerId = 'd';
      worldC.spriteIndex.removeSprite(playerId(3));
      worldC.spriteIndex.removePending();
      final LocalPlayerSprite playerC = worldC.spriteIndex[playerId(2)] as LocalPlayerSprite;
      playerC.info.inGame = false;
      expect(() => drawWinView(
          worldC.byteWorld.canvas!.context2D, worldC, 800, 600,
          playerC, worldC.spriteIndex, worldC.imageIndex()),
          returnsNormally);
    });

    test('ConvertToCommander_skipsClosedAndInactiveConnections', () async {
      // Strict mode: sending on any closed TestConnection throws immediately.
      ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = true;
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");
      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");

      for (int i = 0; i < 8; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 5);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 5);
      }

      // Close BOTH commander 'a' and peer 'c' on worldB before ticking so
      // removeClosedConnection('a') passes a connections map to
      // convertToCommander that still contains already-closed 'c'.
      for (TestConnection conn in List.of(testConnections['a']!)) {
        conn.signalClose();
        conn.close();
      }
      for (TestConnection conn in List.of(testConnections['c']!)) {
        conn.signalClose();
        conn.close();
      }

      // Must not attempt sendPing() on closed 'c' or recycle 'c' into GameState.
      expect(() => worldB.frameDraw(KEY_FRAME_DEFAULT / 5), returnsNormally);
      expect(worldB.network().isCommander(), isTrue);
      expect(worldB, isGameStateOf({playerId(1): "nameB"}).withCommanderId('b'));
    });

    test('E2E_PartialMesh_CommanderAllPeersOnlyOneClientPairWorks_FullGameFlow', () async {
      ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = false;
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");
      WormWorld worldD = await createTestWorld("d");
      final List<WormWorld> allWorlds = [worldA, worldB, worldC, worldD];
      for (WormWorld w in allWorlds) {
        w.network().disableCommandTransferHeuristicForTest = true;
        w.byteWorld.setWorldImage(w.imageIndex().imageFactory.createWithSize(300, 200));
        while (!w.byteWorld.bedrockComputed()) {
          w.byteWorld.bedrockStep();
        }
      }

      // Topology: Commander 'a' connects to all peers ('b', 'c', 'd'), while
      // non-commander peers CANNOT connect to each other EXCEPT 'c' <-> 'd'.
      TestConnectionFactory connectionFactory =
          getIt<ConnectionFactory>() as TestConnectionFactory;
      connectionFactory
          .failConnection('b', 'c')
          .failConnection('c', 'b')
          .failConnection('b', 'd')
          .failConnection('d', 'b');

      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();
      worldC.connectTo("a", "nameC");
      worldC.network().getServerConnection()!.sendClientEnter();
      worldD.connectTo("a", "nameD");
      worldD.network().getServerConnection()!.sendClientEnter();

      // Step enough frames for initial spawn timers (1.0s) and keyframes to sync.
      for (int i = 0; i < 16; i++) {
        for (WormWorld w in allWorlds) {
          w.frameDraw(0.1);
        }
      }

      // 1) Verify partial-mesh connection topology and 4-player GameState/sprites.
      expect(worldA, hasSpecifiedConnections(['b', 'c', 'd']).isValidGameConnections());
      expect(worldB.network().safeActiveConnections().keys.toSet(), equals({'a'}));
      expect(worldC, hasSpecifiedConnections(['a', 'd']).isValidGameConnections());
      expect(worldD, hasSpecifiedConnections(['a', 'c']).isValidGameConnections());

      final Map<int, String> expectedPlayers = {
        playerId(0): "nameA",
        playerId(1): "nameB",
        playerId(2): "nameC",
        playerId(3): "nameD",
      };
      for (WormWorld w in allWorlds) {
        expect(w, isGameStateOf(expectedPlayers).withCommanderId('a'));
        for (int pid in expectedPlayers.keys) {
          LocalPlayerSprite? ps = w.spriteIndex[pid] as LocalPlayerSprite?;
          expect(ps, isNotNull, reason: "${w} missing sprite $pid");
          expect(ps!.inGame(), isTrue, reason: "${w} sprite $pid not inGame");
        }
        // Confirmed mutual P2P link exists ONLY between c and d among clients.
        GameState gs = w.network().getGameState();
        expect(gs.isConnected('c', 'd') && gs.isConnected('d', 'c'), isTrue);
        expect(gs.isConnected('b', 'c'), isFalse);
        expect(gs.isConnected('b', 'd'), isFalse);
      }

      // 2) Verify movement, grappling hook (Rope), particles, and chat messages
      // from isolated peer 'b' reach 'c' and 'd' via commander 'a', and vice versa.
      final LocalPlayerSprite bOnB = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      bOnB.position = Vec2(28.0, 22.0);
      bOnB.velocity = Vec2.ZERO;
      bOnB.gun.angle = 0.25;
      Rope ropeB = Rope.createWithOwner(worldB, bOnB, -pi / 2, 250.0);
      worldB.addSprite(ropeB);
      Particles jetParticlesB = Particles(
          worldB, bOnB, Vec2(28.0, 22.0), Vec2(0.0, 40.0),
          radius: 6.0, count: 4, lifeTime: 80,
          particleType: ParticleEffects_ParticleType.SODA)
        ..sendToNetwork = true;
      worldB.addSprite(jetParticlesB);
      worldB.displayHudMessageAndSendToNetwork("nameB: hello from isolated peer");

      final LocalPlayerSprite cOnC = worldC.spriteIndex[playerId(2)] as LocalPlayerSprite;
      cOnC.position = Vec2(48.0, 22.0);
      cOnC.velocity = Vec2.ZERO;
      Rope ropeC = Rope.createWithOwner(worldC, cOnC, -pi / 2, 250.0);
      worldC.addSprite(ropeC);

      for (int i = 0; i < 8; i++) {
        for (WormWorld w in allWorlds) {
          w.frameDraw(0.1);
        }
      }

      // Isolated 'b' updates reached 'c' and 'd' through commander 'a'.
      expect(worldC.spriteIndex[ropeB.networkId!], isA<Rope>());
      expect(worldD.spriteIndex[ropeB.networkId!], isA<Rope>());
      expect((worldD.spriteIndex[ropeB.networkId!] as Rope).ownerId, equals('b'));
      expect(
          worldC.hudMessages.messages
              .any((m) => m.message == "nameB: hello from isolated peer"),
          isTrue);
      expect(
          worldD.hudMessages.messages
              .any((m) => m.message == "nameB: hello from isolated peer"),
          isTrue);
      expect(
          worldD.spriteIndex.spriteIds().any((id) => worldD.spriteIndex[id] is Particles),
          isTrue);

      // And 'c's rope reached BOTH direct peer 'd' AND isolated peer 'b'!
      expect(worldD.spriteIndex[ropeC.networkId!], isA<Rope>());
      expect(worldB.spriteIndex[ropeC.networkId!], isA<Rope>());

      // Removing 'b' and 'c' ropes propagates removal and stationary positions sync cleanly.
      worldB.removeSprite(ropeB.networkId!);
      worldC.removeSprite(ropeC.networkId!);
      for (WormWorld w in allWorlds) {
        w.frameDraw(0.05);
      }
      bOnB.gravityAffect = 0.0;
      cOnC.gravityAffect = 0.0;
      bOnB.position = Vec2(32.0, 22.0);
      bOnB.velocity = Vec2.ZERO;
      cOnC.position = Vec2(120.0, 22.0);
      cOnC.velocity = Vec2.ZERO;
      for (int i = 0; i < 8; i++) {
        for (WormWorld w in allWorlds) {
          w.frameDraw(0.1);
        }
      }
      for (WormWorld w in allWorlds) {
        expect(w.spriteIndex[ropeB.networkId!], isNull);
        expect(w.spriteIndex[ropeC.networkId!], isNull);
      }
      expect(worldC.spriteIndex[playerId(1)]!.position.x, closeTo(32.0, 1.0));
      expect(worldD.spriteIndex[playerId(1)]!.position.x, closeTo(32.0, 1.0));
      expect(worldB.spriteIndex[playerId(2)]!.position.x, closeTo(120.0, 1.0));
      expect(worldD.spriteIndex[playerId(2)]!.position.x, closeTo(120.0, 1.0));

      // 3) Combat, terrain destruction, kill, scoreboard, and respawn across partial mesh:
      // Paint a destructible terrain wall at x=48..75, y=30..70, place 'c' right
      // at its front face with 5 HP, and have isolated 'b' at x=2 fire Shotgun into it!
      WeaponState.random = Random(1);
      for (WormWorld w in allWorlds) {
        w.byteWorld.clearAt(Vec2(50, 50), 80.0);
        w.byteWorld.fillRectAt(Vec2(48, 30), Vec2(28, 40), "#8b5a2b");
        for (int pid in expectedPlayers.keys) {
          (w.spriteIndex[pid] as LocalPlayerSprite)
            ..gravityAffect = 0.0
            ..flags |= Sprite.FLAG_NO_GRAVITY;
        }
        // Move bystanders 'a' and 'd' out of the firing lane so they don't intercept pellets.
        (w.spriteIndex[playerId(0)] as LocalPlayerSprite)
          ..position = Vec2(2.0, 5.0)
          ..velocity = Vec2.ZERO
          ..collision = false;
        (w.spriteIndex[playerId(3)] as LocalPlayerSprite)
          ..position = Vec2(55.0, 5.0)
          ..velocity = Vec2.ZERO
          ..collision = false;
        (w.spriteIndex[playerId(1)] as LocalPlayerSprite)
          ..position = Vec2(2.0, 48.0)
          ..velocity = Vec2.ZERO
          ..angle = 0.0
          ..gun.angle = 0.0;
        (w.spriteIndex[playerId(2)] as LocalPlayerSprite)
          ..position = Vec2(58.0, 48.0)
          ..velocity = Vec2.ZERO;
      }
      expect(worldD.byteWorld.isSolid(52, 48), isTrue);

      final LocalPlayerSprite cOnA = worldA.spriteIndex[playerId(2)] as LocalPlayerSprite;
      cOnA.health = 5;
      // Weapon index 0 ("Banana pancake") spawns a BananaCake (50 dmg, radius 50,
      // explodeAfter 4.0s) that transfers to all peers, then explodes and spawns bananas!
      final LocalPlayerSprite bOnA = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      bOnB.weaponState!.selectedWeaponIndex = 0;
      bOnA.weaponState!.selectedWeaponIndex = 0;

      // Sync positions onto commander before firing.
      for (int i = 0; i < 4; i++) {
        for (WormWorld w in allWorlds) {
          w.frameDraw(KEY_FRAME_DEFAULT / 2);
        }
      }

      // Press Fire on isolated client 'b' -> syncs KeyState to 'a' -> 'a' spawns
      // BananaCake -> syncs projectile to 'b', 'c', 'd' -> explodes at (50, 48) ->
      // ByteWorldDestruction + kill syncs to all 4 worlds!
      int fireKey = bOnB.getControls()['Fire']!;
      worldB.localKeyState.onKeyDown(fireKey);
      worldA.frameDraw(0.01);
      worldA.frameDraw(0.01);
      worldB.localKeyState.onKeyUp(fireKey);

      final WorldDamageProjectile cake = worldA.spriteIndex
          .spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<WorldDamageProjectile>()
          .first;
      // Keep the BananaCake right next to the wall & 'c' while syncing to all clients.
      cake.gravityAffect = 0.0;
      cake.flags |= Sprite.FLAG_NO_GRAVITY;
      cake.velocity = Vec2.ZERO;
      cake.collision = false;
      cake.position = Vec2(50.0, 48.0);
      for (int i = 0; i < 6; i++) {
        for (WormWorld w in allWorlds) {
          w.frameDraw(0.1);
        }
      }
      // All 4 worlds (including isolated 'b' and 'd') received the live projectile!
      for (WormWorld w in allWorlds) {
        expect(w.spriteIndex.hasSprite(cake.networkId!), isTrue,
            reason: "Projectile did not sync to $w");
      }

      // Advance past explodeAfter (4.0s) so BananaCake detonates (radius 50, 50 dmg).
      for (int i = 0; i < 40; i++) {
        for (WormWorld w in allWorlds) {
          w.frameDraw(0.1);
        }
      }

      // Terrain at (52, 48) was destroyed on all 4 worlds (including isolated 'b' & 'd').
      for (WormWorld w in allWorlds) {
        expect(w.byteWorld.isSolid(52, 48), isFalse,
            reason: "ByteWorldDestruction did not sync to $w");
        PlayerInfoProto infoB = w.network().getGameState().playerInfoByConnectionId('b')!;
        PlayerInfoProto infoC = w.network().getGameState().playerInfoByConnectionId('c')!;
        expect(infoB.score, equals(1), reason: "Score for 'b' did not sync to $w");
        expect(infoC.deaths, equals(1), reason: "Death for 'c' did not sync to $w");
        expect(infoC.inGame, isFalse);
        expect(() => drawPlayerStats(
            w.byteWorld.canvas!.context2D, w, 800, 600,
            w.spriteIndex, w.imageIndex(), false, true), returnsNormally);
      }

      // Advance past RESPAWN_TIME (5.0s) and verify 'c' respawns across all 4 worlds.
      for (int i = 0; i < 55; i++) {
        for (WormWorld w in allWorlds) {
          w.frameDraw(0.1);
        }
      }
      for (WormWorld w in allWorlds) {
        PlayerInfoProto infoC = w.network().getGameState().playerInfoByConnectionId('c')!;
        expect(infoC.inGame, isTrue, reason: "'c' did not respawn on $w");
      }
    });

    test('E2E_PartialMesh_GracefulCommanderLeave_ElectsMostConnectedPeer', () async {
      ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = false;
      logConnectionData = false;
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");
      WormWorld worldD = await createTestWorld("d");
      final List<WormWorld> allWorlds = [worldA, worldB, worldC, worldD];
      for (WormWorld w in allWorlds) {
        w.network().disableCommandTransferHeuristicForTest = true;
        w.byteWorld.setWorldImage(w.imageIndex().imageFactory.createWithSize(300, 200));
        while (!w.byteWorld.bedrockComputed()) {
          w.byteWorld.bedrockStep();
        }
      }

      // Only 'c' <-> 'd' can connect among clients; 'b' is only connected to 'a'.
      TestConnectionFactory connectionFactory =
          getIt<ConnectionFactory>() as TestConnectionFactory;
      connectionFactory
          .failConnection('b', 'c')
          .failConnection('c', 'b')
          .failConnection('b', 'd')
          .failConnection('d', 'b');

      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();
      worldC.connectTo("a", "nameC");
      worldC.network().getServerConnection()!.sendClientEnter();
      worldD.connectTo("a", "nameD");
      worldD.network().getServerConnection()!.sendClientEnter();

      for (int i = 0; i < 12; i++) {
        for (WormWorld w in allWorlds) {
          w.frameDraw(0.1);
        }
      }

      // Give isolated 'b' the HIGHEST FPS (60) and lowest alphabetical ID ('b'),
      // while 'c' has 45 FPS and 'd' has 55 FPS.
      // Because 'c' and 'd' have 1 confirmed peer connection ('c'<->'d') vs 'b's 0,
      // commander election MUST ignore 'b' and pick 'd' (most connections, then highest FPS).
      worldB.drawFps().setFpsForTest(60.0);
      worldC.drawFps().setFpsForTest(45.0);
      worldD.drawFps().setFpsForTest(55.0);
      for (int i = 0; i < 12; i++) {
        for (WormWorld w in allWorlds) {
          w.frameDraw(0.1);
        }
      }

      expect(worldA.network().transferCommander("tab closing"), isTrue);
      expect(worldA.network().pendingCommandTransfer(), equals('d'));
      worldA.network().sendGoodbye("tab closing");

      // Deliberately tick worldC BEFORE worldD to verify worldC already knows 'd'
      // took command and does NOT split-brain elect 'c' on seeing 'a's goodbye.
      for (int i = 0; i < 10; i++) {
        worldC.frameDraw(0.1);
        worldD.frameDraw(0.1);
        worldB.frameDraw(0.1);
      }

      // 'c' and 'd' stay in a healthy 2-player game with 'd' as commander!
      expect(worldD.network().isCommander(), isTrue);
      expect(worldC.network().isCommander(), isFalse);
      expect(worldD, isGameStateOf({playerId(2): "nameC", playerId(3): "nameD"}).withCommanderId('d'));
      expect(worldC, isGameStateOf({playerId(2): "nameC", playerId(3): "nameD"}).withCommanderId('d'));
      expect(worldD, hasSpecifiedConnections(['c']).isValidGameConnections());
      expect(worldC, hasSpecifiedConnections(['d']).isValidGameConnections());

      // Isolated 'b' had no path to 'c' or 'd', so it cleanly became solo commander
      // of its own 1-player game and reconnected to the signaling server.
      expect(worldB.network().isCommander(), isTrue);
      expect(worldB, isGameStateOf({playerId(1): "nameB"}).withCommanderId('b'));
      expect(worldB, isConnectedToServer(true));
    });

    test('E2E_PartialMesh_AbruptCommanderDrop_ElectsMostConnectedPeer', () async {
      ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = false;
      logConnectionData = false;

      // Sub-case 1: Commander 'a' + isolated 'b' + connected pair 'c' <-> 'd'.
      // When 'a' crashes abruptly, 'c' and 'd' elect 'c' and stay together,
      // while isolated 'b' becomes solo commander.
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      WormWorld worldC = await createTestWorld("c");
      WormWorld worldD = await createTestWorld("d");
      TestConnectionFactory connectionFactory =
          getIt<ConnectionFactory>() as TestConnectionFactory;
      connectionFactory
          .failConnection('b', 'c')
          .failConnection('c', 'b')
          .failConnection('b', 'd')
          .failConnection('d', 'b');

      worldA.startAsServer("nameA");
      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();
      worldC.connectTo("a", "nameC");
      worldC.network().getServerConnection()!.sendClientEnter();
      worldD.connectTo("a", "nameD");
      worldD.network().getServerConnection()!.sendClientEnter();

      for (int i = 0; i < 15; i++) {
        worldA.frameDraw(0.1);
        worldB.frameDraw(0.1);
        worldC.frameDraw(0.1);
        worldD.frameDraw(0.1);
      }

      for (TestConnection conn in List.of(testConnections['a']!)) {
        conn.signalClose();
      }
      for (int i = 0; i < 15; i++) {
        worldB.frameDraw(0.1);
        worldC.frameDraw(0.1);
        worldD.frameDraw(0.1);
      }

      expect(worldC, isGameStateOf({playerId(2): "nameC", playerId(3): "nameD"}).withCommanderId('c'));
      expect(worldD, isGameStateOf({playerId(2): "nameC", playerId(3): "nameD"}).withCommanderId('c'));
      expect(worldB, isGameStateOf({playerId(1): "nameB"}).withCommanderId('b'));

      // Sub-case 2: Commander 'a' + clients 'b', 'c', 'd' where 'b' <-> 'c' fails
      // while 'b' <-> 'd' AND 'c' <-> 'd' succeed!
      // Alphabetically 'b' < 'c' < 'd', so pure ID order would pick 'b' and lose 'c',
      // whereas connection-count priority elects 'd' (2 peer connections vs 1),
      // keeping ALL THREE surviving players ('b', 'c', 'd') in the game together!
      clearEnvironment();
      WormWorld hubA = await createTestWorld("a");
      WormWorld peerB = await createTestWorld("b");
      WormWorld peerC = await createTestWorld("c");
      WormWorld hubD = await createTestWorld("d");
      connectionFactory = getIt<ConnectionFactory>() as TestConnectionFactory;
      connectionFactory
          .failConnection('b', 'c')
          .failConnection('c', 'b');

      hubA.startAsServer("nameA");
      peerB.connectTo("a", "nameB");
      peerC.connectTo("a", "nameC");
      hubD.connectTo("a", "nameD");

      for (int i = 0; i < 15; i++) {
        hubA.frameDraw(0.1);
        peerB.frameDraw(0.1);
        peerC.frameDraw(0.1);
        hubD.frameDraw(0.1);
      }
      expect(peerB.network().safeActiveConnections().keys.toSet(), equals({'a', 'd'}));
      expect(peerC, hasSpecifiedConnections(['a', 'd']).isValidGameConnections());
      expect(hubD, hasSpecifiedConnections(['a', 'b', 'c']).isValidGameConnections());

      // Abruptly kill Commander 'a'.
      for (TestConnection conn in List.of(testConnections['a']!)) {
        conn.signalClose();
      }
      for (int i = 0; i < 15; i++) {
        peerB.frameDraw(0.1);
        peerC.frameDraw(0.1);
        hubD.frameDraw(0.1);
      }

      // All 3 peers unanimously elect 'd' (most connections) and stay in the same game!
      final Map<int, String> survivingThree = {
        playerId(1): "nameB",
        playerId(2): "nameC",
        playerId(3): "nameD",
      };
      expect(hubD, isGameStateOf(survivingThree).withCommanderId('d'));
      expect(peerB, isGameStateOf(survivingThree).withCommanderId('d'));
      expect(peerC, isGameStateOf(survivingThree).withCommanderId('d'));

      // Verify new commander 'd' actively forwards 'b' <-> 'c' movement!
      final LocalPlayerSprite bSprite = peerB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      bSprite.position = Vec2(35.0, 33.0);
      bSprite.velocity = Vec2.ZERO;
      for (int i = 0; i < 8; i++) {
        peerB.frameDraw(0.1);
        hubD.frameDraw(0.1);
        peerC.frameDraw(0.1);
      }
      expect(peerC.spriteIndex[playerId(1)]!.position.x, closeTo(35.0, 3.0));
    });
  });
}
