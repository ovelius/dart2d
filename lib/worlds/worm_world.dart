import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/world_phys.dart';
import 'package:dart2d/worlds/world_listener.dart';
import 'package:dart2d/util/util.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/net/net.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/world_util.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/phys/phys.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:di/di.dart';
import 'dart:math';
import 'player_world_selector.dart';

@Injectable()
class WormWorld extends World {
  final Logger log = new Logger('WormWorld');
  Loader loader;
  SpriteIndex spriteIndex;
  ImageIndex _imageIndex;
  MobileControls _mobileControls;
  FpsCounter _drawFps;
  Network _network;
  Map _localStorage;
  KeyState localKeyState;
  HudMessages hudMessages;
  PacketListenerBindings _packetListenerBindings;
  var _canvas = null;
  var _canvasElement = null;
  Vec2 viewPoint = new Vec2();
  Vec2 halfWorld;
  ByteWorld byteWorld;
  Vec2 gravity = new Vec2(0.0, 300.0);

  int _width, _height;
  double explosionFlash = 0.0;

  WormWorld(
      Network network,
      Loader loader,
      @LocalKeyState() KeyState localKeyState,
      @WorldCanvas() Object canvasElement,
      @LocalStorage() Map storage,
      @ServerFrameCounter() FpsCounter serverFrameCounter,
      SpriteIndex spriteIndex,
      ImageIndex imageIndex,
      ChunkHelper chunkHelper,
      ByteWorld byteWorld,
      HudMessages hudMessages,
      WorldListener worldListener,
      MobileControls mobileControls,
      PacketListenerBindings packetListenerBindings) {
    this._localStorage = storage;
    this._imageIndex = imageIndex;
    this._drawFps = serverFrameCounter;
    this._mobileControls = mobileControls;
    this._canvasElement = canvasElement;
    this._width = _canvasElement.width;
    this._height = _canvasElement.height;
    this._canvas = _canvasElement.context2D;
    this.byteWorld = byteWorld;
    halfWorld = new Vec2(this.width() / 2, this.height() / 2 );
    this.spriteIndex = spriteIndex;
    this._packetListenerBindings = packetListenerBindings;
    this.localKeyState = localKeyState;
    localKeyState.world = this;
    localKeyState.registerGenericListener((e) {
      if (playerSprite != null && !playerSprite.isMappedKey(e)) {
        invalidKeysPressed++;
        if (invalidKeysPressed > 2) {
          controlHelperTime = 4.0;
        }
      } else {
        invalidKeysPressed = 0;
      }
    });
    this.hudMessages = hudMessages;
    this._network = network;
    network.world = this;
    this.loader = loader;
    worldListener.setWorld(this);
  }
  
