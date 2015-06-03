library playersprites;

import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/sprites/movingsprite.dart';
import 'package:dart2d/gamestate.dart';
import 'dart:math';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/sprites/sprite_index.dart';
import 'package:dart2d/weapons/weapon_state.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/keystate.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/sprites/stickysprite.dart';
import 'package:dart2d/sprites/rope.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:html';

/**
 * Created on clients to represent other players.
 */
class RemotePlayerClientSprite extends LocalPlayerSprite {
  RemotePlayerClientSprite(World world)
      : super(world, null, null, 0.0, 0.0, 0);

  /**
   * This sprite should not execute controls.
   */
  void checkControlKeys(double duration) {
  }
  
  
  /**
   * This sprite should not execute controls.
   */
  void listenFor(String key, dynamic f) {
    
  }
  
  void checkShouldFire() {
    // Leave this empty.
  }
  
  maybeRespawn(double duration) {
   // Client should not control this. 
  }
}

/**
 * Created on the server to represent clients.
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
    this.collision = this.inGame();
    this.health = LocalPlayerSprite.MAX_HEALTH; // TODO: Make health part of the GameState.
    this.networkId = sprite.networkId;
  }

  void checkControlKeys(double duration) {
    // Don't execute remote movements on the server.
  }
}

/**
 * Created on the client and streamed to the Server.
 */
class RemotePlayerSprite extends LocalPlayerSprite {
  RemotePlayerSprite(World world, KeyState keyState, double x, double y, int imageIndex)
      : super(world, keyState, null, x, y, imageIndex);
  
  void checkShouldFire() {
    // Don't do anything in the local client.
    // The server triggers this.
  }
  
  maybeRespawn(double duration) {
   // Client should not control this. 
  }
}

/**
 * How a server represents itself.
 */
class LocalPlayerSprite extends MovingSprite {
  static const BOUCHYNESS = 0.3;
  static final Vec2 DEFAULT_PLAYER_SIZE = new Vec2(40.0, 40.0);
  static int MAX_HEALTH = 100;
  static const double RESPAWN_TIME = 3.0;
  static const MAX_SPEED = 500.0;
  
  Map<String, int> _controls = {
      "Left": KeyCode.A,
      "Right": KeyCode.D,
      "Aim up": KeyCode.UP,
      "Aim down": KeyCode.DOWN,
      "Jump": KeyCode.W,
      "Fire": KeyCode.F,
      "Rope": KeyCode.S,
      "Next weapon": KeyCode.E,
      "Prev weapon": KeyCode.Q,
  };

  WormWorld world;
  int health = MAX_HEALTH;
  PlayerInfo info;
  Rope rope;
  KeyState keyState;
  WeaponState weaponState;
  
  bool onGround = false;
    
  double spawnIn = 0.0;
  
  MovingSprite gun;

  factory LocalPlayerSprite.copyFromRemotePlayerSprite(RemotePlayerSprite convertSprite) {
    LocalPlayerSprite sprite = new LocalPlayerSprite.copyFromMovingSprite(convertSprite);
    sprite.world = convertSprite.world;
    sprite.info = convertSprite.info;
    sprite.keyState = convertSprite.keyState;
    sprite.health = convertSprite.health;
    sprite.networkId = convertSprite.networkId;
    sprite.networkType = NetworkType.LOCAL;
    sprite.weaponState = new WeaponState(
        sprite.world, sprite.keyState, sprite, sprite.gun);
    return sprite;
  }
  
  LocalPlayerSprite.copyFromMovingSprite(MovingSprite convertSprite)
       : super.withVecPosition(convertSprite.position, convertSprite.imageIndex) {
     this.size = convertSprite.size;
     this.networkId = convertSprite.networkId;
     this.networkType = convertSprite.networkType;
     this.gun = _createGun();
   }
  
  LocalPlayerSprite(World world, KeyState keyState, PlayerInfo info, double x, double y, int imageIndex)
      : super(x, y, imageIndex) {
    this.world = world;
    this.info = info;
    this.keyState = keyState;
    this.size = DEFAULT_PLAYER_SIZE;
    this.gun = _createGun();
    this.weaponState = new WeaponState(world, keyState, this, this.gun);
    this.listenFor("Next weapon", () {
      weaponState.nextWeapon();
    });
    this.listenFor("Prev weapon", () {
      weaponState.prevWeapon();
    });
  }
  
  StickySprite _createGun() {
    return new StickySprite(this, imageByName["gun.png"], Sprite.UNLIMITED_LIFETIME, 30, 7);
  }

  collide(MovingSprite other, ByteWorld world, int direction) {
    if (world != null) {
      if (direction == MovingSprite.DIR_BELOW) {
        onGround = true;
        if (velocity.y > 0) {
          velocity.y = -velocity.y * BOUCHYNESS;
        }
        // Check one more time, but y -1.
        while (world.isCanvasCollide(position.x + 1, position.y + size.y - 1.0, size.x -1, 1)) {
          position.y--;
        }
      }
      if (direction == MovingSprite.DIR_ABOVE) {
        if (velocity.y < 0) {
          velocity.y = -velocity.y * BOUCHYNESS;
        }
      }
      
      if (direction == MovingSprite.DIR_LEFT) {
        if (velocity.x < 0) {
          velocity.x = -velocity.x * BOUCHYNESS;
          position.x++;
        }
      }
      if (direction == MovingSprite.DIR_RIGHT) {
        if (velocity.x > 0) {
          velocity.x = -velocity.x * BOUCHYNESS;
          position.x--;
        }
      }
    }
  }
  
  bool inGame() {
    return info != null && info.inGame;
  }
  
