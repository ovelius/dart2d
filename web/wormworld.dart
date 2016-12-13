library spaceworld;

import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'dart:js';
import 'package:di/di.dart';
import 'package:dart2d/net/rtc.dart';
import 'dart:html';
import 'dart:async';

final int WIDTH = (querySelector("#canvas") as CanvasElement).width;
final int HEIGHT = (querySelector("#canvas") as CanvasElement).height;
const bool USE_LOCAL_HOST_PEER = true;
const Duration TIMEOUT = const Duration(milliseconds: 21);

DateTime lastStep;
World world;

void main() {
  context['onSignIn'] = (param) {
    JsObject user = param;
    JsObject profile = user.callMethod('getBasicProfile');
    String name = profile.callMethod('getName');
    (querySelector("#nameInput") as InputElement).value = name;
    world.playerName = name;
  };

  var canvasElement = (querySelector("#canvas") as CanvasElement);

  var peer = USE_LOCAL_HOST_PEER ? createLocalHostPeerJs() : createPeerJs();

  var injector = new ModuleInjector([new Module()
     ..bind(int, withAnnotation: const WorldWidth(), toValue: WIDTH)
     ..bind(int, withAnnotation: const WorldHeight(), toValue: HEIGHT)
     ..bind(CanvasMarker, withAnnotation: const WorldCanvas(),  toValue: canvasElement)
     ..bind(PeerMarker,  toValue: peer)
     ..bind(WormWorld)
  ]);
  world = injector.get(WormWorld);

  setKeyListeners(world, canvasElement);

  querySelector("#clientBtn").onClick.listen((e) {
    var clientId = (querySelector("#clientId") as InputElement).value;
    var name = (querySelector("#nameInput") as InputElement).value;
    world.restart = true;
    world.connectTo(clientId);
  });

  querySelector("#sendMsg").onClick.listen((e) {
    var message = (querySelector("#chatMsg") as InputElement).value;
    world.hudMessages.displayAndSendToNetwork(
        "${world.network.localPlayerName}: ${message}");
  });

  startTimer();
}

void setKeyListeners(WormWorld world, var canvasElement) {
  document.window.addEventListener("keydown", world.localKeyState.onKeyDown);
  document.window.addEventListener("keyup", world.localKeyState.onKeyUp);

  canvasElement.addEventListener("keydown", world.localKeyState.onKeyDown);
  canvasElement.addEventListener("keyup", world.localKeyState.onKeyUp);
}

void startTimer() {
  lastStep = new DateTime.now();
  new Timer(TIMEOUT, step);
}

void step() {
  DateTime startStep = new DateTime.now();

  DateTime now = new DateTime.now();
  int millis = now.millisecondsSinceEpoch - lastStep.millisecondsSinceEpoch;
  assert(millis >= 0);
  double secs = millis / 1000.0;
  if (secs >= 0.041) {
    // Slow down the game instead of skipping frames.
    secs = 0.041;
  }
  world.frameDraw(secs);
  lastStep = now;

  int frameTimeMillis = new DateTime.now().millisecondsSinceEpoch -
      startStep.millisecondsSinceEpoch;
  if (frameTimeMillis > TIMEOUT.inMilliseconds) {}
  new Timer(TIMEOUT - new Duration(milliseconds: frameTimeMillis), step);
}
