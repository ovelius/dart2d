import 'dart:js_interop';

import 'package:dart2d/net/state_updates.pb.dart';
import 'dart:math';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/util/config_params.dart';
import 'package:dart2d/weapons/weapon_state.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/util/keystate.dart';
import 'package:dart2d/util/mobile_controls.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:web/web.dart';

import '../res/sounds.dart';
import '../weapons/abstractweapon.dart';

/**
 * How a server represents itself.
 */
class LocalPlayerSprite extends MovingSprite {
  final Logger log = new Logger('LocalPlayerSprite');
  static const BOUCHYNESS = 0.2;
  static const WALKABLE_HILL_PIXEL_HEIGHT = 4;
  static const MAX_WALK_SPEED = 150.0;
  static const WALK_ACCELERATION_SPEED = 100.0;
  static const JUMP_VELOCITY = -300;
  static final Vec2 DEFAULT_PLAYER_SIZE = new Vec2(42.0, 42.0);
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

  late WormWorld world;
  int health = MAX_HEALTH;
  int _shieldPoints = 0;
  double _jetPackSec = 0.0;
  Particles? _jetParticles = null;

  late PlayerInfoProto info;
  PlayerInfoProto? _killer = null;
  Rope? rope = null;
  MobileControls? _mobileControls;
  double? _gunAngleTouchLock = null;
  WeaponState? weaponState = null;

  bool onGround = false;

  // Don't spawn player when created.
  double spawnIn = 10000000000.0;

  late MovingSprite gun;

  double _shieldSec = -1.0;
  double _nextDamageAnimation = 0.0;
  late StickySprite _shield;

  PlayerInfoProto? get killer => _killer;

  /**
   * Server constructor.
   */
  LocalPlayerSprite(
      WormWorld world,
      ImageIndex imageIndex,
      MobileControls? mobileControls,
      PlayerInfoProto info,
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
        new WeaponState(world, this, this.gun);
    this.listenFor("Next weapon", () {
      weaponState?.nextWeapon();
    });
    this.listenFor("Prev weapon", () {
      weaponState?.prevWeapon();
    });
  }

  StickySprite _createGun(ImageIndex index) {
    StickySprite sprite = new StickySprite(this, index.getImageIdByName("gun.png"),
        index, Sprite.UNLIMITED_LIFETIME);
    // Gun size here.
    sprite.size = new Vec2(30, 7).multiply(2.0);
    return sprite;
  }

  StickySprite _createShield(ImageIndex index) {
    StickySprite shield = new StickySprite(this, index.getImageIdByName("shield.png"),
        index, Sprite.UNLIMITED_LIFETIME);
    shield.size = LocalPlayerSprite.DEFAULT_PLAYER_SIZE.multiply(1.5);
    shield.rotationVelocity = 200.0;
    shield.setImage(index.getImageIdByName("shield.png"), 2);
    return shield;
  }

  bool drawWeaponHelpers() => _ownedByThisWorld();

  hasCommanderToOwnerData() =>
      world.network().isCommander() && !_ownedByThisWorld();

  ExtraSpriteData getCommanderToOwnerData() {
    ExtraSpriteData data = ExtraSpriteData()
        ..extraInt.add(health)
        ..extraInt.add(_shieldPoints)
        ..extraFloat.add(_shieldSec)
        ..extraFloat.add(spawnIn);
    if (_killer != null) {
      data.extraString.add(_killer!.connectionId);
    }
    if (weaponState != null) {
      Weapon w = weaponState!.getSelectedWeapon();
      data.extraFloat.add(w.untilReload);
      data.extraFloat.add(w.untilNextFire);
      data.extraInt.add(w.shotsLeft);
    }
    return data;
  }

  bool commanderToOwnerData(ExtraSpriteData data) {
    health = data.extraInt[0];
    _shieldPoints = data.extraInt[1];
    _shieldSec = data.extraFloat[0];
    spawnIn = data.extraFloat[1];
    if (data.extraString.isNotEmpty) {
      String killerId = data.extraString[0];
      _killer = world
          .network()
          .gameState
          .playerInfoByConnectionId(killerId);
    }
    if (data.extraFloat.length > 2) {
      Weapon w = weaponState!.getSelectedWeapon();
      w.untilReload = data.extraFloat[2];
      w.untilNextFire = data.extraFloat[3];
      w.shotsLeft = data.extraInt[2];
    }
    return true;
  }

