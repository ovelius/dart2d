library world;

import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/phys/phys.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/fps_counter.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'package:dart2d/sprites/particles.dart';
import 'package:dart2d/worlds/sprite_index.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/rtc.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/worlds/world_util.dart';
import 'package:dart2d/hud_messages.dart';
import 'package:di/di.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/keystate.dart';
import 'dart:math';
import 'dart:html';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

int WIDTH;
int HEIGHT;

int serverFrame = 0;
// 25 server frames per second.
const FRAME_SPEED = 1.0/15;
double untilNextFrame = FRAME_SPEED;

CanvasRenderingContext2D canvas = null;
CanvasElement canvasElement = null;

abstract class World {
  final Logger log = new Logger('World');
  
  String playerName = "Unkown";
  int invalidKeysPressed = 0;

  PeerWrapper peer; 
  // Representing the player in the world.
  LocalPlayerSprite playerSprite;
  // The next id we use for new sprites.
  int spriteNetworkId = 0;

  // Sprite container.
  SpriteIndex spriteIndex;

  HudMessages hudMessages;
  KeyState localKeyState; 
  // For debuggging.
  FpsCounter drawFps = new FpsCounter();
  FpsCounter serverFps = new FpsCounter();
  
  bool restart = false;
  bool freeze = false;
  bool connectOnOpenConnection = false;

  Network network;
  
  Loader loader;
  
  double controlHelperTime = 0.0;
  
  Injector injector;
  
  World(int width, int height) {
    WIDTH = width;
    HEIGHT = height;
    localKeyState = new KeyState(this);
    localKeyState.registerGenericListener((e) {
      if (!playerSprite.isMappedKey(e)) {
        invalidKeysPressed++;
        if (invalidKeysPressed > 2) {
          controlHelperTime = 4.0;
        }
      } else {
        invalidKeysPressed = 0;
      }
    });
    hudMessages = new HudMessages(this);
    loader = new Loader(canvasElement, this);
    spriteIndex = new SpriteIndex();
  }

  /**
   * Connect to the given id.
   * The ID is an id of the rtc subsystem.
   */
  void connectTo(var id, [String name = null]);

  /**
   * Advances the world this amount of time.
   * Update objects.
   * Draw objects.
   * Possibly send updates to network.
   */
  void frameDraw([double duration = 0.01]);

  /**
   * Execute a collision check on this sprite.
   * A collision may occur with other sprite or the world itself.
   */
  void collisionCheck(int networkId, duration);

  MovingSprite getOrCreateSprite(int networkId, int flags, ConnectionWrapper wrapper) {
    Sprite sprite = spriteIndex[networkId];
    if (sprite == null) {
      sprite = SpriteIndex.fromWorldByIndex(this, flags);
      sprite.networkType = NetworkType.REMOTE;
      sprite.networkId = networkId;
      // This might not be 100% accurate, since onwer might be:
      // Client -> Server -> Client.
      // But if that is the case it will be updated when we parse the GameState.
      sprite.ownerId = wrapper.id;
      addSprite(sprite);
    } 
    return sprite;
  }

  void clearScreen() {
    spriteIndex = new SpriteIndex();
  }

  /**
   * Create a local representation of this player in a remote world.
   */
  void createLocalClient(int spriteId, int spriteIndex);

  addLocalPlayerSprite(String name) {
    int id = network.gameState.getNextUsablePlayerSpriteId();
    int imageId = network.gameState.getNextUsableSpriteImage();
    PlayerInfo info = new PlayerInfo(name, network.peer.id, id);
    LocalPlayerSprite playerSprite = new LocalPlayerSprite(
        this, localKeyState, info,
        new Random().nextInt(WIDTH).toDouble(),
        new Random().nextInt(HEIGHT).toDouble(),
        imageByName["shipg01.png"]);
    playerSprite.networkId = id;
    playerSprite.setImage(imageId);
    network.gameState.playerInfo.add(info);
    addSprite(playerSprite);
  }

  startAsServer(String name, [bool forTest = false]) {
    addLocalPlayerSprite(name);
    if (forTest) {
      addLocalPlayerSprite(name);
    }
  }

  void drawFpsCounters() {
    if (localKeyState.debug) {
      var font = canvas.font;
      canvas.fillStyle = "#ffffff";
      canvas.font = '16pt Calibri';
      canvas.fillText("DrawFps: $drawFps", 0, 20);
      canvas.fillText("ServerFps: $serverFps", 0, 40);
      canvas.fillText("NetworkFps: $networkFps", 0, 60);
      canvas.fillText("Sprites: ${spriteIndex.count()}", 0, 80);
      canvas.fillText("KeyFrames: ${network.keyFrameDebugData()}", 0, 100);
      canvas.font = font;
    }
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
  
  setInjector(Injector injector) {
    this.injector = injector;
  }

  num width() => WIDTH;
  num height() => HEIGHT;
  toString() => "World[${peer.id}]";
}


