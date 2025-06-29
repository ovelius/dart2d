library dart2d;

import 'dart:math';

import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:test/test.dart';
import 'lib/test_factories.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/util/util.dart';

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

      for (int i = 0; i < 20; i++) {
        worldC.frameDraw(0.1);
        worldD.frameDraw(0.1);
      }

      // The two worlds still survived, and connected to each other. Yay!
      expect(worldC, isGameStateOf(
          {playerId(2): "nameC", playerId(3): "nameD"}).withCommanderId('d'));
      expect(worldD, isGameStateOf(
          {playerId(2): "nameC", playerId(3): "nameD"}).withCommanderId('d'));
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
  });
}
