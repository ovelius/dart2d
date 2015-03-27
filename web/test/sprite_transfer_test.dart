import 'package:unittest/unittest.dart';
import 'package:unittest/html_config.dart';
import 'test_connection.dart';
import 'test_peer.dart';
import 'matchers.dart';
import '../rtc.dart';
import '../connection.dart';
import '../sprite.dart';
import '../playersprite.dart';
import '../world.dart';
import '../gamestate.dart';
import '../net.dart';
import '../state_updates.dart';
import '../imageindex.dart';
import 'dart:js';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

void main() {
  useHtmlConfiguration();
  setUp(() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((LogRecord rec) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
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
      expect(worldA, hasSpriteWithNetworkId(0)
          .andNetworkType(NetworkType.LOCAL));
      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      expect(worldA, hasExactSprites([
          hasSpriteWithNetworkId(0)
              .andNetworkType(NetworkType.LOCAL),
          hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT)
              .andNetworkType(NetworkType.REMOTE_FORWARD),
          hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT * 2)
              .andNetworkType(NetworkType.REMOTE_FORWARD),
      ]));
      expect(worldB, hasExactSprites([
            hasSpriteWithNetworkId(0)
                .andNetworkType(NetworkType.REMOTE),
            hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT)
                .andNetworkType(NetworkType.LOCAL),
            hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT * 2)
                .andNetworkType(NetworkType.REMOTE),
      ]));
      // Assert server A representation.
      expect(worldA.sprites[0],
          hasType('LocalPlayerSprite'));
      expect(worldB.sprites[0],
          hasType('MovingSprite'));
      expect(worldC.sprites[0],
          hasType('MovingSprite'));
      // Assert client B representation. 
      expect(worldA.sprites[GameState.ID_OFFSET_FOR_NEW_CLIENT],
          hasType('RemotePlayerServerSprite'));
      expect(worldB.sprites[GameState.ID_OFFSET_FOR_NEW_CLIENT],
          hasType('RemotePlayerSprite'));
      expect(worldC.sprites[GameState.ID_OFFSET_FOR_NEW_CLIENT],
          hasType('MovingSprite'));
      // Assert client C representation.
      expect(worldA.sprites[GameState.ID_OFFSET_FOR_NEW_CLIENT * 2],
          hasType('RemotePlayerServerSprite'));
      expect(worldB.sprites[GameState.ID_OFFSET_FOR_NEW_CLIENT * 2],
          hasType('MovingSprite'));
      expect(worldC.sprites[GameState.ID_OFFSET_FOR_NEW_CLIENT * 2],
          hasType('RemotePlayerSprite'));

      testConnections['a'].forEach((e) { e.dropPackets = 100;});
      
      for (int i = 0; i < 20; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }

      expect(worldB.sprites.length, equals(2));
      expect(worldB, hasExactSprites([
          hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT)
              .andNetworkType(NetworkType.LOCAL),
          hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT * 2)
              .andNetworkType(NetworkType.REMOTE_FORWARD),
      ]));
      expect(worldB.sprites[GameState.ID_OFFSET_FOR_NEW_CLIENT],
          hasType('LocalPlayerSprite'));
      expect(worldB.sprites[GameState.ID_OFFSET_FOR_NEW_CLIENT * 2],
          hasType('RemotePlayerServerSprite'));
      
      expect(worldC.sprites.length, equals(2));
          expect(worldC, hasExactSprites([
              hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT)
                  .andNetworkType(NetworkType.REMOTE),
              hasSpriteWithNetworkId(GameState.ID_OFFSET_FOR_NEW_CLIENT * 2)
                  .andNetworkType(NetworkType.LOCAL),
          ]));
      expect(worldC.sprites[GameState.ID_OFFSET_FOR_NEW_CLIENT],
          hasType('MovingSprite'));
      expect(worldC.sprites[GameState.ID_OFFSET_FOR_NEW_CLIENT * 2],
          hasType('RemotePlayerSprite'));
    });
  });
}