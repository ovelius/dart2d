import 'dart:js_interop';

import 'package:dart2d/net/connection.dart';
import 'package:dart2d/res/sounds.dart';
import 'package:dart2d/worlds/powerup_manager.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/worlds/world_listener.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/phys/spatial_grid.dart';
import 'package:dart2d/phys/phys.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/net/chunk_helper.dart';
import 'package:dart2d/net/network.dart';
import 'package:dart2d/net/helpers.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:web/web.dart';
import '../net/state_updates.pb.dart';
import 'byteworld.dart';
import 'loader.dart';
import 'world_generator.dart';
import 'world_themes.dart';
import 'world_util.dart';
import 'dart:math';
import 'player_world_selector.dart';

@Singleton(scope: 'world')
class WormWorld extends World {
  // If the player gives no input for this amount of time we reload the page.
  // We don't want idle players! And players idle att the title screen will
  // actually serve as resource hosts :D
  static final Duration RELOAD_TIMEOUT = new Duration(minutes: 8);
  final Logger log = new Logger('WormWorld');
  late Loader loader;
  late SpriteIndex spriteIndex;
  late ImageIndex _imageIndex;
  late Function _reloadFunction;
  late MobileControls _mobileControls;
  late FpsCounter _drawFps;
  late Network _network;
  late ConfigParams _configParams;
  late LocalStorage _localStorage;
  late GaReporter _gaReporter;
  late PowerupManager _powerupManager;
  late KeyState localKeyState;
  late HudMessages hudMessages;
  late PacketListenerBindings _packetListenerBindings;
  PacketListenerBindings get packetListenerBindings => _packetListenerBindings;
  late CanvasRenderingContext2D _canvas;
  late Sounds _sounds;
  Vec2 viewPoint = new Vec2();
  Vec2 halfWorld = new Vec2();
  ByteWorld byteWorld;
  Vec2 gravity = new Vec2(0.0, 300.0);
  late SpatialGrid _spatialGrid;

  late int _width, _height;
  double explosionFlash = 0.0;
  double _skyTime = 0.0;
  int _frameDebrisEffectCount = 0;
  bool soundEnabled = true;

  // Death camera state: smoothly zooms out to reveal the full battlefield,
  // then zooms back in on the new spawn location until the player spawns.
  double _cameraZoom = 1.0;
  double _deathCameraElapsed = 0.0;
  bool _inDeathCamera = false;
  Vec2 _cameraCenter = new Vec2();

  double get cameraZoom => _cameraZoom;

  WormWorld(
      this._network,
      this.loader,
      @Named(RELOAD_FUNCTION) Function reloadFunction,
      KeyState localKeyState,
      WorldCanvas canvasElement,
      LocalStorage storage,
      FpsCounter serverFrameCounter,
      SpriteIndex spriteIndex,
      this._imageIndex,
      this._configParams,
      this._powerupManager,
      this._gaReporter,
      this._sounds,
      ChunkHelper chunkHelper,
      this.byteWorld,
      HudMessages hudMessages,
      WorldListener worldListener,
      this._mobileControls,
      PacketListenerBindings packetListenerBindings) {
    this._reloadFunction = reloadFunction;
    this._localStorage = storage;
    this._drawFps = serverFrameCounter;
    this._width = canvasElement.width;
    this._height = canvasElement.height;
    this._canvas = canvasElement.context2D;
    halfWorld = new Vec2(this.width() / 2, this.height() / 2 );
    this.spriteIndex = spriteIndex;
    this._packetListenerBindings = packetListenerBindings;
    this.localKeyState = localKeyState;
    localKeyState.world = this;
    localKeyState.registerGenericListener((e) {
      if (playerSprite?.isMappedKey(e) == false) {
        invalidKeysPressed++;
        if (invalidKeysPressed > 2) {
          controlHelperTime = 4.0;
        }
      } else {
        invalidKeysPressed = 0;
      }
    });
    this.hudMessages = hudMessages;
    this._network.world = this;
    this._powerupManager.mysteryPowerupEnabled =
        !this._configParams.getBool(ConfigParam.SANDBOX);
    worldListener.setWorld(this);
    this._spatialGrid = new SpatialGrid(128.0);
    try {
      this.loader.playerWorldSelector.registerRollbackHandler(
          (String winnerId, String winnerMapName) {
        this.rollbackToRemoteMapSelection(winnerId, winnerMapName);
      });
    } catch (_) {}
  }
  
