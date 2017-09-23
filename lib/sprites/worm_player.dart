import 'package:dart2d/util/gamestate.dart';
import 'dart:math';
import 'package:dart2d/net/state_updates.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/weapons/weapon_state.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/util/mobile_controls.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

/**
 * How a server represents itself.
 */
class LocalPlayerSprite extends MovingSprite {
  final Logger log = new Logger('LocalPlayerSprite');
  static const BOUCHYNESS = 0.2;
  static final Vec2 DEFAULT_PLAYER_SIZE = new Vec2(32.0, 32.0);
  static int MAX_HEALTH = 100;
  static int MAX_SHIELD = 200;
  static const double RESPAWN_TIME = 5.0;
  static const MAX_SPEED = 500.0;

  static Map<String, int> _default_controls = {
    "Left": KeyCodeDart.A,
    "Right": KeyCodeDart.D,
    "Aim up": KeyCodeDart.UP,
    "Aim down": KeyCodeDart.DOWN,
    "Jump": KeyCodeDart.W,
    "Fire": KeyCodeDart.F,
    "Rope": KeyCodeDart.S,
    "Next weapon": KeyCodeDart.E,
    "Prev weapon": KeyCodeDart.Q,
  };

  static Set<int> _mappedControls = new Set.from(_default_controls.values);

  Map<String, int> getControls() => _default_controls;

  bool isMappedKey(int code) {
    return _mappedControls.contains(code);
  }

  WormWorld world;
  int health = MAX_HEALTH;
  int _shieldPoints = 0;
  double _jetPackSec = 0.0;
  Particles _jetParticles = null;

  PlayerInfo info;
  PlayerInfo _killer = null;
  Rope rope;
  MobileControls _mobileControls;
  double _gunAngleTouchLock = null;
  WeaponState weaponState;

  bool onGround = false;

  // Don't spawn player when created.
  double spawnIn = 10000000000.0;

  MovingSprite gun;

  double _shieldSec = -1.0;
  StickySprite _shield;

  PlayerInfo get killer => _killer;

  /**
   * Server constructor.
   */
  LocalPlayerSprite(
      WormWorld world,
      ImageIndex imageIndex,
      MobileControls mobileControls,
      PlayerInfo info,
      Vec2 position,
      int imageId)
      : super.imageBasedSprite(position, imageId, imageIndex) {
    this.world = world;
    this.info = info;
    this._mobileControls = mobileControls;
    this.size = DEFAULT_PLAYER_SIZE;
    this.gun = _createGun(imageIndex);
    this._shield = _createShield(imageIndex);
    this.weaponState =
        new WeaponState(world, info.remoteKeyState(), this, this.gun);
    this.listenFor("Next weapon", () {
      weaponState.nextWeapon();
    });
    this.listenFor("Prev weapon", () {
      weaponState.prevWeapon();
    });
  }

  StickySprite _createGun(ImageIndex index) {
    Sprite sprite = new StickySprite(this, index.getImageIdByName("gun.png"),
        index, Sprite.UNLIMITED_LIFETIME);
    sprite.size = new Vec2(30, 7).multiply(1.5);
    return sprite;
  }

  StickySprite _createShield(ImageIndex index) {
    MovingSprite shield = new StickySprite(this, index.getImageIdByName("shield.png"),
        index, Sprite.UNLIMITED_LIFETIME);
    shield.size = LocalPlayerSprite.DEFAULT_PLAYER_SIZE.multiply(1.5);
    shield.rotationVelocity = 200.0;
    shield.setImage(index.getImageIdByName("shield.png"), 80);
    return shield;
  }

  bool drawWeaponHelpers() => _ownedByThisWorld();

  hasServerToOwnerData() =>
      world.network().isCommander() && !_ownedByThisWorld();

  addServerToOwnerData(List data) {
    data.add(health);
    data.add((_shieldSec * 10).toInt());
    data.add(spawnIn * DOUBLE_INT_CONVERSION);
    data.add(_shieldPoints);
    if (_killer != null) {
      data.add(_killer.connectionId);
    } else {
      data.add("");
    }
    if (weaponState != null) {
      data.add(weaponState.addServerToOwnerData(data));
    }
  }

