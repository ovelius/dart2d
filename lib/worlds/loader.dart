import 'dart:js_interop';
import 'dart:math';

import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/util/fps_counter.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:web/web.dart';
import 'package:clock/clock.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'loader_animation.dart';
import 'player_world_selector.dart';

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
  COMPUTING_BYTE_WORLD, // World is being computed.
  LOADING_AS_CLIENT_COMPLETED, // Client ready start game.
  LOADED_AS_SERVER, // Server ready to start game.
}

// What is a reasonable transfer speed when loading from other clients?
const ACCEPTABLE_TRANSFER_SPEED_BYTES_SECOND = 1024*70;
// How many of slow samples we accept before loading from server instead.
const SAMPLES_BEFORE_FALLBACK = 3;
// How often the FPS is computed.
const FRAME_SAMPLE_TIME = 0.5;
// Retry client connect after this time.
const CLIENT_CONNECT_RETRY_TIMER = 0.5;

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
  late ByteWorld _byteWorld;
  late PlayerWorldSelector _playerWorldSelector;
  late CanvasRenderingContext2D _context;
  late int _width;
  late int _height;
  // Capture framerate every 0.5 seconds.
  FpsCounter _loaderFrameCounter = FpsCounter.withPeriod(FRAME_SAMPLE_TIME);

  // Buffered byteworld data.
  final List<ByteWorldDestruction> bufferDestruction = [];
  final List<ByteWorldDraw> bufferDraws = [];

  // How many samples we have that indicates a slow data transfer.
  int _slowDownloadRateSamples = 0;

  LoaderState _currentState = LoaderState.WEB_RTC_INIT;
  bool _completed = false;
  double _nextClientConnectSendTime = 0.0;
  String? _activeJoinCommanderId = null;
  String? _lastClientEnterCommanderId = null;
  double _nextClientEnterSendTime = 0.0;

  PlayerWorldSelector get playerWorldSelector => _playerWorldSelector;

  int _byteWorldComputeSteps = 15;
  // How long until we can adjust _byteWorldComputeSteps again.
  double _nextAllowedAdjustSteps = FRAME_SAMPLE_TIME;

  String _currentMessage = "";
  final LoaderAnimation _animation = LoaderAnimation();
  double _selectorCenterpieceFade = 0.0;

  Loader(
         this._localStorage,
         WorldCanvas canvasElement,
         this._playerWorldSelector,
         this._imageIndex,
         this._network,
         this._chunkHelper,
         this._byteWorld) {
    this._peerWrapper = _network.getPeer();
    _context = canvasElement.context2D;
    _width = canvasElement.width;
    _height = canvasElement.height;
  }

  Map<LoaderState, dynamic> _STATE_PRECONDITIONS = {
    LoaderState.LOADED_AS_SERVER: (LocalStorage storage){
      if (!storage.containsKey('playerSprite')) {
        throw "Missing playerSprite!";
      }
      if (!storage.containsKey('playerName')) {
        throw "Missing playerName!";
      }
    }
  };


  void loaderTick([double duration = 0.01]) {
    _loaderFrameCounter.timeSingleFrame(duration);
    DateTime now = DateTime.now();
    _loaderTickInternal(duration);
    int millis = DateTime.now().millisecondsSinceEpoch - now.millisecondsSinceEpoch;
    if (millis > 100) {
      log.warning("!!Loader tick took ${millis}");
    }
  }

  void _loaderTickInternal([double duration = 0.01]) {
    if (!_localStorage.containsKey('playerName')) {
      setState(LoaderState.WAITING_FOR_NAME);
      _animation.tick(duration, sharkAvailable: false);
      _animation.drawBackdrop(_context, _width, _height, showProwlingFin: true);
      // Start loading images while waiting for a name.
      _tickImagesLoad(duration);
      return;
    }
    if (_imageIndex.playerResourcesLoaded() && !_localStorage.containsKey('playerSprite')) {
      final bool entering = _currentState != LoaderState.PLAYER_SELECT;
      setState(LoaderState.PLAYER_SELECT);
      if (entering) {
        _selectorCenterpieceFade = 1.0;
        _playerWorldSelector.startFadeIn();
      }
      _drawSelectorWithBackdrop(duration);
      // Continue loading other resources while waiting for playerSelect.
      _tickImagesLoad(duration);
      return;
    }
    if (!_imageIndex.finishedLoadingImages()) {
      _selectorCenterpieceFade = 0.0;
      _advanceConnectionStage(duration);
    } else {
      _loaderGameStateTick(duration);
    }
    if (_currentMessage != "" && !completed()) {
      _moveSpinner(duration);
      drawCenteredText(_currentMessage);
    }
  }

  void _drawSelectorWithBackdrop(double duration) {
    final HTMLImageElement? shark = _loadedSharkImage();
    _animation.tick(duration, sharkAvailable: shark != null);
    _selectorCenterpieceFade =
        max(0.0, _selectorCenterpieceFade - duration.clamp(0.0, 0.1) * 2.4);
    _animation.drawBackdrop(
      _context,
      _width,
      _height,
      sharkImage: shark,
      centerpieceAlpha: _selectorCenterpieceFade,
      showProwlingFin: shark == null,
    );
    _playerWorldSelector.clearBackground = false;
    _playerWorldSelector.frame(duration);
  }

  void resetToPlayerSelect() {
    _currentState = LoaderState.PLAYER_SELECT;
    _playerWorldSelector.reset();
    _completed = false;
    _activeJoinCommanderId = null;
    _lastClientEnterCommanderId = null;
    _nextClientEnterSendTime = 0.0;
  }

  void rollbackForMapTieBreak() {
    _completed = false;
    bufferDestruction.clear();
    bufferDraws.clear();
    _nextClientConnectSendTime = 0.0;
    _activeJoinCommanderId = null;
    _lastClientEnterCommanderId = null;
    _nextClientEnterSendTime = 0.0;
    _chunkHelper.resetTransferForIndex(ImageIndex.WORLD_IMAGE_INDEX);
    _imageIndex.clearImageLoader(ImageIndex.WORLD_IMAGE_INDEX);
    _byteWorld.reset();
    setState(LoaderState.WORLD_LOADING);
  }

  void resetPartialJoinForNewCommander() {
    bufferDestruction.clear();
    bufferDraws.clear();
    _nextClientConnectSendTime = 0.0;
    _activeJoinCommanderId = null;
    _lastClientEnterCommanderId = null;
    _nextClientEnterSendTime = 0.0;
    _chunkHelper.resetTransferForIndex(ImageIndex.WORLD_IMAGE_INDEX);
    _imageIndex.clearImageLoader(ImageIndex.WORLD_IMAGE_INDEX);
    _byteWorld.reset();
    if (_currentState == LoaderState.LOADING_GAMESTATE ||
        _currentState == LoaderState.COMPUTING_BYTE_WORLD ||
        _currentState == LoaderState.LOADING_ENTERING_GAME) {
      setState(LoaderState.CONNECTING_TO_GAME);
    }
  }


  void _stepByteWorld(double duration) {
    if (!_byteWorld.worldImageSet()) {
      _initByteWorld(_playerWorldSelector.selectedWorldName == null ?
          "" : _playerWorldSelector.selectedWorldName!);
    }
    for (int i = 0; i < _byteWorldComputeSteps && !_byteWorld.bedrockComputed(); i++) {
      _byteWorld.bedrockStep();
    }
    int percentComplete = (_byteWorld.percentComplete() * 100).toInt();
    setState(LoaderState.COMPUTING_BYTE_WORLD, "Creating world ${percentComplete} %");
    _nextAllowedAdjustSteps -= duration;
    if (_nextAllowedAdjustSteps < 0) {
      _nextAllowedAdjustSteps += FRAME_SAMPLE_TIME;
      // This counter is ever 0.5s so we need to double it to get per second.
      double fps = _loaderFrameCounter.fps() * 2.0;
      if (fps > GAME_TARGET_FPS * 0.7) {
        // Increase at least by one..
        _byteWorldComputeSteps = _byteWorldComputeSteps + max(1, (_byteWorldComputeSteps * 0.5).toInt());
      } else if (fps < GAME_TARGET_FPS / 2 ) {
        _byteWorldComputeSteps = _byteWorldComputeSteps - (_byteWorldComputeSteps * 0.5).toInt();
      }
    }
  }

  void _initByteWorld([String map = ""]) {
    if (map.isNotEmpty) {
      _network.getGameState().gameStateProto.mapName = map;
    }
    final String effectiveMapName =
        map.isNotEmpty ? map : _network.getGameState().gameStateProto.mapName;
    HTMLImageElement worldImage = map.isNotEmpty
        ? _imageIndex.getImageByName(map)
        : _imageIndex.getImageById(ImageIndex.WORLD_IMAGE_INDEX);
    final GeneratedWorldResult? generated =
        WorldGenerator.generateFromMapKey(effectiveMapName);
    _byteWorld.setWorldImage(worldImage,
        bedrockCanvas: generated?.bedrockCanvas);
  }

  void _advanceConnectionStage(double duration) {
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
    if (!_network.findActiveGameConnection()) {
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
      _activeJoinCommanderId = null;
      _lastClientEnterCommanderId = null;
      _tickWorldSelect(duration);
      return;
    }

    if (_activeJoinCommanderId != null &&
        _activeJoinCommanderId != serverConnection.id) {
      log.info(
          "Commander changed from $_activeJoinCommanderId to ${serverConnection.id} while in $_currentState");
      _nextClientConnectSendTime = 0.0;
      _lastClientEnterCommanderId = null;
      _nextClientEnterSendTime = 0.0;
      if (!_imageIndex.imageIsLoaded(ImageIndex.WORLD_IMAGE_INDEX) &&
          !_playerWorldSelector.worldSelectedAndLoaded()) {
        // Restart world image download from the new commander, whose ByteWorld
        // already includes prior mutations.
        _chunkHelper.resetTransferForIndex(ImageIndex.WORLD_IMAGE_INDEX);
        bufferDestruction.clear();
        bufferDraws.clear();
      }
    }
    _activeJoinCommanderId = serverConnection.id;

    // Maybe trigger resend of reliable data.
    serverConnection.tick(duration, []);


    String? selectedWorldName = _playerWorldSelector.selectedWorldName;
    // A world image has been selected and is currently loading.
    if (selectedWorldName != null
      && !_imageIndex.imageNameIsLoaded(selectedWorldName)) {
      setState(LoaderState.WORLD_LOADING);
      return;
    }
    if (_playerWorldSelector.worldSelectedAndLoaded()) {
      if (!_byteWorld.byteWorldReady()) {
        _stepByteWorld(duration);
        return;
      } else  if (!serverConnection.isValidGameConnection()) {
        print("Not valid gamestate: ${_network.getGameState().gameStateProto.toDebugString()}");
        _connectToGameAndLoadGameState(duration, serverConnection);
        return;
      }
    }

    if (_byteWorld.byteWorldReady()) {
      // Actually enter game.
      _enterGame(serverConnection, duration);
    } else if (_imageIndex.imageIsLoaded(ImageIndex.WORLD_IMAGE_INDEX)) {
      // World loaded compute bedrock data.
      _stepByteWorld(duration);
    } else {
      _connectToGameAndLoadGameState(duration, serverConnection);
    }
  }

  void _tickWorldSelect(double duration) {
    if (_playerWorldSelector.worldSelectedAndLoaded()) {
      if (_byteWorld.byteWorldReady()) {
        setState(LoaderState.LOADED_AS_SERVER);
      } else {
        // World loaded compute bedrock data.
        _stepByteWorld(duration);
      }
    } else if (_playerWorldSelector.selectedWorldName != null) {
      setState(LoaderState.WORLD_LOADING);
    } else {
      final bool entering = _currentState != LoaderState.WORLD_SELECT;
      if (entering) {
        _selectorCenterpieceFade =
            _currentState == LoaderState.PLAYER_SELECT ? 0.0 : 1.0;
        _playerWorldSelector.startFadeIn();
      }
      _drawSelectorWithBackdrop(duration);
      setState(LoaderState.WORLD_SELECT);
    }
  }

  void _enterGame(ConnectionWrapper serverConnection,
      [double duration = 0.01]) {
    PlayerInfoProto? ourPlayerInfo = _network
        .getGameState()
        .playerInfoByConnectionId(_network.getPeer().getId());
    if (ourPlayerInfo == null || !ourPlayerInfo.inGame) {
      _nextClientEnterSendTime -= duration;
      if (_currentState != LoaderState.LOADING_ENTERING_GAME ||
          _lastClientEnterCommanderId != serverConnection.id ||
          _nextClientEnterSendTime < 0) {
        serverConnection.sendClientEnter();
        _lastClientEnterCommanderId = serverConnection.id;
        _nextClientEnterSendTime = CLIENT_CONNECT_RETRY_TIMER;
      }
      setState(LoaderState.LOADING_ENTERING_GAME);
    } else {
      setState(LoaderState.LOADING_AS_CLIENT_COMPLETED);
    }
  }

  void _connectToGameAndLoadGameState(double duration, ConnectionWrapper serverConnection) {
    if (!serverConnection.isValidGameConnection()) {
      _nextClientConnectSendTime -= duration;
      if (_currentState != LoaderState.CONNECTING_TO_GAME
         || _nextClientConnectSendTime < 0) {
        int playerSpriteId = _imageIndex.getImageIdByName(_localStorage['playerSprite']);
        serverConnection.connectToGame(_localStorage['playerName'], playerSpriteId);
        _nextClientConnectSendTime = CLIENT_CONNECT_RETRY_TIMER;
      }
      setState(LoaderState.CONNECTING_TO_GAME);
      // Keep buffers empty, we're not loading world yet.
      bufferDestruction.clear();
      bufferDraws.clear();
    } else if (!_byteWorld.byteWorldReady()) {
      _chunkHelper.requestSpecificNetworkData(
          {serverConnection.id : serverConnection}, duration,
          GAME_STATE_RESOURCES);
      // TODO figure out percentage of multiple items?
      int percentComplete = (_chunkHelper.getCompleteRatio(GAME_STATE_RESOURCES[0]) * 100).toInt();
      setState(LoaderState.LOADING_GAMESTATE, "Loading gamestate... ${percentComplete}% ${_chunkHelper.getTransferSpeed()}");
    }
  }

  HTMLImageElement? _loadedSharkImage() {
    if (_imageIndex.imagesIndexed() && _imageIndex.imageNameIsLoaded(LOADER_SPRITE)) {
      return _imageIndex.getImageByName(LOADER_SPRITE);
    }
    return null;
  }

  double? _computeLoadingProgress() {
    switch (_currentState) {
      case LoaderState.LOADING_SERVER:
      case LoaderState.LOADING_OTHER_CLIENT:
        if (IMAGE_SOURCES.isEmpty) return null;
        return (_imageIndex.loadedImages.length / IMAGE_SOURCES.length)
            .clamp(0.0, 1.0);
      case LoaderState.LOADING_GAMESTATE:
        return _chunkHelper
            .getCompleteRatio(GAME_STATE_RESOURCES[0])
            .clamp(0.0, 1.0);
      case LoaderState.COMPUTING_BYTE_WORLD:
        return _byteWorld.percentComplete().clamp(0.0, 1.0);
      default:
        return null;
    }
  }

  void drawCenteredText(String text, [int? y, int size = 20]) {
    _animation.draw(
      _context,
      _width,
      _height,
      message: text,
      sharkImage: _loadedSharkImage(),
      progress: _computeLoadingProgress(),
      isError: _currentState == LoaderState.ERROR,
    );
  }

  void _moveSpinner(double duration) {
    _animation.tick(duration, sharkAvailable: _loadedSharkImage() != null);
  }

  void markCompleted() {
    _completed = true;
  }

  bool completed() => _completed;

  _applyBufferedByteWorldOperations() {
    // It became ready.
    if (_byteWorld.byteWorldReady()) {
      for (ByteWorldDraw buffered in bufferDraws) {
        _byteWorld.drawFromNetworkUpdate(buffered);
      }
      bufferDraws.clear();
      for (ByteWorldDestruction buffered in bufferDestruction) {
        _byteWorld.clearAt(Vec2.fromProto(buffered.position), buffered.radius);
      }
      bufferDestruction.clear();
    }
  }

  setState(LoaderState state, [String? message = null]) {
    if (_STATE_PRECONDITIONS.containsKey(state)) {
      _STATE_PRECONDITIONS[state](_localStorage);
    }
    if (_currentState != state) {
      log.info("Loader state changes from $_currentState to $state");
      if (_currentState == LoaderState.COMPUTING_BYTE_WORLD &&
         state == LoaderState.LOADING_ENTERING_GAME) {
          _applyBufferedByteWorldOperations();
      }
    }
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
  LoaderState.LOADED_AS_SERVER: "Joining as first player...",
  LoaderState.LOADING_ENTERING_GAME: "Entering game...",
  LoaderState.COMPUTING_BYTE_WORLD: "Creating world...",
};
