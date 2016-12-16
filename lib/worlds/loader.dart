library loader;

import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';
import 'package:dart2d/worlds/byteworld.dart';

class Loader {
  WormWorld _wormWorld;
  DynamicFactory _canvasFactory;
  ImageIndex _imageIndex;
  var context_;
  int width;
  int height;
  
  DateTime startedAt;
  
  bool completed_ = false;
  
  Loader(@WorldCanvas() Object canvasElement,
         @CanvasFactory() DynamicFactory canvasFactory,
         ImageIndex imageIndex,
         WormWorld wormWorld) {
   this._canvasFactory = canvasFactory;
   // Hack the typesystem.
   var canvas = canvasElement;
   context_ = canvas.context2D;
   width = canvas.width;
   height = canvas.height;
   this._wormWorld = wormWorld;
   this._imageIndex = imageIndex;
  }
  
  String describeStage() {
    if (_wormWorld.network.peer.id == null) {
      if (_wormWorld.peer.getLastError() != null) {
        return "${_wormWorld.peer.getLastError()}";
      }
      return "Waiting for WebRTC init";
    } else if (!_wormWorld.network.hasOpenConnection() && !_wormWorld.network.connectionsExhausted()) {
      return "Attempting to connect to a peer...";
    } else if (!_imageIndex.finishedLoadingImages()) {
      if (_wormWorld.network.hasOpenConnection()) {
        if (!_imageIndex.imagesIndexed()) {
          _imageIndex.loadImagesFromNetwork();
        }
        List<ConnectionWrapper> connections = _wormWorld.network.safeActiveConnections();
        assert(!connections.isEmpty);
        _wormWorld.peer.chunkHelper.requestNetworkData(connections);
        // load from client.
        return "Loading images from other client(s) ${_imageIndex.imagesLoadedString()} ${_wormWorld.peer.chunkHelper.getTransferSpeed()}";
      }
      if (!_imageIndex.imagesIndexed()) {
        // Load everythng from the server.
        _imageIndex.loadImagesFromServer();
      }
      return "Loading images from server ${_imageIndex.imagesLoadedString()}";
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

    if (_imageIndex.finishedLoadingImages()) {
      ConnectionWrapper serverConnection = _wormWorld.network.getServerConnection();
      if (serverConnection == null) {
        _wormWorld.startAsServer("Blergh", false); // true for two players.
      } else {
        // Connect to the actual game.
        serverConnection.connectToGame();
      }
      _wormWorld.byteWorld = new ByteWorld(
          _imageIndex.getImageByName('world.png'),
          new Vec2(width * 1.0,  height * 1.0), _canvasFactory);
      completed_ = true;
      return true;
    }
    return false;
  }
  
  void drawCenteredText(String text) {
    context_.font = "20px Arial";
    var metrics = context_.measureText(text);
    context_.fillText(
        text, width / 2 - metrics.width / 2, height / 2);
  }
}