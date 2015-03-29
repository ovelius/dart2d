library asteroid;

import 'movingsprite.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/playersprite.dart';
import 'dart:math';
import 'package:dart2d/res/imageindex.dart';

class Astroid extends MovingSprite {
  
  static final List<String> SPRITES  = ["astroid.png", "astroid2.png", "astroid3.png"];
  World world;
  int health = 50;

  Astroid(World world, int health, double x, double y, int imageIndex) : super(x, y, imageIndex) {
    this.world = world;
    int randomIndex = new Random().nextInt(SPRITES.length);
    imageIndex = imageByName[SPRITES[randomIndex]];
    setImage(imageIndex);
    health = health;
  }

  collide(MovingSprite other) {
    if (!(other is Astroid)) {
      if (other.takesDamage()) {
        this.remove = true;
        other.takeDamage(null, health);
      }
    }
    super.collide(other);
  }

  bool takesDamage() {
    return true;
  }

  void takeDamage(Sprite inflictor, int damage) {
    health -= damage;
    if (health < 0) {
      if (inflictor != null && inflictor is LocalPlayerSprite) {
        inflictor.info.score += size.sum().toInt();
      }
      splitAndRemove();
    }
  }
  
  void splitAndRemove() {
    remove = true;
    if (size.x > 20) {
      world.addAstroid(size.x / 1.7, this.centerPoint());
      world.addAstroid(size.x / 1.7, this.centerPoint());
    }
  }
}