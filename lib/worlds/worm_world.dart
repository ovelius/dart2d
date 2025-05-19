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

  late int _width, _height;
  double explosionFlash = 0.0;
  bool soundEnabled = true;

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
    worldListener.setWorld(this);
  }
  
  void collisionCheck(int networkId, duration) {
    Sprite? sprite = spriteIndex[networkId];
    
    if(sprite is MovingSprite) {
      if (sprite.collision) {
        if (_network.isCommander() || sprite.networkType == NetworkType.LOCAL) {
          for (int id in spriteIndex.spriteIds()) {
            // Avoid duplicate checks, but only if server.
            if (_network.isCommander() && networkId >= id) {
              continue;
            }
            var otherSprite = spriteIndex[id];
            if (otherSprite is MovingSprite) {
              if (!otherSprite.collision) continue;
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

    List<int> data = byteWorld.getImageDataFor(xStart, yStart, xWidth, yHeight);

    int xBelowBase = (yHeight - 1) * (xWidth * 4);
    int collisionAngles = 0;
    for (int x = 0; x < xWidth; x++) {
      if (data[ x * 4] > 0) {
        collisionAngles |= MovingSprite.DIR_ABOVE;
      }
      int pos = xBelowBase + (x + 1) * 4 - 1;
      if (data[pos] > 0) {
        collisionAngles |= MovingSprite.DIR_BELOW;
      }
    }
    for (int y = 0; y < yHeight; y++) {
      int pos = y * (xWidth * 4) + 3;
      if (data[pos] > 0) {
        collisionAngles |= MovingSprite.DIR_LEFT;
      }
      int pos2 = y * (xWidth * 4) + (xWidth * 4) - 1;
      if (data[pos2] > 0) {
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
    if (duration >= 0.041 && slowDown) {
      // Slow down the game instead of skipping frames.
      duration = 0.041;
    }
    int frames = advanceFrames(duration);

    List<StateUpdate> particles = [];

    for (Sprite sprite in spriteIndex.putPendingSpritesInWorld()) {
     if (sprite is Particles && sprite.sendToNetwork) {
       particles.add(StateUpdate()..particleEffects = sprite.toNetworkUpdate());
     }
    }
    if (particles.isNotEmpty) {
      // TODO: Make part of main network loop instead.
      _network.peer.sendDataWithKeyFramesToAll(GameStateUpdates()
        ..stateUpdate.addAll(particles));
    }

    _canvas.fillStyle = "rgb(135,206,250)".toJS;
    _canvas
      ..clearRect(0, 0, _width, _height)
      ..fillRect(0, 0, _width, _height)
      ..save();


    if (playerSprite != null) {
      Vec2 playerCenter = playerSprite!.centerPoint();
      viewPoint.x = playerCenter.x - halfWorld.x;
      viewPoint.y = playerCenter.y - halfWorld.y;
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
    }
  
   byteWorld.drawAt(_canvas, viewPoint.x, viewPoint.y);
   _canvas.restore();

    for (int networkId in spriteIndex.spriteIds()) {
      MovingSprite sprite = spriteIndex[networkId] as MovingSprite;
      _canvas.save();
      _canvas.translate(-viewPoint.x, -viewPoint.y);
      if (!freeze && !_network.hasNetworkProblem()) {
        sprite.frame(duration, frames, gravity);
      }
      if(shouldDraw(sprite))
        sprite.draw(_canvas, localKeyState.debug);
      collisionCheck(networkId, duration);
      if (sprite.remove) {
        removeSprite(sprite.networkId!);
      }
      _canvas.restore();
    }

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
    if (_network.isCommander()) {
      _powerupManager.frame(duration);
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
      for (PlayerInfoProto info in _network.getGameState().playerInfoList()) {
        info.inGame = false;
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

  bool shouldDraw(Sprite sprite){
    if(sprite.invisibleOutsideCanvas) {
      double xMin = viewPoint.x;                        //leftest x-value
      double xMax = viewPoint.x + _canvas.canvas.width;  //rightest x-value
      double yMin = viewPoint.y;                        //highest y-value
      double yMax = viewPoint.y + _canvas.canvas.height; //lowest y-value
      
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
    }
    return true;
  }

  void playSound(Sound sound,{double volume = 1.0, bool multiPlay = false, String? playId = null}) {
    _sounds.playSound(sound, volume:volume, multiPlay:multiPlay, playId:playId);
  }

  void playSoundAtSprite(Sprite sprite, Sound sound, {multiPlay = false, playSpriteId = false}) {
    if (playerSprite != null) {
      double distance = (sprite.position.subtract(playerSprite!.position)).sum();
      double volume = 1.0 - (distance / 1000.0);
      if (volume > 0.01) {
        playSound(sound, volume: volume, multiPlay: multiPlay, playId:  playSpriteId ? sprite.networkId.toString() : null);
      }
    }
  }

  void createLocalClient(int spriteId,  Vec2 position) {
    spriteIndex.spriteNetworkId = spriteId;
    PlayerInfoProto? info = _network.getGameState().playerInfoByConnectionId(network().peer.id!);
    if (info == null) {
      throw "Self gamestate data is missing id: ${_network.peer.id}!";
    }
    network().gameState.updateWithLocalKeyState(network().peer.id!, localKeyState);
    playerSprite = new LocalPlayerSprite(
        this, _imageIndex, _mobileControls, info,
        position,
        0);
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
  
  void explosionAt({
        required Vec2 location,
        Vec2? velocity,
        bool addParticles = false,
        required int damage,
        required double radius,
        LocalPlayerSprite? damagerDoer,
        bool fromNetwork = false,
        Mod mod = Mod.UNKNOWN}) {
    clearWorldArea(location, radius);
    if (addParticles) {
      checkNotNull(velocity);
    }
    if (addParticles) {
      int particleCount = _particleCountFromFps();
      if (particleCount > 0) {
        addSprite(new Particles(
            this,
            null,
            location,
            velocity == null ? Vec2.ZERO : velocity,
            radius: radius,
            count: particleCount));
      }
    }
    addVelocityFromExplosion(location, damage, radius, !fromNetwork, damagerDoer, mod);
    if (!fromNetwork) {
      _network.peer.sendSingleStateUpdate(StateUpdate()
        ..byteWorldDestruction = destructionAsNetworkUpdate(
            location, velocity == null ? Vec2.ZERO : velocity, radius, damage, addParticles));
    }
  }

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
    clearWorldArea(sprite.centerPoint(), radius);
    if (radius > 3 && addParticles) {
      playSoundAtSprite(sprite, Sound.EXPLOSION, multiPlay:true);
      addSprite(
          new Particles(this, null, sprite.position, velocity, radius: radius * 1.5, count: _particleCountFromFps()));

    }
    if (damage > 0) {
      addVelocityFromExplosion(
          sprite.centerPoint(), damage, radius, !fromNetwork, damageDoer, mod);
    }
    if (!fromNetwork) {
      // TODO: Buffer here instead ?
      _network.peer.sendSingleStateUpdate(StateUpdate()..
          byteWorldDestruction = destructionAsNetworkUpdate(
              sprite.centerPoint(), velocity, radius, damage, addParticles));
    }
  }

  void clearWorldArea(Vec2 location, double radius) {
    byteWorld.clearAt(location, radius);
  }

  /**
   * Ensures that we have a connection to all clients in the game.
   * This is to be able to elect a new server in case the current server dies.
   *
   * We also ensure the sprites in the world have consistent owners.
   */
  void connectToAllPeersInGameState() {
    for (PlayerInfoProto info in _network.gameState.playerInfoList()) {
      Sprite? sprite = spriteIndex[info.spriteId];
      if (sprite is LocalPlayerSprite) {
        // Make sure the ownerId is consistent with the connectionId.
        sprite.ownerId = info.connectionId;
        sprite.info = info;
      }
      if (!_network.peer.hasConnectionTo(info.connectionId) && !_network.peer.hasHadConnectionTo(info.connectionId)) {
        // Decide if I'm responsible for the connection.
        if (_network.peer.id!.compareTo(info.connectionId) < 0) {
          hudMessages.display(
              "Creating neighbour connection to ${info.name}");
          _network.peer.connectTo(info.connectionId).markAsClientToClientConnection();
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
    for (int networkId in spriteIndex.spriteIds()) {
      Sprite? sprite = spriteIndex[networkId];
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
      var font = _canvas.font;
      _canvas.fillStyle = "#ff0000".toJS;
      _canvas.font = '16pt Calibri';
      _canvas.fillText("DrawFps: $_drawFps", 0, 20);
      _canvas.fillText("Sprites: ${spriteIndex.count()}", 0, 60);
      int i = 0;
      for (String connectionDebug in _network.keyFrameDebugData()) {
        _canvas.fillText(connectionDebug, 0, 80 + i *20);
        i++;
      }
      _canvas.font = font;
    }
  }

  num width() => _width;
  num height() => _height;
  Network network() => _network;
  ImageIndex imageIndex() => _imageIndex;
  FpsCounter drawFps() => _drawFps;
  ConfigParams config() => _configParams;
  gaReporter() => _gaReporter;
  bool get isCommander => _network.isCommander();
  LocalStorage get localStorage => _localStorage;

  toString() => "World[${_network.peer.id}] commander ${_network.isCommander()}";
}
