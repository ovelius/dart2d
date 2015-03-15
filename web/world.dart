library dart2d;

import 'sprite.dart';
import 'movingsprite.dart';
import 'connection.dart';
import 'dart2d.dart';
import 'phys.dart';
import 'gamestate.dart';
import 'vec2.dart';
import 'astroid.dart';
import 'net.dart';
import 'rtc.dart';
import 'hud_messages.dart';
import 'imageindex.dart';
import 'keystate.dart';
import 'dart:math';
import 'playersprite.dart';

class World {
  int width;
  int height;

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

  HudMessages hudMessages;
  KeyState localKeyState;
  // For debuggging.
  FpsCounter drawFps = new FpsCounter();
  FpsCounter serverFps = new FpsCounter();
  
  bool loading = true;
  bool restart = false;
  Network network;
  
  World(int width, int height, var jsPeer) {
    this.width = width;
    this.height = height;
    localKeyState = new KeyState(this);
    peer = new PeerWrapper(this, jsPeer);
    hudMessages = new HudMessages(this);
    network = new Server(this, peer);
  }
  
  void connectTo(var id, String name) {
    network = new Client(this, peer);
    network.localPlayerName = name;
    network.peer.connectTo(id);
  }

  void frameDraw(double duration) {
    if (restart) {
      clearScreen();    
    }
    putPendingSpritesInWorld();
    context.clearRect(0, 0, WIDTH, HEIGHT);
    context.setFillColorRgb(0, 0, 0);
    context.fillRect(0, 0, WIDTH, HEIGHT);
    context.save();
  
    int frames = advanceFrames(duration);
  
    for (int networkId in sprites.keys) {
      var sprite = sprites[networkId];
      context.resetTransform();
      sprite.frame(duration, frames);
      sprite.draw(context, localKeyState.debug);
      collisionCheck(networkId, duration);
      if (sprite.remove) {
        removeSprites.add(sprite.networkId);
      }
    }
  
    while (removeSprites.length > 0) {
      int id = removeSprites.removeAt(0);
      Sprite sprite = sprites[id];
      sprites.remove(id);
      if (sprite != null && !sprite.networkType.remoteControlled()) {
        networkRemovals.add(id);
      }
    }
  
    if (frames > 0) {
      network.frame(duration, networkRemovals);
    }
    drawFps.timeWithFrames(duration, 1);
    drawFpsCounters();
    hudMessages.render(context, duration);
    context.restore();
  }
  