  void collisionCheck(int networkId, duration) {
    Sprite sprite = spriteIndex[networkId];
    
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
        if (sprite.position.x + sprite.size.x > byteWorld.width) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_RIGHT);
        }
        if (sprite.position.x < 0) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_LEFT);
        }
        if (sprite.position.y + sprite.size.y > byteWorld.height) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_BELOW);
        }
        if (sprite.position.y - sprite.size.y < 0) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_ABOVE);
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

  void connectTo(var id, [String name = null, bool startGame = true]) {
    hudMessages.display("Connecting to ${id}");
    _network.peer.connectTo(id);
    _network.gameState.actingCommanderId = null;
    if (startGame) {
      _network.findServer();
      if (_network.getServerConnection() == null) {
        throw new StateError("No server connection, can't connect to game :S Got ${_network.safeActiveConnections()}");
      }

      int playerSpriteId = _imageIndex.getImageIdByName(_localStorage['playerSprite']);
      _network.getServerConnection().connectToGame(
          name == null ? _localStorage['playerName'] : name, playerSpriteId);
    }
  }

  /**
   * Display a message in the world and send it to the network for remote display.
   */
  void displayHudMessageAndSendToNetwork(String message, [double period]) {
    hudMessages.display(message, period);
    _network.sendMessage(message);
  }

  bool loaderCompleted() => loader.completed();

  void frameDraw([double duration = 0.01, bool slowDown = false]) {
    if (!loader.completed()) {
      if (loader.loadedAsServer()) {
        // We are server.
        startAsServer();
        loader.markCompleted();
      } else if (loader.hasGameState()) {
        // We are client.
        initByteWorld("");
        loader.markCompleted();
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

    assert(byteWorld.initialized());

    // Count the draw FPS before adjusting the duration.
    _drawFps.timeWithFrames(duration, 1);
    if (duration >= 0.041 && slowDown) {
      // Slow down the game instead of skipping frames.
      duration = 0.041;
    }
    int frames = advanceFrames(duration);

    for (Sprite sprite in spriteIndex.putPendingSpritesInWorld()) {
     if (sprite is Particles && sprite.sendToNetwork) {
       Map data = {WORLD_PARTICLE: sprite.toNetworkUpdate()};
       _network.peer.sendDataWithKeyFramesToAll(data);
     }
    }

    _canvas
      ..clearRect(0, 0, _width, _height)
      ..setFillColorRgb(135, 206, 250)
      ..fillRect(0, 0, _width, _height)
      ..save();

    if (playerSprite != null) {
      Vec2 playerCenter = playerSprite.centerPoint();
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
    _canvas.globalAlpha = 0.7;
   byteWorld.drawAsMiniMap(_canvas, 0, 0);
    _canvas.restore();

    for (int networkId in spriteIndex.spriteIds()) {
      var sprite = spriteIndex[networkId];
      _canvas.save();
      _canvas.translate(-viewPoint.x, -viewPoint.y);
      if (!freeze && !_network.hasNetworkProblem()) {
        sprite.frame(duration, frames, gravity);
      }
      if(shouldDraw(sprite))
        sprite.draw(_canvas, localKeyState.debug);
      collisionCheck(networkId, duration);
      if (sprite.remove) {
        spriteIndex.removeSprite(sprite.networkId);
      }
      _canvas.restore();
    }

    if (explosionFlash > 0) {
      _canvas.fillStyle = "rgba(255, 255, 255, ${explosionFlash})";
      _canvas.fillRect(0, 0, _width, _height);
      explosionFlash -= duration * 5;
    }

    if (controlHelperTime > 0) {
      drawControlHelper(_canvas, controlHelperTime, playerSprite, _width, _height);
      controlHelperTime -= duration;
    }

    drawKilledView(_canvas, this, _width, _height, playerSprite, spriteIndex, _imageIndex);

    spriteIndex.removePending();

    // Only send to network if server frames has passed.
    if (frames > 0) {
      _network.frame(duration, spriteIndex.getAndClearNetworkRemovals());
    }
    // 1 since we count how many times this method is called.
    drawFpsCounters();
    hudMessages.render(this, _canvas, duration);

    _mobileControls.draw();

    _canvas.restore();
  }

  MovingSprite getOrCreateSprite(int networkId, SpriteConstructor constructor, ConnectionWrapper wrapper) {
    Sprite sprite = spriteIndex[networkId];
    if (sprite == null && constructor != SpriteConstructor.DO_NOT_CREATE) {
      sprite = SpriteIndex.fromWorldByIndex(this, networkId, wrapper.id, constructor);
      if (sprite != null) {
        sprite.networkType = NetworkType.REMOTE;
        sprite.networkId = networkId;
        // This might not be 100% accurate, since onwer might be:
        // Client -> Server -> Client.
        // But if that is the case it will be updated when we parse the GameState.
        sprite.ownerId = wrapper.id;
        addSprite(sprite);
      } else {
        log.warning("Unable to create sprite ${networkId} with constructor ${constructor}");
      }
    }
    return sprite;
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

  void createLocalClient(int spriteId,  Vec2 position) {
    spriteIndex.spriteNetworkId = spriteId;
    PlayerInfo info = _network.getGameState().playerInfoByConnectionId(network().peer.id);
    if (info == null) {
      throw new StateError("Cannot create local client as it is missing from GameState! Was ${_network.getGameState()}");
    }
    info.updateWithLocalKeyState(localKeyState);
    playerSprite = new LocalPlayerSprite(
        this, _imageIndex, _mobileControls, info,
        position,
        0);
    _adjustPlayerSprite();
    addSprite(playerSprite);
  }
  
  addLocalPlayerSprite(String name) {
    int id = _network.gameState.getNextUsablePlayerSpriteId(this);
    PlayerInfo info = new PlayerInfo(name, _network.peer.id, id);
    info.updateWithLocalKeyState(localKeyState);
    playerSprite = new LocalPlayerSprite(
        this, _imageIndex, _mobileControls, info,
        byteWorld.randomPoint(),
        0);
    playerSprite.networkId = id;
    playerSprite.spawnIn = 1.0;
    _adjustPlayerSprite();
    _network.gameState.addPlayerInfo(info);
    addSprite(playerSprite);
  }

  void _adjustPlayerSprite() {
    String spriteName = _localStorage['playerSprite'];
    int playerSpriteId = _imageIndex.getImageIdByName(spriteName);
    var img = _imageIndex.getImageByName(spriteName);
    print("${img.runtimeType}");
    int height = img.height;
    int width = PlayerWorldSelector.playerSpriteWidth(spriteName);
    double ratio = height / width;
    playerSprite.size = LocalPlayerSprite.DEFAULT_PLAYER_SIZE;
    playerSprite.setImage(playerSpriteId, width);
    playerSprite.size.y *= ratio;
  }
  
  void addParticlesFromNetworkData(List<int> data) {
    addSprite(new Particles.fromNetworkUpdate(data, this));
  }
  
  void explosionAt(Vec2 location, Vec2 velocity, int damage, double radius, Sprite damagerDoer, [bool fromNetwork = false]) {
    clearWorldArea(location, radius);
    if (velocity != null) {
      addSprite(new Particles(this, null, location, velocity, radius, _particleCountFromFps()));
    }
    addVelocityFromExplosion(location, damage, radius, !fromNetwork, damagerDoer);
    if (!fromNetwork) {
      Map data = {WORLD_DESTRUCTION: destructionAsNetworkUpdate(location, velocity, radius, damage)};
      _network.peer.sendDataWithKeyFramesToAll(data);
    }
  }

  /**
   * Reduce the amount of particles if FPS is too low.
   */
  int _particleCountFromFps() {
    if (_drawFps.fps() < 25) {
      return 5;
    }
    if (_drawFps.fps() < 40) {
      return 15;
    }
    return 30;
  }

  void fillRectAt(Vec2 pos, Vec2 size, String colorString,  [bool fromNetwork = false]) {
    byteWorld.fillRectAt(pos, size, colorString);
    if (!fromNetwork) {
      Map data = {WORLD_DRAW: drawAsNetworkUpdate(pos, size, colorString)};
      _network.peer.sendDataWithKeyFramesToAll(data);
    }
  }

  int advanceFrames(double duration) {
    int frames = 0;

    untilNextFrame -= duration;
    while (untilNextFrame <= 0.0) {
      untilNextFrame += FRAME_SPEED;
      frames++;
    }
    serverFrame += frames;
    return frames;
  }

  void explosionAtSprite(Sprite sprite, Vec2 velocity, int damage, double radius, Sprite damageDoer, [bool fromNetwork = false]) {
    clearWorldArea(sprite.centerPoint(), radius);
    if (radius > 3) {
      addSprite(
          new Particles(this, null, sprite.position, velocity, radius * 1.5, _particleCountFromFps()));
      addVelocityFromExplosion(
          sprite.centerPoint(), damage, radius, !fromNetwork, damageDoer);
    }
    if (!fromNetwork) {
      Map data = {WORLD_DESTRUCTION: destructionAsNetworkUpdate(sprite.centerPoint(), velocity, radius, damage)};
      _network.peer.sendDataWithKeyFramesToAll(data);
    }
  }


  
  void clearWorldArea(Vec2 location, double radius) {
    byteWorld.clearAt(location, radius);
    // Breaking away stuff is too slow :(
    // WorldPhys.lookAround(this, location.x, location.y, radius);
  }

  /**
   * Ensures that we have a connection to all clients in the game.
   * This is to be able to elect a new server in case the current server dies.
   *
   * We also ensure the sprites in the world have consitent owners.
   */
  void connectToAllPeersInGameState() {
    for (PlayerInfo info in _network.gameState.playerInfoList()) {
      LocalPlayerSprite sprite = spriteIndex[info.spriteId];
      if (sprite != null) {
        // Make sure the ownerId is consistent with the connectionId.
        sprite.ownerId = info.connectionId;
        sprite.info = info;
      } else {
        log.warning("No matching sprite found for ${info}");
      }
      if (!_network.peer.hasConnectionTo(info.connectionId) && !_network.peer.hasHadConnectionTo(info.connectionId)) {
        // Decide if I'm responsible for the connection.
        if (_network.peer.id.compareTo(info.connectionId) < 0) {
          hudMessages.display(
              "Creating neighbour connection to ${info.name}");
          _network.peer.connectTo(info.connectionId).markAsClientToClientConnection();
        }
      }
    }
  }

  clearFromNetworkUpdate(List<int> data) {
    Vec2 pos = new Vec2(data[0] / DOUBLE_INT_CONVERSION, data[1] / DOUBLE_INT_CONVERSION);
    double radius = data[2] / DOUBLE_INT_CONVERSION;
    int damage = data[3];
    Vec2 velocity = null;
    if (data.length > 4) {
      velocity = new Vec2(data[4] / DOUBLE_INT_CONVERSION, data[5] / DOUBLE_INT_CONVERSION);
    }
    explosionAt(pos, velocity, damage, radius, null, true);
  }
  
  List<int> destructionAsNetworkUpdate(Vec2 pos, Vec2 velocity, double radius, int damage) {
    List<int> base = [
      (pos.x * DOUBLE_INT_CONVERSION).toInt(), 
      (pos.y * DOUBLE_INT_CONVERSION).toInt(),      
      (radius * DOUBLE_INT_CONVERSION).toInt(),
      damage];
    if (velocity != null) {
     base.addAll([
         (velocity.x * DOUBLE_INT_CONVERSION).toInt(), 
         (velocity.y * DOUBLE_INT_CONVERSION).toInt()]);
    }
    return base;
  }

  drawFromNetworkUpdate(List data) {
    Vec2 pos = new Vec2(data[0] / DOUBLE_INT_CONVERSION, data[1] / DOUBLE_INT_CONVERSION);
    Vec2 size = new Vec2(data[2] / DOUBLE_INT_CONVERSION, data[3] / DOUBLE_INT_CONVERSION);
    String colorString = data[4];
    fillRectAt(pos, size, colorString, true);
  }

  List drawAsNetworkUpdate(Vec2 pos, Vec2 size, String colorString) {
    return [(pos.x.toInt() * DOUBLE_INT_CONVERSION).toInt(),
    (pos.y.toInt() * DOUBLE_INT_CONVERSION).toInt(),
    (size.x.toInt() * DOUBLE_INT_CONVERSION).toInt(),
    (size.y.toInt() * DOUBLE_INT_CONVERSION).toInt(),
    colorString];
  }
  
  void addVelocityFromExplosion(Vec2 location, int damage, double radius, bool doDamage, Sprite damageDoer) {
    for (int networkId in spriteIndex.spriteIds()) {
      Sprite sprite = spriteIndex[networkId];
      if (sprite is MovingSprite && sprite.collision) {
        int damageTaken = velocityForSingleSprite(sprite, location, radius, damage).toInt();
        if (doDamage && damageTaken > 0 && sprite.takesDamage()) {
          sprite.takeDamage(damageTaken.toInt(), damageDoer);
          if (sprite == this.playerSprite) {
            Random r = new Random();
            this.explosionFlash += r.nextDouble() * 1.5;
          }
        }
      }
    }
  }

  startAsServer([String name]) {
    initByteWorld();
    assert(imageIndex != null);
    addLocalPlayerSprite(_localStorage['playerName']);
    _network.setAsActingCommander();
  }

  void initByteWorld([String map = 'world.png']) {
    var worldImage = map.isNotEmpty
        ? _imageIndex.getImageByName(map)
        : _imageIndex.getImageById(ImageIndex.WORLD_IMAGE_INDEX);
    byteWorld.setWorldImage(worldImage);
  }

  void addSprite(Sprite sprite) {
    spriteIndex.addSprite(sprite);
  }

  void removeSprite(int networkId) {
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
      _canvas.fillStyle = "#ffffff";
      _canvas.font = '16pt Calibri';
      _canvas.fillText("DrawFps: $_drawFps", 0, 20);
      _canvas.fillText("NetworkFps: $networkFps", 0, 40);
      _canvas.fillText("Sprites: ${spriteIndex.count()}", 0, 60);
      _canvas.fillText("KeyFrames: ${_network.keyFrameDebugData()}", 0, 80);
      _canvas.font = font;
    }
  }

  num width() => _width;
  num height() => _height;
  Network network() => _network;
  ImageIndex imageIndex() => _imageIndex;
  FpsCounter drawFps() => _drawFps;

  toString() => "World[${_network.peer.id}] commander ${_network.isCommander()}";
}
