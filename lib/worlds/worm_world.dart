library wormworld;

import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/particles.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/phys/phys.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/rtc.dart';
import 'package:dart2d/res/imageindex.dart'; 
import 'dart:math';
import 'dart:html';

class WormWorld extends World {
  Vec2 centerView = new Vec2();
  Vec2 halfWorld;
  LocalPlayerSprite playerSprite;
  ByteWorld byteWorld;
  Vec2 gravity = new Vec2(0.0, 300.0);
  WormWorld(int width, int height) : super(width, height) {
    halfWorld = new Vec2(width / 2, height / 2 );
  }
  
  void collisionCheck(int networkId, duration) {
    Sprite sprite = sprites[networkId];
    if(sprite is MovingSprite) {
      if (sprite.collision) {
        // Above.
        if (byteWorld.isCanvasCollide(sprite.position.x, sprite.position.y, sprite.size.x, 1)) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_ABOVE);
        }
        // Below.
        if (byteWorld.isCanvasCollide(sprite.position.x, sprite.position.y + sprite.size.y, sprite.size.x, 1)) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_BELOW);
        }
        if (byteWorld.isCanvasCollide(sprite.position.x, sprite.position.y, 1, sprite.size.y)) {
         sprite.collide(null, byteWorld, MovingSprite.DIR_LEFT);
        }
        if (byteWorld.isCanvasCollide(sprite.position.x + sprite.size.x, sprite.position.y, 1, sprite.size.y)) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_RIGHT);
        }
        
        if (sprite.position.x + sprite.size.x > byteWorld.width) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_RIGHT);
        }
        if (sprite.position.x < 0) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_LEFT);
        }
        if (sprite.position.y + sprite.size.y > byteWorld.height) {
          sprite.collide(null, byteWorld, MovingSprite.DIR_BELOW);
        }
      }
    }
  }
  
  void think(double duration, int frames) {
    
  }
  
  setJsPeer(var jsPeer) {
    byteWorld = new ByteWorld(imageByName['mattehorn.png'], new Vec2(WIDTH * 1.0,  HEIGHT * 1.0));
    peer = new PeerWrapper(this, jsPeer);
    network = new Server(this, peer);
  }
  
  void frameDraw([double duration = 0.01]) {
    if (restart) {
      clearScreen();    
    }
    int frames = advanceFrames(duration);
 
    putPendingSpritesInWorld();

    canvas.clearRect(0, 0, WIDTH, HEIGHT);
    canvas.setFillColorRgb(135, 206, 250);
    canvas.fillRect(0, 0, WIDTH, HEIGHT);
    canvas.save();
    
    
    if (playerSprite != null) {
      centerView = playerSprite.position - halfWorld;
      if (centerView.x < 0) {
        centerView.x = 0.0;
      } 
      if (centerView.y < 0) {
        centerView.y = 0.0;
      }
      if (centerView.y > byteWorld.height - HEIGHT) {
        centerView.y = byteWorld.height * 1.0 - HEIGHT;
      }
      if (centerView.x > byteWorld.width - WIDTH) {
        centerView.x = byteWorld.width * 1.0 - WIDTH;
      }
    }
   
   byteWorld.drawAt(canvas, centerView.x, centerView.y);
   canvas.globalAlpha = 0.7;
   byteWorld.drawAsMiniMap(canvas, 0, 0);
   canvas.restore();
   
    for (int networkId in sprites.keys) {
      var sprite = sprites[networkId];
      canvas.save();
      canvas.translate(-centerView.x, -centerView.y);
      if (!freeze && !network.hasNetworkProblem()) {
        sprite.frame(duration, frames, gravity);
      }
      sprite.draw(canvas, localKeyState.debug);
      collisionCheck(networkId, duration);
      if (sprite.remove) {
        removeSprites.add(sprite.networkId);
      }
      canvas.restore();
    }
  
    while (removeSprites.length > 0) {
      int id = removeSprites.removeAt(0);
      Sprite sprite = sprites[id];
      sprites.remove(id);
      this.log.fine("${this}: Removing sprite ${id} from world");
      if (sprite != null && sprite.networkType != NetworkType.REMOTE) {
        this.log.fine("${this}: Removing sprite ${id} from network");
        networkRemovals.add(id);
      }
    }
  
    // Only send to network if server frames has passed.
    if (frames > 0) {
      network.frame(duration, networkRemovals);
    }
    // 1 since we count how many times this method is called.
    drawFps.timeWithFrames(duration, 1);
    drawFpsCounters();
    hudMessages.render(canvas, duration);
    canvas.restore();
  }
  
  void createLocalClient(Map dataFromServer) {
    spriteNetworkId = dataFromServer["spriteId"];
    int spriteIndex = dataFromServer["spriteIndex"];
    playerSprite = new RemotePlayerSprite(
        this, localKeyState, 400.0, 200.0, spriteIndex);
    addSprite(playerSprite);
  }
  
  addLocalPlayerSprite(String name) {
    int id = network.gameState.getNextUsablePlayerSpriteId();
    int imageId = network.gameState.getNextUsableSpriteImage();
    PlayerInfo info = new PlayerInfo(name, network.peer.id, id);
    playerSprite = new LocalPlayerSprite(
        this, localKeyState, info,
        new Random().nextInt(WIDTH).toDouble(),
        new Random().nextInt(HEIGHT).toDouble(),
        imageId);
    playerSprite.size = new Vec2(24.0, 24.0);
    playerSprite.networkId = id;
    playerSprite.setImage(imageId, 24);
    network.gameState.playerInfo.add(info);
    addSprite(playerSprite);
  }
  
  void explosionAt(Vec2 location, Vec2 velocity, int damage, double radius, [bool sendTonetwork = true]) {
    clearWorldArea(location, radius);
    if (velocity != null) {
      addSprite(new Particles(null, location, velocity, radius));
    }
    addVelocityFromExplosion(location, damage, radius);
    if (sendTonetwork) {
      Map data = {WORLD_DESTRUCTION: asNetworkUpdate(location, velocity, radius)};
      network.peer.sendDataWithKeyFramesToAll(data);
    }
  }
  
  void explosionAtSprite(Sprite sprite, Vec2 velocity, int damage, double radius, [bool sendTonetwork = true]) {
    clearWorldArea(sprite.centerPoint(), radius);
    addSprite(new Particles(null, sprite.position, velocity, radius * 1.5));
    addVelocityFromExplosion(sprite.centerPoint(), damage, radius);
    if (sendTonetwork) {
      Map data = {WORLD_DESTRUCTION: asNetworkUpdate(sprite.centerPoint(), velocity, radius)};
      network.peer.sendDataWithKeyFramesToAll(data);
    }
  }
  
  void clearWorldArea(Vec2 location, double radius) {
    byteWorld.clearAt(location, radius);
  }

  clearFromNetworkUpdate(List<int> data) {
    Vec2 pos = new Vec2(data[0] / DOUBLE_INT_CONVERSION, data[1] / DOUBLE_INT_CONVERSION);
    double radius = data[2] / DOUBLE_INT_CONVERSION;
    Vec2 velocity = null;
    if (data.length > 3) {
      velocity = new Vec2(data[3] / DOUBLE_INT_CONVERSION, data[4] / DOUBLE_INT_CONVERSION);
    }
    explosionAt(pos, velocity, 0, radius, false);
  }
  
  List<int> asNetworkUpdate(Vec2 pos, Vec2 velocity, double radius) {
    List<int> base = [
      (pos.x * DOUBLE_INT_CONVERSION).toInt(), 
      (pos.y * DOUBLE_INT_CONVERSION).toInt(),      
      (radius * DOUBLE_INT_CONVERSION).toInt()];
    if (velocity != null) {
     base.addAll([
         (velocity.x * DOUBLE_INT_CONVERSION).toInt(), 
         (velocity.y * DOUBLE_INT_CONVERSION).toInt()]);
    }
    return base;
  }
  
  void addVelocityFromExplosion(Vec2 location, int damage, double radius) {
    for (int networkId in sprites.keys) {
      Sprite sprite = sprites[networkId];
      if (sprite is MovingSprite && sprite.collision) {
        int damageTaken = velocityForSingleSprite(sprite, location, radius, damage).toInt();
        if (damageTaken > 0 && sprite.takesDamage()) {
          sprite.takeDamage(damageTaken.toInt());
        }
      }
    }
  }
}