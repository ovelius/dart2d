import 'package:test/test.dart';
import 'test_connection.dart';
import 'test_peer.dart';
import 'matchers.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/world_phys.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/net/net.dart';

import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/res/imageindex.dart';
import 'dart:html';
import 'dart:async';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

ByteWorld byteWorld;

void main() {
  setUp(() {
    testConnections.clear();
    testPeers.clear();
    canvasElement = (querySelector("#canvas") as CanvasElement);
    canvas = canvasElement.context2D;
    canvas.clearRect(0, 0, canvasElement.width, canvasElement.height);
    useEmptyImagesForTest();
    byteWorld = new ByteWorld.fromCanvas(canvasElement, new Vec2());
  });

  group('ByteWorld tests', () {
    test('TestFloodFill', () {
      // TODO: fix.
      // canvas.fillRect(1, 1, 100, 100);
      // expect(WorldPhys.isConnected(byteWorld, 2, 2), equals({'x':1, 'x2':100, 'y':1, 'y2': 100}));
    });
    test('TestDontDrawOutsideScreen', () {
      WormWorld worldA = testWorld("a");
      worldA.viewPoint = new Vec2();
      worldA.startAsServer("a");
      worldA.frameDraw();
      worldA.spriteIndex[playerId(0)].position = new Vec2();
      
      _TestSprite sprite = new _TestSprite.withVecPosition(new Vec2(), imageByName['fire.png']);
      
      worldA.addSprite(sprite);
      worldA.frameDraw();

      expect(sprite.drawCalls, equals(1));
      expect(sprite.frameCalls, equals(1));
      
      sprite.position = new Vec2(WIDTH * 1.0, HEIGHT * 1.0);
      
      worldA.frameDraw();
      expect(sprite.drawCalls, equals(2));
      expect(sprite.frameCalls, equals(2));
      
      sprite.position = new Vec2(WIDTH * 1.0 + 1, HEIGHT * 1.0 + 1);
           
      worldA.frameDraw();
      expect(sprite.drawCalls, equals(2));
      expect(sprite.frameCalls, equals(3));
    });
  });
}  
 

class _TestSprite extends Sprite {
  int drawCalls = 0;
  int frameCalls = 0;
  
  _TestSprite.withVecPosition(Vec2 position, int imageIndex)
        : super.withVec2(position, imageIndex, new Vec2(1.0, 1.0));
  
  @override
  frame(double duration, int frameStep, [Vec2 gravity]) {
    frameCalls++;
  }
  
  @override
  draw(CanvasRenderingContext2D context, bool debug) {
    drawCalls++;
  }
}
