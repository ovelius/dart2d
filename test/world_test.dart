import 'package:unittest/unittest.dart';
import 'package:unittest/html_config.dart';
import 'test_connection.dart';
import 'test_peer.dart';
import 'matchers.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/worlds/world.dart';
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

CanvasRenderingContext2D canvas;
ByteWorld byteWorld;

void main() {
  useHtmlConfiguration();
  setUp(() {
    CanvasElement canvasElement = (querySelector("#canvas") as CanvasElement);
    canvas = canvasElement.context2D;
    canvas.clearRect(0, 0, canvasElement.width, canvasElement.height);
    byteWorld = new ByteWorld.fromCanvas(canvasElement, new Vec2());
  });

  group('ByteWorld tests', () {
    test('TestFloodFill', () {
      canvas.fillRect(1, 1, 100, 100);
      expect(WorldPhys.isConnected(byteWorld, 2, 2), equals({'x':1, 'x2':100, 'y':1, 'y2': 100}));
    });
  });
}  
  