library loader;

import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';
import 'player_world_selector.dart';
import 'package:dart2d/util/gamestate.dart';

enum LoaderState {
  ERROR,
  WEB_RTC_INIT,
  WAITING_FOR_PEER_DATA,
  CONNECTING_TO_PEER,
  LOADING_SERVER,
  LOADING_OTHER_CLIENT,

  FINDING_SERVER,
  CONNECTING_TO_GAME,
  WAITING_FOR_NAME,
  PLAYER_SELECT,

  LOADING_GAMESTATE,
  LOADING_ENTERING_GAME, // Waiting to enter game.

  // End states.
  LOADING_AS_CLIENT_COMPLETED, // Client ready start game.
  LOADED_AS_SERVER, // Server ready to start game.
}

@Injectable()
class Loader {
  final List<int> GAME_STATE_RESOURCES =
      new List.filled(1, ImageIndex.WORLD_IMAGE_INDEX);
  Network _network;
  PeerWrapper _peerWrapper;
  ImageIndex _imageIndex;
  Map _localStorage;
  ChunkHelper _chunkHelper;
  PlayerWorldSelector _playerWorldSelector;
  var _context;
  int _width;
  int _height;
  
  DateTime startedAt;

  LoaderState _currentState = LoaderState.WEB_RTC_INIT;
  bool _completed = false;

  String _currentMessage = "";

  Loader(@LocalStorage() Map storage,
         @WorldCanvas() Object canvasElement,
         PlayerWorldSelector playerWorldSelector,
         ImageIndex imageIndex,
         Network network,
         ChunkHelper chunkHelper) {
    this._localStorage = storage;
    this._playerWorldSelector = playerWorldSelector;
    this._network = network;
    this._peerWrapper = network.getPeer();
    this._chunkHelper = chunkHelper;
    // Hack the typesystem.
    var canvas = canvasElement;
    _context = canvas.context2D;
    _width = canvas.width;
    _height = canvas.height;
    this._imageIndex = imageIndex;
    // TODO Always remove, change this behavior.
    _localStorage.remove('playerSprite');
  }

  void loaderTick([double duration = 0.01]) {
    if (!_localStorage.containsKey('playerName')) {
      setState(LoaderState.WAITING_FOR_NAME);
      return;
    }
    if (_imageIndex.finishedLoadingImages() && !_localStorage.containsKey('playerSprite')) {
      setState(LoaderState.PLAYER_SELECT);
      _playerWorldSelector.frame(duration);
      return;
    }
    if (_imageIndex.finishedLoadingImages()) {
      this._loaderGameStateTick(duration);
      return;
    }
    if (startedAt == null) {
      startedAt = new DateTime.now();
    }
    _advanceStage(duration);
    drawCenteredText(_currentMessage);
  }

  void _advanceStage(double duration) {
    if (!_peerWrapper.connectedToServer()) {
      if (_peerWrapper.getLastError() != null) {
        this._currentState =  LoaderState.ERROR;
        this._currentMessage = "ERROR: ${_peerWrapper.getLastError()}";
        return;
      }
      setState(LoaderState.WEB_RTC_INIT);
      return;
    }
    if (!_peerWrapper.hasReceivedActiveIds()) {
      setState(LoaderState.WAITING_FOR_PEER_DATA);
      return;
    }
    if (!_network.hasOpenConnection() && !_peerWrapper.connectionsExhausted()) {
      setState(LoaderState.CONNECTING_TO_PEER);
      return;
    }
    if (!_imageIndex.finishedLoadingImages()) {
      _loadImagesStage(duration);
    }
  }

