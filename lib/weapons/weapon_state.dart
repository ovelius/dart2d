library weapon_state;

import 'dart:js_interop';

import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/weapons/abstractweapon.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'dart:math';
import 'package:dart2d/phys/vec2.dart';
import 'package:web/web.dart';

import '../net/state_updates.pb.dart';
import '../res/sounds.dart';
import '../util/config_params.dart';
import '../util/mobile_controls.dart';

enum BingoTier {
  none,
  superBingo,
}

class BingoProbabilities {
  final double superBingo;

  const BingoProbabilities({
    required this.superBingo,
  });
}

class WeaponState {
  static Random random = new Random();
  static const double SHOW_WEAPON_NAME_TIME = 1.3;
  static const double WEAPON_SWITCH_FIRE_DELAY = 0.10;
  static const double ROULETTE_SPIN_DURATION = 1.85;
  static const double ROULETTE_REVEAL_DURATION = 1.50;
  static const double SUPER_BINGO_REVEAL_DURATION = 2.35;
  static const int ROULETTE_TOTAL_STEPS = 16;
  static const int _SANDBOX_MASK_BIT = 1 << 20;

  // Handicap Superbingo probability tuning:
  // - Leader (0% behind): 1% Superbingo.
  // - 50% of maxFrags behind leader: 80% Superbingo.
  static const double LEADER_SUPER_BINGO_PROB = 0.01;
  static const double HALF_DEFICIT_SUPER_BINGO_PROB = 0.80;

  static const int ICON_TILE_SIZE = 68;
  static const int ICON_SIZE_HALF = ICON_TILE_SIZE ~/ 2;
  static const int WHEEL_SIZE = 172;
  static const int SHARK_ICON_INDEX = 14;
  static const double SHARK_MYSTERY_WEIGHT = 0.35;
  WormWorld world;
  LocalPlayerSprite owner;
  Sprite gun;
  MobileControls? mobileControls;
  
  double changeTime = 0.0;
  double _laserTime = 0.0;
  bool _wasReloading = false;
  double _reloadReadyFlash = 0.0;
  String _longestWeaponName = "";
  int selectedWeaponIndex = 2;
  int _lastStarterWeaponIndex = 2;
  double _anglePerWeapon = 0.0;
  bool _remoteSandboxActive = false;

  // Mario Kart-style mystery weapon roulette + handicap bingo state.
  int _rouletteTargetWeaponIndex = -1;
  int _rouletteDisplayWeaponIndex = -1;
  double _rouletteSpinRemaining = 0.0;
  double _rouletteRevealRemaining = 0.0;
  double _rouletteRevealTotalDuration = ROULETTE_REVEAL_DURATION;
  double _rouletteVisualPhase = 0.0;
  int _lastRouletteStepPlayed = -1;
  int _rouletteNonce = 0;
  int _completedRouletteNonce = 0;
  BingoTier _rouletteBingoTier = BingoTier.none;

  String get selectedWeaponName => weapons[selectedWeaponIndex].name;
  bool get isRouletteSpinning =>
      _rouletteSpinRemaining > 0.0 && _rouletteTargetWeaponIndex >= 0;
  bool get isRouletteRevealing =>
      _rouletteSpinRemaining <= 0.0 &&
      _rouletteRevealRemaining > 0.0 &&
      _rouletteTargetWeaponIndex >= 0;
  bool get isRouletteActive => isRouletteSpinning || isRouletteRevealing;
  int get rouletteTargetWeaponIndex => _rouletteTargetWeaponIndex;
  int get rouletteDisplayWeaponIndex => _rouletteDisplayWeaponIndex;
  int get rouletteNonce => _rouletteNonce;
  int get completedRouletteNonce => _completedRouletteNonce;
  double get rouletteSpinRemaining => _rouletteSpinRemaining;
  BingoTier get rouletteBingoTier => _rouletteBingoTier;

  void cancelMysteryRoulette() {
    _rouletteSpinRemaining = 0.0;
    _rouletteRevealRemaining = 0.0;
    _rouletteTargetWeaponIndex = -1;
    _rouletteDisplayWeaponIndex = -1;
    _lastRouletteStepPlayed = -1;
    _rouletteBingoTier = BingoTier.none;
  }

  bool get isSandboxMode {
    if (_remoteSandboxActive) {
      return true;
    }
    try {
      final dynamic cfg = world.config();
      if (cfg != null) {
        return cfg.getBool(ConfigParam.SANDBOX) == true;
      }
    } catch (_) {}
    return false;
  }

  WeaponState(this.world, this.owner, this.gun,  this.mobileControls) {
    for (Weapon w in weapons) {
      if (w.name.length > _longestWeaponName.length) {
        _longestWeaponName = w.name;
      }
    }
    mobileControls?.listenForTouch((int x, int y) {
      if (changeTime > 0 && owner.drawWeaponHelpers()) {
        // Do not hijack taps meant for action/weapon/mute buttons!
        if (mobileControls!.isButtonTouch(x, y)) {
          return;
        }
        final int? tappedIdx = weaponIndexAtScreenPoint(
          Point<int>(x, y),
          mobileControls!.buttonLocation(MobileControls.WEAPON_SELECT_BUTTON),
        );
        if (tappedIdx != null) {
          _selectWeaponIndex(tappedIdx);
          changeTime = 0.0;
        }
      }
    });
    _anglePerWeapon =  (pi * 2)/weapons.length;
  }

  Weapon getSelectedWeapon() => weapons[selectedWeaponIndex];

