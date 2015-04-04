library wormworld;

import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/sprites/astroid.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/worm_player.dart';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/phys/phys.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/rtc.dart';
import 'package:dart2d/res/imageindex.dart'; 
import 'dart:math';
import 'dart:html';

class WormWorld extends World {
  Vec2 centerView = new Vec2();
  Vec2 halfWorld;
  Sprite playerSprite;
  ByteWorld byteWorld;
  Vec2 gravity = new Vec2(0.0, 300.0);
  WormWorld(int width, int height) : super(width, height) {
    halfWorld = new Vec2(width / 2, height / 2 );
  }
  
  void collisionCheck(int networkId, duration) {
    Sprite sprite = sprites[networkId];
    if(sprite is MovingSprite) {
      if (sprite.collision) {
        if (byteWorld.isCanvasCollide(sprite.position.x, sprite.position.y)) {
          sprite.collide(null, byteWorld);
        }
        if (byteWorld.isCanvasCollide(sprite.position.x + sprite.size.x, sprite.position.y)) {
          sprite.collide(null, byteWorld);
        }
        if (byteWorld.isCanvasCollide(sprite.position.x + sprite.size.x, sprite.position.y + sprite.size.y)) {
          sprite.collide(null, byteWorld);
        }
        if (byteWorld.isCanvasCollide(sprite.position.x, sprite.position.y + sprite.size.y)) {
          sprite.collide(null, byteWorld);
        }
      }
    }
  }
  
  void think(double duration, int frames) {
    
  }
  
  setJsPeer(var jsPeer) {
    byteWorld = new ByteWorld(imageByName['stolen_level.png'], new Vec2(WIDTH * 1.0,  HEIGHT * 1.0));
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
    canvas.setFillColorRgb(0, 0, 0);
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
   canvas.restore();
  
   
    for (int networkId in sprites.keys) {
      var sprite = sprites[networkId];
      canvas.resetTransform();
      if (!freeze && !network.hasNetworkProblem()) {
        sprite.frame(duration, frames, gravity);
      }
      sprite.draw(canvas, localKeyState.debug, centerView.multiply(-1.0));
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
      network.frame(duration, networkRemovals);
    }
    // 1 since we count how many times this method is called.
    drawFps.timeWithFrames(duration, 1);
    drawFpsCounters();
    hudMessages.render(canvas, duration);
    canvas.restore();
  }
  
  addLocalPlayerSprite(String name) {
    int id = network.gameState.getNextUsablePlayerSpriteId();
    int imageId = network.gameState.getNextUsableSpriteImage();
    PlayerInfo info = new PlayerInfo(name, network.peer.id, id);
    playerSprite = new WormLocalPlayerSprite(
        this, localKeyState, info,
        new Random().nextInt(WIDTH).toDouble(),
        new Random().nextInt(HEIGHT).toDouble(),
        imageByName["duck.png"]);
    playerSprite.size = new Vec2(24.0, 24.0);
    playerSprite.networkId = id;
    playerSprite.setImage(imageByName["duck.png"], 24);
    network.gameState.playerInfo.add(info);
    addSprite(playerSprite);
  }

  drawCustomImage() {
      // create a new pixel array
      var imageData = canvas.createImageData(100, 100);

      int pos = 0; // index position into imagedata array
      var xoff = 100 /  3; // offsets to "center"
      var yoff = 100 / 3;
      var x= 0;
      var y= 0;

      for (y = 0; y < 100; y++) {
          for (x = 0; x < 100; x++) {
              // calculate sine based on distance
             var x2 = x - xoff;
              var y2 = y - yoff;
             var  d = sqrt(x2 * x2 + y2 * y2);
             var t = sin(d / 6.0);

              // calculate RGB values based on sine
              var r = t * 200;
             var  g = 125 + t * 80;
            var   b = 235 + t * 20;

              // set red, green, blue, and alpha:
              imageData.data[pos++] = max(0, min(255, r)).toInt();
              imageData.data[pos++] = max(0, min(255, g)).toInt();
              imageData.data[pos++] = max(0, min(255, b)).toInt();
              imageData.data[pos++] = 255; // opaque alpha
          }
      }
      return imageData;
  }
  
}