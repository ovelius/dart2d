library dart2d;

import 'imageindex.dart';
import 'playersprite.dart';
import 'stickysprite.dart';
import 'sprite.dart';
import 'keystate.dart';
import 'net.dart';
import 'movingsprite.dart';
import 'phys.dart';
import 'rtc.dart';
import 'vec2.dart';
import 'world.dart';
import 'dart:html';
import 'dart:math';
import 'dart:async';

final CanvasRenderingContext2D context =
  (querySelector("#canvas") as CanvasElement).context2D;
final int WIDTH = (querySelector("#canvas") as CanvasElement).width;
final int HEIGHT = (querySelector("#canvas") as CanvasElement).height;

const TIMEOUT = const Duration(milliseconds: 21);
DateTime lastStep;

// 25 server frames per second.
const FRAME_SPEED = 1.0/25;
double untilNextFrame = FRAME_SPEED;
int serverFrame = 0;
World world;

void main() {
  loadImages().then((_) {
    var name = (querySelector("#nameInput") as InputElement).value;
    world.startAsServer(name, true); 
  });
  // createPeerJs()
  world = new World(WIDTH, HEIGHT, createLocalHostPeerJs());
  document.window.addEventListener("keydown", world.localKeyState.onKeyDown);
  document.window.addEventListener("keyup", world.localKeyState.onKeyUp);
  
  querySelector("#clientBtn").onClick.listen((e) {
    var clientId = (querySelector("#clientId") as InputElement).value;
    var name = (querySelector("#nameInput") as InputElement).value;
    world.restart = true;
    world.connectTo(clientId, name);
    world.hudMessages.display("Connecting to ${clientId}");
  });
  
  querySelector("#sendMsg").onClick.listen((e) {
    var message = (querySelector("#chatMsg") as InputElement).value;
    world.hudMessages.displayAndSendToNetwork("${world.network.localPlayerName}: ${message}");
  });

  lastStep = new DateTime.now();
  new Timer(TIMEOUT, step);
}

void step() {
  DateTime startStep = new DateTime.now();
 
  DateTime now = new DateTime.now();
  int millis = now.millisecondsSinceEpoch - lastStep.millisecondsSinceEpoch;
  assert(millis >= 0);
  double secs = millis / 1000.0;
  assert(secs >= 0.0);
  world.frameDraw(secs);
  lastStep = now;
  
  int frameTimeMillis = new DateTime.now().millisecondsSinceEpoch - startStep.millisecondsSinceEpoch;
  new Timer(TIMEOUT - new Duration(milliseconds: frameTimeMillis), step);
}
