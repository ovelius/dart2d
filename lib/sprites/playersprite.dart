library dart2d;

import 'sprite.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/gamestate.dart';
import 'package:dart2d/sprites/damage_projectile.dart';
import 'dart:math';
import 'package:dart2d/world.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/sprites/stickysprite.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:html';

/**
 * Created on the server and streamed from the client.
 * How the servers represents remote clients.
 */
class RemotePlayerServerSprite extends LocalPlayerSprite {
  RemotePlayerServerSprite(
      World world, KeyState keyState, PlayerInfo info, double x, double y, int imageIndex)
      : super(world, keyState, info, x, y, imageIndex);
  
  RemotePlayerServerSprite.copyFromMovingSprite(
      World world, KeyState keystate, PlayerInfo info, MovingSprite sprite)
      : super.copyFromMovingSprite(sprite) {
    this.world = world;
    this.info = info;
    this.keyState = keystate;
    this.collision = this.inGame;
    this.health = LocalPlayerSprite.MAX_HEALTH; // TODO: Make health part of the GameState.
    this.networkId = sprite.networkId;
  }

  void checkControlKeys(double duration) {
    // Don't execute remote movements on the server.
  }
}

/**
 * A version of the PlayerSprite created in the client and sent to the server.
 * How the client represents itself.
 */
class RemotePlayerSprite extends LocalPlayerSprite {
  RemotePlayerSprite(World world, KeyState keyState, double x, double y, int imageIndex)
      : super(world, keyState, null, x, y, imageIndex);
  
  void fire() {
    // Don't do anything in the local client.
  }
}

/**
 * How a server represents itself.
 */
class LocalPlayerSprite extends MovingSprite {
  static final Vec2 DEFAULT_PLAYER_SIZE = new Vec2(40.0, 40.0);
  static int MAX_HEALTH = 100;
  static const double RESPAWN_TIME = 3.0;
  static const MAX_SPEED = 500.0;

  World world;
  int health = MAX_HEALTH;
  PlayerInfo info;
  Sprite damageSprite;
  KeyState keyState;
  
  static const fireDelay = 5;
  int nextFireFrame = 0;
  
  bool inGame = true;
  double spawnIn = 0.0;

  factory LocalPlayerSprite.copyFromRemotePlayerSprite(RemotePlayerSprite convertSprite) {
    LocalPlayerSprite sprite = new LocalPlayerSprite.copyFromMovingSprite(convertSprite);
    sprite.world = convertSprite.world;
    sprite.info = convertSprite.info;
    sprite.keyState = convertSprite.keyState;
    sprite.collision = convertSprite.inGame;
    sprite.health = convertSprite.health;
    sprite.networkId = convertSprite.networkId;
    sprite.networkType = NetworkType.LOCAL;
    return sprite;
  }
  
  LocalPlayerSprite.copyFromMovingSprite(MovingSprite convertSprite)
       : super.withVecPosition(convertSprite.position, convertSprite.imageIndex) {
     this.collision = inGame;
     this.size = convertSprite.size;
     this.networkId = convertSprite.networkId;
     this.networkType = convertSprite.networkType;
   }
  
  LocalPlayerSprite(World world, KeyState keyState, PlayerInfo info, double x, double y, int imageIndex)
      : super(x, y, imageIndex) {
    this.world = world;
    this.info = info;
    this.keyState = keyState;
    this.collision = inGame;
    this.size = DEFAULT_PLAYER_SIZE;
  }

  draw(CanvasRenderingContext2D context, bool debug) {
    if (!inGame) {
      return;
    }
    super.draw(context, debug);
    _drawHealthBar(context);
  }

  _drawHealthBar(CanvasRenderingContext2D context) {
    double healthFactor = health/MAX_HEALTH;
    context.resetTransform();
    var grad = context.createLinearGradient(0, 0, 3*WIDTH*healthFactor, 10);
    grad.addColorStop(0, "#00ff00");
    grad.addColorStop(1, "#FF0000");
    context.fillStyle = grad;
    context.fillRect(0, HEIGHT - 10, WIDTH, 10);
  }

  frame(double duration, int frames) {
    if (!inGame) {
      spawnIn-= duration;
      if (spawnIn < 0) {
        velocity = new Vec2();
        world.hudMessages.displayAndSendToNetwork("${info.name} is back!");
        inGame = true;
        collision = true;
        health = MAX_HEALTH;
      }
      return;
    }
    checkControlKeys(duration);
    checkForFireFrame(duration);
    super.frame(duration, frames);
    double vsum = velocity.sum();
    if (vsum > MAX_SPEED) {
      velocity = velocity.normalize().multiply(MAX_SPEED);
    } else {
      velocity = velocity.multiply(0.99); 
    }
  }

  void checkControlKeys(double duration) {
    if (keyState.keyIsDown(KeyCode.LEFT)) {
      angle-= 5.0 * duration;
    }
    if (keyState.keyIsDown(KeyCode.RIGHT)) {
      angle+= 5.0 * duration;
    }
    if (keyState.keyIsDown(KeyCode.UP)) {
      acceleration = new Vec2.fromAngle(angle, duration * 10000.0); 
    } else if (keyState.keyIsDown(KeyCode.DOWN)) {
      acceleration = new Vec2.fromAngle(angle, -duration * 10000.0); 
    } else {
      acceleration = new Vec2();
    }
  }

  void checkForFireFrame(double duration) {
    if (keyState.keyIsDown(KeyCode.SPACE)) {
      if (nextFireFrame <= 0) {
        fire();
        nextFireFrame += fireDelay;
      }
    }
    if (nextFireFrame > 0) {
      nextFireFrame -= frames;  
    }
  }
  void fire() {
    DamageProjectile sprite = new DamageProjectile.createWithOwner(this, 3);
    world.addSprite(sprite);
  }
  bool hasValidDamageSprite() {
    return damageSprite != null && damageSprite.lifeTime >  0;
  }
  bool takesDamage() {
    return true;
  }
  void takeDamage(Sprite sprite, int damage) {
    health -= damage;
    if (health <= 0) {
      world.hudMessages.displayAndSendToNetwork("${info.name} died!");
      info.deaths++;
      inGame = false;
      collision = false;
      spawnIn = RESPAWN_TIME;  
      if (hasValidDamageSprite()) {
        damageSprite.remove = true;
        damageSprite = null;
      }
    } else {
      if (!hasValidDamageSprite()) {
        damageSprite = new StickySprite(this, imageByName["shield.png"], 40, 80);
        world.addSprite(damageSprite);
      } else {
        damageSprite.lifeTime = 40;
      }
    }
  }
}