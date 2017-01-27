import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:di/di.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/net/net.dart';

void main() {
  setUp(() {
    logOutputForTest();
    testConnections.clear();
    testPeers.clear();
    logConnectionData = false;
    remapKeyNamesForTest();
  });

  group('Sprite transfer tests', () {
    test('TestBasicSpriteTransfer', () {
      Injector injectorA = createWorldInjector('a');
      Injector injectorB = createWorldInjector('b');
      Injector injectorC = createWorldInjector('c');
      WormWorld worldA = initTestWorld(injectorA);
      WormWorld worldB = initTestWorld(injectorB);;
      WormWorld worldC = initTestWorld(injectorC);;
      worldA.startAsServer("nameA");
      worldA.frameDraw();
      expect(worldA, hasPlayerSpriteWithNetworkId(playerId(0))
          .andNetworkType(NetworkType.LOCAL));
      logConnectionData = true;
      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      logConnectionData = false;
      expect(worldA, hasExactSprites([
          hasPlayerSpriteWithNetworkId(playerId(0))
              .andNetworkType(NetworkType.LOCAL),
          hasPlayerSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.REMOTE_FORWARD)
              .andRemoteKeyState(),
          hasPlayerSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.REMOTE_FORWARD)
              .andRemoteKeyState(),
      ]));
      expect(worldB, hasExactSprites([
        hasPlayerSpriteWithNetworkId(playerId(0))
                .andNetworkType(NetworkType.REMOTE)
                .andRemoteKeyState(),
        hasPlayerSpriteWithNetworkId(playerId(1))
                .andNetworkType(NetworkType.LOCAL),
        hasPlayerSpriteWithNetworkId(playerId(2))
                .andNetworkType(NetworkType.REMOTE)
                .andRemoteKeyState(),
      ]));
      // Assert server A representation.
      expect(worldA.spriteIndex[playerId(0)],
          hasType('LocalPlayerSprite'));
      expect(worldB.spriteIndex[playerId(0)],
          hasType('LocalPlayerSprite'));
      expect(worldC.spriteIndex[playerId(0)],
          hasType('LocalPlayerSprite'));
      // Assert client B representation. 
      expect(worldA.spriteIndex[playerId(1)],
          hasType('LocalPlayerSprite'));
      expect(worldB.spriteIndex[playerId(1)],
          hasType('LocalPlayerSprite'));
      expect(worldC.spriteIndex[playerId(1)],
          hasType('LocalPlayerSprite'));
      // Assert client C representation.
      expect(worldA.spriteIndex[playerId(2)],
          hasType('LocalPlayerSprite'));
      expect(worldB.spriteIndex[playerId(2)],
          hasType('LocalPlayerSprite'));
      expect(worldC.spriteIndex[playerId(2)],
          hasType('LocalPlayerSprite'));

      testConnections['a'].forEach((e) { e.dropPackets = 100;});
      
      for (int i = 0; i < 20; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }      
      expect(worldB.spriteIndex.count(), equals(2));
      expect(worldB, hasExactSprites([
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.LOCAL),
          hasSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.REMOTE_FORWARD),
      ]));
      expect(worldB.spriteIndex[playerId(1)],
          hasType('LocalPlayerSprite'));
      expect(worldB.spriteIndex[playerId(2)],
          hasType('LocalPlayerSprite'));
      
      expect(worldC.spriteIndex.count(), equals(2));
          expect(worldC, hasExactSprites([
              hasSpriteWithNetworkId(playerId(1))
                  .andNetworkType(NetworkType.REMOTE),
              hasSpriteWithNetworkId(playerId(2))
                  .andNetworkType(NetworkType.LOCAL),
          ]));
      expect(worldC.spriteIndex[playerId(1)],
          hasType('LocalPlayerSprite'));
      expect(worldC.spriteIndex[playerId(2)],
          hasType('LocalPlayerSprite'));
      
      // Now test transferring a sprite over the network.
      MovingSprite sprite = new MovingSprite(new Vec2(), new Vec2(1.0, 2.0), SpriteType.RECT);
      MovingSprite imageSprite = new MovingSprite.imageBasedSprite(
          new Vec2(), 0, worldB.imageIndex());
      worldB.addSprite(sprite);
      worldB.addSprite(imageSprite);
      worldB.frameDraw();
      expect(worldB, hasExactSprites([
        hasPlayerSpriteWithNetworkId(playerId(1))
            .andNetworkType(NetworkType.LOCAL),
        hasPlayerSpriteWithNetworkId(playerId(2))
            .andNetworkType(NetworkType.REMOTE_FORWARD)
            .andRemoteKeyState(),
        hasSpriteWithNetworkId(sprite.networkId)
            .andNetworkType(NetworkType.LOCAL),
        hasSpriteWithNetworkId(imageSprite.networkId)
            .andNetworkType(NetworkType.LOCAL),
      ]));
      worldB.frameDraw();
      worldC.frameDraw();
      // Sprite gets added to worldC the next frame.
      expect(worldC, hasExactSprites([
        hasPlayerSpriteWithNetworkId(playerId(1))
             .andNetworkType(NetworkType.REMOTE)
             .andRemoteKeyState(),
        hasPlayerSpriteWithNetworkId(playerId(2))
             .andNetworkType(NetworkType.LOCAL),
        hasSpriteWithNetworkId(sprite.networkId)
             .andNetworkType(NetworkType.REMOTE),
        hasSpriteWithNetworkId(imageSprite.networkId)
             .andNetworkType(NetworkType.REMOTE),
      ]));
      // Now remove the sprite.
      sprite.remove = true;
      imageSprite.remove = true;
      for (int i = 0; i < 9; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldC.frameDraw(KEY_FRAME_DEFAULT);
      }
      
      expect(worldB, hasExactSprites([
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.LOCAL),
          hasSpriteWithNetworkId(playerId(2))
             .andNetworkType(NetworkType.REMOTE_FORWARD),
      ]));
      expect(worldC, hasExactSprites([
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.REMOTE),
          hasSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.LOCAL),
      ]));
      
      expect(recentReceviedDataFrom("b", 1),
          new MapKeyMatcher.doesNotContain(REMOVE_KEY));
      expect(recentReceviedDataFrom("c", 1),
          new MapKeyMatcher.doesNotContain(REMOVE_KEY));
    });
    
    test('TestGameStateTransferKillPlayer', () {
      WormWorld worldA = testWorld("a");
      WormWorld worldB = testWorld("b");
      worldA.startAsServer("nameA");
     
      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection().sendClientEnter();

      logConnectionData = true;
      for (int i = 0; i < 3; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldA.frameDraw(KEY_FRAME_DEFAULT);
      }

      // Both worlds are in the same gamestate.
      expect(worldB.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('a'));
      expect(worldA.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('a'));

      // The player B sprite is hooked up to the gameState.
      LocalPlayerSprite playerBSprite = worldB.spriteIndex[playerId(1)];
      expect(playerBSprite.info.name, equals("nameB"));
      playerBSprite = worldA.spriteIndex[playerId(1)];;
      expect(playerBSprite.info.name, equals("nameB"));
      
      LocalPlayerSprite playerASprite = worldB.spriteIndex[playerId(0)];
      expect(playerASprite.info.name, equals("nameA"));
      playerBSprite = worldA.spriteIndex[playerId(0)];
      expect(playerASprite.info.name, equals("nameA"));
      
      // Now kill one player.
      playerBSprite = worldA.spriteIndex[playerId(1)];
      expect(playerBSprite.collision, equals(true));
      expect(playerBSprite.inGame(), equals(true));
      playerBSprite.takeDamage(playerBSprite.health);
      expect(playerBSprite.collision, equals(false));
      expect(playerBSprite.inGame(), equals(false));
      expect(playerBSprite.maybeRespawn(0.01), equals(true));
      
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);

      // Now look how worldB views this sprite.
      playerBSprite = worldB.spriteIndex[playerId(1)];
      playerBSprite.takeDamage(playerBSprite.health);
      expect(playerBSprite.collision, equals(false));
      expect(playerBSprite.inGame(), equals(false));

      // Pass some time.
      for (int i = 0; i < 10; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldA.frameDraw(KEY_FRAME_DEFAULT);
      }

      // World A
      playerBSprite = worldA.spriteIndex[playerId(1)];
      expect(playerBSprite.collision, equals(true));
      expect(playerBSprite.inGame(), equals(true));
      expect(playerBSprite.maybeRespawn(0.01), equals(true));

      // World B
      playerBSprite = worldB.spriteIndex[playerId(1)];
      expect(playerBSprite.collision, equals(false));
      expect(playerBSprite.inGame(), equals(true));
      expect(playerBSprite.maybeRespawn(0.01), equals(false));

      expect(worldB.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('a'));
      expect(worldA.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('a'));

      // Now force a switch of commander, but kill player first!
      playerBSprite = worldA.spriteIndex[playerId(1)];
      expect(playerBSprite.collision, equals(true));
      playerBSprite.takeDamage(playerBSprite.health);

      worldA.drawFps().setFpsForTest(3.1);
      // Should be enough frames to switch commander and respawn the player.
      for (int i = 0; i < 25; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldA.frameDraw(KEY_FRAME_DEFAULT);
      }
      worldA.drawFps().setFpsForTest(45.0);

      expect(worldB.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('b'));
      expect(worldA.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('b'));

      // Player should be back in game now in both worlds.
      // World A
      playerBSprite = worldA.spriteIndex[playerId(1)];
      expect(playerBSprite.collision, equals(false));
      expect(playerBSprite.inGame(), equals(true));
      expect(playerBSprite.maybeRespawn(0.01), equals(false));

      // World B
      playerBSprite = worldB.spriteIndex[playerId(1)];
      expect(playerBSprite.collision, equals(true));
      expect(playerBSprite.inGame(), equals(true));
      expect(playerBSprite.maybeRespawn(0.01), equals(true));
    });
    
    test('TestPlayerDeath', () {
      WormWorld worldA = testWorld("a");
      WormWorld worldB = testWorld("b");
      worldA.startAsServer("nameA");
      worldA.frameDraw();
      worldB.connectTo("a", "nameB");

      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);
      
      expect(worldA, hasExactSprites([
             hasSpriteWithNetworkId(playerId(0))
                 .andNetworkType(NetworkType.LOCAL),
             hasSpriteWithNetworkId(playerId(1))
                 .andNetworkType(NetworkType.REMOTE_FORWARD),
          ]));
      expect(worldB, hasExactSprites([
               hasSpriteWithNetworkId(playerId(0))
                   .andNetworkType(NetworkType.REMOTE),
               hasSpriteWithNetworkId(playerId(1))
                   .andNetworkType(NetworkType.LOCAL),
            ]));

      LocalPlayerSprite playerBSprite = worldA.spriteIndex[playerId(1)];
      playerBSprite.takeDamage(playerBSprite.health - 1);
      int healthRemaining = playerBSprite.health;

      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);

      // Check state in worldB.
      LocalPlayerSprite playerBSpriteInB = worldB.spriteIndex[playerId(1)];
      expect(playerBSpriteInB.health, equals(playerBSprite.health));

      playerBSprite.takeDamage(1);

      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);

      expect(playerBSprite.inGame(), equals(false));
      expect(playerBSpriteInB.inGame(), equals(false));


      expect(recentReceviedDataFrom("a"), 
          new MapKeysMatcher.containsKeys([MESSAGE_KEY]));
    });
  });
}