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
import 'package:dart2d/bootstrap.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/worlds/space_world.dart';
import 'package:dart2d/worlds/world.dart';
import 'dart:html';
import 'dart:math';
import 'dart:async';

final int WIDTH = (querySelector("#canvas") as CanvasElement).width;
final int HEIGHT = (querySelector("#canvas") as CanvasElement).height;

void main() {
  canvas = (querySelector("#canvas") as CanvasElement).context2D;
  world = new SpaceWorld(WIDTH, HEIGHT);
  document.window.addEventListener("keydown", world.localKeyState.onKeyDown);
  document.window.addEventListener("keyup", world.localKeyState.onKeyUp);
  
  bootstrapWorld(world);
  
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
}


