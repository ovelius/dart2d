library spaceworld;

import 'package:dart2d/bootstrap.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/res/imageindex.dart';
import 'dart:js';
import 'dart:html';

final int WIDTH = (querySelector("#canvas") as CanvasElement).width;
final int HEIGHT = (querySelector("#canvas") as CanvasElement).height;

void main() {
  context['onSignIn'] = (param) {
     JsObject user = param;
     JsObject profile = user.callMethod('getBasicProfile');
     String name = profile.callMethod('getName');
     (querySelector("#nameInput") as InputElement).value = name;
     world.playerName = name;
  };
  
  canvasElement = (querySelector("#canvas") as CanvasElement);
  canvas = canvasElement.context2D;
  world = new WormWorld(WIDTH, HEIGHT);
  document.window.addEventListener("keydown", world.localKeyState.onKeyDown);
  document.window.addEventListener("keyup", world.localKeyState.onKeyUp);
  
  bootstrapWorld(world);
  
  querySelector("#clientBtn").onClick.listen((e) {
    var clientId = (querySelector("#clientId") as InputElement).value;
    var name = (querySelector("#nameInput") as InputElement).value;
    world.restart = true;
    world.connectTo(clientId);
  });
  
  querySelector("#sendMsg").onClick.listen((e) {
    var message = (querySelector("#chatMsg") as InputElement).value;
    world.hudMessages.displayAndSendToNetwork("${world.network.localPlayerName}: ${message}");
  });
}


