library loader;

import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/rtc.dart';
import 'package:di/di.dart';
import 'package:dart2d/worlds/byteworld.dart';


class LoaderState {
  final value;
  final String description;
  const LoaderState._internal(this.value, this.description);
  toString() => 'Enum.$value';

  static const UNKNOWN = const LoaderState._internal(0, "Unkown");
  static const ERROR = const LoaderState._internal(1, "Error");
  static const WEB_RTC_INIT = const LoaderState._internal(2, "Waiting for WebRTC init");
  static const CONNECTING_TO_PEER = const LoaderState._internal(3, "Attempting to connect to a peer...");
  static const LOADING_SERVER = const LoaderState._internal(4, "Loading resources from server...");
  static const LOADING_OTHER_CLIENT = const LoaderState._internal(5, "Loading resources from client...");
  static const LOADING_COMPLETED = const LoaderState._internal(6, "Completed");

  operator ==(LoaderState other) {
    return value == other.value;
  }
}

@Injectable() // TODO make fully injectable.
class Loader {
  WormWorld _wormWorld;
  Network _network;
  PeerWrapper _peerWrapper;
  DynamicFactory _canvasFactory;
  ImageIndex _imageIndex;
  var context_;
  int width;
  int height;
  
  DateTime startedAt;
  
  bool completed_ = false;
  String _currentState = LoaderState.UNKNOWN.description;
  
  Loader(@WorldCanvas() Object canvasElement,
         @CanvasFactory() DynamicFactory canvasFactory,
         ImageIndex imageIndex,
         WormWorld wormWorld,
         Network network,
         PeerWrapper peerWrapper) {
   this._network = network;
   this._peerWrapper = peerWrapper;
   this._canvasFactory = canvasFactory;
   // Hack the typesystem.
   var canvas = canvasElement;
   context_ = canvas.context2D;
   width = canvas.width;
   height = canvas.height;
   this._wormWorld = wormWorld;
   this._imageIndex = imageIndex;
  }

  LoaderState describeStage() {
    if (_peerWrapper.id == null) {
      if (_peerWrapper.getLastError() != null) {
        this._currentState = "${_peerWrapper.getLastError()}";
        return LoaderState.ERROR;
      }
      return LoaderState.WEB_RTC_INIT;
    } else if (!_network.hasOpenConnection() && !_network.connectionsExhausted()) {
      return LoaderState.CONNECTING_TO_PEER;
    } else if (!_imageIndex.finishedLoadingImages()) {
      if (_network.hasOpenConnection()) {
        if (!_imageIndex.imagesIndexed()) {
          _imageIndex.loadImagesFromNetwork();
        }
        List<ConnectionWrapper> connections = _network.safeActiveConnections();
        assert(!connections.isEmpty);
        _peerWrapper.chunkHelper.requestNetworkData(connections);
        // load from client.
        _currentState = "Loading images from other client(s) ${_imageIndex.imagesLoadedString()} ${_peerWrapper.chunkHelper.getTransferSpeed()}";
        return LoaderState.LOADING_OTHER_CLIENT;
      }
      if (!_imageIndex.imagesIndexed()) {
        // Load everythng from the server.
        _imageIndex.loadImagesFromServer();
      }
      _currentState = "Loading images from server ${_imageIndex.imagesLoadedString()}";
      return LoaderState.LOADING_SERVER;
    }
    return LoaderState.UNKNOWN;
  }

  String currentStateAsString() => _currentState;
  
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
    drawCenteredText(currentStateAsString());
    context_.save();

    if (_imageIndex.finishedLoadingImages()) {
      ConnectionWrapper serverConnection = _network.getServerConnection();
      if (serverConnection == null) {
        _wormWorld.startAsServer(); // true for two players.
      } else {
        // Connect to the actual game.
        serverConnection.connectToGame();
      }
      // Move elsewhere to allow choosing map...
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