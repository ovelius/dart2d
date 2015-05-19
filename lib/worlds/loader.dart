library loader;

import 'dart:html';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';
import 'package:dart2d/worlds/byteworld.dart';
import 'dart:async';

class Loader {
  static const Duration IMAGE_RETRY_DURATION = const Duration(milliseconds: 3000);
  WormWorld wormWorld_;
  CanvasElement canvas_;
  CanvasRenderingContext2D context_;
  int width;
  int height;
  
  DateTime startedAt;
  
  bool completed_ = false;
  
  Map<String, DateTime> lastImageRequest = new Map();
  
  Loader(this.canvas_, this.wormWorld_) {
    context_ = canvas_.context2D;
    width = canvas_.width;
    height = canvas_.height;
  }
  
  String describeStage() {
    if (wormWorld_.network.peer.id == null) {
      return "Waiting for WebRTC init";
    } else if (!wormWorld_.network.hasReadyConnection() && !wormWorld_.network.connectionsExhausted()) {
      return "Attempting to connect to a peer...";
    } else if (!finishedLoadingImages()) {
      // TODO: Support loading from client.
      /*
      if (wormWorld_.network.hasReadyConnection()) {
        if (!imagesIndexed()) {
          loadImagesFromNetwork();
        }
        requestNetworkData();
        // load from client.
        return "Loading images from other client ${imagesLoadedString()}";
      }*/
      if (!imagesIndexed()) {
        // Load everythng from the server.
        loadImagesFromServer();
      }
      return "Loading images from server ${imagesLoadedString()}";
    }
    return "Unkown state";
  }
  
  bool frameDraw([double duration = 0.01]) {
    if (completed_) {
      return true;
    }
    if (startedAt == null) {
      startedAt = new DateTime.now();
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
  
  void requestNetworkData() {
    int requestedImages = 0;
    for (String name in imageByName.keys) {
      // Don't request more than 2 images at a time.
      if (requestedImages > 2 && loadedImages[name] != true) {
        lastImageRequest[name] = new DateTime.now();
        continue;
      }
      if (maybeRequestImageLoad(name)) {
        requestedImages++; 
      }
    }
  }
  
  bool maybeRequestImageLoad(String name) {
    DateTime now = new DateTime.now();
    if (loadedImages[name] != true) {
      DateTime lastRequest = lastImageRequest[name];
      if (lastRequest == null || now.difference(lastRequest).inMilliseconds > IMAGE_RETRY_DURATION.inMilliseconds) {
        return requestImageData(name);
      }
    }
    return false;
  }
  
  /**
   * Request image data from a random connection.
   */
  bool requestImageData(String name) {
    print("requesting image ${name}");
    Random r = new Random();
    List<ConnectionWrapper> connections = wormWorld_.network.safeActiveConnections();
    // There is a case were a connection is added, but not yet ready for data transfer :/
    if (connections.length > 0) {
      print("got these ${connections}");
      ConnectionWrapper connection = connections[r.nextInt(connections.length)];
      connection.sendData({IMAGE_DATA_REQUEST:name});
      lastImageRequest[name] = new DateTime.now();
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