  void putPendingSpritesInWorld() {
    while (waitingSprites.length > 0) {
      Sprite newSprite = waitingSprites.removeAt(0);
      if (newSprite.networkId == null) {
        newSprite.networkId = spriteNetworkId++;
        while (sprites.containsKey(newSprite.networkId)) {
          print("${this}: Warning: World contains sprite ${newSprite.networkId} adding 1");
          newSprite.networkId = spriteNetworkId++;
        }
      }
      if (sprites.containsKey(newSprite.networkId)) {
        print("${this}: Warning: World contains sprite ${newSprite.networkId}. Overwritten!");
      }
      sprites[newSprite.networkId] = newSprite;
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
    if (network.isServer()
      //  && network.hasReadyConnection() This is commented out to allow local testing.
        && sprites.length < 40
        && frames > 0
        && new Random().nextDouble() > 0.99) {
      addAstroid(200.0);
    }
    return frames;
  }

  MovingSprite getOrCreateSprite(int networkId, int flags, ConnectionWrapper wrapper) {
    Sprite sprite = sprites[networkId];
    if (sprite == null) {
      if (true) {
        sprite = new MovingSprite(0.0, 0.0, 0);
        sprite.networkType = NetworkType.REMOTE;
        sprite.networkId = networkId;
        waitingSprites.add(sprite);
      } else {
        // TODO: Fix forwarding Client -> Server -> Client.
  /*      print("World does not have sprite ${networkId}?  ${network is Server} ${this.sprites}");
        LocalPlayerSprite sprite = new LocalPlayerSprite(
           world, remoteKeyState, info, 0.0, 0.0, spriteId);
       sprite.networkType =  NetworkType.REMOTE_FORWARD;
        sprite.networkId = id;
        world.addSprite(sprite); */
      }
    }
    return sprite;
  }

  void clearScreen() {
    sprites = {};
    waitingSprites = [];
    restart = false;
  }

  void createLocalClient(Map dataFromServer) {
    spriteNetworkId = dataFromServer["spriteId"];
    int spriteIndex = dataFromServer["spriteIndex"];
    waitingSprites.add(
        new RemotePlayerSprite(
            this, localKeyState, 400.0, 200.0, spriteIndex));
  }

  void collisionCheck(int networkId, duration) {
    if (network.isServer()) {
      var sprite = sprites[networkId];
      if (sprite is MovingSprite) {
        if (!sprite.collision) return;
        for (int id in sprites.keys) {
          // Avoid duplicate checks.
          if (networkId >= id) {
            continue;
          }
          var otherSprite = sprites[id];
          if (otherSprite is MovingSprite) {
            if (!otherSprite.collision) continue;
            if (collision(sprite, otherSprite, duration)) {
              sprite.collide(otherSprite);
              otherSprite.collide(sprite);
            }
          }
        }   
      }
    }
  }
  
  addLocalPlayerSprite(String name) {
    Server server = network as Server;
    int id = server.gameState.getNextUsablePlayerSpriteId();
    int spriteId = server.gameState.getNextUsableSpriteImage();
    PlayerInfo info = new PlayerInfo(name, network.peer.id, id);
    LocalPlayerSprite playerSprite = new LocalPlayerSprite(
        this, localKeyState, info,
        new Random().nextInt(WIDTH).toDouble(),
        new Random().nextInt(WIDTH).toDouble(),
        imageByName["shipg01.png"]);
    playerSprite.networkId = id;
    playerSprite.setImage(spriteId);
    server.gameState.playerInfo.add(info);
    addSprite(playerSprite);
  }

  startAsServer(String name, [bool forTest = false]) {
    loading = false;
    addLocalPlayerSprite(name);
    if (forTest == true) {
      addLocalPlayerSprite(name);
    }
  }

  void drawFpsCounters() {
    if (localKeyState.debug) {
      var font = context.font;
      context.font = '16pt Calibri';
      context.fillText("DrawFps: $drawFps", 0, 20);
      context.fillText("ServerFps: $serverFps", 0, 40);
      context.fillText("NetworkFps: $networkFps", 0, 60);
      context.fillText("Sprites: ${sprites.length}", 0, 80);
      context.fillText("KeyFrames: ${network.keyFrameDebugData()}", 0, 100);
      context.font = font;
    }
  }

  Iterable<Sprite> getFilteredSprites(bool test(Sprite sprite)) {
    return sprites.values.where(test);
  }
  
  void addSprite(var sprite) {
    waitingSprites.add(sprite);
  }
  
  void removeSprite(int networkId) {
    removeSprites.add(networkId);
  }
  
  num negate(Random r) {
    return r.nextBool() ? 1 : -1;    
  }

  void addAstroid(double size, [Vec2 pos]) {
    Random r = new Random();
    var sprite = new Astroid(this,
        size.toInt(), 0.0, 0.0, imageByName['astroid.png']);
    if (pos == null) {
      sprite.position = sprite.position - sprite.size;
    } else {
      sprite.position = pos;
    }
    sprite.velocity = new Vec2.random(negate(r) * 20, negate(r) * 20);
    sprite.rotationVelocity = negate(r) * new Random().nextDouble() * 2.0;
    sprite.size = new Vec2(size, size);
    sprite.setRadius(0.8 * (sprite.size.sum() / 2));
    sprite.networkType = NetworkType.LOCAL;
    addSprite(sprite);
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
