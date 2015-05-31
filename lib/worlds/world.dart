library world;

import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/net/connection.dart';
import 'package:dart2d/phys/phys.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'package:dart2d/sprites/particles.dart';
import 'package:dart2d/sprites/sprite_index.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/rtc.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/hud_messages.dart';
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

  PeerWrapper peer; 
  // Current sprites in our world.
  Map<int, Sprite> sprites = {};
  // The next id we use for new sprites.
  int spriteNetworkId = 0;
  // Sprites that will be added to the world next frame.
  List<Sprite> waitingSprites = [];
  // Removals that needs to sent to the network.
  List<int> networkRemovals = [];
  // Spritest that will be removed from the world next frame;
  List<int> removeSprites = [];
  // Sprites that will replace the current world sprites next frame.
  Map<int, Sprite> _replaceSprite = {};

  HudMessages hudMessages;
  KeyState localKeyState; 
  // For debuggging.
  FpsCounter drawFps = new FpsCounter();
  FpsCounter serverFps = new FpsCounter();
  
  bool restart = false;
  bool freeze = false;
  Network network;
  
  Loader loader;
  
  World(int width, int height) {
    WIDTH = width;
    HEIGHT = height;
    localKeyState = new KeyState(this);
    hudMessages = new HudMessages(this);
    loader = new Loader(canvasElement, this);
  }
  
  setJsPeer(var jsPeer) {
    peer = new PeerWrapper(this, jsPeer);
    network = new Server(this, peer);
  }
  
  void connectTo(var id, String name) {
    hudMessages.display("Connecting to ${id}");
    network = new Client(this, peer);
    network.localPlayerName = name;
    network.peer.connectTo(id);
  }
  
  operator [](id) => sprites[id];

  void frameDraw([double duration = 0.01]) {
    if (restart) {
      clearScreen();
      restart = false;
    }
    int frames = advanceFrames(duration);
 
    putPendingSpritesInWorld();

    canvas.clearRect(0, 0, WIDTH, HEIGHT);
    canvas.setFillColorRgb(0, 0, 0);
    canvas.fillRect(0, 0, WIDTH, HEIGHT);
    canvas.save();
  
    for (int networkId in sprites.keys) {
      var sprite = sprites[networkId];
      canvas.resetTransform();
      if (!freeze && !network.hasNetworkProblem()) {
        sprite.frame(duration, frames);
      }
      sprite.draw(canvas, localKeyState.debug);
      collisionCheck(networkId, duration);
      if (sprite.remove) {
        removeSprites.add(sprite.networkId);
      }
    }
  
    while (removeSprites.length > 0) {
      int id = removeSprites.removeAt(0);
      Sprite sprite = sprites[id];
      sprites.remove(id);
      log.fine("${this}: Removing sprite ${id} from world");
      if (sprite != null && sprite.networkType != NetworkType.REMOTE) {
        log.fine("${this}: Removing sprite ${id} from network");
        networkRemovals.add(id);
      }
    }
  
    // Only send to network if server frames has passed.
    if (frames > 0) {
      if (networkRemovals.length > 0) {
                     /// why why 
                     print("WORLD RTC RTC OOGA BOOGA INCOMING RELIABLE DATA WITH REMOVE KEY??? ${removals}");
                   }
      network.frame(duration, networkRemovals);
      networkRemovals.clear();
    }
    // 1 since we count how many times this method is called.
    drawFps.timeWithFrames(duration, 1);
    drawFpsCounters();
    hudMessages.render(canvas, duration);
    canvas.restore();
  }
  
  void collisionCheck(int networkId, duration);
  
  void putPendingSpritesInWorld() {
    while (waitingSprites.length > 0) {
      Sprite newSprite = waitingSprites.removeAt(0);
      if (newSprite.networkId == null) {
        newSprite.networkId = spriteNetworkId++;
        while (sprites.containsKey(newSprite.networkId)) {
          log.warning("${this}: Warning: World contains sprite ${newSprite.networkId} adding 1");
          newSprite.networkId = spriteNetworkId++;
        }
      }
      if (sprites.containsKey(newSprite.networkId)) {
        log.severe("World ${peer.id} Network controlled sprite ${newSprite}[${newSprite.networkId}] would overwrite existing sprite ${sprites[newSprite.networkId]} not adding it!");
        continue;
      }
      if (newSprite is Particles && newSprite.sendToNetwork) {
        Map data = {WORLD_PARTICLE: newSprite.toNetworkUpdate()};
        network.peer.sendDataWithKeyFramesToAll(data);
      }
      sprites[newSprite.networkId] = newSprite;
    }
    for (int id in new List.from(_replaceSprite.keys)) {
      sprites[id] = _replaceSprite.remove(id);
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
    serverFps.timeWithFrames(duration, frames);
    think(duration, frames);
    return frames;
  }
  
  void think(double duration, int frames);

  MovingSprite getOrCreateSprite(int networkId, int flags, ConnectionWrapper wrapper) {
    Sprite sprite = sprites[networkId];
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
    sprites = {};
    waitingSprites = [];
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
      canvas.fillText("Sprites: ${sprites.length}", 0, 80);
      canvas.fillText("KeyFrames: ${network.keyFrameDebugData()}", 0, 100);
      canvas.font = font;
    }
  }

  Iterable<Sprite> getFilteredSprites(bool test(Sprite sprite)) {
    return sprites.values.where(test);
  }
  
  void addSprite(Sprite sprite) {
    if (sprite.networkId != null) {
      if (sprites.containsKey(sprite.networkId)) {
        throw new StateError("Network controlled sprite ${sprite}[${sprite.networkId}] would overwrite existing sprite ${sprites[sprite.networkId]}");
      }
    }
    waitingSprites.add(sprite);
  }
  
  void removeSprite(int networkId) {
    removeSprites.add(networkId);
  }
  
  void replaceSprite(int id, Sprite sprite) {
    _replaceSprite[id] = sprite;
  }
  
  num negate(Random r) {
    return r.nextBool() ? 1 : -1;    
  }  
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