  void collisionCheck(int networkId, duration) {
    Sprite? sprite = spriteIndex[networkId];
    
    if(sprite is MovingSprite) {
      if (sprite.collision) {
        if (_network.isCommander() || sprite.networkType == NetworkType.LOCAL) {
          for (var otherSprite in _spatialGrid.query(sprite)) {
            if (otherSprite is MovingSprite) {
              if (!otherSprite.collision) continue;
              // Avoid duplicate checks, but only if server.
              if (_network.isCommander() && (sprite.networkId ?? 0) >= (otherSprite.networkId ?? 0)) {
                continue;
              }
              if (collision(sprite, otherSprite, duration)) {
                sprite.collide(otherSprite, null, null);
                otherSprite.collide(sprite, null, null);
              }
            }
          }
        }

        int worldCollisionAngles = _worldCollisionAngles(sprite);
        if (worldCollisionAngles != 0) {
          sprite.collide(null, byteWorld, worldCollisionAngles);
        }
        
        // Out of bounds check.
        bool outOfBounds = false;
        if (sprite.position.x + sprite.size.x > byteWorld.width) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_RIGHT);
          sprite.position.x = byteWorld.width - sprite.size.x;
          outOfBounds = true;
        }
        if (sprite.position.x < 0) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_LEFT);
          sprite.position.x = 0.0;
          outOfBounds = true;
        }
        if (sprite.position.y + sprite.size.y > byteWorld.height) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_BELOW);
          sprite.position.y = byteWorld.height - sprite.size.y;
          outOfBounds = true;
        }
        if (sprite.position.y - sprite.size.y < 0) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_ABOVE);
          outOfBounds = true;
        }

        if (sprite.removeOutOfBounds && outOfBounds) {
          sprite.remove = true;
        }
      }
    }
  }

  int _worldCollisionAngles(Sprite sprite) {
    int xStart = sprite.position.x.toInt();
    int xWidth = sprite.size.x.toInt();
    int yStart = sprite.position.y.toInt();
    int yHeight = sprite.size.y.toInt();

    int collisionAngles = 0;
    for (int x = 0; x < xWidth; x++) {
      if (byteWorld.isSolid(xStart + x, yStart)) {
        collisionAngles |= MovingSprite.DIR_ABOVE;
      }
      if (byteWorld.isSolid(xStart + x, yStart + yHeight - 1)) {
        collisionAngles |= MovingSprite.DIR_BELOW;
      }
    }
    for (int y = 0; y < yHeight; y++) {
      if (byteWorld.isSolid(xStart, yStart + y)) {
        collisionAngles |= MovingSprite.DIR_LEFT;
      }
      if (byteWorld.isSolid(xStart + xWidth - 1, yStart + y)) {
        collisionAngles |= MovingSprite.DIR_RIGHT;
      }
    }
    return collisionAngles;
  }

  void connectTo(var id, [String? name = null, bool startGame = true]) {
    hudMessages.display("Connecting to ${id}");
    _network.peer.connectTo(id);
    _network.gameState.gameStateProto.actingCommanderId = "";
    if (startGame) {
      _network.findActiveGameConnection();
      ConnectionWrapper? serverConnection = _network.getServerConnection();
      if (serverConnection == null) {
        throw new StateError("No server connection, can't connect to game :S Got ${_network.safeActiveConnections()}");
      }

      int playerSpriteId = _imageIndex.getImageIdByName(_localStorage['playerSprite']);
      serverConnection.connectToGame(
            name == null ? _localStorage['playerName'] : name, playerSpriteId);
    }
  }

  /**
   * Display a message in the world and send it to the network for remote display.
   */
  void displayHudMessageAndSendToNetwork(String message, [double? period]) {
    if (period == null) {
      hudMessages.display(message);
    } else {
      hudMessages.display(message, period);
    }
    _network.sendMessage(message);
  }

  bool loaderCompleted() => loader.completed();

  double _winTime = 10.0;

  void frameDraw([double duration = 0.01, bool slowDown = false]) {
    // Keep track on how often we do this :)
    _drawFps.timeWithFrames(duration, 1);
    try {
      loader.playerWorldSelector.tickTieBreakTimer(duration);
    } catch (_) {}

    if (!loader.completed()) {
      if (loader.loadedAsServer()) {
        startAsServer();
        loader.markCompleted();
        _gaReporter.reportEvent("new game", "StartType");
      } else if (loader.hasGameState()) {
        loader.markCompleted();
        _gaReporter.reportEvent("join game", "StartType");
      } else {
        // Tick the loader.
        loader.loaderTick(duration);
      }
      // Don't run the generic game loop.
      return;
    }

    if (restart) {
      clearScreen();
      restart = false;
    }

    assert(byteWorld.byteWorldReady());

    // Count the draw FPS before adjusting the duration.
    performanceGovernor.update(duration, _drawFps.fps(),
        isCommander: isCommander);
    if (duration >= 0.041 && slowDown) {
      // Slow down the game instead of skipping frames.
      duration = 0.041;
    }
    int frames = advanceFrames(duration);

    _spatialGrid.clear();
    _frameDebrisEffectCount = 0;
    for (int networkId in spriteIndex.spriteIds()) {
      final Sprite s = spriteIndex[networkId]!;
      _spatialGrid.insert(s);
      if (s is TerrainDebrisEffect) {
        _frameDebrisEffectCount++;
      }
    }

    List<StateUpdate> particles = [];

    for (Sprite sprite in spriteIndex.putPendingSpritesInWorld()) {
      if (sprite is Powerup) {
        _powerupManager.trackPowerup(sprite);
      }
      if (sprite is Particles && sprite.sendToNetwork) {
        particles.add(StateUpdate()..particleEffects = sprite.toNetworkUpdate());
      }
    }
    if (particles.isNotEmpty) {
      // TODO: Make part of main network loop instead.
      _network.peer.sendDataWithKeyFramesToAll(GameStateUpdates()
        ..stateUpdate.addAll(particles));
    }

    _skyTime += duration;
    final ParsedGeneratedMap? activeMap =
        parseGeneratedMapName(_network.getGameState().gameStateProto.mapName) ??
            parseGeneratedMapName(loader.selectedWorldName());
    gravity.y = activeMap?.theme.gravity ?? DEFAULT_WORLD_GRAVITY;

    _canvas.clearRect(0, 0, _width, _height);
    if (activeMap != null) {
      WorldGenerator.drawGameplaySky(
        _canvas,
        _width,
        _height,
        activeMap.theme,
        _skyTime,
        seed: activeMap.seed,
        detailScale: effectiveDetailScale,
      );
    } else {
      _canvas.fillStyle = "rgb(135,206,250)".toJS;
      _canvas.fillRect(0, 0, _width, _height);
    }
    _canvas.save();


    _updateCamera(duration);

    if (_cameraZoom < 0.999 && byteWorld.canvas != null) {
      _canvas.translate(_width / 2.0, _height / 2.0);
      _canvas.scale(_cameraZoom, _cameraZoom);
      _canvas.translate(-_cameraCenter.x, -_cameraCenter.y);
      _canvas.drawImage(byteWorld.canvas!, 0, 0);
      _canvas.restore();

      _canvas.save();
      _canvas.translate(_width / 2.0, _height / 2.0);
      _canvas.scale(_cameraZoom, _cameraZoom);
      _canvas.translate(-_cameraCenter.x, -_cameraCenter.y);
    } else {
      byteWorld.drawAt(_canvas, viewPoint.x, viewPoint.y);
      _canvas.restore();

      _canvas.save();
      _canvas.translate(-viewPoint.x, -viewPoint.y);
    }
    for (int networkId in spriteIndex.spriteIds()) {
      MovingSprite sprite = spriteIndex[networkId] as MovingSprite;
      if (!freeze && !_network.hasNetworkProblem()) {
        sprite.frame(duration, frames, gravity);
      }
      if(shouldDraw(sprite))
        sprite.draw(_canvas, localKeyState.debug);
      collisionCheck(networkId, duration);
      if (sprite.remove) {
        removeSprite(sprite.networkId!);
      }
    }
    _drawSpawnTargetBeacon(_canvas);
    _canvas.restore();

    if (explosionFlash > 0) {
      _canvas.fillStyle = "rgba(255, 255, 255, ${explosionFlash})".toJS;
      _canvas.fillRect(0, 0, _width, _height);
      explosionFlash -= duration * 5;
    }
    if (playerSprite != null) {
      if (controlHelperTime > 0) {
        drawControlHelper(
            _canvas, controlHelperTime, playerSprite!, _width, _height);
        controlHelperTime -= duration;
      }

      if (network().getGameState().hasWinner()) {
        drawWinView(
            _canvas,
            this,
            _width,
            _height,
            playerSprite!,
            spriteIndex,
            _imageIndex);
        _winTime -= duration;
        if (_winTime < 0) {
          spriteIndex.clear();
          _winTime = 10.0;
          byteWorld.reset();
          _powerupManager.reset();
          network().getGameState().reset();
          network().resetGameConnections();
          _imageIndex.clearImageLoader(ImageIndex.WORLD_IMAGE_INDEX);
          loader.resetToPlayerSelect();
        }
      } else {
        drawKilledView(
            _canvas,
            this,
            _width,
            _height,
            playerSprite!,
            spriteIndex,
            _imageIndex);
      }
    }

    spriteIndex.removePending();

    // Only send to network if server frames has passed.
    _network.frame(duration, spriteIndex.getAndClearNetworkRemovals());
    _checkDormantPlayer();
    if (_network.isCommander() && _network.pendingCommandTransfer() == null) {
      _powerupManager.frame(duration);
    } else {
      _powerupManager.pruneRemoved();
    }

    // 1 since we count how many times this method is called.
    drawFpsCounters();
    hudMessages.render(this, _canvas, duration);

    _mobileControls.draw(duration);
    playerSprite?.weaponState?.drawWeaponHelper(_canvas,
        _mobileControls.buttonLocation(MobileControls.WEAPON_SELECT_BUTTON), true);

    _canvas.restore();

  }

  void checkWinner(PlayerInfoProto info) {
    int max = _configParams.getInt(ConfigParam.MAX_FRAGS);
    if (info.score >= max) {
      _network.getGameState().gameStateProto.winnerPlayerId = info.connectionId;
      for (PlayerInfoProto pInfo in _network.getGameState().playerInfoList()) {
        pInfo.inGame = false;
        final Sprite? s = spriteIndex[pInfo.spriteId];
        if (s is LocalPlayerSprite) {
          s.collision = false;
          s.weaponState?.cancelMysteryRoulette();
        }
      }
      _gaReporter.reportEvent("game_over");
    }
  }

  void _checkDormantPlayer() {
    if (untilNextFrame < 0.01) {
      Duration lastMobileInput = _mobileControls.lastUserInput();
      Duration lastInput = localKeyState.lastUserInput();
      if (lastMobileInput > RELOAD_TIMEOUT && lastInput > RELOAD_TIMEOUT) {
        _gaReporter.reportEvent("dormant_player_reload");
        _reloadFunction();
      }
    }
  }

  double _smoothStep(double t) {
    double c = t.clamp(0.0, 1.0);
    return c * c * (3.0 - 2.0 * c);
  }

  void _updateCamera(double duration) {
    if (playerSprite == null) {
      _cameraZoom = 1.0;
      _inDeathCamera = false;
      _deathCameraElapsed = 0.0;
      _cameraCenter = Vec2(viewPoint.x + halfWorld.x, viewPoint.y + halfWorld.y);
      return;
    }

    LocalPlayerSprite player = playerSprite!;
    bool deadAndRespawning = !player.inGame() &&
        player.info.deaths > 0 &&
        !network().getGameState().hasWinner() &&
        (player.spawnIn <= LocalPlayerSprite.RESPAWN_TIME || _inDeathCamera);

    if (deadAndRespawning) {
      double authElapsed =
          (LocalPlayerSprite.RESPAWN_TIME - player.spawnIn)
              .clamp(0.0, LocalPlayerSprite.RESPAWN_TIME);
      if (!_inDeathCamera || authElapsed < _deathCameraElapsed - 0.5) {
        _inDeathCamera = true;
        _deathCameraElapsed = authElapsed;
      } else {
        _deathCameraElapsed =
            (_deathCameraElapsed + duration).clamp(0.0, LocalPlayerSprite.RESPAWN_TIME);
        if (player.spawnIn <= LocalPlayerSprite.RESPAWN_TIME &&
            (authElapsed - _deathCameraElapsed).abs() > 0.25) {
          _deathCameraElapsed +=
              (authElapsed - _deathCameraElapsed) * min(1.0, duration * 6.0);
        }
      }

      // Compute zoom needed to reveal the entire battlefield.
      double minZoom = 1.0;
      if (byteWorld.worldImageSet() && byteWorld.width > 0 && byteWorld.height > 0) {
        minZoom = min(
          1.0,
          min(_width / byteWorld.width, _height / byteWorld.height),
        );
      }

      // Timeline across the 5.0s respawn:
      // 0.00 - 0.65s: Stay zoomed in on the KO pop.
      // 0.65 - 1.95s: Smoothly zoom out to reveal the whole battlefield.
      // 1.95 - 2.65s: Hold full battlefield overview (new spawn picked at 2.5s).
      // 2.65 - 4.95s: Smoothly zoom back in onto the spawn location until spawn.
      double zoomProgress;
      if (_deathCameraElapsed < 0.65) {
        zoomProgress = 1.0;
      } else if (_deathCameraElapsed < 1.95) {
        zoomProgress = 1.0 - _smoothStep((_deathCameraElapsed - 0.65) / 1.30);
      } else if (_deathCameraElapsed < 2.65) {
        zoomProgress = 0.0;
      } else {
        zoomProgress = _smoothStep((_deathCameraElapsed - 2.65) / 2.30);
      }

      // Exponential zoom interpolation gives constant perceived zoom speed.
      _cameraZoom = minZoom * pow(1.0 / minZoom, zoomProgress).toDouble();
    } else {
      _cameraZoom = 1.0;
      _inDeathCamera = false;
      _deathCameraElapsed = 0.0;
    }

    Vec2 focus = player.centerPoint();
    if (_cameraZoom < 0.999) {
      double visW = _width / _cameraZoom;
      double visH = _height / _cameraZoom;
      double camX;
      if (visW >= byteWorld.width) {
        camX = byteWorld.width / 2.0;
      } else {
        camX = focus.x.clamp(visW / 2.0, byteWorld.width - visW / 2.0);
      }
      double camY;
      if (visH >= byteWorld.height) {
        camY = byteWorld.height / 2.0;
      } else {
        camY = focus.y.clamp(visH / 2.0, byteWorld.height - visH / 2.0);
      }
      _cameraCenter = Vec2(camX, camY);
      viewPoint.x = camX - visW / 2.0;
      viewPoint.y = camY - visH / 2.0;
    } else {
      viewPoint.x = focus.x - halfWorld.x;
      viewPoint.y = focus.y - halfWorld.y;
      if (viewPoint.y > byteWorld.height - _height) {
        viewPoint.y = byteWorld.height * 1.0 - _height;
      }
      if (viewPoint.x > byteWorld.width - _width) {
        viewPoint.x = byteWorld.width * 1.0 - _width;
      }
      if (viewPoint.x < 0) {
        viewPoint.x = 0.0;
      }
      if (viewPoint.y < 0) {
        viewPoint.y = 0.0;
      }
      _cameraCenter = Vec2(viewPoint.x + halfWorld.x, viewPoint.y + halfWorld.y);
    }
  }

  void _drawSpawnTargetBeacon(CanvasRenderingContext2D context) {
    if (!_inDeathCamera || playerSprite == null || playerSprite!.inGame()) {
      return;
    }
    // Show landing beacon once the new spawn location has been chosen (after 2.5s).
    if (playerSprite!.spawnIn >= LocalPlayerSprite.RESPAWN_TIME / 2.0) {
      return;
    }
    Vec2 target = playerSprite!.centerPoint();
    double t = _deathCameraElapsed;
    double pulse = (sin(t * 9.0) + 1.0) * 0.5;
    double outerR = 24.0 + 10.0 * pulse;
    double innerR = 12.0 + 3.0 * (1.0 - pulse);
    double invScale = (1.0 / _cameraZoom).clamp(1.0, 2.5);

    context.save();
    context.translate(target.x, target.y);

    context.strokeStyle = "rgba(255, 235, 110, ${(0.55 + 0.35 * pulse).toStringAsFixed(2)})".toJS;
    context.lineWidth = 2.4 * invScale;
    context.beginPath();
    context.arc(0, 0, outerR, 0, pi * 2.0);
    context.stroke();

    context.strokeStyle = "rgba(255, 255, 255, 0.9)".toJS;
    context.lineWidth = 1.6 * invScale;
    context.beginPath();
    context.arc(0, 0, innerR, 0, pi * 2.0);
    context.stroke();

    // Subtle crosshair ticks.
    double tickInner = outerR + 3.0;
    double tickOuter = outerR + 10.0;
    context.beginPath();
    context.moveTo(-tickOuter, 0);
    context.lineTo(-tickInner, 0);
    context.moveTo(tickInner, 0);
    context.lineTo(tickOuter, 0);
    context.moveTo(0, -tickOuter);
    context.lineTo(0, -tickInner);
    context.moveTo(0, tickInner);
    context.lineTo(0, tickOuter);
    context.stroke();

    context.restore();
  }

  bool shouldDraw(Sprite sprite){
    double visW = _width / _cameraZoom;
    double visH = _height / _cameraZoom;
    double xMin = viewPoint.x;                        //leftest x-value
    double xMax = viewPoint.x + visW;                 //rightest x-value
    double yMin = viewPoint.y;                        //highest y-value
    double yMax = viewPoint.y + visH;                 //lowest y-value

    if(sprite.invisibleOutsideCanvas) {
      double spriteX, spriteY, spriteWidth, spriteHeight;
      
      spriteX = sprite.position.x;   //sprite most left x-value
      spriteY = sprite.position.y;   //sprite most top x-value
      spriteWidth = sprite.size.x;   //sprite width
      spriteHeight = sprite.size.y;  //sprite height

      if(spriteX > xMax)
        return false;
      if(spriteX + spriteWidth < xMin)
        return false;
      if(spriteY > yMax)
        return false;
      if(spriteY + spriteHeight < yMin)
        return false;
    } else if (sprite is ExplosionEffect ||
        sprite is HyperExplosion ||
        sprite is TerrainDebrisEffect ||
        sprite is JellybeanPopEffect ||
        sprite is DartImpactEffect ||
        sprite is Particles) {
      // Cull off-screen local visual effects with a generous radius margin so
      // distant blasts/trails on the 2080x900 arena don't burn Canvas2D draw calls.
      double margin = 220.0 * effectiveDetailScale.clamp(0.4, 1.0);
      Vec2 anchor = sprite.position;
      if (sprite is HyperExplosion) {
        margin = sprite.maxRadius * 1.35 + 40.0;
      } else if (sprite is ExplosionEffect) {
        margin = sprite.blastRadius * 1.5 + 50.0;
      } else if (sprite is Particles && sprite.follow != null) {
        anchor = sprite.follow!.position;
        margin = max(margin, 240.0);
      }
      if (anchor.x < xMin - margin ||
          anchor.x > xMax + margin ||
          anchor.y < yMin - margin ||
          anchor.y > yMax + margin) {
        return false;
      }
    }
    return true;
  }

  void playSound(Sound sound,{double volume = 1.0, bool multiPlay = false, String? playId = null}) {
    _sounds.playSound(sound, volume:volume, multiPlay:multiPlay, playId:playId);
  }

  void playSoundAtSprite(Sprite sprite, Sound sound, {multiPlay = false, playSpriteId = false}) {
    playSoundAtPosition(
        sprite.position,
        sound,
        multiPlay: multiPlay,
        playId: playSpriteId ? sprite.networkId.toString() : null);
  }

  void playSoundAtPosition(Vec2 location, Sound sound, {bool multiPlay = false, String? playId = null}) {
    if (playerSprite != null) {
      double distance = (location.subtract(playerSprite!.position)).sum();
      double volume = 1.0 - (distance / 1000.0);
      if (volume > 0.01) {
        playSound(sound, volume: volume, multiPlay: multiPlay, playId: playId);
      }
    }
  }

  void createLocalClient(int spriteId,  Vec2 position) {
    // Keep client-generated non-player sprites strictly inside (spriteId, spriteId + 1000)
    // so they never collide with our own playerSprite or another player's ID block.
    spriteIndex.setLocalIdRange(spriteId + 1, spriteId + GameState.ID_OFFSET_FOR_NEW_CLIENT);
    PlayerInfoProto? info = _network.getGameState().playerInfoByConnectionId(network().peer.id!);
    if (info == null) {
      throw "Self gamestate data is missing id: ${_network.peer.id}!";
    }
    network().gameState.updateWithLocalKeyState(network().peer.id!, localKeyState);
    playerSprite = new LocalPlayerSprite(
        this, _imageIndex, _mobileControls, info,
        position,
        0);
    playerSprite!.networkId = spriteId;
    _adjustPlayerSprite();
    addSprite(playerSprite!);
  }
  
  addLocalPlayerSprite(String name) {
    if (!_localStorage.containsKey('playerSprite')) {
      throw StateError("PlayerSprite not selected!");
    }
    int id = _network.gameState.getNextUsablePlayerSpriteId(this);
    PlayerInfoProto info = new PlayerInfoProto()
      ..name = name
      ..connectionId = _network.peer.id!
      ..spriteId = id;
    network().gameState.updateWithLocalKeyState(info.connectionId, localKeyState);
    playerSprite = new LocalPlayerSprite(
        this, _imageIndex, _mobileControls, info,
        byteWorld.randomNotSolidPoint(LocalPlayerSprite.DEFAULT_PLAYER_SIZE),
        0);
    playerSprite!.networkId = id;
    playerSprite!.spawnIn = 1.0;
    _adjustPlayerSprite();
    _network.gameState.addPlayerInfo(info);
    addSprite(playerSprite!);
  }

  void _adjustPlayerSprite() {
    adjustPlayerSprite(this.playerSprite!, _imageIndex.getImageIdByName(_localStorage['playerSprite']));
  }

  void adjustPlayerSprite(LocalPlayerSprite playerSprite, int playerSpriteId) {
    HTMLImageElement img = _imageIndex.getImageById(playerSpriteId);
    int height = img.height;
    int width = PlayerWorldSelector.playerSpriteWidth(_imageIndex.imageNameFromIndex(playerSpriteId));
    double ratio = height / width;
    playerSprite.size = new Vec2.copy(LocalPlayerSprite.DEFAULT_PLAYER_SIZE);
    playerSprite.setImage(playerSpriteId, 4);
    playerSprite.size.y *= ratio;
  }
  
  void addParticlesFromNetworkData(StateUpdate data) {
    addSprite(new Particles.fromNetworkUpdate(data.particleEffects, this));
  }
  
  void _spawnExplosionVisuals(Vec2 location, Vec2 velocity, double radius) {
    if (radius <= 3) {
      return;
    }
    playSoundAtPosition(location, Sound.EXPLOSION, multiPlay: true);
    addSprite(ExplosionEffect(location, velocity, radius,
        detailScale: effectiveDetailScale));
  }

  void explosionAt({
        required Vec2 location,
        Vec2? velocity,
        bool addParticles = false,
        required int damage,
        required double radius,
        LocalPlayerSprite? damagerDoer,
        bool fromNetwork = false,
        Mod mod = Mod.UNKNOWN}) {
    bool fullExplosion = addParticles || mod == Mod.HYPER || radius >= 35.0;
    clearWorldArea(location, radius, velocity, fullExplosion);
    if (addParticles) {
      checkNotNull(velocity);
      _spawnExplosionVisuals(location, velocity == null ? Vec2.ZERO : velocity, radius);
    }
    addVelocityFromExplosion(location, damage, radius, !fromNetwork, damagerDoer, mod);
    if (!fromNetwork) {
      _network.peer.sendSingleStateUpdate(StateUpdate()
        ..byteWorldDestruction = destructionAsNetworkUpdate(
            location, velocity == null ? Vec2.ZERO : velocity, radius, damage, addParticles));
    }
  }

  /// Returns a [0.0, 1.0] scale factor for terrain debris based on current draw FPS.
  /// Defaults to 1.0 before the first second of FPS samples has been collected.
  double _debrisBudgetScaleFromFps() {
    double fps = _drawFps.fps();
    final bool commander = isCommander;
    double instant = 1.0;
    if (fps > 0.0) {
      if (commander) {
        if (fps < 28.0) {
          instant = 0.0;
        } else if (fps < 40.0) {
          instant = 0.25;
        } else if (fps < 53.0) {
          instant = 0.55;
        }
      } else {
        if (fps < 25.0) {
          instant = 0.0;
        } else if (fps < 35.0) {
          instant = 0.35;
        } else if (fps < 48.0) {
          instant = 0.65;
        }
      }
    }
    final double governed = performanceGovernor.tier == QualityTier.low
        ? 0.0
        : performanceGovernor.detailScaleForRole(isCommander: commander);
    return min(instant, governed);
  }

  int _activeDebrisEffectCount() => _frameDebrisEffectCount;

  /**
   * Reduce the amount of particles if FPS is too low.
   */
  int _particleCountFromFps() {
    if (_drawFps.fps() < 25) {
      return 0;
    }
    if (_drawFps.fps() < 40) {
      return 10;
    }
    return 20;
  }

  void fillRectAt(Vec2 pos, Vec2 size, String colorString,  [bool fromNetwork = false]) {
    byteWorld.fillRectAt(pos, size, colorString);
    if (!fromNetwork) {
      _network.peer.sendSingleStateUpdate(StateUpdate()..byteWorldDraw = drawAsNetworkUpdate(pos, size, colorString));
    }
  }

  int advanceFrames(double duration) {
    int frames = 0;

    untilNextFrame -= duration;
    while (untilNextFrame <= 0.0) {
      untilNextFrame += FRAME_SPEED;
      frames++;
    }
    return frames;
  }

  void explosionAtSprite({
        required Sprite sprite,
        required Vec2 velocity,
        bool addParticles = false,
        required int damage,
        required double radius,
        required LocalPlayerSprite damageDoer,
        bool fromNetwork = false,
        Mod mod = Mod.UNKNOWN}) {
    Vec2 center = sprite.centerPoint();
    bool fullExplosion = addParticles || mod == Mod.HYPER || radius >= 35.0;
    clearWorldArea(center, radius, velocity, fullExplosion);
    if (radius > 3 && addParticles) {
      _spawnExplosionVisuals(center, velocity, radius);
    }
    if (damage > 0) {
      addVelocityFromExplosion(
          center, damage, radius, !fromNetwork, damageDoer, mod);
    }
    if (!fromNetwork) {
      // TODO: Buffer here instead ?
      _network.peer.sendSingleStateUpdate(StateUpdate()..
          byteWorldDestruction = destructionAsNetworkUpdate(
              center, velocity, radius, damage, addParticles));
    }
  }

  void clearWorldArea(Vec2 location, double radius,
      [Vec2? velocity, bool fullExplosion = true]) {
    double fpsScale = _debrisBudgetScaleFromFps();
    int maxActive = ((fullExplosion ? 18 : 7) * fpsScale).round();
    bool canSpawnDebris =
        radius >= 6.0 && fpsScale > 0.0 && _activeDebrisEffectCount() < maxActive;
    int maxSamples = canSpawnDebris ? (fullExplosion ? 18 : 4) : 0;
    bool drawScorch = effectiveDetailScale > 0.35;

    dynamic sampled = byteWorld.clearAt(
      location,
      radius,
      maxColorSamples: maxSamples,
      drawScorch: drawScorch,
    );
    if (canSpawnDebris && sampled is List<String> && sampled.isNotEmpty) {
      TerrainDebrisEffect debris = TerrainDebrisEffect(
        this,
        location,
        velocity ?? Vec2.ZERO,
        radius,
        sampled,
        fullExplosion: fullExplosion,
        budgetScale: fpsScale,
      );
      if (!debris.remove) {
        _frameDebrisEffectCount++;
        addSprite(debris);
      }
    }
  }

  /**
   * Ensures that we have a connection to all clients in the game.
   * This is to be able to elect a new server in case the current server dies.
   *
   * We also ensure the sprites in the world have consistent owners.
   */
  void connectToAllPeersInGameState() {
    final String? selfId = _network.peer.id;
    final String commanderId =
        _network.gameState.gameStateProto.actingCommanderId;
    if (!_network.isCommander() &&
        selfId != null &&
        commanderId.isNotEmpty &&
        commanderId != selfId &&
        !_network.peer.hasConnectionTo(commanderId) &&
        !_network.peer.hasHadConnectionTo(commanderId)) {
      _network.peer.connectTo(commanderId);
    }
    final bool selfJoinedGame =
        selfId != null && _network.gameState.isInGame(selfId);

    for (PlayerInfoProto info in _network.gameState.playerInfoList()) {
      Sprite? sprite = spriteIndex[info.spriteId];
      if (sprite is LocalPlayerSprite) {
        // Make sure the ownerId is consistent with the connectionId.
        sprite.ownerId = info.connectionId;
        sprite.info = info;
      }
      if (!_network.peer.hasConnectionTo(info.connectionId) && !_network.peer.hasHadConnectionTo(info.connectionId)) {
        // Decide if I'm responsible for the connection.
        // Joining clients (!loader.completed()) proactively connect to all
        // in-game peers so a direct connection already exists if the commander
        // changes mid-join before existing peers know about the joiner.
        if (selfId != null &&
            info.connectionId != selfId &&
            (selfId.compareTo(info.connectionId) < 0 || !loader.completed())) {
          hudMessages.display(
              "Creating neighbour connection to ${info.name}");
          ConnectionWrapper conn = _network.peer.connectTo(info.connectionId);
          if (selfJoinedGame && info.connectionId != commanderId) {
            conn.markAsClientToClientConnection();
          }
        }
      } else if (!_network.isCommander() &&
          selfJoinedGame &&
          info.connectionId != selfId &&
          info.connectionId != commanderId) {
        // Connection may have been opened early via autoConnectToPeers() before
        // this peer appeared in GameState; promote it to a valid client-to-client
        // game connection so frames and sprites flow immediately.
        ConnectionWrapper? existing = _network.peer.connections[info.connectionId];
        if (existing != null && !existing.isValidGameConnection() && !existing.isClosedConnection()) {
          existing.markAsClientToClientConnection();
        }
      }
    }
  }

  clearFromNetworkUpdate(ByteWorldDestruction data) {
    Vec2 pos =  Vec2.fromProto(data.position);
    double radius = data.radius;
    int damage = data.damage;
    Vec2 velocity = Vec2.fromProto(data.velocity);
    explosionAt(
        location:pos, velocity:velocity,
        addParticles:data.addParticles, damage:damage,
        radius:radius, fromNetwork:true);
  }

  ByteWorldDestruction destructionAsNetworkUpdate(Vec2 pos, Vec2 velocity, double radius, int damage,
      bool addParticles) {
    return ByteWorldDestruction()
      ..position = pos.toProto()
      ..velocity = velocity.toProto()
      ..radius = radius
      ..addParticles = addParticles
      ..damage = damage;
  }

  ByteWorldDraw drawAsNetworkUpdate(Vec2 pos, Vec2 size, String colorString) {
    return
      ByteWorldDraw()
      ..position = pos.toProto()
      ..size = size.toProto()
      ..color = colorString;
  }
  
  void addVelocityFromExplosion(Vec2 location, int damage, double radius, bool doDamage, LocalPlayerSprite? damageDoer, Mod mod) {
    for (Sprite sprite in _spatialGrid.queryArea(location.x, location.y, radius)) {
      if (sprite is MovingSprite && sprite.collision) {
        int damageTaken = velocityForSingleSprite(sprite, location, radius, damage);
        if (doDamage && damageTaken > 0 && sprite.takesDamage(mod)) {
          if (damageDoer == null) {
            log.warning("Can't take damager $damageTaken - not inflicted by player!");
          } else {
            sprite.takeDamage(damageTaken.toInt(), damageDoer, mod);
            if (sprite == this.playerSprite) {
              Random r = new Random();
              this.explosionFlash += r.nextDouble() * 1.5;
            }
          }
        }
      }
    }
  }

  startAsServer([String? name]) {
    assert(network().peer.connectedToServer());
    assert(network().peer.id != null);
    assert(loader.selectedWorldName() != null);
    addLocalPlayerSprite(name == null ? _localStorage['playerName'] : name);
    _network.setAsActingCommander();
    final String? selected = loader.selectedWorldName();
    if (selected != null && selected.isNotEmpty) {
      _network.gameState.gameStateProto.mapName = selected;
    }
  }


  void addSprite(Sprite sprite) {
    if (sprite.spawn_sound != null) {
      playSoundAtSprite(sprite, sprite.spawn_sound!);
    }
    spriteIndex.addSprite(sprite);
  }

  void removeSprite(int networkId) {
    if (networkId == playerSprite?.networkId) {
      log.severe("Removal of playerSprite is not allowed!");
      return;
    }
    // Remove any associated sound.
    _sounds.stopPlayId(networkId.toString());
    spriteIndex.removeSprite(networkId);
  }

  void replaceSprite(int id, Sprite sprite) {
    spriteIndex.replaceSprite(id, sprite);
  }

  void clearScreen() {
    spriteIndex.clear();
  }

  void drawFpsCounters() {
    if (localKeyState.debug) {
      final font = _canvas.font;
      final List<String> lines = [
        "DrawFps: $_drawFps",
        "Quality: ${qualityTier.name.toUpperCase()} (${(effectiveDetailScale * 100).round()}%) NetFPS: ${performanceGovernor.targetNetworkFrameRate()}",
        "Sprites: ${spriteIndex.count()}",
        ..._network.keyFrameDebugData(),
      ];
      _canvas.font = 'bold 14pt Calibri';
      _canvas.strokeStyle = "#000000".toJS;
      _canvas.lineWidth = 3;
      _canvas.fillStyle = "#ffeb3b".toJS;
      const double lineHeight = 20.0;
      final double startY = _height - 10.0 - (lines.length - 1) * lineHeight;
      for (int i = 0; i < lines.length; i++) {
        final double y = startY + i * lineHeight;
        _canvas.strokeText(lines[i], 8, y);
        _canvas.fillText(lines[i], 8, y);
      }
      _canvas.font = font;
    }
  }

  num width() => _width;
  num height() => _height;
  Network network() => _network;
  ImageIndex imageIndex() => _imageIndex;
  PowerupManager? powerupManager() => _powerupManager;
  FpsCounter drawFps() => _drawFps;
  ConfigParams config() => _configParams;
  gaReporter() => _gaReporter;
  bool get isCommander => _network.isCommander();
  LocalStorage get localStorage => _localStorage;

  toString() => "World[${_network.peer.id}] commander ${_network.isCommander()}";

  final PerformanceGovernor performanceGovernor = PerformanceGovernor();

  QualityTier get qualityTier => performanceGovernor.tier;

  double get effectiveDetailScale {
    double fps = 0.0;
    bool commander = false;
    try {
      fps = drawFps().fps();
      commander = isCommander;
    } catch (_) {}
    return performanceGovernor.effectiveDetailScale(fps,
        isCommander: commander);
  }

  void rollbackToRemoteMapSelection(String winnerId, String winnerMapName) {
    clearScreen();
    playerSprite = null;
    _inDeathCamera = false;
    _cameraZoom = 1.0;
    _network.gameState.reset();
    _network.gameState.gameStateProto.actingCommanderId = winnerId;
    if (winnerMapName.isNotEmpty) {
      _network.gameState.gameStateProto.mapName = winnerMapName;
    }
    _network.resetGameConnections();
    loader.rollbackForMapTieBreak();
    if (!_network.peer.connectedToServer() && _network.peer.id != null) {
      _network.peer.reconnect();
    }
  }

  void resetPartialJoinForNewCommander(ConnectionWrapper? newCommanderConn) {
    clearScreen();
    playerSprite = null;
    newCommanderConn?.resetHandshakeReceived();
    loader.resetPartialJoinForNewCommander();
  }
}
