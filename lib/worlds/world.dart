library world;

import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/phys/phys.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'package:dart2d/sprites/particles.dart';
import 'package:dart2d/worlds/sprite_index.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/rtc.dart';
import 'package:dart2d/worlds/loader.dart';
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

Map<int, String> KEY_TO_NAME = {
  KeyCode.LEFT: "Left",
  KeyCode.RIGHT: "Right",
  KeyCode.DOWN: "Down",
  KeyCode.UP: "Up",   
};

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
  
  setJsPeer(var jsPeer) {
    peer = new PeerWrapper(this, jsPeer);
    network = new Server(this, peer);
  }
  
  String toKey(int code) {
    if (KeyCode.isCharacterKey(code)) {
      return new String.fromCharCode(code);
    } else {
      return KEY_TO_NAME[code];
    }
  }
  
  void drawControlHelper(CanvasRenderingContext2D context) {
    if (controlHelperTime > 0) {
      context.setFillColorRgb(255, 255, 255);
      context.setStrokeColorRgb(255, 255, 255);
      context.fillText("Controls are:", WIDTH ~/ 3, 40);
      int i = LocalPlayerSprite.controls.length;
      for (String key in LocalPlayerSprite.controls.keys) {
        int x = WIDTH ~/ 3;
        int y = 70 + i*30;
        String current = toKey(LocalPlayerSprite.controls[key]);
        context.fillText("${key}: ${current}", x, y);
        i--;
      }
    }    
  }
  
  void connectTo(var id, [String name = null]) {
    if (name != null) {
      this.playerName = name;
    }
    hudMessages.display("Connecting to ${id}");
    network = new Client(this, peer);
    network.localPlayerName = this.playerName;
    network.peer.connectTo(id);
  }

  void frameDraw([double duration = 0.01]) {
    if (restart) {
      clearScreen();
      restart = false;
    }
    int frames = advanceFrames(duration);
 
    for (Sprite sprite in spriteIndex.putPendingSpritesInWorld()) {
      if (sprite is Particles && sprite.sendToNetwork) {
        Map data = {WORLD_PARTICLE: sprite.toNetworkUpdate()};
        network.peer.sendDataWithKeyFramesToAll(data);
      } 
    }

    canvas.clearRect(0, 0, WIDTH, HEIGHT);
    canvas.setFillColorRgb(0, 0, 0);
    canvas.fillRect(0, 0, WIDTH, HEIGHT);
    canvas.save();
  
    for (int networkId in spriteIndex.spriteIds()) {
      var sprite = spriteIndex[networkId];
      canvas.resetTransform();
      if (!freeze && !network.hasNetworkProblem()) {
        sprite.frame(duration, frames);
      }
      sprite.draw(canvas, localKeyState.debug);
      collisionCheck(networkId, duration);
      if (sprite.remove) {
        spriteIndex.removeSprite(sprite.networkId);
      }
    }
  
    spriteIndex.removePending();
  
    // Only send to network if server frames has passed.
    if (frames > 0) {
      network.frame(duration, spriteIndex.getAndClearNetworkRemovals());
    }
    // 1 since we count how many times this method is called.
    drawFps.timeWithFrames(duration, 1);
    drawFpsCounters();
    hudMessages.render(canvas, duration);
    canvas.restore();
  }
  
  void collisionCheck(int networkId, duration);
  
  int advanceFrames(double duration) {
    int frames = 0;
    
    untilNextFrame -= duration;
    while (untilNextFrame <= 0.0) {
      untilNextFrame += FRAME_SPEED;
      frames++;
    }
    serverFrame += frames;
    serverFps.timeWithFrames(duration, frames);
    think(duration, frames);
    return frames;
  }
  
  void think(double duration, int frames);

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

  void createLocalClient(Map dataFromServer) {
    spriteNetworkId = dataFromServer["spriteId"];
    int spriteIndex = dataFromServer["spriteIndex"];
    addSprite(
        new RemotePlayerSprite(
            this, localKeyState, 400.0, 200.0, spriteIndex));
  }

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

  /*
  Iterable<Sprite> getFilteredSprites(bool test(Sprite sprite)) {
    return sprites.values.where(test);
  }*/
  
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
  
  num negate(Random r) {
    return r.nextBool() ? 1 : -1;    
  }

  num width() => WIDTH;
  num height() => HEIGHT;
  toString() => "World[${peer.id}]";
}


class FpsCounter extends FrameTrigger {
  FpsCounter() : super(1.0);
}

class FrameTrigger {
  double period = 1.0;
  double fps = 0.0;

  double nextTriggerIn = 1.0;
  int frames = 0;

  FrameTrigger(double period) {
    this.period = period;
    this.nextTriggerIn = period;
  }

  bool timeWithFrames(double time, int framesPassed) {
    this.frames += framesPassed;
    nextTriggerIn -= time;
    if (nextTriggerIn < 0.0) {
      fps = frames / (1.0 - nextTriggerIn); 
      frames = 0;
      nextTriggerIn += period;
      return true;
    }
    return false;
  }
  
  String toString() {
    return fps.toStringAsFixed(2);
  }
}