  draw(CanvasRenderingContext2D context, bool debug) {
    if (!inGame()) {
      return;
    }
    if (weaponState != null) {
      weaponState.draw(context);
    }
    context.save();
    gun.draw(context, debug);
    context.restore();
    super.draw(context, debug);
    _drawHealthBar(context);
  }

  _drawHealthBar(CanvasRenderingContext2D context) {
    double healthFactor = health/MAX_HEALTH;
    context.resetTransform();
    var grad = context.createLinearGradient(0, 0, 3*WIDTH*healthFactor, 10);
    grad.addColorStop(0, "#00ff00");
    grad.addColorStop(1, "#FF0000");
    context.globalAlpha = 0.5;
    context.fillStyle = grad;
    context.fillRect(0, HEIGHT - 10, WIDTH * healthFactor, 10);
    context.globalAlpha = 1.0;
  }
  
  maybeRespawn(double duration) {
    if (info != null && !inGame()) {
      spawnIn-= duration;
      if (spawnIn < 0) {
        velocity = new Vec2();
        world.hudMessages.displayAndSendToNetwork("${info.name} is back!");
        info.inGame = true;
        collision = true;
        health = MAX_HEALTH;
      }
      return;
    }  
  }
  
  frame(double duration, int frames, [Vec2 gravity]) {
    maybeRespawn(duration);
    checkControlKeys(duration);
    checkShouldFire();
    super.frame(duration, frames, gravity);
    gun.frame(duration, frames, gravity);
    
    if (weaponState != null) {
      weaponState.think(duration);
    }
    if (velocity.x.abs() < 10.0) {
      this.frameIndex = 0;
    }
  }

  bool downKeyIsPressed = false;
  bool upKeyIsPressed = false;
  
  void checkControlKeys(double duration) {
    if (keyIsDown("Left")) {
      if (velocity.x > -100) {
        velocity.x -= 20.0;
      } if (velocity.x < -100) {
        velocity.x = -100.0;
      }
      if (angle <  PI * 2) {
        gun.angle -= (gun.angle + PI / 2) * 2;
        angle = PI * 2 + 0.01;
      }
    } else if (keyIsDown("Right")) {
      if (velocity.x < 100) {
        velocity.x += 20.0;
      } if (velocity.x > 100) {
        velocity.x = 100.0;
      }
      if (angle != 0.0) {
        angle = 0.0;
        gun.angle -= (gun.angle + PI / 2) * 2;
      }
    } else {
      velocity.x = velocity.x * 0.94; 
    }
    
    if (keyIsDown("Jump") && rope != null) {
      world.removeSprite(rope.networkId);
      rope = null;
    }
    
    if (keyIsDown("Jump") && onGround) {
      this.velocity.y -= 200.0; 
      this.onGround = false;
     
    } if (keyIsDown("Aim down") && !downKeyIsPressed) {
      gunDown();
      downKeyIsPressed = true;
    }else if(!keyIsDown("Aim down"))
      downKeyIsPressed = false;
    if (keyIsDown("Aim up") && !upKeyIsPressed) {
      gunUp();
      upKeyIsPressed = true;
    } else if(!keyIsDown("Aim up"))
      upKeyIsPressed = false;
    
   
    if (keyIsDown("Rope")) {
      fireRope();
    }
  }
  
  void checkShouldFire() {
    if (keyIsDown("Fire")) {
      weaponState.fire();
    } 
  }
  
  void gunDown() {
    if (angle != 0.0) {           //left
      gun.angle -= PI/5;
      if (gun.angle < -(PI + PI/3)) {
        gun.angle = -(PI + PI/3);
      }
    } else {                      //right
      gun.angle += PI/5;
      if (gun.angle > PI/3) {
        gun.angle = PI/3;
      }
    }
  }
  
  void gunUp() {
    // Diffent if facing left or right.
    if (angle != 0.0) {
      gun.angle += PI/5;
      if (gun.angle > -PI/2) {
        gun.angle = -PI/2;
      }
    } else {
      gun.angle -= PI/5;
      if (gun.angle < -PI/2) {
        gun.angle = -PI/2;
      }
    }
  }
  
  void fireRope() {
    if (rope != null) {
      world.removeSprite(rope.networkId);
    }
    rope = new Rope.createWithOwner(this.world, this, this.gun.angle, 600.0);
    world.addSprite(rope);
  }

  bool takesDamage() {
    return true;
  }
  
  void takeDamage(int damage) {
    health -= damage;
    if (health <= 0) {
      world.hudMessages.displayAndSendToNetwork("${info.name} died!");
      info.deaths++;
      info.inGame = false;
      collision = false;
      spawnIn = RESPAWN_TIME;  
    }
  }
  
  void listenFor(String key, dynamic f) {
    assert(_controls.containsKey(key));
    keyState.registerListener(_controls[key], f);
  }
  
  bool keyIsDown(String key) {
    assert(_controls.containsKey(key));
    return keyState.keyIsDown(_controls[key]);
  }
  
  void addExtraNetworkData(List<int> data) {
    data.add((gun.angle * DOUBLE_INT_CONVERSION).toInt());
    data.add(weaponState.selectedWeaponIndex);
  }
   
  void parseExtraNetworkData(List<int> data, int startAt) {
    gun.angle = data[startAt] / DOUBLE_INT_CONVERSION;
    if(weaponState != null) {
      weaponState.selectedWeaponIndex = data[startAt + 1];
    }
  }
  
  int sendFlags() {
    return 0;
  }
  
  int remoteRepresentation() {
    return SpriteIndex.REMOTE_PLAYER_CLIENT_SPRITE;
  }
}