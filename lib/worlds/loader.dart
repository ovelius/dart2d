library loader;

import 'dart:html';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'dart:async';

class Loader {
  WormWorld wormWorld_;
  CanvasElement canvas_;
  CanvasRenderingContext2D context_;
  int width;
  int height;
  
  bool completed_ = false;
  
  Loader(this.canvas_, this.wormWorld_) {
    context_ = canvas_.context2D;
    width = canvas_.width;
    height = canvas_.height;
  }
  
  String describeStage() {
    if (wormWorld_.network.peer.id == null) {
      return "Waiting for WebRTC init";
    } else if (!finishedLoadingImages()) {
      loadImages();
      return "Loading images ${imagesLoadedString()}";
    }
    return "Unkown state";
  }
  
  bool frameDraw([double duration = 0.01]) {
    if (completed_) {
      return true;
    }
    context_.clearRect(0, 0, width, height);
    context_.setFillColorRgb(-0, 0, 0);
    drawCenteredText(describeStage());
    context_.save();

    if (finishedLoadingImages()) {
      wormWorld_.startAsServer("Blergh", false); // true for two players. 
      wormWorld_.byteWorld = new ByteWorld(imageByName['mattehorn.png'], new Vec2(width * 1.0,  height * 1.0));
      completed_ = true;
      return true;
    }
    return false;
  }
  
  void drawCenteredText(String text) {
    context_.font = "30px Arial";
    TextMetrics metrics = context_.measureText(text);
    context_.fillText(
        text, width / 2 - metrics.width / 2, height / 2);
  }
}