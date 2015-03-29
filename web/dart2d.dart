library dart2d;

import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/playersprite.dart';
import 'package:dart2d/sprites/stickysprite.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/phys/phys.dart';
import 'package:dart2d/net/rtc.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/worlds/space_world.dart';
import 'package:dart2d/worlds/world.dart';
import 'dart:html';
import 'dart:math';
import 'dart:async';

final int WIDTH = (querySelector("#canvas") as CanvasElement).width;
final int HEIGHT = (querySelector("#canvas") as CanvasElement).height;

const TIMEOUT = const Duration(milliseconds: 21);
DateTime lastStep;

World world;

void main() {
  canvas = (querySelector("#canvas") as CanvasElement).context2D;
  loadImages().then((_) {
    // Starting the server here will have no peerId.
    // var name = (querySelector("#nameInput") as InputElement).value;
    // world.startAsServer(name, true); 
  });
  world = new SpaceWorld(WIDTH, HEIGHT,  createPeerJs() /*createLocalHostPeerJs() */);
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