  bool parseServerToOwnerData(List data, int startAt) {
    health = data[startAt];
    _shieldSec = data[startAt + 1] / 10.0;
    spawnIn = data[startAt + 2] / DOUBLE_INT_CONVERSION;
    _shieldPoints = data[startAt + 3];
    String killerId = data[startAt + 4];
    _killer = world.network().gameState.playerInfoByConnectionId(killerId);
    if (data.length > 6) {
      this.weaponState.parseServerToOwnerData(data, startAt + 5);
    }
    return true;
  }

  collide(MovingSprite other, ByteWorld world, int direction) {
    if (world != null) {
      if (direction & MovingSprite.DIR_BELOW == MovingSprite.DIR_BELOW) {
        onGround = true;
        if (velocity.y > 0.5) {
          velocity.y = -velocity.y * BOUCHYNESS;
        } else {
          velocity.y = 0.0;
        }
        // Check one more time, but y -1.
        while (world.isCanvasCollide(
            position.x + 1, position.y + size.y - 1.0, size.x - 1, 1)) {
          position.y--;
        }
      }
      if (direction & MovingSprite.DIR_ABOVE == MovingSprite.DIR_ABOVE) {
        if (velocity.y < 0) {
          velocity.y = -velocity.y * BOUCHYNESS;
        }
      }

      if (direction & MovingSprite.DIR_LEFT == MovingSprite.DIR_LEFT) {
        if (velocity.x < 0) {
          velocity.x = -velocity.x * BOUCHYNESS;
          position.x++;
        }
      }
      if (direction & MovingSprite.DIR_RIGHT == MovingSprite.DIR_RIGHT) {
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

  draw(var context, bool debug) {
    if (!inGame()) {
      this.velocity.x = 0.0;
      this.velocity.y = 0.0;
      if (rope != null) {
        rope.remove = true;
        rope = null;
      }
      return;
    }
    if (weaponState != null) {
      weaponState.draw(context);
    }
    context.save();
    gun.draw(context, debug);
    context.restore();
    if (_shieldSec > 0) {
      context.save();
      super.draw(context, debug);
      context.restore();
      context.save();
      _shield.draw(context, debug);
      context.restore();
    } else {
      super.draw(context, debug);
    }
    drawHealthBar(context);
  }

  bool drawHealthBar(var context) {
    if (!_ownedByThisWorld()) {
      return false;
    }
    double healthFactor = health / MAX_HEALTH;
    context.resetTransform();
    var grad = context.createLinearGradient(
        0, 0, 2 * world.width() * healthFactor, 10);
    grad.addColorStop(0, "#00ff00");
    grad.addColorStop(1, "#FF0000");
    context.globalAlpha = 0.5;
    context.fillStyle = grad;
    int size = 20;
    context.fillRect(
        0, world.height() - size, world.width() * healthFactor, size);
    if (_shieldPoints > 0) {
      double shieldFactor = _shieldPoints / MAX_SHIELD;
      context.fillStyle = "#0000ff";
      context.fillRect(
          0, world.height() - size, world.width() * shieldFactor, size);
    }
    context.globalAlpha = 1.0;
    return true;
  }

  bool _ownedByThisWorld() {
    if (info == null) {
      throw new StateError(
          "Info should never be null! ${world.network().peer.getId()} type ${this.runtimeType} id ${networkId} gs ${world.network().getGameState()}");
    }
    return info.connectionId == world.network().peer.getId();
  }

  bool _updatePosition = false;

  bool maybeRespawn(double duration) {
    if (_ownedByThisWorld()) {
      if (!inGame() && spawnIn < RESPAWN_TIME / 2) {
        if (_updatePosition) {
          position = world.byteWorld.randomNotSolidPoint(size);
          // TODO zoom in on the new position?
          _updatePosition = false;
        }
      } else {
        _updatePosition = true;
      }
    }
    if (!world.network().isCommander()) {
      return false;
    }
    if (info != null && !inGame() && !world.network().getGameState().hasWinner()) {
      spawnIn -= duration;
      if (spawnIn < 0) {
        velocity = new Vec2();
        world.displayHudMessageAndSendToNetwork("${info.name} is back!");
        world.network().gameState.markAsUrgent();
        info.inGame = true;
        collision = true;
        health = MAX_HEALTH;
      }
    }
    return true;
  }

  frame(double duration, int frames, [Vec2 gravity]) {
    maybeRespawn(duration);
    checkControlKeys(duration);
    checkShouldFire();
    super.frame(duration, frames, gravity);
    gun.frame(duration, frames, gravity);
    _shield.frame(duration, frames, gravity);
    _shieldSec -= duration;
    _jetPackSec -= duration;
    if (weaponState != null) {
      weaponState.think(duration);
    }
    if (velocity.x.abs() < 10.0) {
      this.frameIndex = 0;
    }
  }

  /**
   * return true
   */
  bool checkControlKeys(double duration) {
    if (!_ownedByThisWorld()) {
      return false;
    }
    if (!inGame()) {
      return true;
    }
    double left = keyIsDownStrength("Left");
    double right = keyIsDownStrength("Right");
    double aimUp = keyIsDownStrength("Aim up");
    double aimDown = keyIsDownStrength("Aim down");

    _applyVel(right, left);

    if (keyIsDown("Jump") && rope != null) {
      world.removeSprite(rope.networkId);
      rope = null;
    }

    if (_jetPackSec <= 0 || !keyIsDown("Jump")) {
      if (_jetParticles != null) {
        _jetParticles.remove = true;
        _jetParticles = null;
      }
    }

    if (keyIsDown("Jump")) {
      if (_jetPackSec > 0) {
        velocity.y -= 700 * duration;
        if (_jetParticles != null && _jetParticles.remove) {
          _jetParticles = null;
        }
        if (_jetParticles == null) {
          _jetParticles = new Particles(weaponState.world,
              this, new Vec2.copy(this.position), new Vec2(0, velocity.y + 50),
              new Vec2(0, size.y / 2), 10.0, 10, 10, 0.8, Particles.SODA);
          _jetParticles.sendToNetwork = true;
          world.addSprite(_jetParticles);
        }
      } else if (onGround) {
        velocity.y -= 200.0;
        onGround = false;
      }
    }

    if (aimUp != null) {
      _gunUp(duration * aimUp);
    } else if (aimDown != null) {
      _gunDown(duration * aimDown);
    }

    if (keyIsDown("Rope")) {
      _fireRope();
    }

    assert(_mobileControls != null);
    Point<int> delta = _mobileControls.getTouchDeltaForButton();
    if (_mobileControls.buttonIsDown()) {
      if (_gunAngleTouchLock == null) {
        _gunAngleTouchLock = gun.angle;
      }
      if (delta != null) {
        checkMobileControls(delta.x, delta.y);
      }
    } else {
      _gunAngleTouchLock = null;
    }
    return true;
  }

  void _applyVel(double right, double left) {
    if (left != null) {
      if (velocity.x > -100) {
        velocity.x -= 20.0 * left;
      }
      if (velocity.x < -100 * left) {
        velocity.x = -100.0 * left;
      }
      if (velocity.x < -100) {
        velocity.x = -100.0;
      }
      if (angle < PI * 2) {
        gun.angle -= (gun.angle + PI / 2) * 2;
        if (_gunAngleTouchLock != null) {
          _gunAngleTouchLock -= (_gunAngleTouchLock + PI / 2) * 2;
          ;
        }
        angle = PI * 2 + 0.01;
      }
    } else if (right != null) {
      if (velocity.x < 100 * right) {
        velocity.x += 20.0 * right;
      }
      if (velocity.x > 100 * right) {
        velocity.x = 100.0 * right;
      }
      if (velocity.x > 100) {
        velocity.x = 100.0;
      }
      if (angle != 0.0) {
        angle = 0.0;
        gun.angle -= (gun.angle + PI / 2) * 2;
        ;
        if (_gunAngleTouchLock != null) {
          _gunAngleTouchLock -= (_gunAngleTouchLock + PI / 2) * 2;
          ;
        }
      }
    } else {
      velocity.x = velocity.x * 0.94;
    }
  }

  bool checkMobileControls(int xD, yD) {
    if (angle != 0.0) {
      gun.angle = _gunAngleTouchLock + (yD * 0.02);
      if (gun.angle > -PI / 2) {
        gun.angle = -PI / 2;
      }
      if (gun.angle < -(PI + PI / 3)) {
        gun.angle = -(PI + PI / 3);
      }
    } else {
      gun.angle = _gunAngleTouchLock - (yD * 0.02);
      if (gun.angle > PI / 3) {
        gun.angle = PI / 3;
      }
      if (gun.angle < -PI / 2) {
        gun.angle = -PI / 2;
      }
    }

    if (xD > 0) {
      _applyVel(null, xD.abs() / 40);
    } else {
      _applyVel(xD.abs() / 40, null);
    }
    return true;
  }

  bool checkShouldFire() {
    if (!world.network().isCommander()) {
      return false;
    }
    if (keyIsDown("Fire") && inGame() && weaponState != null) {
      weaponState.fire();
    }
    return true;
  }

  void _gunDown(double duration) {
    if (angle != 0.0) {
      gun.angle -= duration * 4.0;
      if (gun.angle < -(PI + PI / 3)) {
        gun.angle = -(PI + PI / 3);
      }
    } else {
      gun.angle += duration * 4.0;
      if (gun.angle > PI / 3) {
        gun.angle = PI / 3;
      }
    }
  }

  void _gunUp(double duration) {
    // Diffent if facing left or right.
    if (angle != 0.0) {
      gun.angle += duration * 4.0;
      if (gun.angle > -PI / 2) {
        gun.angle = -PI / 2;
      }
    } else {
      gun.angle -= duration * 4.0;
      if (gun.angle < -PI / 2) {
        gun.angle = -PI / 2;
      }
    }
  }

  void _fireRope() {
    if (rope != null) {
      world.removeSprite(rope.networkId);
    }
    rope = new Rope.createWithOwner(this.world, this, this.gun.angle, 600.0);
    world.addSprite(rope);
  }

  bool takesDamage() {
    return collision;
  }

  void takeDamage(int damage, LocalPlayerSprite inflictor) {
    if (world.network().isCommander()) {
      if (_shieldPoints > 0) {
        _shieldSec = 0.8;
        _shieldPoints -= damage;
        if (_shieldPoints < 0) {
          health += _shieldPoints;
          _shieldPoints = 0;
          _shieldSec = 0.0;
        }
      } else {
        health -= damage;
      }
      if (health <= 0) {
        world.gaReporter().reportEvent("player_killed", "Frags");
        world
            .network()
            .gameState
            .markAsUrgent();
        info.deaths++;
        info.inGame = false;
        collision = false;
        _killer = inflictor != null
            ? world
            .network()
            .gameState
            .playerInfoBySpriteId(inflictor.networkId)
            : null;
        if (_killer != null && _killer != info) {
          _killer.score++;
          world.gaReporter().reportEvent("player_frags", "Frags");
          world.checkWinner(killer);
        }
        spawnIn = RESPAWN_TIME;
        _deathMessage(Mod.UNKNOWN);
      }
    }
  }

  void _deathMessage(Mod mod) {
    if (_killer != null) {
      if (_killer == info) {
        world.displayHudMessageAndSendToNetwork("${info.name} killed iself!");
        world.gaReporter().reportEvent("self_kill", "Frags");
      } else {
        String message = killedMessage(info.name, killer.name, mod);
        world.displayHudMessageAndSendToNetwork(message);
      }
    } else {
      world.displayHudMessageAndSendToNetwork("${info.name} died!");
    }
  }

  bool listenFor(String key, dynamic f) {
    assert(getControls().containsKey(key));
    info.remoteKeyState().registerListener(getControls()[key], f);
    return true;
  }

  bool keyIsDown(String key) {
    assert(getControls().containsKey(key));
    return info.remoteKeyState().keyIsDown(getControls()[key]);
  }

  double keyIsDownStrength(String key) {
    assert(getControls().containsKey(key));
    return info.remoteKeyState().keyIsDownStrength(getControls()[key]);
  }

  void addExtraNetworkData(List data) {
    data.add((gun.angle * DOUBLE_INT_CONVERSION).toInt());
    data.add(weaponState.selectedWeaponIndex);
    if (world.network().isCommander()) {
      data.add(health);
      data.add(_shieldPoints);
      data.add(_shieldSec);
    }
  }

  void parseExtraNetworkData(List data, int startAt) {
    gun.angle = data[startAt] / DOUBLE_INT_CONVERSION;
    if (weaponState != null) {
      if (!_ownedByThisWorld()) {
        weaponState.selectedWeaponIndex = data[startAt + 1];
      }
    }
    if (data.length > startAt + 2) {
      health = data[startAt + 2];
      _shieldPoints = data[startAt + 3];
      _shieldSec = data[startAt + 4];
    }
  }

  int get shieldPoints => _shieldPoints;

  void set shieldPoints(int shieldPoints) {
    this._shieldPoints = shieldPoints;
  }

  void set jetPackSec(double secs) {
    this._jetPackSec = secs;
  }

  int extraSendFlags() {
    return 0;
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.REMOTE_PLAYER_CLIENT_SPRITE;
  }

  String toString() => "PlayerSprite for ${info.name}";
}
