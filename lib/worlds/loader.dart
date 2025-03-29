import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'player_world_selector.dart';
import 'package:dart2d/util/gamestate.dart';

enum LoaderState {
  ERROR,
  WEB_RTC_INIT,
  WAITING_FOR_PEER_DATA,
  CONNECTING_TO_PEER,
  // Loading images from server..
  LOADING_SERVER,
  LOADING_OTHER_CLIENT,

  FINDING_SERVER,
  CONNECTING_TO_GAME,
  WAITING_FOR_NAME,
  PLAYER_SELECT,
  WORLD_SELECT,
  WORLD_LOADING,

  LOADING_GAMESTATE,
  LOADING_ENTERING_GAME, // Waiting to enter game.

  // End states.
  LOADING_AS_CLIENT_COMPLETED, // Client ready start game.
  LOADED_AS_SERVER, // Server ready to start game.
}

// What is a reasonable transfer speed when loading from other clients?
const ACCEPTABLE_TRANSFER_SPEED_BYTES_SECOND = 1024*70;
// How many of slow samples we accept before loading from server instead.
const SAMPLES_BEFORE_FALLBACK = 3;

@Singleton(scope: 'world')
class Loader {
  final Logger log = new Logger('Loader');
  final List<int> GAME_STATE_RESOURCES =
      new List.filled(1, ImageIndex.WORLD_IMAGE_INDEX);
  late Network _network;
  late PeerWrapper _peerWrapper;
  late ImageIndex _imageIndex;
  late LocalStorage _localStorage;
  late ChunkHelper _chunkHelper;
  late PlayerWorldSelector _playerWorldSelector;
  var _context;
  late int _width;
  late int _height;

  // When we started loading data.
  DateTime? startedAt;
  // How many samples we have that indicates a slow data transfer.
  int _slowDownloadRateSamples = 0;

  LoaderState _currentState = LoaderState.WEB_RTC_INIT;
  bool _completed = false;

  String _currentMessage = "";

  Loader(LocalStorage storage,
         WorldCanvas canvasElement,
         PlayerWorldSelector playerWorldSelector,
         ImageIndex imageIndex,
         Network network,
         ChunkHelper chunkHelper) {
    this._localStorage = storage;
    this._playerWorldSelector = playerWorldSelector;
    this._network = network;
    this._peerWrapper = network.getPeer();
    this._chunkHelper = chunkHelper;
    _context = canvasElement.context2D;
    _width = canvasElement.width;
    _height = canvasElement.height;
    this._imageIndex = imageIndex;
  }

  void loaderTick([double duration = 0.01]) {
    if (!_localStorage.containsKey('playerName')) {
      setState(LoaderState.WAITING_FOR_NAME);
      // Start loading images while waiting for a name.
      _tickImagesLoad(duration);
      return;
    }
    if (startedAt == null) {
      startedAt = new DateTime.now();
    }
    if (_imageIndex.playerResourcesLoaded() && !_localStorage.containsKey('playerSprite')) {
      setState(LoaderState.PLAYER_SELECT);
      _playerWorldSelector.frame(duration);
      // Continue loading other resources while waiting for playerSelect.
      _tickImagesLoad(duration);
      return;
    }
    if (_imageIndex.finishedLoadingImages()) {
      _loaderGameStateTick(duration);
    } else {
      _advanceStage(duration);
    }
    if (_currentMessage != "") {
      drawCenteredText(_currentMessage);
    }
  }