  collide(MovingSprite? other, ByteWorld? world, int? direction) {
    if (world != null && direction != null) {
      if (direction & MovingSprite.DIR_BELOW == MovingSprite.DIR_BELOW) {
        onGround = true;
        if (velocity.y.abs() > 1.0) {
          velocity.y = -velocity.y * BOUCHYNESS;
        } else {
          velocity.y = 0.0;
        }
        if (direction != MovingSprite.DIR_BELOW) {
          // Go back right a bit.
          if (direction & MovingSprite.DIR_LEFT == MovingSprite.DIR_LEFT) {
            while (world.isCanvasCollide(
                position.x.toInt(), position.y.toInt(),
                // Allow a few pixels of incline...
                1, size.y.toInt() - WALKABLE_HILL_PIXEL_HEIGHT)) {
              position.x++;
            }
            direction -= MovingSprite.DIR_LEFT;
          }
          // Go back left a bit.
          if (direction & MovingSprite.DIR_RIGHT == MovingSprite.DIR_RIGHT) {
            while (world.isCanvasCollide(
                position.x.toInt() + size.x
                .toInt(), position.y.toInt(),
                // Allow a few pixels of incline...
                1, size.y.toInt() - WALKABLE_HILL_PIXEL_HEIGHT)) {
              position.x--;
            }
            direction -= MovingSprite.DIR_RIGHT;
          }
        }
        // Check one more time, but y -1.
        while (world.isCanvasCollide(
            (position.x + 1).toInt(), (position.y + size.y - 1.0).toInt(), (size.x - 1).toInt(), 1)) {
          position.y--;
        }
      }
      if (direction & MovingSprite.DIR_ABOVE == MovingSprite.DIR_ABOVE) {
        if (velocity.y < 0) {
          velocity.y = -velocity.y * BOUCHYNESS;
        }
        // Check one more time, but more above..
        while (world.isCanvasCollide(
            (position.x + 2).toInt(),
            (position.y - 1).toInt(),
               (size.x - 4).toInt(), 1)) {
          position.y++;
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
    return info.inGame == true;
  }

  draw(CanvasRenderingContext2D context, bool debug) {
    if (!inGame()) {
      this.velocity.x = 0.0;
      this.velocity.y = 0.0;
      if (rope != null) {
        rope!.remove = true;
        rope = null;
      }
      return;
    }
    weaponState?.draw(context);
    context.save();
    gun.draw(context, debug);
    context.restore();
    context.save();
    drawHealthBar(context);
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
  }

  bool drawHealthBar(CanvasRenderingContext2D context) {
    if (!_ownedByThisWorld()) {
      return false;
    }
    if (shieldPoints <=0 && health == MAX_HEALTH) {
      // Don't draw if max health.
      return true;
    }
    int height = 5;
    int x = position.x.toInt();
    int y = (position.y  + size.y + size.y /3).toInt();
    int width = (size.x * health / MAX_HEALTH).toInt();
    context.globalAlpha = 0.5;
    context.fillStyle = "#FF0000".toJS;
    context.fillRect(x, y, size.x.toInt() , height);
    context.fillStyle = "#00FF00".toJS;;
    context.fillRect(x, y, width, height);
    if (_shieldPoints > 0) {
      int shieldWidth = (size.x * _shieldPoints / MAX_SHIELD).toInt();
      context.fillStyle = "#0000ff".toJS;
      context.fillRect(
          x, y, shieldWidth, height);
    }
    context.globalAlpha = 1.0;
    return true;
  }

  bool _ownedByThisWorld() {
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
    if (!inGame() && !world.network().getGameState().hasWinner()) {
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

  frame(double duration, int frames, [Vec2? gravity]) {
    maybeRespawn(duration);
    checkControlKeys(duration);
    checkShouldFire();
    super.frame(duration, frames, gravity);
    gun.frame(duration, frames, gravity);
    _shield.frame(duration, frames, gravity);
    _shieldSec -= duration;
    _jetPackSec -= duration;
    _nextDamageAnimation -= duration;
    weaponState?.think(duration);
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
    double? left = keyIsDownStrength("Left");
    double? right = keyIsDownStrength("Right");
    double? aimUp = keyIsDownStrength("Aim up");
    double? aimDown = keyIsDownStrength("Aim down");

    _applyVel(right, left);

    if (keyIsDown("Jump") && rope != null) {
      world.removeSprite(rope!.networkId!);
      rope = null;
    }

    if (_jetPackSec <= 0 || !keyIsDown("Jump")) {
      if (_jetParticles != null) {
        _jetParticles!.remove = true;
        _jetParticles = null;
      }
    }

    if (keyIsDown("Jump")) {
      if (_jetPackSec > 0) {
        velocity.y -= 700 * duration;
        if (_jetParticles != null && _jetParticles!.remove) {
          _jetParticles = null;
        }
        if (_jetParticles == null) {
          _jetParticles = new Particles(weaponState!.world,
              this, new Vec2.copy(this.position), new Vec2(0, velocity.y + 50),
              followOffset: new Vec2(0, size.y / 2), radius: 10.0, count: 10, lifeTime: 10,
              shrinkPerStep: 0.8, particleType:  ParticleEffects_ParticleType.SODA);
          _jetParticles!.sendToNetwork = true;
          _jetParticles!.spawn_sound = Sound.FIZZ;
          world.addSprite(_jetParticles!);
        }
      } else if (onGround) {
        velocity.y += JUMP_VELOCITY;
        world.playSound(Sound.JUMP);
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
    Point<int>? delta = _mobileControls!.getTouchDeltaForButton();
    if (_mobileControls!.buttonIsDown()) {
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

  int extraSendFlags() {
   return 0;
  }

  void _applyVel(double? right, double? left) {
    if (left != null) {
      if (velocity.x > -WALK_ACCELERATION_SPEED) {
        velocity.x -= WALK_ACCELERATION_SPEED * left;
      }
      if (velocity.x < -MAX_WALK_SPEED * left) {
        velocity.x = -MAX_WALK_SPEED * left;
      }
      if (velocity.x < -MAX_WALK_SPEED) {
        velocity.x = -MAX_WALK_SPEED;
      }
      if (angle < pi * 2) {
        gun.angle -= (gun.angle + pi / 2) * 2;
        if (_gunAngleTouchLock != null) {
          _gunAngleTouchLock = _gunAngleTouchLock! - (_gunAngleTouchLock! + pi / 2) * 2;
          ;
        }
        angle = pi * 2 + 0.01;
      }
    } else if (right != null) {
      if (velocity.x < MAX_WALK_SPEED * right) {
        velocity.x += WALK_ACCELERATION_SPEED * right;
      }
      if (velocity.x > MAX_WALK_SPEED * right) {
        velocity.x = MAX_WALK_SPEED * right;
      }
      if (velocity.x > MAX_WALK_SPEED) {
        velocity.x = MAX_WALK_SPEED;
      }
      if (angle != 0.0) {
        angle = 0.0;
        gun.angle -= (gun.angle + pi / 2) * 2;
        ;
        if (_gunAngleTouchLock != null) {
          _gunAngleTouchLock = _gunAngleTouchLock! - (_gunAngleTouchLock! + pi / 2) * 2;
          ;
        }
      }
    } else {
      velocity.x = velocity.x * 0.94;
    }
  }

  bool checkMobileControls(int xD, yD) {
    if (angle != 0.0) {
      gun.angle = _gunAngleTouchLock! + (yD * 0.02);
      if (gun.angle > -pi / 2) {
        gun.angle = -pi / 2;
      }
      if (gun.angle < -(pi + pi / 3)) {
        gun.angle = -(pi + pi / 3);
      }
    } else {
      gun.angle = _gunAngleTouchLock! - (yD * 0.02);
      if (gun.angle > pi / 3) {
        gun.angle = pi / 3;
      }
      if (gun.angle < -pi / 2) {
        gun.angle = -pi / 2;
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
    if (keyIsDown("Fire") && inGame()) {
      weaponState?.fire();
    }
    return true;
  }

  void _gunDown(double duration) {
    if (angle != 0.0) {
      gun.angle -= duration * 4.0;
      if (gun.angle < -(pi + pi / 3)) {
        gun.angle = -(pi + pi / 3);
      }
    } else {
      gun.angle += duration * 4.0;
      if (gun.angle > pi / 3) {
        gun.angle = pi / 3;
      }
    }
  }

  void _gunUp(double duration) {
    // Diffent if facing left or right.
    if (angle != 0.0) {
      gun.angle += duration * 4.0;
      if (gun.angle > -pi / 2) {
        gun.angle = -pi / 2;
      }
    } else {
      gun.angle -= duration * 4.0;
      if (gun.angle < -pi / 2) {
        gun.angle = -pi / 2;
      }
    }
  }

  void _fireRope() {
    world.playSoundAtSprite(this, Sound.WHIP);
    if (rope != null) {
      world.removeSprite(rope!.networkId!);
    }
    rope = new Rope.createWithOwner(this.world, this, this.gun.angle, 600.0);
    world.addSprite(rope!);
  }

  bool takesDamage() {
    return collision;
  }

  void takeDamage(int damage, LocalPlayerSprite inflictor, Mod mod) {
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
        _killer = world
            .network()
            .gameState
            .playerInfoBySpriteId(inflictor.networkId!);
        if (_killer != null && _killer != info) {
          _killer!.score++;
          world.gaReporter().reportEvent("player_frags", "Frags");
          world.checkWinner(killer!);
        }
        spawnIn = RESPAWN_TIME;
        _deathMessage(mod);
        _addDeathParticles();
        world.playSound(Sound.DEATH);
      } else if (_shieldPoints <= 0) {
        _addDamageParticles();
      }
    }
  }

  void _addDeathParticles() {
    int blood = world.config().getInt(ConfigParam.BLOOD);
    int countLifeTime = blood > 0 ? blood : 120;
    Particles p = Particles(world, null, centerPoint(), Vec2(200,300),
        radius: 25.0, count:countLifeTime, lifeTime: countLifeTime, shrinkPerStep: 0.3,
        particleType:
        blood > 0  ?
            ParticleEffects_ParticleType.BLOOD :
            ParticleEffects_ParticleType.CONFETTI);
    p.sendToNetwork = true;
    world.addSprite(p);
  }

  void _addDamageParticles() {
    if (_nextDamageAnimation < 0) {
      int blood = world.config().getInt(ConfigParam.BLOOD);
      int countLifeTime = blood > 0 ? blood : 120;
      Particles p = Particles(
          world,
          null,
          centerPoint(),
          Vec2(200, 300),
          radius: 8.0,
          count: (countLifeTime / 10).toInt(),
          lifeTime: (countLifeTime / 2).toInt(),
          shrinkPerStep: 0.3,
          particleType: blood > 0 ?
              ParticleEffects_ParticleType.BLOOD :
              ParticleEffects_ParticleType.CONFETTI);
      p.sendToNetwork = true;
      world.addSprite(p);
      world.playSoundAtSprite(this, Sound.OW);
      _nextDamageAnimation = 0.3;
    }
  }

  void _deathMessage(Mod mod) {
    if (_killer != null) {
      if (_killer == info) {
        world.displayHudMessageAndSendToNetwork("${info.name} killed itself!");
        world.gaReporter().reportEvent("self_kill", "Frags");
      } else {
        String message = killedMessage(info.name, killer!.name, mod);
        world.displayHudMessageAndSendToNetwork(message);
      }
    } else {
      world.displayHudMessageAndSendToNetwork("${info.name} died!");
    }
  }

  KeyState getKeyState() {
    KeyState? keyState = world.network().getGameState().getKeyStateFor(info.connectionId);
    if (keyState == null) {
      throw "No keystate for ${info.connectionId} in world ${world}";
    }
    return keyState;
  }

  bool listenFor(String key, dynamic f) {
    assert(getControls().containsKey(key));
    getKeyState().registerListener(getControls()[key]!, f);
    return true;
  }

  bool keyIsDown(String key) {
    assert(getControls().containsKey(key));
    return getKeyState().keyIsDown(getControls()[key]!);
  }

  double? keyIsDownStrength(String key) {
    assert(getControls().containsKey(key));
    return getKeyState().keyIsDownStrength(getControls()[key]!);
  }

  ExtraSpriteData addExtraNetworkData() {
    ExtraSpriteData data = ExtraSpriteData()
      ..extraFloat.add(gun.angle)
      ..extraInt.add(weaponState!.selectedWeaponIndex);
    if (world.network().isCommander()) {
      data.extraInt
        ..add(health)
        ..add(_shieldPoints);
      data.extraFloat.add(_shieldSec);
    }
    return data;
  }

  void parseExtraNetworkData(ExtraSpriteData data) {
    gun.angle = data.extraFloat[0];
    if (weaponState != null) {
      if (!_ownedByThisWorld()) {
        weaponState!.selectedWeaponIndex = data.extraInt[0];
      }
    }
    if (data.extraInt.length > 1) {
      health = data.extraInt[1];
      _shieldPoints = data.extraInt[2];
      _shieldSec = data.extraFloat[1];
    }
  }

  int get shieldPoints => _shieldPoints;

  void set shieldPoints(int shieldPoints) {
    this._shieldPoints = shieldPoints;
  }

  void set jetPackSec(double secs) {
    this._jetPackSec = secs;
  }

  SpriteConstructor remoteRepresentation() {
    return SpriteConstructor.REMOTE_PLAYER_CLIENT_SPRITE;
  }

  String toString() => "PlayerSprite for ${info.name}";
}
