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
  static const WAITING_FOR_PEER_DATA = const LoaderState._internal(7, "Fetching list of active peers...");
  static const CONNECTING_TO_PEER = const LoaderState._internal(3, "Attempting to connect to a peer...");
  static const LOADING_SERVER = const LoaderState._internal(4, "Loading resources from server...");
  static const LOADING_OTHER_CLIENT = const LoaderState._internal(5, "Loading resources from client...");

  static const LOADING_RESOURCES_COMPLETED = const LoaderState._internal(6, "Completed loading resources.");

  static const LOADING_GAMESTATE =  const LoaderState._internal(8, "Loading gamestate...");
  static const LOADING_GAMESTATE_COMPLETED =  const LoaderState._internal(9, "All done.");

  operator ==(LoaderState other) {
    return value == other.value;
  }
}

@Injectable() // TODO make fully injectable.
class Loader {
  final List<int> GAME_STATE_RESOURCES =
      new List.filled(1, ImageIndex.WORLD_IMAGE_INDEX);
  Network _network;
  PeerWrapper _peerWrapper;
  ImageIndex _imageIndex;
  var context_;
  int width;
  int height;
  
  DateTime startedAt;

  LoaderState _currentState = LoaderState.UNKNOWN;
  
  Loader(@WorldCanvas() Object canvasElement,
         ImageIndex imageIndex,
         Network network,
         PeerWrapper peerWrapper) {
   this._network = network;
   this._peerWrapper = peerWrapper;
   // Hack the typesystem.
   var canvas = canvasElement;
   context_ = canvas.context2D;
   width = canvas.width;
   height = canvas.height;
   this._imageIndex = imageIndex;
  }

  void _advanceStage(double duration) {
    if (_peerWrapper.id == null) {
      if (_peerWrapper.getLastError() != null) {
        this._currentState = new LoaderState._internal(2, "${_peerWrapper.getLastError()}");
        return;
      }
      this._currentState = LoaderState.WEB_RTC_INIT;
      return;
    } else if (!_peerWrapper.hasReceivedActiveIds()) {
      this._currentState =  LoaderState.WAITING_FOR_PEER_DATA;
      return;
    } if (!_network.hasOpenConnection() && !_peerWrapper.connectionsExhausted()) {
      this._currentState =  LoaderState.CONNECTING_TO_PEER;
      return;
    } else if (!_imageIndex.finishedLoadingImages()) {
      if (_network.hasOpenConnection()) {
        if (!_imageIndex.imagesIndexed()) {
          _imageIndex.loadImagesFromNetwork();
        }
        List<ConnectionWrapper> connections = _network.safeActiveConnections();
        assert(!connections.isEmpty);
        _peerWrapper.chunkHelper.requestNetworkData(connections, duration);
        // load from client.
        _currentState = new LoaderState._internal(
            5, "Loading images from other client(s) ${_imageIndex.imagesLoadedString()} ${_peerWrapper.chunkHelper.getTransferSpeed()}");
        return;
      }

      // Either we
      // 1) Didn't find a client to load data from OR
      // 2) We're currently in the state of loading form other client.
      // But somehow the connection closed on us :(
      if (!_imageIndex.imagesIndexed()
          || _currentState == LoaderState.LOADING_OTHER_CLIENT) {
        // Load everythng from the server.
        _imageIndex.loadImagesFromServer();
      }
      _currentState = new LoaderState._internal(
          4, "Loading images from server ${_imageIndex.imagesLoadedString()}");
      return;
    }
  }

  LoaderState currentState() => _currentState;
  
  bool completedResources() => (_currentState == LoaderState.LOADING_RESOURCES_COMPLETED
      || hasGameState());

  bool hasGameState() => _currentState == LoaderState.LOADING_GAMESTATE_COMPLETED;
  
  void loaderTick([double duration = 0.01]) {
    if (_imageIndex.finishedLoadingImages()) {
      _currentState = LoaderState.LOADING_RESOURCES_COMPLETED;
      return;
    }
    if (startedAt == null) {
      startedAt = new DateTime.now();
    }
    _advanceStage(duration);
    drawCenteredText(currentState().description);
  }

  void loaderGameStateTick([double duration = 0.01]) {
    if (_imageIndex.imageIsLoaded(ImageIndex.WORLD_IMAGE_INDEX)) {
      _currentState = LoaderState.LOADING_GAMESTATE_COMPLETED;
      return;
    }
    _loadGameStateStage(duration);
    drawCenteredText(currentState().description);
  }

  void _loadGameStateStage(double duration) {
    ConnectionWrapper serverConnection = _network.getServerConnection();
    if (serverConnection == null) {
      // TODO: Handle this.
      throw new StateError("No server connection!");
    }
    _peerWrapper.chunkHelper.requestSpecificNetworkData(
        new List.filled(1, serverConnection), duration, GAME_STATE_RESOURCES);
    this._currentState == LoaderState.LOADING_GAMESTATE;
  }
  
  void drawCenteredText(String text) {
    context_.clearRect(0, 0, width, height);
    context_.setFillColorRgb(-0, 0, 0);
    context_.font = "20px Arial";
    var metrics = context_.measureText(text);
    context_.fillText(
        text, width / 2 - metrics.width / 2, height / 2);
    context_.save();
  }

  setStateForTest(LoaderState state) {
    this._currentState = state;
  }
}