  void resetToPlayerSelect() {
    _currentState = LoaderState.PLAYER_SELECT;
    _playerWorldSelector.reset();
    _completed = false;
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

  /**
   * Try fetching resources from other clients.
   */
  void _tickImagesLoad(double duration) {
    if (_imageIndex.finishedLoadingImages()) {
      return;
    }
    Map<String, ConnectionWrapper> connections = _network.safeActiveConnections();
    if (connections.isEmpty) {
      return;
    }
    if (!_imageIndex.imagesIndexed()) {
      _imageIndex.loadImagesFromNetwork();
    }
    _chunkHelper.requestNetworkData(connections, duration);
  }

  void _loadImagesStage(double duration) {
    if (_currentState != LoaderState.LOADING_SERVER && _network.hasOpenConnection()) {
      _tickImagesLoad(duration);
      if (_currentState != LoaderState.LOADING_OTHER_CLIENT) {
        _chunkHelper.bytesPerSecondSamples().listen((int sample) {
          if (sample < ACCEPTABLE_TRANSFER_SPEED_BYTES_SECOND) {
            _slowDownloadRateSamples++;
          } else {
            _slowDownloadRateSamples = 0;
          }
        });
      }
      // load from client.
      setState(LoaderState.LOADING_OTHER_CLIENT,
          "Loading images from other client(s) ${_imageIndex.imagesLoadedString()} ${_chunkHelper.getTransferSpeed()}");
      if (_slowDownloadRateSamples < SAMPLES_BEFORE_FALLBACK) {
        // Continue loading from other clients.
        return;
      } else {
        // Fall through to load from Server.
        log.info("Slow download rate from clients, switching to server.");
      }
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
    if (!_network.findServer()) {
      int connectionCount = 0;
      int connectionPongCount = 0;
      for (ConnectionWrapper connection in _network.safeActiveConnections().values) {
        if (connection.initialPongReceived()) {
          connectionPongCount++;
        }
        connectionCount++;
      }
      setState(LoaderState.FINDING_SERVER, "Finding game to join... $connectionPongCount/$connectionCount");
      return;
    }
    ConnectionWrapper? serverConnection = _network.getServerConnection();
    if (serverConnection == null) {
      _tickWorldSelect(duration);
      return;
    }

    // Maybe trigger resend of reliable data.
    serverConnection.tick(duration, {}, {}, []);

    if (_imageIndex.imageIsLoaded(ImageIndex.WORLD_IMAGE_INDEX)) {
      // World loaded, enter game.
      _enterGame(serverConnection);
    } else {
      _connectToGameAndLoadGameState(duration, serverConnection);
    }
  }

  void _tickWorldSelect(double duration) {
    if (_playerWorldSelector.worldSelectedAndLoaded()) {
      setState(LoaderState.LOADED_AS_SERVER);
    } else if (_playerWorldSelector.selectedWorldName != null) {
      setState(LoaderState.WORLD_LOADING);
    } else {
      _playerWorldSelector.frame(duration);
      setState(LoaderState.WORLD_SELECT);
    }
  }

  void _enterGame(ConnectionWrapper serverConnection) {
    PlayerInfo? ourPlayerInfo =_network.getGameState().playerInfoByConnectionId(_network.getPeer().getId());
    if (ourPlayerInfo == null || !ourPlayerInfo.inGame) {
      if (_currentState != LoaderState.LOADING_ENTERING_GAME) {
        serverConnection.sendClientEnter();
      }
      setState(LoaderState.LOADING_ENTERING_GAME);
    } else {
      setState(LoaderState.LOADING_AS_CLIENT_COMPLETED);
    }
  }

  void _connectToGameAndLoadGameState(double duration, ConnectionWrapper serverConnection) {
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
      setState(LoaderState.LOADING_GAMESTATE, "Loading gamestate... ${percentComplete}% ${_chunkHelper.getTransferSpeed()}");
    }
  }

  void drawCenteredText(String text, [int? y, int size = 20]) {
    if (y == null) {
      y = _height ~/ 2;
    }
    _context.save();
    _context.globalAlpha = 1.0;
    _context.clearRect(0, 0, _width, _height);
    _context.setFillColorRgb(0, 0, 0);
    _context.setStrokeColorRgb(0, 0, 0);
    _context.font = "${size}px Arial";
    var metrics = _context.measureText(text);
    _context.fillText(
        text, _width / 2 - metrics.width / 2, y);
    _context.restore();
  }

  void markCompleted() {
    _completed = true;
  }

  bool completed() => _completed;

  setState(LoaderState state, [String? message = null]) {
    this._currentState = state;
    if (message == null) {
      this._currentMessage = _STATE_DESCRIPTIONS[state]!;
    } else {
      this._currentMessage = message;
    }
  }

  String? selectedWorldName() => _playerWorldSelector.selectedWorldName;
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
  LoaderState.WORLD_SELECT: "",
  LoaderState.WORLD_LOADING: "Loading selected world...",

  LoaderState.FINDING_SERVER: "Finding game to join...",
  LoaderState.LOADING_AS_CLIENT_COMPLETED: "Loading completed.",
  LoaderState.LOADED_AS_SERVER: "Start as server!",
  LoaderState.LOADING_ENTERING_GAME: "Entering game...",
};