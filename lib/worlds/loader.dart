library loader;

import 'dart:html';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';
import 'package:dart2d/worlds/byteworld.dart';

class Loader {
  WormWorld _wormWorld;
  CanvasFactory _canvasFactory;
  var context_;
  int width;
  int height;
  
  DateTime startedAt;
  
  bool completed_ = false;
  
  Loader(@WorldCanvas() CanvasMarker canvasElement,
         CanvasFactory canvasFactory,
         WormWorld wormWorld) {
   this._canvasFactory = canvasFactory;
   context_ = canvasElement.context2D;
   width = canvasElement.width;
   height = canvasElement.height;
   this._wormWorld = wormWorld;
  }
  
  String describeStage() {
    if (_wormWorld.network.peer.id == null) {
      return "Waiting for WebRTC init";
    } else if (!_wormWorld.network.hasOpenConnection() && !_wormWorld.network.connectionsExhausted()) {
      return "Attempting to connect to a peer...";
    } else if (!finishedLoadingImages()) {
      if (_wormWorld.network.hasOpenConnection()) {
        if (!imagesIndexed()) {
          loadImagesFromNetwork();
        }
        List<ConnectionWrapper> connections = _wormWorld.network.safeActiveConnections();
        assert(!connections.isEmpty);
        _wormWorld.peer.chunkHelper.requestNetworkData(connections);
        // load from client.
        return "Loading images from other client(s) ${imagesLoadedString()} ${_wormWorld.peer.chunkHelper.getTransferSpeed()}";
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
      ConnectionWrapper serverConnection = _wormWorld.network.getServerConnection();
      if (serverConnection == null) {
        _wormWorld.startAsServer("Blergh", false); // true for two players.
      } else {
        // Connect to the actual game.
        serverConnection.connectToGame();
      }
      _wormWorld.byteWorld = new ByteWorld(imageByName['world.png'], new Vec2(width * 1.0,  height * 1.0), _canvasFactory);
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