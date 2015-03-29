library spaceworld;

import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/sprites/astroid.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/phys/phys.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';

class SpaceWorld extends World {
  SpaceWorld(int width, int height) : super(width, height);
  
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
  
  void think(double duration, int frames) {
    if (network.isServer()
       //  && network.hasReadyConnection() This is commented out to allow local testing.
         && sprites.length < 40
         && frames > 0
         && new Random().nextDouble() > 0.99) {
       addAstroid(200.0);
    }
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
}