  void _loadImagesStage(double duration) {
    if (_network.hasOpenConnection()) {
      if (!_imageIndex.imagesIndexed()) {
        _imageIndex.loadImagesFromNetwork();
      }
      Map<String, ConnectionWrapper> connections = _network.safeActiveConnections();
      assert(!connections.isEmpty);
      _chunkHelper.requestNetworkData(connections, duration);
      // load from client.
      setState(LoaderState.LOADING_OTHER_CLIENT,
          "Loading images from other client(s) ${_imageIndex.imagesLoadedString()} ${_chunkHelper.getTransferSpeed()}");
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
    setState(LoaderState.LOADING_SERVER,
        "Loading images from server ${_imageIndex.imagesLoadedString()}");
  }

  LoaderState currentState() => _currentState;

  bool hasGameState() => _currentState == LoaderState.LOADING_AS_CLIENT_COMPLETED;
  bool loadedAsServer() => _currentState == LoaderState.LOADED_AS_SERVER;

  void _loaderGameStateTick([double duration = 0.01]) {
    if (loadedAsServer()) {
      return;
    }
    if (_imageIndex.imageIsLoaded(ImageIndex.WORLD_IMAGE_INDEX)) {
      PlayerInfo ourPlayerInfo =_network.getGameState().playerInfoByConnectionId(_network.getPeer().getId());
      if (ourPlayerInfo == null || !ourPlayerInfo.inGame) {
        if (_currentState != LoaderState.LOADING_ENTERING_GAME) {
          ConnectionWrapper serverConnection = _network.getServerConnection();
          if (serverConnection == null) {
            setState(LoaderState.LOADED_AS_SERVER);
            return;
          }
          serverConnection.sendClientEnter();
        }
        setState(LoaderState.LOADING_ENTERING_GAME);
      } else {
        setState(LoaderState.LOADING_AS_CLIENT_COMPLETED);
      }
      return;
    }
    _loadGameStateStage(duration);
    drawCenteredText(_currentMessage);
  }

  void _loadGameStateStage(double duration) {
    if (!_network.hasOpenConnection()) {
      setState(LoaderState.LOADED_AS_SERVER);
      return;
    }
    if (!_network.findServer()) {
      setState(LoaderState.FINDING_SERVER);
      return;
    }
    ConnectionWrapper serverConnection = _network.getServerConnection();
    if (serverConnection == null) {
      setState(LoaderState.LOADED_AS_SERVER);
      return;
    }

    if (!serverConnection.isValidGameConnection()) {
      if (_currentState != LoaderState.CONNECTING_TO_GAME) {
        int playerSpriteId = _imageIndex.getImageIdByName(_localStorage['playerSprite']);
        serverConnection.connectToGame(_localStorage['playerName'], playerSpriteId);
      }
      setState(LoaderState.CONNECTING_TO_GAME);
    } else {
      _chunkHelper.requestSpecificNetworkData(
          {serverConnection.id : serverConnection}, duration,
          GAME_STATE_RESOURCES);
      // TODO figure out percentage of multiple items?
      int percentComplete = (_chunkHelper.getCompleteRatio(GAME_STATE_RESOURCES[0]) * 100).toInt();
      setState(LoaderState.LOADING_GAMESTATE, "Loading gamestate... ${percentComplete}%");
    }
  }
  
  void drawCenteredText(String text, [int y, int size = 20]) {
    if (y == null) {
      y = _height ~/ 2;
    }
    _context.clearRect(0, 0, _width, _height);
    _context.setFillColorRgb(-0, 0, 0);
    _context.font = "${size}px Arial";
    var metrics = _context.measureText(text);
    _context.fillText(
        text, _width / 2 - metrics.width / 2, y);
    _context.save();
  }

  void markCompleted() {
    _completed = true;
  }

  bool completed() => _completed;

  setState(LoaderState state, [String message = null]) {
    this._currentState = state;
    if (message == null) {
      this._currentMessage = _STATE_DESCRIPTIONS[state];
    } else {
      this._currentMessage = message;
    }
    if (_currentMessage == null) {
      throw new StateError("Missing message for ${state}");
    }
  }
}

Map<LoaderState, String> _STATE_DESCRIPTIONS = {
  LoaderState.WEB_RTC_INIT : "Waiting for WebRTC init",
  LoaderState.WAITING_FOR_PEER_DATA : "Fetching list of active peers...",
  LoaderState.CONNECTING_TO_PEER : "Attempting to connect to a peer...",
  LoaderState.LOADING_SERVER: "Loading resources from server...",
  LoaderState.LOADING_OTHER_CLIENT: "Loading resources from client...",

  LoaderState.CONNECTING_TO_GAME: "Connecting to game...",

  LoaderState.WAITING_FOR_NAME: "Waiting to receive a player name...",
  LoaderState.PLAYER_SELECT: "Waiting for player select...",

  LoaderState.FINDING_SERVER: "Finding game to join..",
  LoaderState.LOADING_AS_CLIENT_COMPLETED: "Loading completed.",
  LoaderState.LOADED_AS_SERVER: "Start as server!",
  LoaderState.LOADING_ENTERING_GAME: "Entering game...",
};