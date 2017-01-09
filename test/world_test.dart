import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/phys/vec2.dart';

ByteWorld byteWorld;

void main() {
  setUp(() {
    testConnections.clear();
    testPeers.clear();
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
      
      _TestSprite sprite = new _TestSprite.withVecPosition(new Vec2());
      
      worldA.addSprite(sprite);
      worldA.frameDraw();

      expect(sprite.drawCalls, equals(1));
      expect(sprite.frameCalls, equals(1));
      
      sprite.position = new Vec2(worldA.width() * 1.0, worldA.height() * 1.0);
      
      worldA.frameDraw();
      expect(sprite.drawCalls, equals(2));
      expect(sprite.frameCalls, equals(2));
      
      sprite.position = new Vec2(worldA.width() * 1.0 + 1, worldA.height() * 1.0 + 1);
           
      worldA.frameDraw();
      expect(sprite.drawCalls, equals(2));
      expect(sprite.frameCalls, equals(3));
    });
  });
}

class _TestSprite extends Sprite {
  int drawCalls = 0;
  int frameCalls = 0;
  _TestSprite.withVecPosition(Vec2 position)
        : super(position, new Vec2(1.0, 1.0), SpriteType.RECT);
  
  @override
  frame(double duration, int frameStep, [Vec2 gravity]) {
    frameCalls++;
  }
  
  @override
  draw(var context, bool debug) {
    drawCalls++;
  }
}