  List<Weapon> weapons = [
    new Weapon("Banana pancake", 4, 2, 5.0, 1.0, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new BananaCake.createWithOwner(weaponState.world,  weaponState.owner, 50, weaponState.owner.gun);
      sprite.explodeAfter = 4.0;
      sprite.owner = weaponState.owner;
      sprite.radius = 50.0;
      sprite.spawn_sound = Sound.SWOSH;
      weaponState.world.addSprite(sprite);
    }, isMysteryWeapon: true),
    new Weapon("Brick builder", 9, 20, 5.0, 0.3, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new BrickBuilder.createWithOwner(weaponState.world, weaponState.owner, 2, weaponState.owner.gun);
      sprite.mod = Mod.BRICK;
      sprite.spawn_sound = Sound.THUD;
      sprite.owner = weaponState.owner;
      sprite.radius = 50.0;
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Chicken shooter", 0, 6, 2.0, 1.0, (WeaponState weaponState) {
      weaponState.world.playSoundAtSprite(weaponState.owner, Sound.SHOTGUN);
      for (int i = 0; i < 8; i++) {
        ChickenProjectile sprite = new ChickenProjectile.createWithOwner(
            weaponState.world, weaponState.owner, 7, weaponState.owner.gun);
        double sum = sprite.velocity.sum();
        sprite.velocity.x = sprite.velocity.x + random.nextDouble() * sum / 4;
        sprite.velocity.y = sprite.velocity.y + random.nextDouble() * sum / 4;
        weaponState.world.addSprite(sprite);
      }
    }),
    new Weapon("Dart gun", 1, 120, 6.0, .12, (WeaponState weaponState) {
      DartProjectile sprite = new DartProjectile.createWithOwner(
          weaponState.world, weaponState.owner, 8, weaponState.owner.gun);
      weaponState.world.addSprite(sprite);
    }),
    new Weapon("Jellybean Jet", 8, 40, 9.0, .11, (WeaponState weaponState) {
      JellybeanProjectile sprite = new JellybeanProjectile.createWithOwner(
          weaponState.world, weaponState.owner, 8, weaponState.owner.gun);
      weaponState.world.addSprite(sprite);
    }, isMysteryWeapon: true),
    new Weapon("Coffee Burn", 2, 150, 2.0, .05, (WeaponState weaponState) {
      Vec2 vel = new Vec2(cos(weaponState.gun.angle), sin(weaponState.gun.angle));
      Vec2 position = weaponState.gun.centerPoint();
      double gunRadius = weaponState.gun.size.sum() / 2;
      position.x += cos(weaponState.gun.angle) * gunRadius;
      position.y += sin(weaponState.gun.angle) * gunRadius;
      Particles p = new Particles(
          weaponState.world,
          null, position, vel.multiply(400.0),
          radius: 10.0, count: 5, lifeTime: 65, shrinkPerStep: -0.3, particleType: ParticleEffects_ParticleType.FIRE);
      p.sendToNetwork = true;
      p.world = weaponState.world;
      p.collision = true;
      p.damage = 7;
      p.spawn_sound = Sound.BURN;
      p.owner = weaponState.owner;
      weaponState.world.addSprite(p);
    }, isMysteryWeapon: true),
    new Weapon("Snailgun", 3, 3, 1.0, 0.6, (WeaponState weaponState) {
      SnailProjectile sprite = new SnailProjectile.createWithOwner(
          weaponState.world, weaponState.owner, 12, weaponState.owner.gun);

      Vec2 offset = Vec2(-sprite.size.x * cos(sprite.angle),
          -sprite.size.y * sin(sprite.angle)).multiply(0.35);

      Particles p = new Particles(weaponState.world, sprite, sprite.position, sprite.velocity.multiply(0.2),
          radius: 6.8, count: 42, lifeTime: 115, shrinkPerStep: 0.25, followOffset: offset);
      p.sendToNetwork = true;
      // The order is important here.
      weaponState.world.addSprite(sprite);
      weaponState.world.addSprite(p);
    }, hasLaserSight: true, isMysteryWeapon: true),
    new Weapon("Cat litter box", 5, 2, 5.0, 1.0, (WeaponState weaponState) {
      CatLitterBox sprite = new CatLitterBox.createWithOwner(
          weaponState.world, weaponState.owner, 100, weaponState.owner.gun);
      sprite.spawn_sound = Sound.SWOSH;
      weaponState.world.addSprite(sprite);
    }, isMysteryWeapon: true),
    /*
    new Weapon("Black sheep down", 1, 5.0, 0.01, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(weaponState.world, weaponState.gun, 100);
      sprite.radius = 450.0;
      sprite.owner = weaponState.owner;
      sprite.explodeAfter = 5.0;
      sprite.size = new Vec2(58.0 * 0.7, 58.0 * 0.7);
      sprite.angle = 0.0;
      sprite.bounche = 1.0;
      sprite.velocity = sprite.velocity.multiply(0.4);
      sprite.setImage(weaponState.world.imageIndex().getImageIdByName("sheep_black58.png"), 58);
      weaponState.world.addSprite(sprite);
    }), */
    new Weapon("Zooka", 6, 5, 2.5, 0.8, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new WorldDamageProjectile.createWithOwner(
          weaponState.world, weaponState.owner, 40,
          positionBase: weaponState.owner.gun, size: new Vec2(38.0, 16.0));
      sprite.mod = Mod.ZOOKA;
      sprite.spawn_sound = Sound.ZOOKA;
      sprite.radius = 40.0;
      sprite.owner = weaponState.owner;
      sprite.gravityAffect = 0.05;
      // sprite.velocity = sprite.velocity.multiply(0.2);
      sprite.setImage(weaponState.world.imageIndex().getImageIdByName("zooka.png"), 1);
      Vec2 offset = Vec2(-cos(sprite.angle), -sin(sprite.angle)).multiply(sprite.size.x * 0.46);
      Particles p = new Particles(weaponState.world, sprite, sprite.position, sprite.velocity.multiply(0.2),
          count: 45, lifeTime: 55, radius: 9.0, shrinkPerStep: 0.2, followOffset: offset);
      p.sendToNetwork = true;
      // The order is important here.
      weaponState.world.addSprite(sprite);
      weaponState.world.addSprite(p);
    }),
    new Weapon("Neon Blaster", 7, 5, 2.5, 1.20, (WeaponState weaponState) {
      WorldDamageProjectile sprite = new Hyper.createWithOwner(weaponState.world, weaponState.owner, 30, weaponState.owner.gun);
      sprite.radius = Hyper.DEFAULT_BLAST_RADIUS;
      sprite.spawn_sound = Sound.HYPER;
      sprite.owner = weaponState.owner;
      sprite.gravityAffect = 0.00;
      weaponState.world.addSprite(sprite);
    }, isMysteryWeapon: true),
    new Weapon("Spiky Hedgehog", 10, 2, 5.5, 0.9, (WeaponState weaponState) {
      HedgehogMine sprite = new HedgehogMine.createWithOwner(
          weaponState.world, weaponState.owner, 38, weaponState.owner.gun);
      sprite.spawn_sound = Sound.SWOSH;
      weaponState.world.addSprite(sprite);
    }, isMysteryWeapon: true),
    new Weapon("Turbo Mole", 11, 4, 5.0, 1.0, (WeaponState weaponState) {
      MoleDrillProjectile sprite = new MoleDrillProjectile.createWithOwner(
          weaponState.world, weaponState.owner, 45, weaponState.owner.gun);
      sprite.spawn_sound = Sound.ZOOKA;
      weaponState.world.addSprite(sprite);
    }, isMysteryWeapon: true),
    new Weapon("Angry Beehive", 12, 2, 5.5, 1.0, (WeaponState weaponState) {
      AngryBeehive sprite = new AngryBeehive.createWithOwner(
          weaponState.world, weaponState.owner, 18, weaponState.owner.gun);
      sprite.spawn_sound = Sound.SWOSH;
      weaponState.world.addSprite(sprite);
    }, isMysteryWeapon: true),
    new Weapon("Pigeon Strike", 13, 1, 6.5, 1.0, (WeaponState weaponState) {
      PigeonStrikeFlare sprite = new PigeonStrikeFlare.createWithOwner(
          weaponState.world, weaponState.owner, weaponState.owner.gun);
      sprite.spawn_sound = Sound.DARTGUN;
      weaponState.world.addSprite(sprite);
    }, isMysteryWeapon: true),
    new Weapon("Mega Shark", SHARK_ICON_INDEX, 1, 8.0, 1.0,
        (WeaponState weaponState) {
      HunterSharkProjectile sprite = new HunterSharkProjectile.createWithOwner(
          weaponState.world, weaponState.owner, weaponState.owner.gun);
      sprite.spawn_sound = Sound.SPAWN;
      weaponState.world.addSprite(sprite);
    }, isMysteryWeapon: true, mysteryWeight: SHARK_MYSTERY_WEIGHT),
  ];

  bool isCarryingReadyShark() {
    final Weapon w = getSelectedWeapon();
    return w.name == "Mega Shark" &&
        w.shotsLeft > 0 &&
        !w.reloading() &&
        !isRouletteActive;
  }
  
  bool isWeaponAvailable(int index) {
    if (index < 0 || index >= weapons.length) {
      return false;
    }
    final Weapon w = weapons[index];
    if (!w.isMysteryWeapon || isSandboxMode) {
      return true;
    }
    return w.unlocked && w.shotsLeft > 0;
  }

  List<int> availableWeaponIndices() {
    final List<int> indices = <int>[];
    for (int i = 0; i < weapons.length; i++) {
      if (isWeaponAvailable(i)) {
        indices.add(i);
      }
    }
    return indices;
  }

  List<int> mysteryWeaponIndices() {
    final List<int> indices = <int>[];
    for (int i = 0; i < weapons.length; i++) {
      if (weapons[i].isMysteryWeapon) {
        indices.add(i);
      }
    }
    return indices;
  }

  int get unlockedWeaponsBitmask {
    int mask = isSandboxMode ? _SANDBOX_MASK_BIT : 0;
    for (int i = 0; i < weapons.length; i++) {
      if (isWeaponAvailable(i)) {
        mask |= (1 << i);
      }
    }
    return mask;
  }

  static BingoProbabilities computeBingoProbabilitiesFor({
    required int playerScore,
    required int leaderScore,
    required int maxFrags,
  }) {
    final int safeMaxFrags = max(1, maxFrags);
    final int fragsBehind = max(0, leaderScore - playerScore);
    final double deficitRatio = fragsBehind / safeMaxFrags;

    double superProb;
    if (deficitRatio <= 0.5) {
      final double t = (deficitRatio / 0.5).clamp(0.0, 1.0);
      superProb = LEADER_SUPER_BINGO_PROB +
          (HALF_DEFICIT_SUPER_BINGO_PROB - LEADER_SUPER_BINGO_PROB) * t;
    } else {
      final double overT = ((deficitRatio - 0.5) / 0.5).clamp(0.0, 1.0);
      superProb = HALF_DEFICIT_SUPER_BINGO_PROB + 0.10 * overT;
    }
    return BingoProbabilities(
      superBingo: superProb.clamp(0.0, 1.0),
    );
  }

  /// Returns true when [owner] strictly holds the lowest score in a 2+ player
  /// match (so neither an all-way tie nor a bottom tie).
  bool isStrictlyLastPlace() {
    final List<PlayerInfoProto> players =
        world.network().getGameState().playerInfoList();
    if (players.length < 2) {
      return false;
    }
    final int myScore = owner.info.score;
    int minScore = players.first.score;
    int maxScore = players.first.score;
    int minCount = 0;
    for (final PlayerInfoProto p in players) {
      if (p.score < minScore) {
        minScore = p.score;
        minCount = 1;
      } else if (p.score == minScore) {
        minCount++;
      }
      if (p.score > maxScore) {
        maxScore = p.score;
      }
    }
    return minScore < maxScore && myScore == minScore && minCount == 1;
  }

  BingoProbabilities currentBingoProbabilities() {
    int maxFrags = 10;
    int leaderScore = owner.info.score;
    try {
      final dynamic cfg = world.config();
      if (cfg != null) {
        final int configured = cfg.getInt(ConfigParam.MAX_FRAGS);
        if (configured > 0) {
          maxFrags = configured;
        }
      }
    } catch (_) {}
    try {
      final List<PlayerInfoProto> players =
          world.network().getGameState().playerInfoList();
      for (final PlayerInfoProto p in players) {
        if (p.score > leaderScore) {
          leaderScore = p.score;
        }
      }
    } catch (_) {}
    return computeBingoProbabilitiesFor(
      playerScore: owner.info.score,
      leaderScore: leaderScore,
      maxFrags: maxFrags,
    );
  }

  BingoTier rollBingoTier([double? rollOverride]) {
    final BingoProbabilities probs = currentBingoProbabilities();
    final double r = (rollOverride ?? random.nextDouble()).clamp(0.0, 0.999999);
    if (r < probs.superBingo) {
      return BingoTier.superBingo;
    }
    return BingoTier.none;
  }

  void applyCommanderSync({
    required int unlockedMask,
    required int rouletteNonce,
    required int rouletteTarget,
    required double rouletteSpinRem,
    int rouletteBingoIndex = 0,
  }) {
    _remoteSandboxActive = (unlockedMask & _SANDBOX_MASK_BIT) != 0;
    final bool matchEndedOrOut =
        !owner.inGame() || world.network().getGameState().hasWinner();
    for (int i = 0; i < weapons.length; i++) {
      final Weapon w = weapons[i];
      if (!w.isMysteryWeapon) {
        w.unlocked = true;
        continue;
      }
      final bool nowUnlocked = (unlockedMask & (1 << i)) != 0;
      final bool pendingRevealForThisWeapon = !matchEndedOrOut &&
          (rouletteNonce > _rouletteNonce || _rouletteSpinRemaining > 0.0) &&
          rouletteTarget == i &&
          rouletteSpinRem > 0.05;
      if (nowUnlocked && !w.unlocked && !pendingRevealForThisWeapon) {
        w.unlocked = true;
        if (w.shotsLeft <= 0) {
          w.shotsLeft = w.shotsPerClip;
        }
        w.untilReload = 0.0;
        w.untilNextFire = 0.0;
      } else if (!nowUnlocked && w.unlocked && !isSandboxMode) {
        // Don't strip a weapon on client while the local roulette hasn't finished revealing yet.
        if (!(_rouletteSpinRemaining > 0.0 && _rouletteTargetWeaponIndex == i)) {
          w.unlocked = false;
          w.shotsLeft = 0;
          w.untilReload = 0.0;
          if (selectedWeaponIndex == i) {
            selectedWeaponIndex = _fallbackStarterIndex();
          }
        }
      }
    }

    if (matchEndedOrOut) {
      if (isRouletteActive) {
        cancelMysteryRoulette();
      }
      return;
    }

    if (rouletteNonce > _rouletteNonce &&
        rouletteTarget >= 0 &&
        rouletteTarget < weapons.length) {
      _rouletteNonce = rouletteNonce;
      _rouletteTargetWeaponIndex = rouletteTarget;
      final int safeBingo =
          rouletteBingoIndex.clamp(0, BingoTier.values.length - 1);
      _rouletteBingoTier = BingoTier.values[safeBingo];
      if (rouletteSpinRem > 0.05) {
        _rouletteSpinRemaining = rouletteSpinRem;
        _rouletteRevealRemaining = 0.0;
        _lastRouletteStepPlayed = -1;
        _updateRouletteStep(playTickSound: false);
      } else {
        // Spin already finished on commander before packet arrived -> award & reveal!
        _completeMysteryRoulette();
      }
    } else if (rouletteNonce == _rouletteNonce &&
        rouletteNonce > 0 &&
        rouletteTarget >= 0 &&
        rouletteTarget < weapons.length) {
      _rouletteTargetWeaponIndex = rouletteTarget;
      final int safeBingo =
          rouletteBingoIndex.clamp(0, BingoTier.values.length - 1);
      _rouletteBingoTier = BingoTier.values[safeBingo];
      if (_rouletteSpinRemaining > 0.0 && rouletteSpinRem <= 0.0) {
        // Commander already finished spinning -> settle client's final tick promptly.
        _rouletteSpinRemaining = min(_rouletteSpinRemaining, 0.10);
      } else if (_completedRouletteNonce < rouletteNonce &&
          _rouletteSpinRemaining <= 0.0 &&
          rouletteSpinRem <= 0.0) {
        _completeMysteryRoulette();
      }
    }
  }

  int _fallbackStarterIndex() {
    if (isWeaponAvailable(_lastStarterWeaponIndex) &&
        !weapons[_lastStarterWeaponIndex].isMysteryWeapon) {
      return _lastStarterWeaponIndex;
    }
    for (int i = 0; i < weapons.length; i++) {
      if (!weapons[i].isMysteryWeapon) {
        return i;
      }
    }
    return 0;
  }

  void onMysteryWeaponDepleted(Weapon depletedWeapon) {
    if (isSandboxMode) {
      return;
    }
    final int idx = weapons.indexOf(depletedWeapon);
    if (idx >= 0 && selectedWeaponIndex == idx) {
      selectedWeaponIndex = _fallbackStarterIndex();
      final Weapon fallback = weapons[selectedWeaponIndex];
      fallback.untilNextFire = max(
        fallback.untilNextFire,
        max(0.45, depletedWeapon.fireDelay),
      );
      changeTime = 0.85;
    }
  }

  int triggerMysteryRoulette({
    int? forcedWeaponIndex,
    BingoTier? forcedBingoTier,
    double? bingoRollOverride,
  }) {
    if (isSandboxMode ||
        !owner.inGame() ||
        world.network().getGameState().hasWinner()) {
      return -1;
    }
    // If a previous spin was still active, grant its pending weapon & bingo
    // immediately before starting the new spin so picking up two boxes never drops one.
    if (_rouletteSpinRemaining > 0.0 &&
        _rouletteTargetWeaponIndex >= 0 &&
        _rouletteTargetWeaponIndex < weapons.length) {
      final Weapon prev = weapons[_rouletteTargetWeaponIndex];
      prev.unlocked = true;
      prev.shotsLeft = prev.shotsPerClip;
      prev.untilReload = 0.0;
      _applyBingoRewardToOwner(_rouletteBingoTier);
    }

    final List<int> allMystery = mysteryWeaponIndices();
    if (allMystery.isEmpty) {
      return -1;
    }
    final List<int> lockedPool = allMystery
        .where((int i) => !weapons[i].unlocked || weapons[i].shotsLeft <= 0)
        .toList();
    final List<int> pool = lockedPool.isNotEmpty ? lockedPool : allMystery;

    final int winnerIdx = (forcedWeaponIndex != null &&
            forcedWeaponIndex >= 0 &&
            forcedWeaponIndex < weapons.length &&
            weapons[forcedWeaponIndex].isMysteryWeapon)
        ? forcedWeaponIndex
        : _pickWeightedMysteryIndex(pool);

    // Always restore full health when the strictly last-place player picks up a mystery powerup.
    if (isStrictlyLastPlace() && owner.health < LocalPlayerSprite.MAX_HEALTH) {
      owner.health = LocalPlayerSprite.MAX_HEALTH;
    }

    final BingoTier rolledTier =
        forcedBingoTier ?? rollBingoTier(bingoRollOverride);

    _rouletteNonce++;
    _rouletteTargetWeaponIndex = winnerIdx;
    _rouletteBingoTier = rolledTier;
    _rouletteSpinRemaining = ROULETTE_SPIN_DURATION;
    _rouletteRevealRemaining = 0.0;
    _lastRouletteStepPlayed = -1;
    _updateRouletteStep(playTickSound: true);
    return winnerIdx;
  }

  int _pickWeightedMysteryIndex(List<int> pool) {
    double totalWeight = 0.0;
    for (final int idx in pool) {
      totalWeight += max(0.01, weapons[idx].mysteryWeight);
    }
    double roll = random.nextDouble() * totalWeight;
    for (final int idx in pool) {
      roll -= max(0.01, weapons[idx].mysteryWeight);
      if (roll <= 0.0) {
        return idx;
      }
    }
    return pool.last;
  }

  void _applyBingoRewardToOwner(BingoTier tier) {
    if (tier == BingoTier.superBingo) {
      owner.applySuperBingoBonus();
    }
  }

  void _updateRouletteStep({required bool playTickSound}) {
    final List<int> mystery = mysteryWeaponIndices();
    if (mystery.isEmpty || _rouletteTargetWeaponIndex < 0) {
      return;
    }
    final double progress = (1.0 -
            (_rouletteSpinRemaining / ROULETTE_SPIN_DURATION))
        .clamp(0.0, 1.0);
    // Mario Kart-style deceleration: fast blur at first, dramatic slow-down on final ticks.
    final double eased = 1.0 - pow(1.0 - progress, 2.8).toDouble();
    final double exactStep = eased * ROULETTE_TOTAL_STEPS;
    _rouletteVisualPhase = exactStep;
    final int step = exactStep.floor().clamp(0, ROULETTE_TOTAL_STEPS);
    final int targetPos = max(0, mystery.indexOf(_rouletteTargetWeaponIndex));
    final int n = mystery.length;
    final int remainingSteps = ROULETTE_TOTAL_STEPS - step;
    _rouletteDisplayWeaponIndex =
        mystery[((targetPos - (remainingSteps % n)) + n) % n];

    if (step > _lastRouletteStepPlayed && step < ROULETTE_TOTAL_STEPS) {
      _lastRouletteStepPlayed = step;
      if (playTickSound && owner.drawWeaponHelpers()) {
        try {
          world.playSound(Sound.ROULETTE_TICK, volume: 0.72, multiPlay: true);
        } catch (_) {}
      }
    }
  }

  void _completeMysteryRoulette() {
    _rouletteSpinRemaining = 0.0;
    if (_rouletteTargetWeaponIndex < 0 ||
        _rouletteTargetWeaponIndex >= weapons.length) {
      return;
    }
    _completedRouletteNonce = _rouletteNonce;
    _rouletteDisplayWeaponIndex = _rouletteTargetWeaponIndex;
    _rouletteVisualPhase = ROULETTE_TOTAL_STEPS.toDouble();
    if (_rouletteBingoTier == BingoTier.superBingo) {
      _rouletteRevealTotalDuration = SUPER_BINGO_REVEAL_DURATION;
    } else {
      _rouletteRevealTotalDuration = ROULETTE_REVEAL_DURATION;
    }
    _rouletteRevealRemaining = _rouletteRevealTotalDuration;

    final Weapon won = weapons[_rouletteTargetWeaponIndex];
    won.unlocked = true;
    won.shotsLeft = won.shotsPerClip;
    won.untilReload = 0.0;
    won.untilNextFire = 0.0;
    if (!weapons[selectedWeaponIndex].isMysteryWeapon) {
      _lastStarterWeaponIndex = selectedWeaponIndex;
    }
    selectedWeaponIndex = _rouletteTargetWeaponIndex;
    changeTime = SHOW_WEAPON_NAME_TIME;

    _applyBingoRewardToOwner(_rouletteBingoTier);

    final Sound landingSound = _rouletteBingoTier == BingoTier.superBingo
        ? Sound.SUPER_BINGO
        : Sound.ROULETTE_WIN;

    try {
      if (owner.drawWeaponHelpers()) {
        world.playSound(landingSound, volume: 0.98, multiPlay: true);
      } else {
        world.playSoundAtSprite(owner, landingSound, multiPlay: true);
      }
    } catch (_) {}
  }

  void _selectWeaponIndex(int idx) {
    if (idx != selectedWeaponIndex) {
      selectedWeaponIndex = idx;
      final Weapon w = weapons[selectedWeaponIndex];
      w.untilNextFire = max(w.untilNextFire, WEAPON_SWITCH_FIRE_DELAY);
    }
    if (!weapons[selectedWeaponIndex].isMysteryWeapon) {
      _lastStarterWeaponIndex = selectedWeaponIndex;
    }
  }

  nextWeapon() {
    final List<int> avail = availableWeaponIndices();
    if (avail.isEmpty) return;
    final int pos = avail.indexOf(selectedWeaponIndex);
    _selectWeaponIndex(
        pos < 0 ? avail.first : avail[(pos + 1) % avail.length]);
    changeTime = SHOW_WEAPON_NAME_TIME;
  }

  prevWeapon() {
    final List<int> avail = availableWeaponIndices();
    if (avail.isEmpty) return;
    final int pos = avail.indexOf(selectedWeaponIndex);
    _selectWeaponIndex(pos <= 0 ? avail.last : avail[pos - 1]);
    changeTime = SHOW_WEAPON_NAME_TIME;
  }

  fire() {
    weapons[selectedWeaponIndex].fireButton(this);
  }

  think(double duration) {
    changeTime -= duration;
    _laserTime += duration;
    if (_reloadReadyFlash > 0.0) {
      _reloadReadyFlash = max(0.0, _reloadReadyFlash - duration * 3.6);
    }

    if (!owner.inGame() || world.network().getGameState().hasWinner()) {
      if (isRouletteActive) {
        cancelMysteryRoulette();
      }
    } else if (_rouletteSpinRemaining > 0.0) {
      _rouletteSpinRemaining -= duration;
      if (_rouletteSpinRemaining <= 0.0) {
        _completeMysteryRoulette();
      } else {
        _updateRouletteStep(playTickSound: true);
      }
    } else if (_rouletteRevealRemaining > 0.0) {
      _rouletteRevealRemaining = max(0.0, _rouletteRevealRemaining - duration);
    }

    final bool sandbox = isSandboxMode;
    weapons[selectedWeaponIndex].think(duration, allowAutoReload: sandbox);
    // Also advance reload timers on starter weapons in the background so switching
    // away and back feels smooth, while depleted mystery weapons stay gone.
    for (int i = 0; i < weapons.length; i++) {
      if (i != selectedWeaponIndex && (!weapons[i].isMysteryWeapon || sandbox)) {
        weapons[i].think(duration, allowAutoReload: sandbox);
      }
    }

    final bool nowReloading = reloading();
    if (_wasReloading && !nowReloading) {
      _reloadReadyFlash = 1.0;
    }
    _wasReloading = nowReloading;
  }

  int _viewportWidth() {
    final int mcW = mobileControls?.width ?? 0;
    return mcW > 0 ? mcW : world.width().toInt();
  }

  int _viewportHeight() {
    final int mcH = mobileControls?.height ?? 0;
    return mcH > 0 ? mcH : world.height().toInt();
  }

  double _effectiveWheelRadius() {
    final double w = _viewportWidth().toDouble();
    final double h = _viewportHeight().toDouble();
    if (w <= 0 || h <= 0) {
      return WHEEL_SIZE.toDouble();
    }
    return min(WHEEL_SIZE.toDouble(), min(w, h) * 0.34)
        .clamp(92.0, WHEEL_SIZE.toDouble());
  }

  Point<int> _clampedWheelCenter(Point<int> center) {
    final int w = _viewportWidth();
    final int h = _viewportHeight();
    if (w <= 0 || h <= 0) {
      return center;
    }
    final int margin = (_effectiveWheelRadius() + ICON_SIZE_HALF + 8.0).ceil();
    final int cx = w > margin * 2
        ? center.x.clamp(margin, w - margin)
        : w ~/ 2;
    final int cy = h > margin * 2
        ? center.y.clamp(margin, h - margin)
        : h ~/ 2;
    return Point<int>(cx, cy);
  }

  weaponStateSelector(Point<int> delta) {
    final List<int> avail = availableWeaponIndices();
    if (avail.isEmpty) {
      return;
    }
    changeTime = SHOW_WEAPON_NAME_TIME;
    final double wheelR = _effectiveWheelRadius();
    final double angleStep = (pi * 2) / avail.length;

    double currentAngle = 0.0;
    int closestWeapon = avail.first;
    double closest = 9999999.0;

    for (final int weaponIdx in avail) {
      double deltaX = (sin(currentAngle) * wheelR) + delta.x;
      double deltaY = (cos(currentAngle) * wheelR) + delta.y;
      double distance = sqrt(deltaX * deltaX + deltaY * deltaY);
      if (distance < closest) {
        closestWeapon = weaponIdx;
        closest = distance;
      }
      currentAngle += angleStep;
    }
    _selectWeaponIndex(closestWeapon);
  }

  static const int GRID_TILE_SIZE = 68;
  static const int GRID_GAP = 8;
  static const int GRID_PAD = 10;

  List<int> _gridWeaponIndices() {
    return availableWeaponIndices();
  }

  _WeaponGridLayout _computeGridLayout(Point<int> buttonCenter, int count) {
    final int cols = min(3, max(1, count));
    final int rows = (count / cols).ceil();
    final int panelW =
        GRID_PAD * 2 + cols * GRID_TILE_SIZE + (cols - 1) * GRID_GAP;
    final int panelH =
        GRID_PAD * 2 + rows * GRID_TILE_SIZE + (rows - 1) * GRID_GAP;
    final int vw = _viewportWidth();
    final int vh = _viewportHeight();

    // Anchor just to the left of the weapon button, aligned near its top.
    int left = buttonCenter.x - ICON_SIZE_HALF - panelW - 8;
    int top = buttonCenter.y - ICON_SIZE_HALF;
    if (vw > panelW + 16) {
      left = left.clamp(8, vw - panelW - 8);
    } else {
      left = max(0, (vw - panelW) ~/ 2);
    }
    if (vh > panelH + 16) {
      top = top.clamp(8, vh - panelH - 8);
    } else {
      top = max(0, (vh - panelH) ~/ 2);
    }
    return _WeaponGridLayout(
      left: left.toDouble(),
      top: top.toDouble(),
      width: panelW.toDouble(),
      height: panelH.toDouble(),
      cols: cols,
      rows: rows,
    );
  }

  int? weaponIndexAtScreenPoint(Point<int> pt, Point<int> buttonCenter) {
    final List<int> gridWeapons = _gridWeaponIndices();
    if (gridWeapons.isEmpty) {
      return null;
    }
    final _WeaponGridLayout layout =
        _computeGridLayout(buttonCenter, gridWeapons.length);
    for (int i = 0; i < gridWeapons.length; i++) {
      final int col = i % layout.cols;
      final int row = i ~/ layout.cols;
      final double tx = layout.left + GRID_PAD + col * (GRID_TILE_SIZE + GRID_GAP);
      final double ty = layout.top + GRID_PAD + row * (GRID_TILE_SIZE + GRID_GAP);
      if (pt.x >= tx - 4 &&
          pt.x <= tx + GRID_TILE_SIZE + 4 &&
          pt.y >= ty - 4 &&
          pt.y <= ty + GRID_TILE_SIZE + 4) {
        return gridWeapons[i];
      }
    }
    return null;
  }

  void selectWeaponAtScreenPoint(Point<int> pt, Point<int> buttonCenter) {
    changeTime = SHOW_WEAPON_NAME_TIME;
    final int? idx = weaponIndexAtScreenPoint(pt, buttonCenter);
    if (idx != null) {
      _selectWeaponIndex(idx);
    }
  }

  _drawIconImageAt(CanvasRenderingContext2D context,
      HTMLImageElement iconImages, int index, num x, num y,
      [int tileSize = ICON_TILE_SIZE]) {
    if (index == SHARK_ICON_INDEX) {
      _drawSharkWeaponIcon(context, x.toDouble(), y.toDouble(), tileSize.toDouble());
      return;
    }
    if ((index + 1) * 128 <= iconImages.width && iconImages.height >= 128) {
      context.drawImage(iconImages,
          index * 128, 0, 128, 128,
          x, y,
          tileSize, tileSize);
    } else {
      context.save();
      context.fillStyle = "#424b54".toJS;
      context.beginPath();
      context.roundRect(x, y, tileSize, tileSize, 10.0.toJS);
      context.fill();
      context.restore();
    }
  }

  void _drawSharkWeaponIcon(
      CanvasRenderingContext2D context, double x, double y, double size) {
    final double cx = x + size * 0.5;
    final double cy = y + size * 0.5;
    final double r = size * 0.44;
    context.save();
    final CanvasGradient bg =
        context.createRadialGradient(cx, cy - r * 0.25, 2.0, cx, cy, r);
    bg.addColorStop(0.0, "#66e8ff");
    bg.addColorStop(1.0, "#0e4d78");
    context.fillStyle = bg;
    context.strokeStyle = "#ffe97a".toJS;
    context.lineWidth = max(1.5, size * 0.045);
    context.beginPath();
    context.arc(cx, cy, r, 0.0, pi * 2.0);
    context.fill();
    context.stroke();

    final imgIdx = world.imageIndex();
    final int? sharkId = imgIdx.imageByName["shark.png"];
    if (sharkId != null && sharkId >= 0 && sharkId < imgIdx.images.length) {
      final HTMLImageElement sharkImg = imgIdx.getImageById(sharkId);
      if (sharkImg.width > 0 && sharkImg.height > 0) {
        final double srcW = HunterSharkProjectile.frameWidthForImage(sharkImg);
        final double drawW = size * 0.84;
        final double drawH = drawW * (sharkImg.height / srcW);
        context.drawImage(
          sharkImg,
          0,
          0,
          srcW,
          sharkImg.height,
          cx - drawW * 0.5,
          cy - drawH * 0.5,
          drawW,
          drawH,
        );
      }
    }
    context.restore();
  }

  _drawChangeTime(CanvasRenderingContext2D context,
      HTMLImageElement iconImages, Point<int> buttonCenter) {
    final List<int> gridWeapons = _gridWeaponIndices();
    context.save();
    if (gridWeapons.isNotEmpty) {
      final _WeaponGridLayout layout =
          _computeGridLayout(buttonCenter, gridWeapons.length);

      // Compact dark-glass grid panel.
      context.fillStyle = "rgba(14, 20, 32, 0.88)".toJS;
      context.strokeStyle = "rgba(255, 233, 122, 0.65)".toJS;
      context.lineWidth = 2.0;
      context.beginPath();
      context.roundRect(
          layout.left, layout.top, layout.width, layout.height, 14.0.toJS);
      context.fill();
      context.stroke();

      for (int i = 0; i < gridWeapons.length; i++) {
        final int weaponIdx = gridWeapons[i];
        final bool isSelected = weaponIdx == selectedWeaponIndex;
        final int col = i % layout.cols;
        final int row = i ~/ layout.cols;
        final double tileX =
            layout.left + GRID_PAD + col * (GRID_TILE_SIZE + GRID_GAP);
        final double tileY =
            layout.top + GRID_PAD + row * (GRID_TILE_SIZE + GRID_GAP);

        context.fillStyle = (isSelected
                ? "rgba(72, 92, 132, 0.96)"
                : "rgba(34, 46, 68, 0.85)")
            .toJS;
        context.beginPath();
        context.roundRect(
            tileX, tileY, GRID_TILE_SIZE, GRID_TILE_SIZE, 10.0.toJS);
        context.fill();
        if (isSelected) {
          context.strokeStyle = "#ffe97a".toJS;
          context.lineWidth = 2.4;
          context.stroke();
        }

        _drawIconImageAt(
          context,
          iconImages,
          weapons[weaponIdx].iconIndex,
          tileX,
          tileY,
          GRID_TILE_SIZE,
        );
        _drawWheelClipBadge(
          context,
          weapons[weaponIdx],
          tileX,
          tileY,
          isSelected,
          tileSize: GRID_TILE_SIZE,
        );
      }

      // Draw the currently selected weapon's name cleanly below the grid.
      context.font = 'bold 16px "Trebuchet MS", Arial, sans-serif';
      final String selectedWeaponName = weapons[selectedWeaponIndex].name;
      final TextMetrics metrics = context.measureText(selectedWeaponName);
      final double textX =
          layout.left + (layout.width - metrics.width) * 0.5;
      final double textY = layout.top + layout.height + 18.0;
      context.lineJoin = "round";
      context.strokeStyle = "#161b24".toJS;
      context.lineWidth = 4.0;
      context.strokeText(selectedWeaponName, textX, textY);
      context.fillStyle = "#ffe97a".toJS;
      context.fillText(selectedWeaponName, textX, textY);
    }
    context.restore();
  }

  /// Draws a compact cartoon clip-size pill badge (`shotsLeft/shotsPerClip`
  /// plus a slim ammo/reload bar) at the bottom of each weapon wheel tile.
  void _drawWheelClipBadge(
    CanvasRenderingContext2D context,
    Weapon weapon,
    double tileX,
    double tileY,
    bool isSelected, {
    int tileSize = ICON_TILE_SIZE,
  }) {
    final int maxShots = weapon.shotsPerClip;
    if (maxShots <= 0) return;

    final bool isReloading = weapon.reloading();
    final int remaining = isReloading ? 0 : weapon.shotsLeft.clamp(0, maxShots);
    final double frac = isReloading
        ? (weapon.reloadTime > 0
            ? (1.0 - weapon.untilReload / weapon.reloadTime).clamp(0.0, 1.0)
            : 0.0)
        : (remaining / maxShots).clamp(0.0, 1.0);
    final bool isLow = !isReloading && (remaining == 1 || frac <= 0.25);

    final String label = isReloading
        ? "${max(0.0, weapon.untilReload).toStringAsFixed(1)}s"
        : "$remaining/$maxShots";

    context.save();
    context.globalAlpha = isSelected ? 1.0 : 0.86;
    context.font = 'bold 10px "Trebuchet MS", Arial, sans-serif';
    final double textW = context.measureText(label).width;
    final double pillW = max(32.0, min(tileSize - 4.0, textW + 12.0));
    const double pillH = 17.0;
    final double pillX = tileX + (tileSize - pillW) * 0.5;
    final double pillY = tileY + tileSize - pillH - 2.0;
    const double radius = 6.5;

    // Dark cartoon capsule background.
    context.fillStyle = "rgba(18, 25, 38, 0.90)".toJS;
    context.beginPath();
    context.roundRect(pillX, pillY, pillW, pillH, radius.toJS);
    context.fill();

    // Slim bottom ammo / reload progress bar clipped inside the pill.
    const double barH = 3.5;
    final double barX = pillX + 3.0;
    final double barY = pillY + pillH - barH - 2.0;
    final double barW = pillW - 6.0;
    context.fillStyle = "rgba(255, 255, 255, 0.14)".toJS;
    context.beginPath();
    context.roundRect(barX, barY, barW, barH, 2.0.toJS);
    context.fill();

    if (frac > 0.0) {
      context.fillStyle = (isReloading
              ? "#5ce8ff"
              : (isLow ? "#ff6e48" : "#ffe252"))
          .toJS;
      context.beginPath();
      context.roundRect(barX, barY, max(2.0, barW * frac), barH, 2.0.toJS);
      context.fill();
    }

    // Crisp comic border (gold highlight on the currently selected weapon).
    context.strokeStyle = (isSelected
            ? "#ffe97a"
            : (isReloading ? "#5ce8ff" : "#3a4a61"))
        .toJS;
    context.lineWidth = isSelected ? 1.8 : 1.3;
    context.beginPath();
    context.roundRect(pillX, pillY, pillW, pillH, radius.toJS);
    context.stroke();

    // Centered bold ammo text.
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.fillStyle = (isReloading
            ? "#9ef4ff"
            : (isLow
                ? "#ff9675"
                : (remaining >= maxShots ? "#fff29e" : "#ffffff")))
        .toJS;
    context.fillText(label, pillX + pillW * 0.5, pillY + 7.2);

    context.restore();
  }


  drawWeaponHelper(CanvasRenderingContext2D context, Point<int> center, bool drawCurrentWeapon) {
    if (!owner.inGame() || world.network().getGameState().hasWinner()) {
      return;
    }
    HTMLImageElement iconImages = world.imageIndex().getImageByName("weapon_icons.png");
    if (changeTime > 0 && owner.drawWeaponHelpers()) {
      _drawChangeTime(context, iconImages, center);
    }
    if (drawCurrentWeapon) {
      if (changeTime <= 0) {
        context.globalAlpha = 0.3;
      }
      _drawIconImageAt(context, iconImages,
          weapons[selectedWeaponIndex].iconIndex,  center.x  -ICON_SIZE_HALF,  center.y -ICON_SIZE_HALF);
      context.globalAlpha = 1.0;
    }
    if (isRouletteActive && owner.drawWeaponHelpers()) {
      _drawMysteryRouletteHud(context, iconImages);
    }
  }

  /// Draws a Mario Kart-style spinning weapon roulette box in upper-center
  /// screen space, followed by a celebratory winner pop & one-time clip banner!
  void _drawMysteryRouletteHud(
      CanvasRenderingContext2D context, HTMLImageElement iconImages) {
    final List<int> mystery = mysteryWeaponIndices();
    if (mystery.isEmpty || _rouletteTargetWeaponIndex < 0) {
      return;
    }
    final int vw = _viewportWidth();
    final int vh = _viewportHeight();
    final double cx = (vw > 0 ? vw : 800) * 0.5;
    final double cy = max(92.0, (vh > 0 ? vh : 600) * 0.24);
    const double boxSize = 96.0;
    const double halfBox = boxSize * 0.5;

    final bool revealing = isRouletteRevealing;
    final BingoTier bingo = revealing ? _rouletteBingoTier : BingoTier.none;
    final bool isSuper = bingo == BingoTier.superBingo;
    double scale = 1.0;
    double alpha = 1.0;
    if (revealing) {
      final double elapsed =
          _rouletteRevealTotalDuration - _rouletteRevealRemaining;
      if (elapsed < 0.42) {
        final double u = (elapsed / 0.42).clamp(0.0, 1.0);
        final double popAmp = isSuper ? 0.48 : 0.32;
        scale = 1.0 + popAmp * sin(u * pi);
      } else if (isSuper) {
        scale = 1.06 + 0.05 * sin(_laserTime * 14.0);
      }
      if (_rouletteRevealRemaining < 0.28) {
        alpha = (_rouletteRevealRemaining / 0.28).clamp(0.0, 1.0);
      }
    }

    context.save();
    context.globalAlpha = alpha;
    context.translate(cx, cy);
    context.scale(scale, scale);

    // 1. Radiant rotating comic sunburst rays (+ double shockwave ring on Superbingo!).
    if (isSuper) {
      final double elapsed =
          _rouletteRevealTotalDuration - _rouletteRevealRemaining;
      final double ringT = (elapsed / 1.1).clamp(0.0, 1.0);
      if (ringT < 1.0) {
        context.strokeStyle =
            "rgba(255, 240, 110, ${(1.0 - ringT) * 0.85 * alpha})".toJS;
        context.lineWidth = 4.5 * (1.0 - ringT) + 1.0;
        context.beginPath();
        context.arc(0, 0, 52.0 + ringT * 88.0, 0, pi * 2);
        context.stroke();

        context.strokeStyle =
            "rgba(90, 245, 255, ${(1.0 - ringT) * 0.72 * alpha})".toJS;
        context.lineWidth = 3.0 * (1.0 - ringT) + 0.8;
        context.beginPath();
        context.arc(0, 0, 38.0 + ringT * 68.0, 0, pi * 2);
        context.stroke();
      }
    }

    context.save();
    context.rotate(_laserTime * (isSuper ? 3.8 : (revealing ? 2.4 : 4.2)));
    final int rayCount = isSuper ? 16 : 12;
    for (int i = 0; i < rayCount; i++) {
      final double a0 = (i / rayCount) * pi * 2;
      final double a1 = a0 + (isSuper ? 0.16 : 0.19);
      final double rLen =
          (isSuper ? 104.0 : (revealing ? 84.0 : 68.0)) +
              (i.isEven ? 12.0 : 0.0);
      String rayFill;
      if (isSuper) {
        const List<String> rainbowRays = <String>[
          "rgba(255, 236, 96, 0.55)",
          "rgba(92, 244, 255, 0.48)",
          "rgba(255, 112, 232, 0.48)",
          "rgba(116, 255, 148, 0.48)",
        ];
        rayFill = rainbowRays[i % rainbowRays.length];
      } else if (revealing) {
        rayFill = i.isEven
            ? "rgba(255, 232, 92, 0.45)"
            : "rgba(255, 126, 226, 0.32)";
      } else {
        rayFill = i.isEven
            ? "rgba(96, 236, 255, 0.30)"
            : "rgba(218, 122, 255, 0.26)";
      }
      context.fillStyle = rayFill.toJS;
      context.beginPath();
      context.moveTo(0, 0);
      context.arc(0, 0, rLen, a0, a1);
      context.closePath();
      context.fill();
    }
    context.restore();

    // 2. Drop shadow + glossy deep arcade item-box body.
    context.fillStyle = "rgba(8, 12, 24, 0.55)".toJS;
    context.beginPath();
    context.roundRect(
        -halfBox + 3.0, -halfBox + 4.5, boxSize, boxSize, 18.0.toJS);
    context.fill();

    final CanvasGradient boxGrad =
        context.createLinearGradient(0, -halfBox, 0, halfBox);
    if (revealing) {
      boxGrad.addColorStop(0.0, "#47256e");
      boxGrad.addColorStop(0.5, "#281748");
      boxGrad.addColorStop(1.0, "#160d2b");
    } else {
      boxGrad.addColorStop(0.0, "#253966");
      boxGrad.addColorStop(1.0, "#121b33");
    }
    context.fillStyle = boxGrad;
    context.beginPath();
    context.roundRect(-halfBox, -halfBox, boxSize, boxSize, 18.0.toJS);
    context.fill();

    // 3. Clipped interior slot reel (vertical scrolling icons while spinning;
    //    locked glowing winner icon when revealed!).
    context.save();
    context.beginPath();
    context.roundRect(
        -halfBox + 6.0, -halfBox + 6.0, boxSize - 12.0, boxSize - 12.0, 13.0.toJS);
    context.clip();

    if (revealing) {
      final Weapon won = weapons[_rouletteTargetWeaponIndex];
      final CanvasGradient glow =
          context.createRadialGradient(0, 0, 4.0, 0, 0, halfBox);
      glow.addColorStop(0.0, "rgba(255, 240, 128, 0.55)");
      glow.addColorStop(1.0, "rgba(255, 240, 128, 0.0)");
      context.fillStyle = glow;
      context.fillRect(-halfBox, -halfBox, boxSize, boxSize);

      _drawIconImageAt(
        context,
        iconImages,
        won.iconIndex,
        -ICON_SIZE_HALF,
        -ICON_SIZE_HALF,
      );
    } else {
      final int n = mystery.length;
      final int targetPos = max(0, mystery.indexOf(_rouletteTargetWeaponIndex));
      final int baseStep = _rouletteVisualPhase.floor();
      final double frac = _rouletteVisualPhase - baseStep;
      const double slotStride = 74.0;

      for (int offset = -1; offset <= 1; offset++) {
        final int stepIdx = baseStep + offset;
        final int rem = ROULETTE_TOTAL_STEPS - stepIdx;
        final int wIdx = mystery[((targetPos - (rem % n)) + n) % n];
        final double yCenter = (offset - frac) * slotStride;
        context.globalAlpha =
            alpha * (1.0 - (yCenter.abs() / (slotStride * 1.15)).clamp(0.0, 0.55));
        _drawIconImageAt(
          context,
          iconImages,
          weapons[wIdx].iconIndex,
          -ICON_SIZE_HALF,
          yCenter - ICON_SIZE_HALF,
        );
      }
      context.globalAlpha = alpha;
    }
    context.restore();

    // 4. Crisp outer dark ink border + rainbow/gold Mario Kart inner rim!
    context.strokeStyle = "#0e1322".toJS;
    context.lineWidth = 4.5;
    context.beginPath();
    context.roundRect(-halfBox, -halfBox, boxSize, boxSize, 18.0.toJS);
    context.stroke();

    final CanvasGradient rimGrad =
        context.createLinearGradient(-halfBox, -halfBox, halfBox, halfBox);
    if (revealing) {
      rimGrad.addColorStop(0.0, "#fff49c");
      rimGrad.addColorStop(0.5, "#ffcf40");
      rimGrad.addColorStop(1.0, "#ff7ae6");
    } else {
      rimGrad.addColorStop(0.0, "#5ef2ff");
      rimGrad.addColorStop(0.5, "#ffe45e");
      rimGrad.addColorStop(1.0, "#ff73d0");
    }
    context.strokeStyle = rimGrad;
    context.lineWidth = 3.0;
    context.beginPath();
    context.roundRect(
        -halfBox + 2.0, -halfBox + 2.0, boxSize - 4.0, boxSize - 4.0, 16.0.toJS);
    context.stroke();

    // 5. Celebratory sparkle stars on winner reveal (extra lush for Superbingo)!
    if (revealing) {
      final double elapsed =
          _rouletteRevealTotalDuration - _rouletteRevealRemaining;
      final double burstT =
          (elapsed / _rouletteRevealTotalDuration).clamp(0.0, 1.0);
      final int starCount = isSuper ? 14 : 8;
      for (int i = 0; i < starCount; i++) {
        final double a = (i / starCount) * pi * 2 + burstT * (isSuper ? 2.0 : 1.2);
        final double dist =
            (isSuper ? 60.0 : 54.0) + burstT * (isSuper ? 40.0 : 26.0) + (i.isEven ? 6.0 : 0.0);
        final double sx = cos(a) * dist;
        final double sy = sin(a) * dist;
        final double sr =
            ((isSuper ? 7.6 : 6.0) - burstT * 3.0).clamp(2.2, 8.0);
        context.save();
        context.translate(sx, sy);
        context.rotate(burstT * 4.5);
        final String starColor = isSuper
            ? (const <String>["#ffe96b", "#7df9ff", "#ff85f2", "#7dff9b"])[i % 4]
            : (i.isEven ? "#ffe96b" : "#7df9ff");
        context.fillStyle = starColor.toJS;
        context.beginPath();
        for (int p = 0; p < 8; p++) {
          final double pa = p * pi / 4.0;
          final double pr = p.isEven ? sr : sr * 0.32;
          if (p == 0) {
            context.moveTo(cos(pa) * pr, sin(pa) * pr);
          } else {
            context.lineTo(cos(pa) * pr, sin(pa) * pr);
          }
        }
        context.closePath();
        context.fill();
        context.restore();
      }
    }

    // 6. Header & Winner Weapon Name + One-Time Magazine / Bingo Bonus Callout!
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.lineJoin = "round";

    final String topHeader = isSuper
        ? "⚡ SUPERBINGO! ⚡"
        : (revealing ? "★ WINNER! ★" : "★ MYSTERY SPIN ★");
    context.font = isSuper
        ? '900 18px "Trebuchet MS", Arial, sans-serif'
        : '900 13px "Trebuchet MS", Arial, sans-serif';
    context.strokeStyle = "#120c24".toJS;
    context.lineWidth = isSuper ? 4.6 : 3.8;
    context.strokeText(topHeader, 0, -halfBox - 15.0);
    context.fillStyle = (isSuper
            ? "#fff066"
            : (revealing ? "#ffe96b" : "#9ef4ff"))
        .toJS;
    context.fillText(topHeader, 0, -halfBox - 15.0);

    final int shownIdx = revealing
        ? _rouletteTargetWeaponIndex
        : (_rouletteDisplayWeaponIndex >= 0
            ? _rouletteDisplayWeaponIndex
            : _rouletteTargetWeaponIndex);
    final Weapon shownWeapon = weapons[shownIdx];
    final String weaponTitle =
        revealing ? "${shownWeapon.name.toUpperCase()}!" : shownWeapon.name;
    context.font = revealing
        ? '900 20px "Trebuchet MS", Arial, sans-serif'
        : 'bold 15px "Trebuchet MS", Arial, sans-serif';
    context.strokeStyle = "#120c24".toJS;
    context.lineWidth = 4.5;
    context.strokeText(weaponTitle, 0, halfBox + 17.0);
    context.fillStyle = (revealing ? "#ffe96b" : "#ffffff").toJS;
    context.fillText(weaponTitle, 0, halfBox + 17.0);

    if (revealing) {
      final int clip = shownWeapon.shotsPerClip;
      final String subText =
          "ONE-TIME MAG · $clip ${clip == 1 ? 'SHOT' : 'SHOTS'}";
      context.font = 'bold 12px "Trebuchet MS", Arial, sans-serif';
      context.strokeStyle = "#120c24".toJS;
      context.lineWidth = 3.2;
      context.strokeText(subText, 0, halfBox + 36.0);
      context.fillStyle = "#ff9ef5".toJS;
      context.fillText(subText, 0, halfBox + 36.0);

      if (isSuper) {
        const String bonusCallout = "+ FULL SHIELD & FULL HEALTH!";
        context.font = '900 14px "Trebuchet MS", Arial, sans-serif';
        context.strokeStyle = "#101824".toJS;
        context.lineWidth = 3.8;
        context.strokeText(bonusCallout, 0, halfBox + 55.0);
        context.fillStyle = "#7df9ff".toJS;
        context.fillText(bonusCallout, 0, halfBox + 55.0);
      }
    }

    context.restore();
  }

  LaserSightTrace computeLaserSightTrace() {
    final Vec2 center = owner.centerPoint();
    final double dirX = cos(gun.angle);
    final double dirY = sin(gun.angle);
    final double muzzleOffset = gun.size.x * 0.5;
    final double startX = center.x + dirX * muzzleOffset;
    final double startY = center.y + dirY * muzzleOffset;

    double maxDist = 2500.0;
    final bool worldReady = world.byteWorld.byteWorldReady();
    if (worldReady) {
      final double maxW = world.byteWorld.width.toDouble();
      final double maxH = world.byteWorld.height.toDouble();
      double boundDist = double.infinity;
      if (dirX.abs() > 1e-6) {
        final double tx = dirX > 0 ? (maxW - startX) / dirX : (0.0 - startX) / dirX;
        if (tx >= 0.0) boundDist = min(boundDist, tx);
      }
      if (dirY.abs() > 1e-6) {
        final double ty = dirY > 0 ? (maxH - startY) / dirY : (0.0 - startY) / dirY;
        if (ty >= 0.0) boundDist = min(boundDist, ty);
      }
      if (boundDist.isFinite) {
        maxDist = boundDist.clamp(0.0, 4000.0);
      }
    }

    // Find first terrain contact (the Snailgun pierces straight through terrain,
    // so we show a crisp laser beam up to terrain and a glowing dashed x-ray
    // penetration path beyond it).
    double? terrainHitDist;
    if (worldReady && maxDist > 0.0) {
      const double step = 6.0;
      for (double d = 0.0; d <= maxDist; d += step) {
        final int sx = (startX + dirX * d).round();
        final int sy = (startY + dirY * d).round();
        if (world.byteWorld.isSolid(sx, sy)) {
          // Refine within the last step for a crisp dot right on the surface.
          double refined = max(0.0, d - step);
          while (refined < d &&
              !world.byteWorld.isSolid(
                  (startX + dirX * refined).round(),
                  (startY + dirY * refined).round())) {
            refined += 1.0;
          }
          terrainHitDist = refined;
          break;
        }
      }
    }

    // Find any enemy players along the snail's straight path for target-lock dots.
    final List<Vec2> playerHits = [];
    for (int id in world.spriteIndex.spriteIds()) {
      final Sprite? s = world.spriteIndex[id];
      if (s is LocalPlayerSprite && s != owner && s.inGame()) {
        final Vec2 targetCenter = s.centerPoint();
        final double toX = targetCenter.x - startX;
        final double toY = targetCenter.y - startY;
        final double proj = toX * dirX + toY * dirY;
        if (proj > 0.0 && proj <= maxDist) {
          final double perpSq =
              (toX - dirX * proj) * (toX - dirX * proj) +
              (toY - dirY * proj) * (toY - dirY * proj);
          final double hitRadius = s.getRadius() * 0.95;
          if (perpSq <= hitRadius * hitRadius) {
            playerHits.add(Vec2(startX + dirX * proj, startY + dirY * proj));
          }
        }
      }
    }

    return LaserSightTrace(
      start: Vec2(startX, startY),
      dir: Vec2(dirX, dirY),
      totalDistance: maxDist,
      terrainHitDistance: terrainHitDist,
      playerHits: playerHits,
    );
  }

  void _drawLaserSight(CanvasRenderingContext2D context) {
    final LaserSightTrace trace = computeLaserSightTrace();
    if (trace.totalDistance <= 1.0) return;

    final bool isLocalOwner = owner.drawWeaponHelpers();
    final double reloadDim = (isLocalOwner && reloading()) ? 0.32 : 1.0;
    final double ownerAlpha = (isLocalOwner ? 1.0 : 0.68) * reloadDim;
    final double pulse = 0.88 + 0.12 * sin(_laserTime * 14.0);
    final double alpha = ownerAlpha * pulse;
    final bool lockedOnPlayer = trace.hasLivePlayerInPath;

    final String outerGlowRgb = lockedOnPlayer ? "32, 248, 112" : "255, 32, 48";
    final String coreBeamRgb = lockedOnPlayer ? "56, 255, 128" : "255, 48, 62";
    final String hotFilamentRgb =
        lockedOnPlayer ? "224, 255, 236" : "255, 232, 234";
    final String pierceGlowRgb =
        lockedOnPlayer ? "42, 240, 116" : "255, 52, 68";
    final String pierceDashRgb =
        lockedOnPlayer ? "96, 255, 156" : "255, 92, 102";

    final double startX = trace.start.x;
    final double startY = trace.start.y;
    final double dirX = trace.dir.x;
    final double dirY = trace.dir.y;
    final double solidEndDist = trace.terrainHitDistance ?? trace.totalDistance;
    final double solidEndX = startX + dirX * solidEndDist;
    final double solidEndY = startY + dirY * solidEndDist;

    context.save();
    context.lineCap = "round";

    // 1. Primary open-air laser beam (turns neon lock-on green when a live player is in path!).
    if (solidEndDist > 0.5) {
      context.strokeStyle = "rgba($outerGlowRgb, ${0.28 * alpha})".toJS;
      context.lineWidth = 6.5;
      context.beginPath();
      context.moveTo(startX, startY);
      context.lineTo(solidEndX, solidEndY);
      context.stroke();

      context.strokeStyle = "rgba($coreBeamRgb, ${0.86 * alpha})".toJS;
      context.lineWidth = 2.2;
      context.beginPath();
      context.moveTo(startX, startY);
      context.lineTo(solidEndX, solidEndY);
      context.stroke();

      context.strokeStyle = "rgba($hotFilamentRgb, ${0.94 * alpha})".toJS;
      context.lineWidth = 0.9;
      context.beginPath();
      context.moveTo(startX, startY);
      context.lineTo(solidEndX, solidEndY);
      context.stroke();
    }

    // 2. Piercing path continuation beyond first terrain hit (animated dashed beam
    // showing the snail will burrow straight through the wall!).
    if (trace.terrainHitDistance != null &&
        trace.terrainHitDistance! < trace.totalDistance - 1.0) {
      final double pierceStart = trace.terrainHitDistance!;
      const double dashLen = 11.0;
      const double gapLen = 9.0;
      const double period = dashLen + gapLen;
      final double phase = (_laserTime * 55.0) % period;

      // Soft outer piercing glow.
      context.strokeStyle = "rgba($pierceGlowRgb, ${0.24 * alpha})".toJS;
      context.lineWidth = 4.2;
      context.beginPath();
      for (double d = pierceStart + phase; d < trace.totalDistance; d += period) {
        final double segEnd = min(d + dashLen, trace.totalDistance);
        context.moveTo(startX + dirX * d, startY + dirY * d);
        context.lineTo(startX + dirX * segEnd, startY + dirY * segEnd);
      }
      context.stroke();

      // Crisp inner piercing laser dashes.
      context.strokeStyle = "rgba($pierceDashRgb, ${0.76 * alpha})".toJS;
      context.lineWidth = 1.5;
      context.beginPath();
      for (double d = pierceStart + phase; d < trace.totalDistance; d += period) {
        final double segEnd = min(d + dashLen, trace.totalDistance);
        context.moveTo(startX + dirX * d, startY + dirY * d);
        context.lineTo(startX + dirX * segEnd, startY + dirY * segEnd);
      }
      context.stroke();

      // Glowing laser contact dot right where the beam hits terrain.
      final double dotR = 3.2 + 0.8 * sin(_laserTime * 18.0);
      context.fillStyle = "rgba($coreBeamRgb, ${0.40 * alpha})".toJS;
      context.beginPath();
      context.arc(solidEndX, solidEndY, dotR * 2.1, 0, 2 * pi);
      context.fill();

      context.fillStyle = "rgba($hotFilamentRgb, ${0.95 * alpha})".toJS;
      context.beginPath();
      context.arc(solidEndX, solidEndY, dotR * 0.85, 0, 2 * pi);
      context.fill();
    }

    // 3. Target-lock laser reticle on any live enemy player along the snail's trajectory!
    for (final Vec2 hit in trace.playerHits) {
      final double lockPulse = 1.0 + 0.22 * sin(_laserTime * 20.0);
      final double ringR = 8.0 * lockPulse;
      context.strokeStyle = "rgba($coreBeamRgb, ${0.92 * alpha})".toJS;
      context.lineWidth = 2.0;
      context.beginPath();
      context.arc(hit.x, hit.y, ringR, 0, 2 * pi);
      context.stroke();

      // Crisp lock-on cardinal ticks around the green target ring.
      context.lineWidth = 1.6;
      context.beginPath();
      context.moveTo(hit.x - ringR - 3.5, hit.y);
      context.lineTo(hit.x - ringR + 1.5, hit.y);
      context.moveTo(hit.x + ringR - 1.5, hit.y);
      context.lineTo(hit.x + ringR + 3.5, hit.y);
      context.moveTo(hit.x, hit.y - ringR - 3.5);
      context.lineTo(hit.x, hit.y - ringR + 1.5);
      context.moveTo(hit.x, hit.y + ringR - 1.5);
      context.lineTo(hit.x, hit.y + ringR + 3.5);
      context.stroke();

      context.fillStyle = "rgba($hotFilamentRgb, ${0.96 * alpha})".toJS;
      context.beginPath();
      context.arc(hit.x, hit.y, 2.8, 0, 2 * pi);
      context.fill();
    }

    // 4. Tiny glowing emitter dot at the gun barrel tip.
    context.fillStyle = "rgba($coreBeamRgb, ${0.52 * alpha})".toJS;
    context.beginPath();
    context.arc(startX, startY, 3.8, 0, 2 * pi);
    context.fill();
    context.fillStyle = "rgba($hotFilamentRgb, ${0.95 * alpha})".toJS;
    context.beginPath();
    context.arc(startX, startY, 1.6, 0, 2 * pi);
    context.fill();

    context.restore();
  }

  static const double AIM_GUIDE_DISTANCE = 170.0;

  static WeaponBallisticsProfile ballisticsForWeapon(String weaponName) {
    switch (weaponName) {
      case "Zooka":
        return const WeaponBallisticsProfile(launchSpeed: 500.0, gravityAffect: 0.05);
      case "Neon Blaster":
        return const WeaponBallisticsProfile(launchSpeed: 150.0, gravityAffect: 0.0);
      case "Snailgun":
        return const WeaponBallisticsProfile(launchSpeed: 500.0, gravityAffect: 0.0);
      case "Jellybean Jet":
        return const WeaponBallisticsProfile(launchSpeed: 435.0, gravityAffect: 0.10);
      case "Dart gun":
        return const WeaponBallisticsProfile(launchSpeed: 530.0, gravityAffect: 0.30);
      case "Chicken shooter":
      case "Shotgun":
        return const WeaponBallisticsProfile(launchSpeed: 540.0, gravityAffect: 0.50);
      case "Brick builder":
        return const WeaponBallisticsProfile(launchSpeed: 500.0, gravityAffect: 1.0);
      case "Coffee Burn":
        return const WeaponBallisticsProfile(launchSpeed: 400.0, gravityAffect: 0.0);
      case "Pigeon Strike":
        return const WeaponBallisticsProfile(launchSpeed: 360.0, gravityAffect: 0.72);
      case "Turbo Mole":
        return const WeaponBallisticsProfile(launchSpeed: 320.0, gravityAffect: 0.85);
      case "Spiky Hedgehog":
        return const WeaponBallisticsProfile(launchSpeed: 240.0, gravityAffect: 1.0);
      case "Banana pancake":
      case "Angry Beehive":
        return const WeaponBallisticsProfile(launchSpeed: 200.0, gravityAffect: 1.0);
      case "Cat litter box":
        return const WeaponBallisticsProfile(launchSpeed: 100.0, gravityAffect: 1.0);
      case "Mega Shark":
        return const WeaponBallisticsProfile(launchSpeed: 120.0, gravityAffect: 0.0);
      default:
        return const WeaponBallisticsProfile(launchSpeed: 350.0, gravityAffect: 0.5);
    }
  }

  /// Computes a simple, static, fixed-distance ballistic aim guide from the gun
  /// muzzle based solely on `gun.angle` and the selected weapon's launch speed
  /// and gravity (ignoring player velocity and world terrain collisions).
  TrajectoryGuideTrace computeTrajectoryGuide() {
    final WeaponBallisticsProfile profile =
        ballisticsForWeapon(getSelectedWeapon().name);
    final Vec2 center = owner.centerPoint();
    final double dirX = cos(gun.angle);
    final double dirY = sin(gun.angle);
    final double muzzleOffset = gun.size.x * 0.5;

    final double startX = center.x + dirX * muzzleOffset;
    final double startY = center.y + dirY * muzzleOffset;
    final double vx = dirX * profile.launchSpeed;
    final double vy = dirY * profile.launchSpeed;

    double worldGravityY = 300.0;
    try {
      worldGravityY = world.gravity.y;
    } catch (_) {}
    final double gy = worldGravityY * profile.gravityAffect;

    const double dt = 0.025;
    const int maxSteps = 60;
    final List<Vec2> points = [Vec2(startX, startY)];
    double px = startX;
    double py = startY;
    double traveled = 0.0;

    for (int i = 1; i <= maxSteps; i++) {
      final double t = i * dt;
      final double nx = startX + vx * t;
      final double ny = startY + vy * t + 0.5 * gy * t * t;
      final double segDx = nx - px;
      final double segDy = ny - py;
      final double segLen = sqrt(segDx * segDx + segDy * segDy);

      if (traveled + segLen >= AIM_GUIDE_DISTANCE && segLen > 1e-6) {
        final double frac = (AIM_GUIDE_DISTANCE - traveled) / segLen;
        points.add(Vec2(px + segDx * frac, py + segDy * frac));
        break;
      }
      traveled += segLen;
      px = nx;
      py = ny;
      points.add(Vec2(px, py));
    }

    return TrajectoryGuideTrace(
      points: points,
      crosshair: points.last,
    );
  }

  void _drawTrajectoryGuide(CanvasRenderingContext2D context) {
    final TrajectoryGuideTrace guide = computeTrajectoryGuide();
    if (guide.points.length < 2) return;

    final double alpha = reloading() ? 0.32 : 0.82;
    final List<double> cumDist = [0.0];
    for (int i = 1; i < guide.points.length; i++) {
      final double dx = guide.points[i].x - guide.points[i - 1].x;
      final double dy = guide.points[i].y - guide.points[i - 1].y;
      cumDist.add(cumDist.last + sqrt(dx * dx + dy * dy));
    }
    final double totalArc = cumDist.last;
    if (totalArc < 6.0) return;

    context.save();
    context.globalAlpha = alpha;

    // Static, evenly-spaced guide dots out to the fixed crosshair distance.
    const double dotSpacing = 22.0;
    int segIdx = 0;
    for (double d = 18.0; d < totalArc - 14.0; d += dotSpacing) {
      while (segIdx < cumDist.length - 2 && cumDist[segIdx + 1] < d) {
        segIdx++;
      }
      final double segStart = cumDist[segIdx];
      final double segSpan = max(1e-6, cumDist[segIdx + 1] - segStart);
      final double t = ((d - segStart) / segSpan).clamp(0.0, 1.0);
      final double x = guide.points[segIdx].x +
          (guide.points[segIdx + 1].x - guide.points[segIdx].x) * t;
      final double y = guide.points[segIdx].y +
          (guide.points[segIdx + 1].y - guide.points[segIdx].y) * t;

      context.fillStyle = "rgba(16, 22, 34, 0.80)".toJS;
      context.beginPath();
      context.arc(x, y, 3.0, 0, 2 * pi);
      context.fill();

      context.fillStyle = "#fffdf0".toJS;
      context.beginPath();
      context.arc(x, y, 1.9, 0, 2 * pi);
      context.fill();
    }

    // Simple static crosshair reticle at the fixed endpoint.
    final Vec2 ch = guide.crosshair;
    const double ringR = 6.8;
    const double tickIn = 2.0;
    const double tickOut = 3.2;
    context.lineCap = "round";

    for (int pass = 0; pass < 2; pass++) {
      context.strokeStyle =
          (pass == 0 ? "rgba(16, 22, 34, 0.85)" : "#fffdf0").toJS;
      context.lineWidth = pass == 0 ? 3.0 : 1.5;
      context.beginPath();
      context.arc(ch.x, ch.y, ringR, 0, 2 * pi);
      context.moveTo(ch.x - ringR - tickOut, ch.y);
      context.lineTo(ch.x - ringR + tickIn, ch.y);
      context.moveTo(ch.x + ringR - tickIn, ch.y);
      context.lineTo(ch.x + ringR + tickOut, ch.y);
      context.moveTo(ch.x, ch.y - ringR - tickOut);
      context.lineTo(ch.x, ch.y - ringR + tickIn);
      context.moveTo(ch.x, ch.y + ringR - tickIn);
      context.lineTo(ch.x, ch.y + ringR + tickOut);
      context.stroke();
    }

    context.restore();
  }

  draw(CanvasRenderingContext2D context) {
    context.save();
    if (!isCarryingReadyShark()) {
      if (getSelectedWeapon().hasLaserSight) {
        _drawLaserSight(context);
      } else if (owner.drawWeaponHelpers()) {
        _drawTrajectoryGuide(context);
      }
    }
    if (owner.drawWeaponHelpers()) {
      if (!isCarryingReadyShark()) {
        _drawMagazineIndicator(context);
      }
      if (reloading()) {
        _drawReloadIndicator(context);
      }
      if (changeTime > 0) {
        _drawSelectedWeaponBelowPlayer(context);
      }
    }
    context.restore();
  }

  void _drawSelectedWeaponBelowPlayer(CanvasRenderingContext2D context) {
    final Weapon weapon = getSelectedWeapon();
    final Vec2 center = owner.centerPoint();
    final double alpha = (changeTime / 0.25).clamp(0.0, 1.0);
    const int iconSize = 22;
    const double padX = 8.0;
    const double gap = 6.0;
    const double pillH = 28.0;

    context.save();
    context.globalAlpha = alpha * 0.94;
    context.font = 'bold 12px "Trebuchet MS", Arial, sans-serif';
    final double textW = context.measureText(weapon.name).width;
    final double pillW = padX * 2 + iconSize + gap + textW;
    final double pillX = center.x - pillW * 0.5;
    final double pillY = owner.position.y + owner.size.y + 28.0;

    context.fillStyle = "rgba(14, 20, 32, 0.90)".toJS;
    context.strokeStyle = "#ffe97a".toJS;
    context.lineWidth = 1.6;
    context.beginPath();
    context.roundRect(pillX, pillY, pillW, pillH, (pillH * 0.5).toJS);
    context.fill();
    context.stroke();

    final HTMLImageElement iconImages =
        world.imageIndex().getImageByName("weapon_icons.png");
    _drawIconImageAt(
      context,
      iconImages,
      weapon.iconIndex,
      pillX + padX,
      pillY + (pillH - iconSize) * 0.5,
      iconSize,
    );

    context.textAlign = "left";
    context.textBaseline = "middle";
    context.fillStyle = "#ffe97a".toJS;
    context.fillText(
      weapon.name,
      pillX + padX + iconSize + gap,
      pillY + pillH * 0.52,
    );
    context.restore();
  }

  /// Draws a fresh cartoon reload widget cleanly above the clip size indicator:
  /// a compact glossy rounded pill with a spinning cartoon reload arrow glyph
  /// and a smooth candy-gradient progress bar with gliding shine.
  void _drawReloadIndicator(CanvasRenderingContext2D context) {
    final Weapon weapon = getSelectedWeapon();
    final double progress = weapon.reloadTime > 0.0
        ? (1.0 - (weapon.untilReload / weapon.reloadTime)).clamp(0.0, 1.0)
        : 1.0;

    final Vec2 center = owner.centerPoint();
    final double bobY = sin(_laserTime * 7.5) * 1.2;
    const double pillW = 62.0;
    const double pillH = 15.0;
    const double radius = pillH * 0.5;
    final double pillX = center.x - pillW * 0.5;
    final double pillY = owner.position.y - 31.0 + bobY;

    context.save();
    context.globalAlpha = 0.95;

    // Cartoon drop shadow.
    context.fillStyle = "rgba(10, 16, 28, 0.45)".toJS;
    context.beginPath();
    context.roundRect(pillX + 1.4, pillY + 1.8, pillW, pillH, radius.toJS);
    context.fill();

    // Glossy cartoon slate-navy capsule body.
    final CanvasGradient bodyGrad =
        context.createLinearGradient(0, pillY, 0, pillY + pillH);
    bodyGrad.addColorStop(0.0, "#243b5c");
    bodyGrad.addColorStop(1.0, "#132036");
    context.fillStyle = bodyGrad;
    context.beginPath();
    context.roundRect(pillX, pillY, pillW, pillH, radius.toJS);
    context.fill();

    // Glossy top shine strip.
    context.fillStyle = "rgba(255, 255, 255, 0.16)".toJS;
    context.beginPath();
    context.roundRect(
        pillX + 3.0, pillY + 1.2, pillW - 6.0, pillH * 0.36, (radius * 0.5).toJS);
    context.fill();

    // Bold cartoon ink border + subtle golden accent rim.
    context.strokeStyle = "#0e1726".toJS;
    context.lineWidth = 2.0;
    context.beginPath();
    context.roundRect(pillX, pillY, pillW, pillH, radius.toJS);
    context.stroke();

    // Spinning circular reload arrow icon on the left side of the pill.
    final double iconCx = pillX + 9.0;
    final double iconCy = pillY + pillH * 0.5;
    const double iconR = 4.2;
    context.save();
    context.translate(iconCx, iconCy);
    context.rotate(_laserTime * 6.5);
    context.strokeStyle = "#ffe454".toJS;
    context.fillStyle = "#ffe454".toJS;
    context.lineWidth = 1.6;
    context.lineCap = "round";
    for (int half = 0; half < 2; half++) {
      final double startA = half * pi + 0.35;
      final double endA = startA + pi * 0.65;
      context.beginPath();
      context.arc(0, 0, iconR, startA, endA);
      context.stroke();

      // Tiny arrowhead at end of arc.
      final double ax = cos(endA) * iconR;
      final double ay = sin(endA) * iconR;
      final double tangent = endA + pi * 0.5;
      context.beginPath();
      context.moveTo(ax + cos(tangent) * 2.2, ay + sin(tangent) * 2.2);
      context.lineTo(ax + cos(endA) * 1.9 - cos(tangent) * 1.2,
          ay + sin(endA) * 1.9 - sin(tangent) * 1.2);
      context.lineTo(ax - cos(endA) * 1.7 - cos(tangent) * 1.2,
          ay - sin(endA) * 1.7 - sin(tangent) * 1.2);
      context.closePath();
      context.fill();
    }
    context.restore();

    // Smooth candy-gradient reload progress track to the right of the icon.
    final double trackX = pillX + 16.5;
    final double trackW = pillW - 21.5;
    const double trackH = 7.0;
    final double trackY = pillY + (pillH - trackH) * 0.5;
    const double trackR = trackH * 0.5;

    context.fillStyle = "rgba(8, 14, 24, 0.82)".toJS;
    context.beginPath();
    context.roundRect(trackX, trackY, trackW, trackH, trackR.toJS);
    context.fill();

    if (progress > 0.0) {
      context.save();
      context.beginPath();
      context.roundRect(trackX, trackY, trackW, trackH, trackR.toJS);
      context.clip();

      final double fillW = max(trackH * 0.6, trackW * progress);
      final CanvasGradient fillGrad =
          context.createLinearGradient(trackX, 0, trackX + trackW, 0);
      fillGrad.addColorStop(0.0, "#47f0ff");
      fillGrad.addColorStop(0.55, "#6dff8f");
      fillGrad.addColorStop(1.0, "#ffe44d");
      context.fillStyle = fillGrad;
      context.fillRect(trackX, trackY, fillW, trackH);

      // Gliding cartoon shine highlight across the reload bar.
      final double sheenX =
          trackX + ((_laserTime * 75.0) % (trackW + 24.0)) - 12.0;
      final CanvasGradient sheen =
          context.createLinearGradient(sheenX - 7.0, 0, sheenX + 7.0, 0);
      sheen.addColorStop(0.0, "rgba(255, 255, 255, 0.0)");
      sheen.addColorStop(0.5, "rgba(255, 255, 255, 0.62)");
      sheen.addColorStop(1.0, "rgba(255, 255, 255, 0.0)");
      context.fillStyle = sheen;
      context.fillRect(trackX, trackY, fillW, trackH);

      // Glossy top highlight.
      context.fillStyle = "rgba(255, 255, 255, 0.34)".toJS;
      context.fillRect(trackX, trackY + 0.6, fillW, trackH * 0.36);
      context.restore();
    }

    context.strokeStyle = "rgba(255, 255, 255, 0.30)".toJS;
    context.lineWidth = 0.9;
    context.beginPath();
    context.roundRect(trackX, trackY, trackW, trackH, trackR.toJS);
    context.stroke();

    context.restore();
  }

  /// Draws a discreet cartoon magazine indicator above the local player:
  /// - Small clips (<= 6 shots): individual rounded ammo pips.
  /// - Large clips (> 6 shots): a slim rounded cartoon ammo bar.
  void _drawMagazineIndicator(CanvasRenderingContext2D context) {
    final Weapon weapon = getSelectedWeapon();
    final int maxShots = weapon.shotsPerClip;
    if (maxShots <= 0) return;

    final bool isReloading = reloading();
    final int remaining = isReloading ? 0 : weapon.shotsLeft.clamp(0, maxShots);
    final double frac = remaining / maxShots;
    final Vec2 center = owner.centerPoint();
    final double baseY = owner.position.y - 10.0;
    // Stay subtle when full, become clearly visible as the clip drains or reloads.
    final bool isFull = !isReloading && remaining >= maxShots;
    final bool isLow = !isReloading && (remaining == 1 || frac <= 0.25);
    final double alpha = _reloadReadyFlash > 0.0
        ? 0.96
        : (isFull ? 0.45 : (isReloading ? 0.72 : 0.88));
    final double popScale = 1.0 + _reloadReadyFlash * 0.16;

    context.save();
    context.globalAlpha = alpha;
    if (_reloadReadyFlash > 0.01) {
      context.translate(center.x, baseY);
      context.scale(popScale, popScale);
      context.translate(-center.x, -baseY);
    }

    if (maxShots <= 6) {
      final double pipW = maxShots == 1 ? 12.0 : 7.0;
      final double pipH = 5.0;
      final double gap = 3.0;
      final double totalW = maxShots * pipW + (maxShots - 1) * gap;
      final double startX = center.x - totalW * 0.5;
      final double y = baseY - pipH * 0.5;
      final double r = pipH * 0.5;

      for (int i = 0; i < maxShots; i++) {
        final double x = startX + i * (pipW + gap);
        final bool filled = i < remaining;
        if (filled) {
          context.fillStyle = (isLow ? "#ff7a45" : "#ffe252").toJS;
        } else {
          context.fillStyle = "rgba(18, 24, 36, 0.55)".toJS;
        }
        context.beginPath();
        context.roundRect(x, y, pipW, pipH, r.toJS);
        context.fill();

        if (filled) {
          context.fillStyle = "rgba(255, 255, 255, 0.45)".toJS;
          context.fillRect(x + 1.0, y + 0.7, pipW - 2.0, pipH * 0.35);
        }

        context.strokeStyle = "#121b28".toJS;
        context.lineWidth = 1.3;
        context.beginPath();
        context.roundRect(x, y, pipW, pipH, r.toJS);
        context.stroke();
      }
    } else {
      const double barW = 38.0;
      const double barH = 5.0;
      final double x = center.x - barW * 0.5;
      final double y = baseY - barH * 0.5;
      const double r = barH * 0.5;

      // Dark trough.
      context.fillStyle = "rgba(18, 24, 36, 0.72)".toJS;
      context.beginPath();
      context.roundRect(x, y, barW, barH, r.toJS);
      context.fill();

      // Clipped ammo fill.
      if (frac > 0.0) {
        context.save();
        context.beginPath();
        context.roundRect(x, y, barW, barH, r.toJS);
        context.clip();
        final double fillW = barW * frac;
        context.fillStyle = (isLow ? "#ff684a" : "#ffe054").toJS;
        context.fillRect(x, y, fillW, barH);
        context.fillStyle = "rgba(255, 255, 255, 0.38)".toJS;
        context.fillRect(x, y + 0.6, fillW, barH * 0.38);
        context.restore();
      }

      // Crisp thin comic border.
      context.strokeStyle = "#121b28".toJS;
      context.lineWidth = 1.4;
      context.beginPath();
      context.roundRect(x, y, barW, barH, r.toJS);
      context.stroke();
    }

    context.restore();
  }

  bool reloading() => weapons[selectedWeaponIndex].reloading();
  int reloadPercent() => weapons[selectedWeaponIndex].reloadPercent();
}

class _WeaponGridLayout {
  final double left;
  final double top;
  final double width;
  final double height;
  final int cols;
  final int rows;

  const _WeaponGridLayout({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.cols,
    required this.rows,
  });
}

class LaserSightTrace {
  final Vec2 start;
  final Vec2 dir;
  final double totalDistance;
  final double? terrainHitDistance;
  final List<Vec2> playerHits;

  const LaserSightTrace({
    required this.start,
    required this.dir,
    required this.totalDistance,
    required this.terrainHitDistance,
    required this.playerHits,
  });

  bool get hasLivePlayerInPath => playerHits.isNotEmpty;

  String get beamColorMode => hasLivePlayerInPath ? "green" : "red";

  Vec2 get end =>
      Vec2(start.x + dir.x * totalDistance, start.y + dir.y * totalDistance);
}

class WeaponBallisticsProfile {
  final double launchSpeed;
  final double gravityAffect;

  const WeaponBallisticsProfile({
    required this.launchSpeed,
    required this.gravityAffect,
  });
}

class TrajectoryGuideTrace {
  final List<Vec2> points;
  final Vec2 crosshair;

  const TrajectoryGuideTrace({
    required this.points,
    required this.crosshair,
  });
}