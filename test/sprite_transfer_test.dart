import 'package:unittest/unittest.dart';
import 'package:unittest/html_config.dart';
import 'test_connection.dart';
import 'test_peer.dart';
import 'matchers.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/res/imageindex.dart';
import 'dart:html';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

void main() {
  useHtmlConfiguration();
  setUp(() {
    canvas = (querySelector("#canvas") as CanvasElement).context2D;
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
      expect(worldA.sprites[playerId(0)],
          hasType('LocalPlayerSprite'));
      expect(worldB.sprites[playerId(0)],
          hasType('MovingSprite'));
      expect(worldC.sprites[playerId(0)],
          hasType('MovingSprite'));
      // Assert client B representation. 
      expect(worldA.sprites[playerId(1)],
          hasType('RemotePlayerServerSprite'));
      expect(worldB.sprites[playerId(1)],
          hasType('RemotePlayerSprite'));
      expect(worldC.sprites[playerId(1)],
          hasType('MovingSprite'));
      // Assert client C representation.
      expect(worldA.sprites[playerId(2)],
          hasType('RemotePlayerServerSprite'));
      expect(worldB.sprites[playerId(2)],
          hasType('MovingSprite'));
      expect(worldC.sprites[playerId(2)],
          hasType('RemotePlayerSprite'));

      testConnections['a'].forEach((e) { e.dropPackets = 100;});
      
      for (int i = 0; i < 20; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }

      expect(worldB.sprites.length, equals(2));
      expect(worldB, hasExactSprites([
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.LOCAL),
          hasSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.REMOTE_FORWARD),
      ]));
      expect(worldB.sprites[playerId(1)],
          hasType('LocalPlayerSprite'));
      expect(worldB.sprites[playerId(2)],
          hasType('RemotePlayerServerSprite'));
      
      expect(worldC.sprites.length, equals(2));
          expect(worldC, hasExactSprites([
              hasSpriteWithNetworkId(playerId(1))
                  .andNetworkType(NetworkType.REMOTE),
              hasSpriteWithNetworkId(playerId(2))
                  .andNetworkType(NetworkType.LOCAL),
          ]));
      expect(worldC.sprites[playerId(1)],
          hasType('MovingSprite'));
      expect(worldC.sprites[playerId(2)],
          hasType('RemotePlayerSprite'));
    });
  });
}