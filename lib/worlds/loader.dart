library loader;

import 'dart:html';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:di/di.dart';
import 'package:dart2d/worlds/byteworld.dart';

class Loader {
  WormWorld wormWorld_;
  var canvas_;
  var context_;
  int width;
  int height;
  
  DateTime startedAt;
  
  bool completed_ = false;
  
  Loader(this.canvas_, this.wormWorld_) {
    context_ = canvas_.context2D;
    width = canvas_.width;
    height = canvas_.height;
  }
  
  String describeStage() {
    if (wormWorld_.network.peer.id == null) {
      return "Waiting for WebRTC init";
    } else if (!wormWorld_.network.hasOpenConnection() && !wormWorld_.network.connectionsExhausted()) {
      return "Attempting to connect to a peer...";
    } else if (!finishedLoadingImages()) {
      if (wormWorld_.network.hasOpenConnection()) {
        if (!imagesIndexed()) {
          loadImagesFromNetwork();
        }
        List<ConnectionWrapper> connections = wormWorld_.network.safeActiveConnections();
        assert(!connections.isEmpty);
        wormWorld_.peer.chunkHelper.requestNetworkData(connections);
        // load from client.
        return "Loading images from other client(s) ${imagesLoadedString()} ${wormWorld_.peer.chunkHelper.getTransferSpeed()}";
      }
      if (!imagesIndexed()) {
        // Load everythng from the server.
        loadImagesFromServer();
      }
      return "Loading images from server ${imagesLoadedString()}";
    }
    return "Unkown state";
  }
  
  bool completed() => completed_;
  
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
      ConnectionWrapper serverConnection = wormWorld_.network.getServerConnection();
      if (serverConnection == null) {
        wormWorld_.startAsServer("Blergh", false); // true for two players.
      } else {
        // Connect to the actual game.
        serverConnection.connectToGame();
      }
      wormWorld_.byteWorld = new ByteWorld(imageByName['world.png'], new Vec2(width * 1.0,  height * 1.0));
      completed_ = true;
      return true;
    }
    return false;
  }
  
  void drawCenteredText(String text) {
    context_.font = "20px Arial";
    TextMetrics metrics = context_.measureText(text);
    context_.fillText(
        text, width / 2 - metrics.width / 2, height / 2);
  }
}