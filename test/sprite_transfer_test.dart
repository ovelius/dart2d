import 'package:test/test.dart';
import 'test_connection.dart';
import 'test_peer.dart';
import 'matchers.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/res/imageindex.dart';
import 'dart:html';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

void main() {
  setUp(() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((LogRecord rec) {
      print('${rec.loggerName} ${rec.level.name}: ${rec.time}: ${rec.message}');
    });
    testConnections.clear();
    testPeers.clear();
    logConnectionData = false;
    useEmptyImagesForTest();
    remapKeyNamesForTest();
  });
  
  group('Sprite transfer tests', () {
    test('TestBasicSpriteTransfer', () {
      World worldA = testWorld("a");
      World worldB = testWorld("b");
      World worldC = testWorld("c");
      worldA.startAsServer("nameA");
      worldA.frameDraw();
      expect(worldA, hasSpriteWithNetworkId(playerId(0))
          .andNetworkType(NetworkType.LOCAL));
      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      expect(worldA, hasExactSprites([
          hasSpriteWithNetworkId(playerId(0))
              .andNetworkType(NetworkType.LOCAL),
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.REMOTE_FORWARD),
          hasSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.REMOTE_FORWARD),
      ]));
      expect(worldB, hasExactSprites([
            hasSpriteWithNetworkId(playerId(0))
                .andNetworkType(NetworkType.REMOTE),
            hasSpriteWithNetworkId(playerId(1))
                .andNetworkType(NetworkType.LOCAL),
            hasSpriteWithNetworkId(playerId(2))
                .andNetworkType(NetworkType.REMOTE),
      ]));
      // Assert server A representation.
      expect(worldA.spriteIndex[playerId(0)],
          hasType('LocalPlayerSprite'));
      expect(worldB.spriteIndex[playerId(0)],
          hasType('RemotePlayerClientSprite'));
      expect(worldC.spriteIndex[playerId(0)],
          hasType('RemotePlayerClientSprite'));
      // Assert client B representation. 
      expect(worldA.spriteIndex[playerId(1)],
          hasType('RemotePlayerServerSprite'));
      expect(worldB.spriteIndex[playerId(1)],
          hasType('RemotePlayerSprite'));
      expect(worldC.spriteIndex[playerId(1)],
          hasType('RemotePlayerClientSprite'));
      // Assert client C representation.
      expect(worldA.spriteIndex[playerId(2)],
          hasType('RemotePlayerServerSprite'));
      expect(worldB.spriteIndex[playerId(2)],
          hasType('RemotePlayerClientSprite'));
      expect(worldC.spriteIndex[playerId(2)],
          hasType('RemotePlayerSprite'));

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
          hasType('RemotePlayerServerSprite'));
      
      expect(worldC.spriteIndex.count(), equals(2));
          expect(worldC, hasExactSprites([
              hasSpriteWithNetworkId(playerId(1))
                  .andNetworkType(NetworkType.REMOTE),
              hasSpriteWithNetworkId(playerId(2))
                  .andNetworkType(NetworkType.LOCAL),
          ]));
      expect(worldC.spriteIndex[playerId(1)],
          hasType('RemotePlayerClientSprite'));
      expect(worldC.spriteIndex[playerId(2)],
          hasType('RemotePlayerSprite'));
      
      // Now test transferring a sprite over the network.
      MovingSprite sprite = new MovingSprite(1.0, 2.0, imageByName['fire.png']);
      worldB.addSprite(sprite);
      worldB.frameDraw();
      expect(worldB, hasExactSprites([
        hasSpriteWithNetworkId(playerId(1))
            .andNetworkType(NetworkType.LOCAL),
        hasSpriteWithNetworkId(playerId(2))
            .andNetworkType(NetworkType.REMOTE_FORWARD),
        hasSpriteWithNetworkId(sprite.networkId)
            .andNetworkType(NetworkType.LOCAL),
      ]));
      worldB.frameDraw();
      worldC.frameDraw();
      // Sprite gets added to worldC the next frame.
      expect(worldC, hasExactSprites([
         hasSpriteWithNetworkId(playerId(1))
             .andNetworkType(NetworkType.REMOTE),
         hasSpriteWithNetworkId(playerId(2))
             .andNetworkType(NetworkType.LOCAL),
         hasSpriteWithNetworkId(sprite.networkId)
             .andNetworkType(NetworkType.REMOTE),
      ]));
      // Now remove the sprite.
      sprite.remove = true;
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
    
    test('TestGameStateTransfer', () {
      World worldA = testWorld("a");
      World worldB = testWorld("b");
      worldA.startAsServer("nameA");
     
      worldB.connectTo("a", "nameB");

      logConnectionData = true;
      for (int i = 0; i < 3; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldA.frameDraw(KEY_FRAME_DEFAULT);
      }

      // Both worlds are in the same gamestate.
      expect(worldB.network.gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}));
      expect(worldA.network.gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}));

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
      playerBSprite.takeDamage(playerBSprite.health);
      expect(playerBSprite.collision, equals(false));
      expect(playerBSprite.inGame(), equals(false));
      
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);

      // Now look how worldB views this sprite.
      playerBSprite = worldB.spriteIndex[playerId(1)];
      playerBSprite.takeDamage(playerBSprite.health);
      expect(playerBSprite.collision, equals(false));
      expect(playerBSprite.inGame(), equals(false));
    });
    
    test('TestPlayerDeath', () {
      World worldA = testWorld("a");
      World worldB = testWorld("b");
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
      playerBSprite.takeDamage(playerBSprite.health);
      expect(playerBSprite.inGame(), equals(false));

      expect(recentReceviedDataFrom("a"), 
          new MapKeysMatcher.containsKeys([MESSAGE_KEY]));
    });
  });
}