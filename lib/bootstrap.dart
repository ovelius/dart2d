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

const TIMEOUT = const Duration(milliseconds: 21);
DateTime lastStep;

World world;

void bootstrapWorld(World world) {
  loadImages();
  var peer = createPeerJs() /*createLocalHostPeerJs() */;
  world.setJsPeer(peer);
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