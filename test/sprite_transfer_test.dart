import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:dart2d/worlds/world_util.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/weapons/abstractweapon.dart';
import 'package:dart2d/weapons/weapon_state.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/net/net.dart';

void main() {
  setUpAll((){
    configureDependencies();
  });
  setUp(() {
    ConnectionWrapper.THROW_SEND_ERRORS_FOR_TEST = true;
    logOutputForTest();
    testConnections.clear();
    testPeers.clear();
    logConnectionData = false;
    Logger.root.level = Level.INFO;
  });


  group('World creation test', () {
    test('TestCreateWorld!', () async {
      WormWorld a = await createTestWorld('a');
      WormWorld b = await createTestWorld('b');
      WormWorld c = await createTestWorld('c');
    });
  });

  group('Sprite transfer tests', () {
    test('TestBasicSpriteTransfer', () async {
      throwIfLoggingUnexpected = false;
      logConnectionData = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      WormWorld worldC = await createTestWorld('c');
      worldA.startAsServer("nameA");
      worldA.frameDraw();
      expect(worldA, hasPlayerSpriteWithNetworkId(playerId(0))
          .andNetworkType(NetworkType.LOCAL));
      logConnectionData = true;
      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      logConnectionData = false;
      expect(worldA, hasExactSprites([
          hasPlayerSpriteWithNetworkId(playerId(0))
              .andNetworkType(NetworkType.LOCAL),
          hasPlayerSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.REMOTE_FORWARD)
              .andOwnerId('b')
              .andRemoteKeyState(),
          hasPlayerSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.REMOTE_FORWARD)
              .andOwnerId('c')
              .andRemoteKeyState(),
      ]));
      expect(worldB, hasExactSprites([
        hasPlayerSpriteWithNetworkId(playerId(0))
                .andNetworkType(NetworkType.REMOTE)
                .andOwnerId('a')
                .andRemoteKeyState(),
        hasPlayerSpriteWithNetworkId(playerId(1))
                .andNetworkType(NetworkType.LOCAL),
        hasPlayerSpriteWithNetworkId(playerId(2))
                .andNetworkType(NetworkType.REMOTE)
                .andOwnerId('c')
                .andRemoteKeyState(),
      ]));
      // Assert server A representation.
      expect(worldA.spriteIndex[playerId(0)],
          hasType('LocalPlayerSprite'));
      expect(worldB.spriteIndex[playerId(0)],
          hasType('LocalPlayerSprite'));
      expect(worldC.spriteIndex[playerId(0)],
          hasType('LocalPlayerSprite'));
      // Assert client B representation. 
      expect(worldA.spriteIndex[playerId(1)],
          hasType('LocalPlayerSprite'));
      expect(worldB.spriteIndex[playerId(1)],
          hasType('LocalPlayerSprite'));
      expect(worldC.spriteIndex[playerId(1)],
          hasType('LocalPlayerSprite'));
      // Assert client C representation.
      expect(worldA.spriteIndex[playerId(2)],
          hasType('LocalPlayerSprite'));
      expect(worldB.spriteIndex[playerId(2)],
          hasType('LocalPlayerSprite'));
      expect(worldC.spriteIndex[playerId(2)],
          hasType('LocalPlayerSprite'));

      testConnections['a']!.forEach((e) { e.signalClose(); });
      
      for (int i = 0; i < 20; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT / 8 );
        worldC.frameDraw(KEY_FRAME_DEFAULT / 8 );
      }
      expect(worldC.isCommander, isTrue);
      expect(worldC.spriteIndex.count(), equals(2));
      expect(worldC, hasExactSprites([
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.REMOTE_FORWARD),
          hasSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.LOCAL),
      ]));
      expect(worldB.spriteIndex.count(), equals(2));
          expect(worldB, hasExactSprites([
              hasSpriteWithNetworkId(playerId(1))
                  .andNetworkType(NetworkType.LOCAL),
              hasSpriteWithNetworkId(playerId(2))
                  .andNetworkType(NetworkType.REMOTE),
          ]));
      expect(worldB.spriteIndex[playerId(1)],
          hasType('LocalPlayerSprite'));
      expect(worldB.spriteIndex[playerId(2)],
          hasType('LocalPlayerSprite'));
      
      // Now test transferring a sprite over the network.
      MovingSprite sprite = new MovingSprite(new Vec2(), new Vec2(1.0, 2.0), SpriteType.RECT);
      MovingSprite imageSprite = new MovingSprite.imageBasedSprite(
          new Vec2(), 0, worldB.imageIndex());
      worldB.addSprite(sprite);
      worldB.addSprite(imageSprite);
      worldB.frameDraw();
      expect(worldB, hasExactSprites([
        hasPlayerSpriteWithNetworkId(playerId(1))
            .andNetworkType(NetworkType.LOCAL),
        hasPlayerSpriteWithNetworkId(playerId(2))
            .andNetworkType(NetworkType.REMOTE)
            .andRemoteKeyState(),
        hasSpriteWithNetworkId(sprite.networkId)
            .andNetworkType(NetworkType.LOCAL),
        hasSpriteWithNetworkId(imageSprite.networkId)
            .andNetworkType(NetworkType.LOCAL),
      ]));
      worldB.frameDraw();
      worldC.frameDraw();
      // Sprite gets added to worldC the next frame.
      expect(worldC, hasExactSprites([
        hasPlayerSpriteWithNetworkId(playerId(1))
             .andNetworkType(NetworkType.REMOTE_FORWARD)
             .andRemoteKeyState(),
        hasPlayerSpriteWithNetworkId(playerId(2))
             .andNetworkType(NetworkType.LOCAL),
        hasSpriteWithNetworkId(sprite.networkId)
             .andOwnerId('b')
             .andNetworkType(NetworkType.REMOTE),
        hasSpriteWithNetworkId(imageSprite.networkId)
             .andOwnerId('b')
             .andNetworkType(NetworkType.REMOTE),
      ]));
      // Now remove the sprite.
      sprite.remove = true;
      imageSprite.remove = true;
      for (int i = 0; i < 9; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldC.frameDraw(KEY_FRAME_DEFAULT);
      }

      // It's removed from all worlds.
      expect(worldB, hasExactSprites([
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.LOCAL),
          hasSpriteWithNetworkId(playerId(2))
             .andNetworkType(NetworkType.REMOTE_FORWARD),
      ]));
      expect(worldC, hasExactSprites([
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.REMOTE),
          hasSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.LOCAL),
      ]));
    });

    test('Particles_TransfersOverNetwork', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 10; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }

      LocalPlayerSprite sprite = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      Particles p = new Particles(worldA, sprite, sprite.position, sprite.velocity.multiply(0.2));
      p.sendToNetwork = true;

      worldA.addSprite(p);
      worldA.frameDraw(0.1);
      expect(p.networkId, isNotNull);
      worldB.frameDraw(0.1);

      Particles? bParticles = null;
      for (int spriteId in worldB.spriteIndex.spriteIds()) {
        print(worldB.spriteIndex[spriteId].runtimeType);
        if (worldB.spriteIndex[spriteId] is Particles) {
          bParticles = worldB.spriteIndex[spriteId] as Particles;
        }
      }
      expect(bParticles, isNotNull,
          reason: "Expect particle to transfer over network!");

      ParticleEffects bParticleData = bParticles!.toNetworkUpdate();
      ParticleEffects aParticleData = p.toNetworkUpdate();

      // Same data on both sides.
      expect(aParticleData.position.x, closeTo(bParticleData.position.x, 0.1));
      expect(aParticleData.position.y, closeTo(bParticleData.position.y, 0.1));
      expect(aParticleData.velocity, bParticleData.velocity);
      expect(aParticleData.particleCount, bParticleData.particleCount);
      expect(aParticleData.radius, bParticleData.radius);
      expect(aParticleData.followId, bParticleData.followId);
      expect(aParticleData.particleType, bParticleData.particleType);
    });

    test('Hyper_ExplodesAndTransfersOverNetwork', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 10; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      Hyper hyper = Hyper.createWithOwner(worldA, playerA, 30, playerA.gun);
      hyper.radius = Hyper.DEFAULT_BLAST_RADIUS;
      worldA.addSprite(hyper);
      worldA.frameDraw(0.05);

      // Simulate hitting the world terrain.
      hyper.collide(null, worldA.byteWorld, MovingSprite.DIR_BELOW);
      expect(hyper.remove, isTrue);

      // Step frames to insert and transfer the HyperExplosion & red FIRE particles.
      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }

      HyperExplosion? explosionA;
      for (int id in worldA.spriteIndex.spriteIds()) {
        if (worldA.spriteIndex[id] is HyperExplosion) {
          explosionA = worldA.spriteIndex[id] as HyperExplosion;
        }
      }
      HyperExplosion? explosionB;
      for (int id in worldB.spriteIndex.spriteIds()) {
        if (worldB.spriteIndex[id] is HyperExplosion) {
          explosionB = worldB.spriteIndex[id] as HyperExplosion;
        }
      }

      expect(explosionA, isNotNull, reason: "Expected HyperExplosion on commander");
      expect(explosionB, isNotNull, reason: "Expected HyperExplosion to transfer to client");
      expect(explosionB!.networkType, equals(NetworkType.REMOTE));
      expect(explosionB.color, equals(Hyper.COLOR));
      expect(explosionB.maxRadius, closeTo(explosionA!.maxRadius, 0.1));

      // Advance past explosion duration and verify cleanup on both peers.
      for (int i = 0; i < 20; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }
      expect(worldA.spriteIndex.hasSprite(explosionA.networkId!), isFalse);
      expect(worldB.spriteIndex.hasSprite(explosionB.networkId!), isFalse);
    });

    test('DefaultExplosion_TransfersOverNetwork', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 10; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      worldA.explosionAtSprite(
        sprite: playerA,
        velocity: Vec2(10.0, -20.0),
        addParticles: true,
        damage: 10,
        radius: 40.0,
        damageDoer: playerA,
      );

      worldA.frameDraw(0.05);
      worldB.frameDraw(0.05);

      ExplosionEffect? effectA;
      for (int id in worldA.spriteIndex.spriteIds()) {
        if (worldA.spriteIndex[id] is ExplosionEffect) {
          effectA = worldA.spriteIndex[id] as ExplosionEffect;
        }
      }
      ExplosionEffect? effectB;
      for (int id in worldB.spriteIndex.spriteIds()) {
        if (worldB.spriteIndex[id] is ExplosionEffect) {
          effectB = worldB.spriteIndex[id] as ExplosionEffect;
        }
      }

      expect(effectA, isNotNull, reason: "Expected ExplosionEffect on commander");
      expect(effectB, isNotNull, reason: "Expected ExplosionEffect on client via ByteWorldDestruction");
      expect(effectB!.blastRadius, closeTo(40.0, 0.1));
      expect(effectB.position.x, closeTo(effectA!.position.x, 0.1));
      expect(effectB.position.y, closeTo(effectA.position.y, 0.1));

      // Advance past explosion duration and verify cleanup on both peers.
      for (int i = 0; i < 20; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }
      expect(worldA.spriteIndex.hasSprite(effectA.networkId!), isFalse);
      expect(worldB.spriteIndex.hasSprite(effectB.networkId!), isFalse);
    });

    test('Jellybean_TransfersOverNetwork', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 10; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      JellybeanProjectile beanA =
          JellybeanProjectile.createWithOwner(worldA, playerA, 8, playerA.gun);
      // Keep the projectile clear of random player spawn collisions during transfer.
      beanA.collision = false;
      worldA.addSprite(beanA);

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }

      JellybeanProjectile? beanB;
      for (int id in worldB.spriteIndex.spriteIds()) {
        if (worldB.spriteIndex[id] is JellybeanProjectile) {
          beanB = worldB.spriteIndex[id] as JellybeanProjectile;
        }
      }

      expect(beanB, isNotNull, reason: "Expected JellybeanProjectile to transfer to client");
      expect(beanB!.networkType, equals(NetworkType.REMOTE));
      expect(beanB.flavorIndex, equals(beanA.flavorIndex));
      expect(beanB.color, equals(beanA.color));
      expect(beanB.spriteType, equals(SpriteType.CUSTOM));
      expect(beanB.rotationVelocity, closeTo(beanA.rotationVelocity, 0.01));

      // Hit and destroy the jellybean -> verify JellybeanPopEffect spawns on both peers!
      beanA.takeDamage(10, playerA, Mod.ZOOKA);
      expect(beanA.remove, isTrue);

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }

      bool hasPopA = worldA.spriteIndex
          .spriteIds()
          .any((id) => worldA.spriteIndex[id] is JellybeanPopEffect);
      bool hasPopB = worldB.spriteIndex
          .spriteIds()
          .any((id) => worldB.spriteIndex[id] is JellybeanPopEffect);
      expect(hasPopA, isTrue, reason: "Expected JellybeanPopEffect on commander when bean removed");
      expect(hasPopB, isTrue, reason: "Expected JellybeanPopEffect on client when bean removed");

      // Advance past pop duration and verify cleanup on both peers.
      for (int i = 0; i < 15; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }
      expect(
          worldA.spriteIndex.spriteIds().any((id) => worldA.spriteIndex[id] is JellybeanPopEffect),
          isFalse);
      expect(
          worldB.spriteIndex.spriteIds().any((id) => worldB.spriteIndex[id] is JellybeanPopEffect),
          isFalse);
    });

    test('Dart_TransfersAndSpawnsImpactEffectOnRemoval', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 10; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      DartProjectile dartA =
          DartProjectile.createWithOwner(worldA, playerA, 8, playerA.gun);
      dartA.collision = false;
      worldA.addSprite(dartA);

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }

      DartProjectile? dartB;
      for (int id in worldB.spriteIndex.spriteIds()) {
        if (worldB.spriteIndex[id] is DartProjectile) {
          dartB = worldB.spriteIndex[id] as DartProjectile;
        }
      }
      expect(dartB, isNotNull, reason: "Expected DartProjectile to transfer to client");

      // Simulate dart hitting terrain/target and being removed.
      dartA.explode();
      expect(dartA.remove, isTrue);

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }

      bool hasImpactA = worldA.spriteIndex
          .spriteIds()
          .any((id) => worldA.spriteIndex[id] is DartImpactEffect);
      bool hasImpactB = worldB.spriteIndex
          .spriteIds()
          .any((id) => worldB.spriteIndex[id] is DartImpactEffect);
      expect(hasImpactA, isTrue, reason: "Expected DartImpactEffect on commander");
      expect(hasImpactB, isTrue, reason: "Expected DartImpactEffect on client");

      // Advance past impact duration and verify cleanup on both peers.
      for (int i = 0; i < 15; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }
      expect(
          worldA.spriteIndex.spriteIds().any((id) => worldA.spriteIndex[id] is DartImpactEffect),
          isFalse);
      expect(
          worldB.spriteIndex.spriteIds().any((id) => worldB.spriteIndex[id] is DartImpactEffect),
          isFalse);
    });

    test('Dart_InterceptsAndDetonatesOrStopsProjectiles', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 10; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      LocalPlayerSprite playerB = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;

      // 1. Same-owner darts do NOT intercept each other.
      DartProjectile ownDart1 =
          DartProjectile.createWithOwner(worldA, playerA, 8, playerA.gun);
      DartProjectile ownDart2 =
          DartProjectile.createWithOwner(worldA, playerA, 8, playerA.gun);
      ownDart1.collide(ownDart2, null, null);
      expect(ownDart1.remove, isFalse);
      expect(ownDart2.remove, isFalse);

      // 2. Enemy darts stop each other mid-air.
      DartProjectile enemyDart =
          DartProjectile.createWithOwner(worldA, playerB, 8, playerB.gun);
      ownDart1.collide(enemyDart, null, null);
      expect(ownDart1.remove, isTrue);
      expect(enemyDart.remove, isTrue);

      // 3. Dart detonates an explosive BananaCake into BananaClusterProjectiles.
      DartProjectile dartVsCake =
          DartProjectile.createWithOwner(worldA, playerA, 8, playerA.gun);
      BananaCake cake =
          BananaCake.createWithOwner(worldA, playerB, 50, playerB.gun);
      cake.position = Vec2(40.0, 40.0);
      cake.radius = 40.0;
      worldA.addSprite(cake);
      dartVsCake.collide(cake, null, null);
      expect(dartVsCake.remove, isTrue);
      expect(cake.remove, isTrue);
      worldA.frameDraw(0.004);
      int clusterCount = worldA.spriteIndex
          .spriteIds()
          .where((id) => worldA.spriteIndex[id] is BananaClusterProjectile)
          .length;
      expect(clusterCount, greaterThan(0),
          reason: "Expected BananaCake to explode into banana clusters when hit by a dart");

      // 4. Dart stops a piercing Snailgun (removeOnCollision == false).
      DartProjectile dartVsSnail =
          DartProjectile.createWithOwner(worldA, playerA, 8, playerA.gun);
      WorldDamageProjectile snail = WorldDamageProjectile.createWithOwner(
          worldA, playerB, 12, positionBase: playerB.gun);
      snail.mod = Mod.SNAIL;
      snail.removeOnCollision = false;
      snail.radius = 19.0;
      dartVsSnail.collide(snail, null, null);
      expect(dartVsSnail.remove, isTrue);
      expect(snail.remove, isTrue,
          reason: "Expected piercing Snailgun projectile to be stopped by dart");

      // 5. Dart stops a BrickBuilder mid-air without placing a brick.
      DartProjectile dartVsBrick =
          DartProjectile.createWithOwner(worldA, playerA, 8, playerA.gun);
      BrickBuilder brick =
          BrickBuilder.createWithOwner(worldA, playerB, 2, playerB.gun);
      dartVsBrick.collide(brick, null, null);
      expect(dartVsBrick.remove, isTrue);
      expect(brick.remove, isTrue);
    });

    test('CoffeeParticles_ExpireAndCollideNormally', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.01);

      Particles coffee = Particles(
        worldA,
        null,
        Vec2(100.0, 100.0),
        Vec2(400.0, 0.0),
        radius: 10.0,
        count: 5,
        lifeTime: 65,
        shrinkPerStep: -0.3,
        particleType: ParticleEffects_ParticleType.FIRE,
      );
      coffee.collision = true;
      coffee.damage = 7;
      coffee.owner = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      worldA.addSprite(coffee);

      // Droplets stay alive through the main spray, then all expire once 66 frames pass.
      for (int i = 0; i < 40; i++) {
        coffee.frame(0.016, 0);
      }
      expect(coffee.particles.any((p) => p.lifeTimeRemaining > 0), isTrue);

      for (int i = 0; i < 30; i++) {
        coffee.frame(0.016, 0);
      }
      expect(coffee.particles.every((p) => p.lifeTimeRemaining < 0), isTrue);

      // World collision sets lifeTime to 0 and marks the sprite for removal on next frame.
      coffee.collide(null, worldA.byteWorld, MovingSprite.DIR_RIGHT);
      expect(coffee.lifeTime, equals(0));
      coffee.frame(0.016, 0);
      expect(coffee.remove, isTrue);
    });

    test('PlayerDeathEffect_TransfersOverNetworkAndRespectsBloodParam', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 10; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      LocalPlayerSprite playerB = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      // Lethal damage on commander spawns PlayerDeathEffect without blood by default.
      playerB.takeDamage(LocalPlayerSprite.MAX_HEALTH + 10, playerA, Mod.ZOOKA);

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }

      PlayerDeathEffect? deathA;
      for (int id in worldA.spriteIndex.spriteIds()) {
        if (worldA.spriteIndex[id] is PlayerDeathEffect) {
          deathA = worldA.spriteIndex[id] as PlayerDeathEffect;
        }
      }
      PlayerDeathEffect? deathB;
      for (int id in worldB.spriteIndex.spriteIds()) {
        if (worldB.spriteIndex[id] is PlayerDeathEffect) {
          deathB = worldB.spriteIndex[id] as PlayerDeathEffect;
        }
      }

      expect(deathA, isNotNull, reason: "Expected PlayerDeathEffect on commander");
      expect(deathB, isNotNull, reason: "Expected PlayerDeathEffect to transfer to client");
      expect(deathB!.networkType, equals(NetworkType.REMOTE));
      expect(deathA!.bloodEnabled, isFalse, reason: "No blood unless blood param is enabled");
      expect(deathB.bloodEnabled, isFalse);
      expect(deathB.seed, equals(deathA.seed));
      expect(deathB.playerImageId, equals(playerB.imageId));
      // Player A killed Player B -> kill chime & "+1" popup play ONLY for killer A, NOT victim B.
      expect(deathA.killerConnectionId, equals('a'));
      expect(deathB.killerConnectionId, equals('a'));
      expect(deathA.playedKillSound, isTrue, reason: "Killer should hear the kill chime");
      expect(deathB.playedKillSound, isFalse, reason: "Victim must not hear the kill chime");
      expect(
          worldA.spriteIndex.spriteIds().any((id) => worldA.spriteIndex[id] is KillScorePopup),
          isTrue,
          reason: "Killer A should see the +1 score popup");
      expect(
          worldB.spriteIndex.spriteIds().any((id) => worldB.spriteIndex[id] is KillScorePopup),
          isFalse,
          reason: "Victim B must not see the +1 score popup");

      // Advance past full death animation duration and verify cleanup on both peers.
      for (int i = 0; i < 70; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }
      expect(worldA.spriteIndex.hasSprite(deathA.networkId!), isFalse);
      expect(worldB.spriteIndex.hasSprite(deathB.networkId!), isFalse);
      expect(
          worldA.spriteIndex.spriteIds().any((id) => worldA.spriteIndex[id] is KillScorePopup),
          isFalse);

      // Now client B kills commander A -> kill chime & "+1" popup must trigger ONLY on client B!
      playerA.takeDamage(LocalPlayerSprite.MAX_HEALTH + 10, playerB, Mod.ZOOKA);
      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }
      PlayerDeathEffect? death2A;
      for (int id in worldA.spriteIndex.spriteIds()) {
        if (worldA.spriteIndex[id] is PlayerDeathEffect) {
          death2A = worldA.spriteIndex[id] as PlayerDeathEffect;
        }
      }
      PlayerDeathEffect? death2B;
      for (int id in worldB.spriteIndex.spriteIds()) {
        if (worldB.spriteIndex[id] is PlayerDeathEffect) {
          death2B = worldB.spriteIndex[id] as PlayerDeathEffect;
        }
      }
      expect(death2A, isNotNull);
      expect(death2B, isNotNull);
      expect(death2A!.playedKillSound, isFalse, reason: "Commander victim must not hear kill chime");
      expect(death2B!.playedKillSound, isTrue, reason: "Remote killer B must hear kill chime");
      expect(
          worldA.spriteIndex.spriteIds().any((id) => worldA.spriteIndex[id] is KillScorePopup),
          isFalse,
          reason: "Victim A must not see +1 popup");
      expect(
          worldB.spriteIndex.spriteIds().any((id) => worldB.spriteIndex[id] is KillScorePopup),
          isTrue,
          reason: "Remote killer B should see +1 popup");
    });

    test('BananaPancake_ExplodesIntoBananasAndTransfersOverNetwork', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 10; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      BananaCake pancakeA = BananaCake.createWithOwner(worldA, playerA, 50, playerA.gun);
      pancakeA.position = Vec2(worldA.byteWorld.width / 2.0, worldA.byteWorld.height / 2.0);
      pancakeA.velocity = Vec2.ZERO;
      pancakeA.explodeAfter = 4.0;
      pancakeA.radius = 50.0;
      pancakeA.collision = false;
      worldA.addSprite(pancakeA);

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }

      BananaCake? pancakeB;
      for (int id in worldB.spriteIndex.spriteIds()) {
        if (worldB.spriteIndex[id] is BananaCake) {
          pancakeB = worldB.spriteIndex[id] as BananaCake;
        }
      }
      expect(pancakeB, isNotNull, reason: "Expected BananaCake to transfer to client");
      expect(pancakeB!.spriteType, equals(SpriteType.CUSTOM));

      // Explode the pancake in-bounds and verify BananaClusterProjectiles spread and transfer.
      pancakeA.position = Vec2(worldA.byteWorld.width / 2.0, worldA.byteWorld.height / 2.0);
      pancakeA.velocity = Vec2.ZERO;
      pancakeA.explode();
      expect(pancakeA.remove, isTrue);

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.004);
        worldB.frameDraw(0.004);
      }

      int bananasA = worldA.spriteIndex
          .spriteIds()
          .where((id) => worldA.spriteIndex[id] is BananaClusterProjectile)
          .length;
      int bananasB = worldB.spriteIndex
          .spriteIds()
          .where((id) => worldB.spriteIndex[id] is BananaClusterProjectile)
          .length;
      expect(bananasA, greaterThan(0), reason: "Expected BananaClusterProjectile burst on commander");
      expect(bananasB, greaterThan(0), reason: "Expected BananaClusterProjectile burst to transfer to client");
    });

    test('CatLitterBox_ExplodesIntoRunningCatsAndTransfersOverNetwork', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 10; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      CatLitterBox boxA = CatLitterBox.createWithOwner(worldA, playerA, 100, playerA.gun);
      boxA.position = Vec2(worldA.byteWorld.width / 2.0, worldA.byteWorld.height / 2.0);
      boxA.velocity = Vec2.ZERO;
      boxA.collision = false;
      worldA.addSprite(boxA);

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }

      CatLitterBox? boxB;
      for (int id in worldB.spriteIndex.spriteIds()) {
        if (worldB.spriteIndex[id] is CatLitterBox) {
          boxB = worldB.spriteIndex[id] as CatLitterBox;
        }
      }
      expect(boxB, isNotNull, reason: "Expected CatLitterBox to transfer to client");
      expect(boxB!.spriteType, equals(SpriteType.CUSTOM));

      // Explode the litter box centered in-bounds and verify all cats jump out in both directions and sync!
      final Vec2 mid = Vec2(worldA.byteWorld.width / 2.0, worldA.byteWorld.height / 2.0);
      boxA.setCenter(mid);
      boxA.velocity = Vec2.ZERO;
      // Disable remote player collision in this tiny 100x100 test world so the 4 leaping cats aren't immediately eaten by playerB.
      (worldA.spriteIndex[playerId(1)] as MovingSprite).collision = false;
      boxA.explode();
      expect(boxA.remove, isTrue);

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.004);
        worldB.frameDraw(0.004);
      }

      List<RunningCatProjectile> catsA = worldA.spriteIndex
          .spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<RunningCatProjectile>()
          .toList();
      List<RunningCatProjectile> catsB = worldB.spriteIndex
          .spriteIds()
          .map((id) => worldB.spriteIndex[id])
          .whereType<RunningCatProjectile>()
          .toList();
      expect(catsA.length, equals(CatLitterBox.CAT_COUNT),
          reason: "Expected ${CatLitterBox.CAT_COUNT} running cats to jump out of the box");
      expect(catsB.length, greaterThan(0),
          reason: "Expected RunningCatProjectiles to transfer to remote client");
      expect(catsA.any((c) => c.runDirection < 0), isTrue);
      expect(catsA.any((c) => c.runDirection > 0), isTrue);
      expect(catsA.every((c) => c.velocity.y < 0), isTrue,
          reason: "Cats should initially jump upward out of the box");
      expect(catsA.every((c) => c.explodeAfter != null && c.explodeAfter! <= RunningCatProjectile.FUSE_SECONDS),
          isTrue);
    });

    test('RunningCat_ExplodesWhenHittingWall', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.02);

      // Build a vertical solid wall directly in front of the running cat.
      worldA.byteWorld.fillRectAt(Vec2(60.0, 10.0), Vec2(16.0, 80.0), "#444444");

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      RunningCatProjectile cat = RunningCatProjectile.createFromBox(
        worldA,
        playerA,
        Vec2(24.0, 40.0),
        Vec2(RunningCatProjectile.RUN_SPEED, 0.0),
        runDirection: 1.0,
        catVariant: 0,
      );
      cat.gravityAffect = 0.0;
      worldA.addSprite(cat);

      // Step up to 0.5s (well under the 2.0s timer) -> must explode on wall impact!
      for (int i = 0; i < 20 && !cat.remove; i++) {
        worldA.frameDraw(0.025);
      }
      expect(cat.remove, isTrue, reason: "Running cat should explode upon hitting a wall");
      expect(cat.explodeAfter!, greaterThan(1.0),
          reason: "Cat should have exploded from the wall well before its 2s timer");
    });

    test('RunningCat_RunsAndExplodesAfterTwoSeconds', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.02);

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      RunningCatProjectile cat = RunningCatProjectile.createFromBox(
        worldA,
        playerA,
        Vec2(10.0, 40.0),
        Vec2(RunningCatProjectile.RUN_SPEED, 0.0),
        runDirection: 1.0,
        catVariant: 2,
      );
      cat.collision = false; // Open run with no wall collision.
      worldA.addSprite(cat);

      final double startX = cat.position.x;
      // After 1.5s the cat has been running and hasn't blown up yet.
      for (int i = 0; i < 30; i++) {
        worldA.frameDraw(0.05);
      }
      expect(cat.remove, isFalse, reason: "Running cat should still be alive at 1.5s");
      expect(cat.position.x, greaterThan(startX + 100.0),
          reason: "Running cat should sprint forward across the world");

      // After passing 2.0s total -> cat blows up automatically!
      for (int i = 0; i < 15; i++) {
        worldA.frameDraw(0.05);
      }
      expect(cat.remove, isTrue, reason: "Running cat must explode after 2 seconds");
    });

    test('RacerSnail_StaysUprightWhenShootingLeftAndTransfersOverNetwork', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 8; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      // Fire a racer snail to the LEFT (angle = pi -> must flip upright, not upside down!).
      playerA.gun.angle = 3.14159265;
      SnailProjectile leftSnail = SnailProjectile.createWithOwner(
          worldA, playerA, 12, playerA.gun, variant: 1);
      leftSnail.position = Vec2(50.0, 50.0);
      leftSnail.removeOutOfBounds = false;
      expect(leftSnail.isFacingLeft, isTrue);

      // Fire a racer snail to the RIGHT (angle = 0 -> upright without flip).
      playerA.gun.angle = 0.0;
      SnailProjectile rightSnail = SnailProjectile.createWithOwner(
          worldA, playerA, 12, playerA.gun, variant: 2);
      rightSnail.position = Vec2(40.0, 50.0);
      rightSnail.removeOutOfBounds = false;
      expect(rightSnail.isFacingLeft, isFalse);

      // Verify all 3 racer liveries render cleanly in both left & right orientations.
      FakeCanvas canvas = FakeCanvas();
      for (int v = 0; v < 3; v++) {
        leftSnail.snailVariant = v;
        leftSnail.draw(canvas.context2D, false);
        rightSnail.snailVariant = v;
        rightSnail.draw(canvas.context2D, false);
      }
      leftSnail.snailVariant = 1;

      worldA.addSprite(leftSnail);
      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.02);
        worldB.frameDraw(0.02);
      }

      SnailProjectile? remoteSnail;
      for (int id in worldB.spriteIndex.spriteIds()) {
        if (worldB.spriteIndex[id] is SnailProjectile) {
          remoteSnail = worldB.spriteIndex[id] as SnailProjectile;
        }
      }
      expect(remoteSnail, isNotNull,
          reason: "Expected SnailProjectile to transfer to client");
      expect(remoteSnail!.snailVariant, equals(1));
      expect(remoteSnail.isFacingLeft, isTrue);
    });

    test('KittenKill_SyncsModMessageAndDrawsKittenEasterEggOnDeathScreen', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 8; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      LocalPlayerSprite playerBOnA = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      LocalPlayerSprite playerBOnB = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;

      // Verify RunningCatProjectile uses its dedicated Mod.KITTEN.
      RunningCatProjectile cat = RunningCatProjectile.createFromBox(
        worldA,
        playerA,
        Vec2(40.0, 40.0),
        Vec2(100.0, 0.0),
        runDirection: 1.0,
        catVariant: 0,
      );
      expect(cat.mod, equals(Mod.KITTEN));
      expect(killedMessage("nameB", "playerA", Mod.KITTEN).toLowerCase(),
          contains("kitten"));
      expect(selfKillMessage("nameB", Mod.KITTEN).toLowerCase(),
          contains("kitten"));

      // Kill player B with Mod.KITTEN on commander and sync to client B.
      playerBOnA.takeDamage(LocalPlayerSprite.MAX_HEALTH + 10, playerA, Mod.KITTEN);
      expect(playerBOnA.killedByMod, equals(Mod.KITTEN));
      expect(playerBOnA.killedByMessage, isNotNull);
      expect(playerBOnA.killedByMessage!.toLowerCase(), contains("kitten"));

      for (int i = 0; i < 4; i++) {
        worldA.frameDraw(0.05);
        worldB.frameDraw(0.05);
      }

      expect(playerBOnB.killedByMod, equals(Mod.KITTEN),
          reason: "Remote killed player should receive Mod.KITTEN from commander");
      expect(playerBOnB.killedByMessage, equals(playerBOnA.killedByMessage),
          reason: "Remote killed player should display the exact same Mod kill message");

      // Advance into the visible killed-screen fade window and render drawKilledView
      // with the kitten easter egg & killer avatar!
      playerBOnB.spawnIn = LocalPlayerSprite.RESPAWN_TIME - 2.2;
      FakeCanvas canvas = FakeCanvas();
      drawKilledView(
        canvas.context2D,
        worldB,
        canvas.width,
        canvas.height,
        playerBOnB,
        worldB.spriteIndex,
        worldB.imageIndex(),
      );
    });
    test('TestKillDormantSprites', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      WormWorld worldC = await createTestWorld('c');
      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;
      worldC.network().disableCommandTransferHeuristicForTest = true;
      worldA.startAsServer("nameA");
      worldA.frameDraw();
      expect(worldA, hasPlayerSpriteWithNetworkId(playerId(0))
          .andNetworkType(NetworkType.LOCAL));
      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }

      LocalPlayerSprite playerSprite = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      expect(playerSprite, isNotNull);
      _TestDamageProjectile sprite = new _TestDamageProjectile(worldA, playerSprite, 100);
      sprite.explodeAfter = 1000.0;
      sprite.position.y = 0.0;
      sprite.networkId = 999;
      worldA.addSprite(sprite);
      worldA.frameDraw();

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }
      expect(worldB, hasSpriteWithNetworkId(sprite.networkId)
          .andNetworkType(NetworkType.REMOTE)
          .andOwnerId('a'));
      expect(worldA, hasSpriteWithNetworkId(sprite.networkId)
          .andNetworkType(NetworkType.LOCAL));
      expect(worldC, hasSpriteWithNetworkId(sprite.networkId)
          .andNetworkType(NetworkType.REMOTE)
          .andOwnerId('a'));

      sprite.verifyAgainst(worldA.spriteIndex[sprite.networkId]);
      sprite.verifyAgainst(worldB.spriteIndex[sprite.networkId]);
      sprite.verifyAgainst(worldC.spriteIndex[sprite.networkId]);

      // A is dying.
      testConnections['a']!.forEach((e) { e.signalClose(); });

      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldB.frameDraw(KEY_FRAME_DEFAULT + 0.01);
        worldC.frameDraw(KEY_FRAME_DEFAULT + 0.01);
      }

      // WorldB took ownership of this sprite, but deleted it since
      // a was the owner of it.
      expect(worldB.network().isCommander(), isTrue);
      expect(worldB.spriteIndex.hasSprite(sprite.networkId!), isFalse);
      expect(worldC.spriteIndex.hasSprite(sprite.networkId!), isFalse);
      // Still remains in a.
      expect(worldA.spriteIndex.hasSprite(sprite.networkId!), isTrue);
    });

    test('TestGameStateTransferKillPlayer', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      worldA.startAsServer("nameA");

      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();

      for (int i = 0; i < 3; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldA.frameDraw(KEY_FRAME_DEFAULT);
      }

      // Both worlds are in the same gamestate.
      expect(worldB.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('a'));
      expect(worldA.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('a'));

      // The player B sprite is hooked up to the gameState.
      LocalPlayerSprite playerBSprite = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(playerBSprite.info.name, equals("nameB"));
      playerBSprite = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(playerBSprite.info.name, equals("nameB"));

      LocalPlayerSprite playerASprite = worldB.spriteIndex[playerId(0)] as LocalPlayerSprite;
      expect(playerASprite.info.name, equals("nameA"));
      playerASprite = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      expect(playerASprite.info.name, equals("nameA"));

      // Keep commander FPS healthy during respawn test.
      worldA.drawFps().setFpsForTest(45.0);
      worldB.drawFps().setFpsForTest(45.0);

      // Now kill one player.
      playerBSprite = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(playerBSprite.collision, equals(true));
      expect(playerBSprite.inGame(), equals(true));
      // Store away the position of the sprite in worldB.
      Vec2 positionBeforeDeath = new Vec2.copy(playerBSprite.position);
      playerBSprite.takeDamage(playerBSprite.health, playerBSprite, Mod.UNKNOWN);
      expect(playerBSprite.position, equals(positionBeforeDeath));
      expect(playerBSprite.collision, equals(false));
      expect(playerBSprite.inGame(), equals(false));
      expect(playerBSprite.maybeRespawn(0.01), equals(true));

      playerBSprite = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      // Tick down half of respawn time.
      int guard = 0;
      while (playerBSprite.spawnIn > LocalPlayerSprite.RESPAWN_TIME / 2 + 0.01 && guard++ < 40) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }
      // Now look how worldB views this sprite.
      expect(playerBSprite.inGame(), equals(false));
      // Position got updated to random before spawning.
      expect(playerBSprite.position == positionBeforeDeath, isFalse);

      // Pass some time.
      for (int i = 0; i < 20; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldA.frameDraw(KEY_FRAME_DEFAULT);
      }

      // World A
      playerBSprite = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(playerBSprite.collision, equals(true));
      expect(playerBSprite.inGame(), equals(true));
      expect(playerBSprite.ownerId, equals('b'));
      expect(playerBSprite.maybeRespawn(0.01), equals(true));

      // World B
      playerBSprite = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(playerBSprite.inGame(), equals(true));
      expect(playerBSprite.ownerId, equals('b'));
      expect(playerBSprite.maybeRespawn(0.01), equals(false));

      expect(worldB.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('a'));
      expect(worldA.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('a'));

      // Now force a switch of commander, but kill player first!
      playerBSprite = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(playerBSprite.collision, equals(true));
      playerBSprite.takeDamage(playerBSprite.health, playerBSprite, Mod.UNKNOWN);

      worldA.network().disableCommandTransferHeuristicForTest = false;
      worldB.network().disableCommandTransferHeuristicForTest = false;
      worldA.drawFps().setFpsForTest(3.1);
      // Should be enough frames to switch commander and respawn the player.
      for (int i = 0; i < 25; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldA.frameDraw(KEY_FRAME_DEFAULT);
      }
      worldA.drawFps().setFpsForTest(45.0);

      expect(worldB.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('b'));
      expect(worldA.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('b'));

      // Player should be back in game now in both worlds.
      // World A
      playerBSprite = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(playerBSprite.collision, equals(false));
      expect(playerBSprite.inGame(), equals(true));
      expect(playerBSprite.ownerId, equals('b'));
      expect(playerBSprite.maybeRespawn(0.01), equals(false));

      // World B
      playerBSprite = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(playerBSprite.collision, equals(true));
      expect(playerBSprite.inGame(), equals(true));
      expect(playerBSprite.ownerId, equals('b'));
      expect(playerBSprite.maybeRespawn(0.01), equals(true));

      // Player A should also be in game in both worlds.
      // World A
      playerASprite = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      expect(playerASprite.collision, equals(true));
      expect(playerASprite.inGame(), equals(true));
      expect(playerASprite.ownerId, 'a');
      expect(playerASprite.networkType, equals(NetworkType.LOCAL));
      expect(playerASprite.maybeRespawn(0.01), equals(false));

      // World B
      playerASprite = worldB.spriteIndex[playerId(0)] as LocalPlayerSprite;
      expect(playerASprite.collision, equals(true));
      expect(playerASprite.inGame(), equals(true));
      expect(playerASprite.ownerId, 'a');
      expect(playerASprite.networkType, equals(NetworkType.REMOTE_FORWARD));
      expect(playerASprite.maybeRespawn(0.01), equals(true));

      // Now switch back.
      worldA.drawFps().setFpsForTest(46.1);
      worldB.drawFps().setFpsForTest(2.0);
      for (int i = 0; i < 25; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldA.frameDraw(KEY_FRAME_DEFAULT);
      }

      expect(worldB.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('a'));
      expect(worldA.network().gameState,
          isGameStateOf({playerId(0): "nameA", playerId(1): "nameB"}).withCommanderId('a'));

      playerASprite = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      expect(playerASprite.ownerId, 'a');
      playerBSprite = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(playerBSprite.ownerId, 'b');

      playerASprite = worldB.spriteIndex[playerId(0)] as LocalPlayerSprite;
      expect(playerASprite.ownerId, 'a');
      playerBSprite = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(playerBSprite.ownerId, 'b');
    });

    test('TestPlayerDeath', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      worldA.startAsServer("nameA");
      worldA.frameDraw();
      worldB.connectTo("a", "nameB");

      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);

      expect(worldA, hasExactSprites([
             hasSpriteWithNetworkId(playerId(0))
                 .andNetworkType(NetworkType.LOCAL),
             hasSpriteWithNetworkId(playerId(1))
                 .andNetworkType(NetworkType.REMOTE_FORWARD),
          ]));
      expect(worldB, hasExactSprites([
               hasSpriteWithNetworkId(playerId(0))
                   .andNetworkType(NetworkType.REMOTE),
               hasSpriteWithNetworkId(playerId(1))
                   .andNetworkType(NetworkType.LOCAL),
            ]));

      LocalPlayerSprite playerBSprite = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      playerBSprite.takeDamage(playerBSprite.health - 1, playerBSprite, Mod.UNKNOWN);

      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);

      // Check state in worldB.
      LocalPlayerSprite playerBSpriteInB = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      expect(playerBSpriteInB.health, equals(playerBSprite.health));

      playerBSprite.takeDamage(1, playerBSprite, Mod.UNKNOWN);

      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(KEY_FRAME_DEFAULT);

      expect(playerBSprite.inGame(), equals(false));
      expect(playerBSpriteInB.inGame(), equals(false));

      expect(
          recentReceviedDataFrom("a").stateUpdate.any((u) => u.hasGameState()),
          isTrue);
    });

    test('TestParticleTransfer', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      worldA.startAsServer("nameA");

      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();

      // Give it some frames.
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      Particles p = new Particles(
        worldA,
        null,
        Vec2.ONE,
        new Vec2(50, 50),
        radius: 10.0,
        count: 20,
        lifeTime: 100000,
        shrinkPerStep: 0.8,
        particleType: ParticleEffects_ParticleType.SODA,
      );
      p.sendToNetwork = true;
      worldA.addSprite(p);

      worldA.frameDraw();
      worldB.frameDraw();

      expect(worldA.spriteIndex.count(), equals(3));
      expect(worldB.spriteIndex.count(), equals(3));
    });

    test('TestPlayerFireBasicGun', () async {
      throwIfLoggingUnexpected = false;
      WorldDamageProjectile.random = new Random(1);
      WeaponState.random = new Random(1);
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;
      worldA.startAsServer("nameA");

      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();

      // Give it some frames.
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      for (int id in [playerId(0), playerId(1)]) {
        LocalPlayerSprite spriteInB = worldB.spriteIndex[id] as LocalPlayerSprite;
        LocalPlayerSprite spriteInA = worldA.spriteIndex[id] as LocalPlayerSprite;
        expect(spriteInB.inGame(), isTrue);
        expect(spriteInA.inGame(), isTrue);
      }

      expect(worldA.spriteIndex.count(), 2);
      expect(worldB.spriteIndex.count(), 2);
      LocalPlayerSprite bSelfSprite = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      LocalPlayerSprite aBSprite = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      LocalPlayerSprite aSelfSprite = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      // Hover in open sky (center of 100x100 arena) so pellets fly unobstructed.
      bSelfSprite.gravityAffect = 0.0;
      aBSprite.gravityAffect = 0.0;
      aSelfSprite.gravityAffect = 0.0;
      aSelfSprite.collision = false;
      bSelfSprite.position = Vec2(40.0, 50.0);
      bSelfSprite.velocity = Vec2.ZERO;
      aSelfSprite.position = Vec2(5.0, 5.0);
      aSelfSprite.velocity = Vec2.ZERO;

      // Aim slightly up!
      int aimUp = bSelfSprite.getControls()['Aim up']!;
      worldB.localKeyState.onKeyDown(aimUp);
      worldB.frameDraw(0.1);
      worldA.frameDraw(0.1);
      worldB.localKeyState.onKeyUp(aimUp);
      worldB.frameDraw(0.02);
      worldA.frameDraw(0.02);
      // Advance right up to the next keyframe boundary before firing.
      worldA.frameDraw(KEY_FRAME_DEFAULT - 0.02);
      worldB.frameDraw(KEY_FRAME_DEFAULT - 0.02);

      int fireKey = bSelfSprite.getControls()['Fire']!;
      worldB.localKeyState.onKeyDown(fireKey);
      // KeyState update is sent to worldA right away, since A decides when to fire.
      expect(
          recentSentDataTo("a").stateUpdate.any(
              (u) => u.hasKeyState() && u.keyState.keysDown.contains(fireKey)),
          isTrue);

      worldA.frameDraw(0.01);
      worldA.frameDraw(0.02);
      worldB.frameDraw(0.02);

      int projectilesA = worldA.spriteIndex
          .spriteIds()
          .where((id) => worldA.spriteIndex[id] is WorldDamageProjectile)
          .length;
      int projectilesB = worldB.spriteIndex
          .spriteIds()
          .where((id) => worldB.spriteIndex[id] is WorldDamageProjectile)
          .length;
      expect(projectilesA, greaterThan(0),
          reason: "Expected commander A to fire projectiles for client B");
      expect(projectilesB, equals(projectilesA),
          reason: "Expected all fired projectiles to transfer to client B");
    });

    test('TestPlayerFireGunExplosionsAndKill', () async {
      throwIfLoggingUnexpected = false;
      // Use a seeded random here. This is important to make the test deterministic.
      WorldDamageProjectile.random = new Random(1);
      WeaponState.random = new Random(1);
      WormWorld worldA = await createTestWorld("a");
      WormWorld worldB = await createTestWorld("b");
      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;
      worldA.startAsServer("nameA");

      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();

      // Give it some frames.
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      // Keep both players standing on solid ground so they don't fall off the 100x100 arena.
      worldA.byteWorld.fillRectAt(Vec2(0.0, 90.0), Vec2(100.0, 10.0), "#444444");
      worldB.byteWorld.fillRectAt(Vec2(0.0, 90.0), Vec2(100.0, 10.0), "#444444");

      LocalPlayerSprite bSelfSprite = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      bSelfSprite.position.x = 5.0;
      bSelfSprite.position.y = 90.0 - bSelfSprite.size.y;
      bSelfSprite.velocity = Vec2.ZERO;
      LocalPlayerSprite aSelfSprite = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      LocalPlayerSprite aBSprite = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      // Place A on the far right so BananaCake doesn't immediately detonate on spawn.
      aSelfSprite.position = Vec2(58.0, 90.0 - aSelfSprite.size.y);
      aSelfSprite.velocity = Vec2.ZERO;
      aSelfSprite.collision = false;

      // Give it some frames to propagate positions.
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      // Unlock Banana pancake (a mystery powerup weapon) so B can cycle to it via Next weapon.
      int nextWeaponKey = bSelfSprite.getControls()["Next weapon"]!;
      Weapon bananaWeapons = findBananaWeapons(bSelfSprite);
      bananaWeapons.unlocked = true;
      findBananaWeapons(aBSprite).unlocked = true;
      int guard = 0;
      while (bSelfSprite.weaponState!.selectedWeaponName != bananaWeapons.name && guard++ < 30) {
        worldB.localKeyState.onKeyDown(nextWeaponKey);
        expect(
            recentSentDataTo("a").stateUpdate.any(
                (u) => u.hasKeyState() && u.keyState.keysDown.contains(nextWeaponKey)),
            isTrue);
        worldB.localKeyState.onKeyUp(nextWeaponKey);
      }

      // Propagate selected weapon to A.
      worldB.frameDraw(KEY_FRAME_DEFAULT);
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      expect(bSelfSprite.weaponState!.selectedWeaponName, equals(bananaWeapons.name));
      expect(aBSprite.weaponState!.selectedWeaponName, equals(bananaWeapons.name));

      // Aim up!
      int aimUp = bSelfSprite.getControls()['Aim up']!;
      worldB.localKeyState.onKeyDown(aimUp);
      worldB.frameDraw(0.05);
      worldA.frameDraw(0.05);

      // Now fire our weapon!
      int fireKey = bSelfSprite.getControls()['Fire']!;
      worldB.localKeyState.onKeyDown(fireKey);

      expect(worldA.spriteIndex.count(), equals(2));
      expect(worldB.spriteIndex.count(), equals(2));
      // The banana weapon produces one BananaCake shot.
      worldA.frameDraw(0.01);
      worldA.frameDraw(0.01);
      expect(worldA.spriteIndex.count(), equals(3));
      // Find the projectile.
      WorldDamageProjectile projectile = worldA.spriteIndex
          .spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<WorldDamageProjectile>()
          .first;
      expect(projectile, isNotNull);

      // Keep projectile centered inside the 100x100 test world while syncing to B.
      projectile.position = Vec2(worldA.byteWorld.width / 2.0, worldA.byteWorld.height / 2.0);
      projectile.velocity = Vec2.ZERO;
      projectile.collision = false;
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(0.05);
      expect(worldB.spriteIndex.hasSprite(projectile.networkId!), isTrue);

      // Detonate it and verify cluster burst spawns.
      projectile.position = Vec2(worldA.byteWorld.width / 2.0, worldA.byteWorld.height / 2.0);
      projectile.velocity = Vec2.ZERO;
      worldA.frameDraw(projectile.explodeAfter! + 0.1);
      expect(projectile.remove, isTrue);
      worldA.frameDraw(0.01);
      worldB.frameDraw(0.01);

      expect(worldA.spriteIndex.count(), greaterThan(3));
    });

    test('Rope_RendersBraidedRopeAndGrapplingHookAndTransfersOverNetwork', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 8; i++) {
        worldB.frameDraw(0.1);
        worldA.frameDraw(0.1);
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      playerA.position = Vec2(20.0, 50.0);
      Rope ropeA = Rope.createWithOwner(worldA, playerA, -0.4, 300.0);
      ropeA.position = Vec2(80.0, 25.0);
      ropeA.removeOutOfBounds = false;
      expect(ropeA.spriteType, equals(SpriteType.CUSTOM));

      // Render both flying and locked grappling hook states to a canvas.
      FakeCanvas canvas = FakeCanvas();
      ropeA.draw(canvas.context2D, false);
      ropeA.collide(null, worldA.byteWorld, MovingSprite.DIR_ABOVE);
      expect(ropeA.locked, isTrue);
      ropeA.draw(canvas.context2D, false);

      // Verify transfer to client preserves owner and locked-on-terrain state.
      worldA.addSprite(ropeA);
      for (int i = 0; i < 4; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 2);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 2);
      }
      Rope? ropeB;
      for (int id in worldB.spriteIndex.spriteIds()) {
        if (worldB.spriteIndex[id] is Rope) {
          ropeB = worldB.spriteIndex[id] as Rope;
        }
      }
      expect(ropeB, isNotNull, reason: "Expected Rope to transfer to client");
      expect(ropeB!.owner?.networkId, equals(playerId(0)));
      expect(ropeB.locked, isTrue, reason: "Expected terrain-locked state to sync over FLAG_NO_GRAVITY");
      ropeB.draw(canvas.context2D, false);
    });

    test('Powerup_DrawsVisiblyOnClientTracksInManagerAndPicksUpAllTypes', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;
      worldA.startAsServer("playerA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");

      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      // Move both players out of the way so spawned powerups don't immediately get picked up.
      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      LocalPlayerSprite playerBOnA = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      LocalPlayerSprite playerBOnB = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      for (final p in [playerA, playerBOnA, playerBOnB]) {
        p.collision = false;
        p.flags |= Sprite.FLAG_NO_GRAVITY;
        p.position = Vec2(2.0, 2.0);
        p.velocity = Vec2.ZERO;
      }

      // Spawn all 4 powerup types on commander A and track them via PowerupManager.
      final List<Powerup> spawnedOnA = [];
      double xPos = 15.0;
      for (final PowerUpType type in PowerUpType.values) {
        Powerup p = Powerup(Vec2(xPos, 45.0), type, worldA.imageIndex())
          ..velocity = Vec2.ZERO
          ..flags = Sprite.FLAG_NO_GRAVITY;
        worldA.addSprite(p);
        worldA.powerupManager()!.trackPowerup(p);
        spawnedOnA.add(p);
        xPos += 18.0;
      }

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 2);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 2);
      }

      expect(worldA.powerupManager()!.activePowerups, hasLength(4));
      expect(worldB.powerupManager()!.activePowerups, hasLength(4),
          reason: "Client PowerupManager must track all active powerups in the world");

      // Paint an opaque 37x37 swatch image so we can verify real pixel alpha on client canvas
      // for image-based powerups as well as the procedural mystery cloud powerup.
      HTMLCanvasElement swatchCanvas = HTMLCanvasElement()
        ..width = 37
        ..height = 37;
      swatchCanvas.context2D.fillStyle = "rgba(255, 80, 40, 1.0)".toJS;
      swatchCanvas.context2D.fillRect(0, 0, 37, 37);
      HTMLImageElement opaqueSwatch = HTMLImageElement();
      opaqueSwatch.src = swatchCanvas.toDataUrl("image/png");
      await opaqueSwatch.onLoad.first;

      for (final Powerup commanderPowerup in spawnedOnA) {
        Sprite? remote = worldB.spriteIndex[commanderPowerup.networkId!];
        expect(remote, isA<Powerup>(),
            reason: "Expected ${commanderPowerup.type} powerup on client B");
        Powerup clientPowerup = remote as Powerup;
        expect(clientPowerup.networkType, equals(NetworkType.REMOTE));
        expect(clientPowerup.ownerId, equals('a'));
        expect(clientPowerup.type, equals(commanderPowerup.type));
        expect(clientPowerup.spriteType, equals(SpriteType.IMAGE));
        expect(clientPowerup.size.x, closeTo(Powerup.SIZE_OFFSET.x, 0.01));
        expect(clientPowerup.size.y, closeTo(Powerup.SIZE_OFFSET.y, 0.01));
        expect(clientPowerup.lifeTime, greaterThan(Powerup.ALPHA_LOWER));
        expect(clientPowerup.fadeAlpha, equals(1.0),
            reason: "Fresh powerup on client must draw at full 1.0 alpha, not 0.0");

        // Temporarily swap opaqueSwatch into imageIndex for image-drawn powerups and
        // verify actual visible pixels are rendered onto a blank client canvas!
        final int imgId = clientPowerup.imageId;
        final HTMLImageElement prevImg = worldB.imageIndex().images[imgId];
        worldB.imageIndex().images[imgId] = opaqueSwatch;
        HTMLCanvasElement verifyCanvas = HTMLCanvasElement()
          ..width = 160
          ..height = 160;
        clientPowerup.draw(verifyCanvas.context2D, false);
        worldB.imageIndex().images[imgId] = prevImg;

        final Uint8ClampedList rgba =
            verifyCanvas.context2D.getImageData(0, 0, 160, 160).data.toDart;
        int visiblePixels = 0;
        for (int idx = 3; idx < rgba.length; idx += 4) {
          if (rgba[idx] > 100) {
            visiblePixels++;
          }
        }
        expect(visiblePixels, greaterThan(100),
            reason: "Client must visibly render ${clientPowerup.type} pixels onto canvas");
      }

      // Verify fade-out alpha syncs cleanly when commander powerup nears expiry.
      final Powerup firstOnA = spawnedOnA.first;
      firstOnA.lifeTime = (Powerup.ALPHA_LOWER ~/ 2);
      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(0.01);
      final Powerup firstOnB = worldB.spriteIndex[firstOnA.networkId!] as Powerup;
      expect(firstOnB.fadeAlpha, greaterThan(0.35));
      expect(firstOnB.fadeAlpha, lessThan(0.65));

      // Verify client pickup of JETPACK on commander syncs jetPackSec to client B
      // and removes the powerup from both SpriteIndex and PowerupManager on both peers!
      final Powerup jetpackOnA =
          spawnedOnA.firstWhere((p) => p.type == PowerUpType.JETPACK);
      playerBOnA.collision = true;
      jetpackOnA.collide(playerBOnA, null, null);
      expect(jetpackOnA.remove, isTrue);

      for (int i = 0; i < 4; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT / 2);
        worldB.frameDraw(KEY_FRAME_DEFAULT / 2);
      }

      expect(playerBOnB.jetPackSec, greaterThan(50.0),
          reason: "Client B must receive jetpack seconds when picking up JETPACK powerup");
      expect(worldA.spriteIndex.hasSprite(jetpackOnA.networkId!), isFalse);
      expect(worldB.spriteIndex.hasSprite(jetpackOnA.networkId!), isFalse);
      expect(worldA.powerupManager()!.activePowerups, hasLength(3));
      expect(worldB.powerupManager()!.activePowerups, hasLength(3));
    });

    test('Powerup_TransfersAsIsAcrossGracefulAndAbruptMultiHopCommandTransfers', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      WormWorld worldC = await createTestWorld('c');
      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;
      worldC.network().disableCommandTransferHeuristicForTest = true;

      worldA.startAsServer("nameA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");
      worldC.connectTo("a", "nameC");

      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldC.frameDraw(KEY_FRAME_DEFAULT);
      }

      // Park all players out of collision range so powerups remain untouched during transfers.
      for (final WormWorld w in [worldA, worldB, worldC]) {
        for (final int pid in [playerId(0), playerId(1), playerId(2)]) {
          final LocalPlayerSprite? ps = w.spriteIndex[pid] as LocalPlayerSprite?;
          if (ps != null) {
            ps.collision = false;
            ps.flags |= Sprite.FLAG_NO_GRAVITY;
            ps.position = Vec2(2.0, 2.0);
            ps.velocity = Vec2.ZERO;
          }
        }
      }

      // Build a solid floor at y = 85 so resting powerups sit stably under real physics.
      for (final WormWorld w in [worldA, worldB, worldC]) {
        w.byteWorld.fillRectAt(Vec2(0.0, 85.0), Vec2(100.0, 15.0), "#444444");
      }

      // Commander A spawns 2 distinct powerups via PowerupManager / addSprite with custom remaining lifetimes.
      Powerup shieldA = Powerup(Vec2(20.0, 85.0 - Powerup.SIZE_OFFSET.y), PowerUpType.SHIELD, worldA.imageIndex())
        ..velocity = Vec2.ZERO
        ..lifeTime = 340;
      Powerup mysteryA = Powerup(Vec2(60.0, 85.0 - Powerup.SIZE_OFFSET.y), PowerUpType.POWERUP, worldA.imageIndex())
        ..velocity = Vec2.ZERO
        ..lifeTime = 290;
      worldA.addSprite(shieldA);
      worldA.addSprite(mysteryA);
      worldA.powerupManager()!.trackPowerup(shieldA);
      worldA.powerupManager()!.trackPowerup(mysteryA);

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
        worldC.frameDraw(KEY_FRAME_DEFAULT);
      }

      final int shieldId = shieldA.networkId!;
      final int mysteryId = mysteryA.networkId!;
      for (final WormWorld clientWorld in [worldB, worldC]) {
        expect(clientWorld.powerupManager()!.activePowerups, hasLength(2));
        expect((clientWorld.spriteIndex[shieldId] as Powerup).type, equals(PowerUpType.SHIELD));
        expect((clientWorld.spriteIndex[mysteryId] as Powerup).type, equals(PowerUpType.POWERUP));
      }

      final int shieldLifeBeforeTransfer = shieldA.lifeTime;
      final Vec2 shieldPosBeforeTransfer = Vec2.copy(shieldA.position);

      // 1. Graceful command transfer from A -> B (while A stays in the game as a client!).
      worldB.drawFps().setFpsForTest(60.0);
      worldC.drawFps().setFpsForTest(40.0);
      expect(worldA.network().transferCommander("test graceful handoff"), isTrue);

      // Step small frames to complete the handoff without large physics displacement,
      // verifying position & remaining lifetime are preserved as-is at transfer time!
      worldB.frameDraw(0.01);
      worldA.frameDraw(0.01);
      worldC.frameDraw(0.01);
      worldB.frameDraw(KEY_FRAME_DEFAULT);
      worldA.frameDraw(0.01);
      worldC.frameDraw(0.01);

      expect(worldB.isCommander, isTrue, reason: "B should now be commander");
      expect(worldA.isCommander, isFalse, reason: "A should now be a client");
      expect(worldC.isCommander, isFalse);

      // Verify both powerups transferred AS IS:
      // - LOCAL (ownerId == null) on new commander B
      // - Demoted to REMOTE (ownerId == 'b') on former commander A
      // - Updated to REMOTE (ownerId == 'b') on client C
      // - Tracked in PowerupManager on all 3 worlds with no duplicate spawns!
      for (final int id in [shieldId, mysteryId]) {
        final Powerup onB = worldB.spriteIndex[id] as Powerup;
        final Powerup onA = worldA.spriteIndex[id] as Powerup;
        final Powerup onC = worldC.spriteIndex[id] as Powerup;

        expect(onB.networkType, equals(NetworkType.LOCAL));
        expect(onB.ownerId, isNull);
        expect(onA.networkType, equals(NetworkType.REMOTE),
            reason: "Former commander A must demote transferred powerups to REMOTE");
        expect(onA.ownerId, equals('b'));
        expect(onC.networkType, equals(NetworkType.REMOTE));
        expect(onC.ownerId, equals('b'),
            reason: "Client C must update powerup ownerId to new commander B");
        expect(onB.fadeAlpha, equals(1.0));
        expect(onA.fadeAlpha, equals(1.0));
        expect(onC.fadeAlpha, equals(1.0));
        expect(onA.position.x, closeTo(onB.position.x, 1.0));
        expect(onA.position.y, closeTo(onB.position.y, 2.0));
        expect(onC.position.x, closeTo(onB.position.x, 1.0));
        expect(onC.position.y, closeTo(onB.position.y, 2.0));
      }
      final Powerup shieldOnB = worldB.spriteIndex[shieldId] as Powerup;
      expect(shieldOnB.type, equals(PowerUpType.SHIELD));
      expect(shieldOnB.position.x, closeTo(shieldPosBeforeTransfer.x, 0.5));
      expect(shieldOnB.lifeTime, lessThanOrEqualTo(shieldLifeBeforeTransfer));
      expect(shieldOnB.lifeTime, greaterThan(shieldLifeBeforeTransfer - 25));

      expect(worldB.powerupManager()!.activePowerups, hasLength(2));
      expect(worldA.powerupManager()!.activePowerups, hasLength(2));
      expect(worldC.powerupManager()!.activePowerups, hasLength(2));

      // 2. Abrupt multi-hop disconnect: Commander B drops -> A or C takes command
      // and must inherit the exact same powerups (even though A originally created them!).
      // Also disconnect A first so C becomes commander (testing full A -> B -> C multi-hop!).
      testConnections['a']!.forEach((e) => e.signalClose());
      for (int i = 0; i < 6; i++) {
        worldB.frameDraw(KEY_FRAME_DEFAULT / 2);
        worldC.frameDraw(KEY_FRAME_DEFAULT / 2);
      }
      expect(worldB.isCommander, isTrue);

      testConnections['b']!.forEach((e) => e.signalClose());
      for (int i = 0; i < 8; i++) {
        worldC.frameDraw(KEY_FRAME_DEFAULT / 2);
      }

      expect(worldC.isCommander, isTrue,
          reason: "C should become commander after A and B leave");
      expect(worldC.powerupManager()!.activePowerups, hasLength(2),
          reason: "New commander C must retain both powerups after A -> B -> C handoff");

      final Powerup shieldOnC = worldC.spriteIndex[shieldId] as Powerup;
      final Powerup mysteryOnC = worldC.spriteIndex[mysteryId] as Powerup;
      expect(shieldOnC.networkType, equals(NetworkType.LOCAL));
      expect(shieldOnC.ownerId, isNull);
      expect(shieldOnC.type, equals(PowerUpType.SHIELD));
      expect(mysteryOnC.networkType, equals(NetworkType.LOCAL));
      expect(mysteryOnC.ownerId, isNull);
      expect(mysteryOnC.type, equals(PowerUpType.POWERUP));

      // Verify C can now pick up the transferred shield powerup as authoritative commander!
      final LocalPlayerSprite playerC = worldC.spriteIndex[playerId(2)] as LocalPlayerSprite;
      playerC.collision = true;
      shieldOnC.collide(playerC, null, null);
      expect(playerC.shieldPoints, equals(LocalPlayerSprite.MAX_SHIELD));
      expect(shieldOnC.remove, isTrue);
      worldC.frameDraw(0.05);
      expect(worldC.powerupManager()!.activePowerups, equals([mysteryOnC]));
    });

    test('SpikyHedgehog_ArmsTriggersOnProximityBurstsQuillsAndTransfersOverNetwork', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;
      worldA.startAsServer("nameA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();

      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      for (final WormWorld w in [worldA, worldB]) {
        w.byteWorld.setWorldImage(w.imageIndex().imageFactory.createWithSize(400, 300));
        while (!w.byteWorld.bedrockComputed()) {
          w.byteWorld.bedrockStep();
        }
        w.byteWorld.fillRectAt(Vec2(0.0, 240.0), Vec2(400.0, 60.0), "#444444");
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      LocalPlayerSprite playerBOnA = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      LocalPlayerSprite playerBOnB = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      playerA.position = Vec2(40.0, 190.0);
      playerA.velocity = Vec2.ZERO;
      playerBOnA.position = Vec2(320.0, 190.0);
      playerBOnA.velocity = Vec2.ZERO;
      playerBOnB.position = Vec2(320.0, 190.0);
      playerBOnB.velocity = Vec2.ZERO;

      // Verify WeaponState includes Spiky Hedgehog and fires HedgehogMine.
      final int idx = playerA.weaponState!.weapons
          .indexWhere((w) => w.name == "Spiky Hedgehog");
      expect(idx, greaterThanOrEqualTo(0));
      playerA.weaponState!.selectedWeaponIndex = idx;
      playerA.gun.angle = -0.25;
      playerA.weaponState!.fire();

      worldA.frameDraw(0.02);
      HedgehogMine mineA = worldA.spriteIndex
          .spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<HedgehogMine>()
          .single;
      mineA.setCenter(Vec2(180.0, 228.0));
      mineA.velocity = Vec2.ZERO;
      expect(mineA.armed, isFalse);

      // Step past ARM_TIME (1.0s) with enemy far away -> armed, not triggered.
      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(0.20);
        worldB.frameDraw(0.20);
      }
      expect(mineA.armed, isTrue);
      expect(mineA.triggered, isFalse);

      HedgehogMine? mineB = worldB.spriteIndex[mineA.networkId!] as HedgehogMine?;
      expect(mineB, isNotNull, reason: "Expected HedgehogMine to sync to client B");
      expect(mineB!.armed, isTrue);
      FakeCanvas canvas = FakeCanvas();
      mineB.draw(canvas.context2D, false);

      // Walk enemy player B into the larger outer proximity radius (~84px away > old 62px,
      // < new 92px PROXIMITY_RADIUS!) -> mine triggers its ~0.55s activation animation!
      playerBOnA.setCenter(Vec2(264.0, 220.0));
      playerBOnB.setCenter(Vec2(264.0, 220.0));
      for (int i = 0; i < 4; i++) {
        worldA.frameDraw(0.08);
        worldB.frameDraw(0.08);
      }
      expect(mineA.triggered, isTrue);
      expect(mineA.remove, isFalse,
          reason: "HedgehogMine must play its ~0.55s activation heads-up before exploding");
      expect(mineA.activationProgress, greaterThan(0.25));
      expect(mineB.triggered, isTrue);
      mineB.draw(canvas.context2D, false);

      // Finish remaining ~0.55s trigger countdown -> explodes and fires radial quills!
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(0.10);
        worldB.frameDraw(0.10);
      }
      expect(mineA.remove, isTrue);
      final List<HedgehogQuillProjectile> quillsA = worldA.spriteIndex
          .spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<HedgehogQuillProjectile>()
          .toList();
      final List<HedgehogQuillProjectile> quillsB = worldB.spriteIndex
          .spriteIds()
          .map((id) => worldB.spriteIndex[id])
          .whereType<HedgehogQuillProjectile>()
          .toList();
      expect(quillsA, isNotEmpty, reason: "Expected radial quill burst on detonation");
      expect(quillsB, isNotEmpty, reason: "Expected quills to sync to client B");
      quillsB.first.draw(canvas.context2D, false);

      // Also verify HedgehogMine lifetime was doubled to 36s and DartProjectile snipes enemy mines!
      HedgehogMine enemyMine =
          HedgehogMine.createWithOwner(worldA, playerBOnA, 38, playerBOnA.gun)
            ..setCenter(Vec2(120.0, 120.0))
            ..velocity = Vec2.ZERO;
      expect(enemyMine.explodeAfter, equals(36.0));
      worldA.addSprite(enemyMine);
      DartProjectile dart =
          DartProjectile.createWithOwner(worldA, playerA, 8, playerA.gun);
      dart.collide(enemyMine, null, null);
      expect(enemyMine.remove, isTrue);
      expect(dart.remove, isTrue);
    });

    test('TurboMole_DrillsThroughSolidWallCarvesTunnelAndDetonatesOnEmergence', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;
      worldA.startAsServer("nameA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();

      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      for (final WormWorld w in [worldA, worldB]) {
        w.byteWorld.setWorldImage(w.imageIndex().imageFactory.createWithSize(500, 300));
        while (!w.byteWorld.bedrockComputed()) {
          w.byteWorld.bedrockStep();
        }
        // Build a 45px-thick solid bunker wall from x = 160..205!
        w.byteWorld.fillRectAt(Vec2(160.0, 40.0), Vec2(45.0, 220.0), "rgb(130, 100, 70)");
      }
      expect(worldA.byteWorld.isSolid(182, 150), isTrue);
      expect(worldB.byteWorld.isSolid(182, 150), isTrue);

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      LocalPlayerSprite playerBOnA = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      LocalPlayerSprite playerBOnB = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      playerA.collision = false;
      playerA.flags |= Sprite.FLAG_NO_GRAVITY;
      playerA.setCenter(Vec2(80.0, 150.0));
      // Park enemy B right behind the bunker wall at x = 232!
      playerBOnA.flags |= Sprite.FLAG_NO_GRAVITY;
      playerBOnB.flags |= Sprite.FLAG_NO_GRAVITY;
      playerBOnA.setCenter(Vec2(232.0, 150.0));
      playerBOnB.setCenter(Vec2(232.0, 150.0));
      final int initialHealthB = playerBOnA.health;

      final int idx = playerA.weaponState!.weapons
          .indexWhere((w) => w.name == "Turbo Mole");
      expect(idx, greaterThanOrEqualTo(0));
      playerA.weaponState!.selectedWeaponIndex = idx;
      playerA.gun.angle = 0.0;
      playerA.weaponState!.fire();

      worldA.frameDraw(0.02);
      MoleDrillProjectile moleA = worldA.spriteIndex
          .spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<MoleDrillProjectile>()
          .single;
      moleA.gravityAffect = 0.0;
      moleA.setCenter(Vec2(135.0, 150.0));
      moleA.velocity = Vec2(MoleDrillProjectile.LAUNCH_SPEED, 0.0);

      FakeCanvas canvas = FakeCanvas();
      bool sawDrillingOnClient = false;
      for (int i = 0; i < 25 && !moleA.remove; i++) {
        worldA.frameDraw(0.04);
        worldB.frameDraw(0.04);
        final MoleDrillProjectile? moleB =
            worldB.spriteIndex[moleA.networkId!] as MoleDrillProjectile?;
        if (moleB != null) {
          moleB.draw(canvas.context2D, false);
          if (moleB.drilling) {
            sawDrillingOnClient = true;
          }
        }
      }

      expect(sawDrillingOnClient, isTrue,
          reason: "Client B must receive MoleDrillProjectile in active drilling state");
      expect(moleA.remove, isTrue,
          reason: "Mole should detonate after bursting through the bunker wall");
      expect(worldA.byteWorld.isSolid(182, 150), isFalse,
          reason: "Mole must carve a hollow tunnel through the solid wall on commander");
      // Verify carved tunnel is wide enough (~51.5px diameter, TUNNEL_RADIUS = 25.75) for a player sprite to enter!
      expect(worldA.byteWorld.isSolid(175, 150 - 22), isFalse,
          reason: "Upper tunnel clearance must accommodate a walking player");
      expect(worldA.byteWorld.isSolid(175, 150 + 22), isFalse,
          reason: "Lower tunnel clearance must accommodate a walking player");
      expect(worldB.byteWorld.isSolid(182, 150), isFalse,
          reason: "Carved mole tunnel must sync to client ByteWorld");
      expect(playerBOnA.health, lessThan(initialHealthB),
          reason: "Camper hiding behind bunker wall should take bunker-buster damage");

      // Regression 1: Deep mountain (> 250px thick) where Mole drills for the full
      // MAX_DRILL_TIME (25+ carve ticks) — must NOT die to its own carve ticks and
      // MUST detonate a full 60px-radius chamber at the end!
      for (final WormWorld w in [worldA, worldB]) {
        w.byteWorld.fillRectAt(Vec2(240.0, 30.0), Vec2(250.0, 240.0), "rgb(110, 85, 60)");
      }
      MoleDrillProjectile deepMole =
          MoleDrillProjectile.createWithOwner(worldA, playerA, 45, playerA.gun);
      expect(deepMole.gravityAffect, equals(MoleDrillProjectile.AIR_GRAVITY));
      deepMole.gravityAffect = 0.0;
      deepMole.setCenter(Vec2(225.0, 150.0));
      deepMole.velocity = Vec2(MoleDrillProjectile.LAUNCH_SPEED, 0.0);
      worldA.addSprite(deepMole);

      for (int i = 0; i < 45 && !deepMole.remove; i++) {
        worldA.frameDraw(0.04);
        worldB.frameDraw(0.04);
      }
      expect(deepMole.remove, isTrue,
          reason: "Deep-burrowing mole should finish MAX_DRILL_TIME and detonate");
      expect(deepMole.health, equals(25),
          reason: "Mole must not lose health to its own tunnel-carving steps");
      final int endX = deepMole.centerPoint().x.round();
      // Tunnel radius is 24.5px, whereas final explosion radius is 60px — verify
      // terrain 42px vertically above the final center was cleared by the blast!
      expect(worldA.byteWorld.isSolid(endX, 150 - 42), isFalse,
          reason: "Mole must detonate a full 60px blast chamber at end of deep tunnel");
      expect(worldB.byteWorld.isSolid(endX, 150 - 42), isFalse,
          reason: "Deep tunnel final blast chamber must sync to client B");

      // Regression 2: Drilling downward into the bottom map edge must detonate
      // at the boundary instead of silently removing out-of-bounds!
      for (final WormWorld w in [worldA, worldB]) {
        w.byteWorld.fillRectAt(Vec2(60.0, 250.0), Vec2(120.0, 50.0), "rgb(90, 80, 70)");
      }
      MoleDrillProjectile floorMole =
          MoleDrillProjectile.createWithOwner(worldA, playerA, 45, playerA.gun);
      floorMole.setCenter(Vec2(120.0, 235.0));
      floorMole.drillAngle = pi / 2.0;
      floorMole.angle = pi / 2.0;
      floorMole.velocity = Vec2(0.0, MoleDrillProjectile.LAUNCH_SPEED);
      worldA.addSprite(floorMole);

      for (int i = 0; i < 20 && !floorMole.remove; i++) {
        worldA.frameDraw(0.04);
        worldB.frameDraw(0.04);
      }
      expect(floorMole.remove, isTrue);
      // 42px horizontally from x = 120 is outside TUNNEL_RADIUS (24.5px) and only cleared
      // if explode() (BLAST_RADIUS = 60px) ran on hitting the bottom boundary!
      expect(worldA.byteWorld.isSolid(120 + 42, 285), isFalse,
          reason: "Mole hitting bottom map boundary must explode rather than vanish");
    });

    test('AngryBeehive_ShattersIntoHomingBeesSteersTowardEnemyAndCanBeSwattedByDarts', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;
      worldA.startAsServer("nameA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();

      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      for (final WormWorld w in [worldA, worldB]) {
        w.byteWorld.setWorldImage(w.imageIndex().imageFactory.createWithSize(500, 300));
        while (!w.byteWorld.bedrockComputed()) {
          w.byteWorld.bedrockStep();
        }
        w.byteWorld.fillRectAt(Vec2(0.0, 240.0), Vec2(500.0, 60.0), "#556644");
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      LocalPlayerSprite playerBOnA = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      LocalPlayerSprite playerBOnB = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      for (final p in [playerA, playerBOnA, playerBOnB]) {
        p.flags |= Sprite.FLAG_NO_GRAVITY;
        p.velocity = Vec2.ZERO;
      }
      playerA.collision = false;
      playerA.setCenter(Vec2(60.0, 150.0));
      playerBOnA.setCenter(Vec2(360.0, 150.0));
      playerBOnB.setCenter(Vec2(360.0, 150.0));

      final int idx = playerA.weaponState!.weapons
          .indexWhere((w) => w.name == "Angry Beehive");
      expect(idx, greaterThanOrEqualTo(0));
      playerA.weaponState!.selectedWeaponIndex = idx;
      playerA.gun.angle = 0.0;
      playerA.weaponState!.fire();

      for (int i = 0; i < 2; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      AngryBeehive hiveA = worldA.spriteIndex
          .spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<AngryBeehive>()
          .single;
      expect(hiveA.showCounter, isTrue);
      expect(hiveA.explodeAfter, isNotNull);
      // Drop onto solid ground at y = 240 — verify it bounces like CatLitterBox instead of exploding on impact!
      hiveA.setCenter(Vec2(180.0, 224.0));
      hiveA.velocity = Vec2(40.0, 140.0);
      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.06);
        worldB.frameDraw(0.06);
      }
      expect(hiveA.remove, isFalse,
          reason: "AngryBeehive should bounce on terrain while its timer counts down");

      AngryBeehive? hiveB = worldB.spriteIndex[hiveA.networkId!] as AngryBeehive?;
      expect(hiveB, isNotNull, reason: "Expected AngryBeehive to transfer to client B");
      expect(hiveB!.explodeAfter, isNotNull);
      FakeCanvas canvas = FakeCanvas();
      hiveB.draw(canvas.context2D, false);

      // Let the countdown timer expire -> shatters into 5 HomingBeeProjectiles!
      hiveA.setCenter(Vec2(180.0, 180.0));
      hiveA.explodeAfter = 0.05;
      worldA.frameDraw(0.10);
      worldB.frameDraw(0.10);
      expect(hiveA.remove, isTrue);

      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.12);
        worldB.frameDraw(0.12);
      }

      List<HomingBeeProjectile> beesA = worldA.spriteIndex
          .spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<HomingBeeProjectile>()
          .toList();
      List<HomingBeeProjectile> beesB = worldB.spriteIndex
          .spriteIds()
          .map((id) => worldB.spriteIndex[id])
          .whereType<HomingBeeProjectile>()
          .toList();
      expect(beesA.length, equals(AngryBeehive.BEE_COUNT));
      expect(beesB.length, equals(AngryBeehive.BEE_COUNT));
      beesB.first.draw(canvas.context2D, false);

      final double avgXBefore =
          beesA.map((b) => b.centerPoint().x).reduce((a, b) => a + b) / beesA.length;
      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(0.06);
        worldB.frameDraw(0.06);
      }
      final double avgXAfter =
          beesA.map((b) => b.centerPoint().x).reduce((a, b) => a + b) / beesA.length;
      expect(avgXAfter, greaterThan(avgXBefore + 30.0),
          reason: "Homing bees should steer toward enemy player B on the right");

      // Verify Dart gun cleanly swats a HomingBeeProjectile out of the air!
      final HomingBeeProjectile targetBee = beesA.first;
      DartProjectile swatDart =
          DartProjectile.createWithOwner(worldA, playerBOnA, 8, playerBOnA.gun);
      swatDart.collide(targetBee, null, null);
      expect(targetBee.remove, isTrue);
      expect(swatDart.remove, isTrue);
    });

    test('PigeonStrike_FlareSummonsBomberPigeonsThatDropExplosiveBombsAndSyncOverNetwork', () async {
      throwIfLoggingUnexpected = false;
      WormWorld worldA = await createTestWorld('a');
      WormWorld worldB = await createTestWorld('b');
      worldA.network().disableCommandTransferHeuristicForTest = true;
      worldB.network().disableCommandTransferHeuristicForTest = true;
      worldA.startAsServer("nameA");
      worldA.frameDraw(0.1);
      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();

      for (int i = 0; i < 6; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      for (final WormWorld w in [worldA, worldB]) {
        w.byteWorld.setWorldImage(w.imageIndex().imageFactory.createWithSize(500, 320));
        while (!w.byteWorld.bedrockComputed()) {
          w.byteWorld.bedrockStep();
        }
        w.byteWorld.fillRectAt(Vec2(0.0, 260.0), Vec2(500.0, 60.0), "#444444");
      }

      LocalPlayerSprite playerA = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      LocalPlayerSprite playerBOnA = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      LocalPlayerSprite playerBOnB = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      playerA.collision = false;
      playerA.flags |= Sprite.FLAG_NO_GRAVITY;
      playerA.setCenter(Vec2(50.0, 210.0));
      playerBOnA.flags |= Sprite.FLAG_NO_GRAVITY;
      playerBOnB.flags |= Sprite.FLAG_NO_GRAVITY;
      playerBOnA.velocity = Vec2.ZERO;
      playerBOnB.velocity = Vec2.ZERO;
      playerBOnA.setCenter(Vec2(232.0, 238.0));
      playerBOnB.setCenter(Vec2(232.0, 238.0));

      final int idx = playerA.weaponState!.weapons
          .indexWhere((w) => w.name == "Pigeon Strike");
      expect(idx, greaterThanOrEqualTo(0));
      playerA.weaponState!.selectedWeaponIndex = idx;
      playerA.gun.angle = -0.3;
      playerA.weaponState!.fire();

      worldA.frameDraw(0.02);
      PigeonStrikeFlare flareA = worldA.spriteIndex
          .spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<PigeonStrikeFlare>()
          .single;
      // Land flare on terrain at x = 190 (44.6px > 37.6px clear of playerB at 232, inside carpet spread)!
      flareA.setCenter(Vec2(190.0, 253.0));
      flareA.velocity = Vec2(0.0, 20.0);

      FakeCanvas canvas = FakeCanvas();
      for (int i = 0; i < 3; i++) {
        worldA.frameDraw(0.14);
        worldB.frameDraw(0.14);
      }
      expect(flareA.landed, isTrue);
      expect(flareA.strikeConfirmed, isFalse,
          reason: "Flare must wait the full 2.30s landed fuse before confirming strike");
      PigeonStrikeFlare? flareB =
          worldB.spriteIndex[flareA.networkId!] as PigeonStrikeFlare?;
      expect(flareB, isNotNull);
      expect(flareB!.landed, isTrue);
      expect(flareB.strikeConfirmed, isFalse);
      flareB.draw(canvas.context2D, false);

      // Verify destroying an unconfirmed flare beforehand cancels its airstrike and spawns a fizzle effect!
      PigeonStrikeFlare doomedFlare =
          PigeonStrikeFlare.createWithOwner(worldA, playerA, playerA.gun)
            ..setCenter(Vec2(95.0, 253.0))
            ..landed = true;
      worldA.addSprite(doomedFlare);
      worldA.frameDraw(0.02);
      doomedFlare.takeDamage(15, playerBOnA, Mod.SHOTGUN);
      expect(doomedFlare.remove, isTrue);
      expect(doomedFlare.strikeConfirmed, isFalse);

      // Finish longer landed fuse (2.30s total) -> flare transitions to strikeConfirmed = true
      // (staying alive on the ground with its INCOMING! beacon animation!) and summons 5 BomberPigeons!
      for (int i = 0; i < 16; i++) {
        worldA.frameDraw(0.14);
        worldB.frameDraw(0.14);
      }
      expect(flareA.strikeConfirmed, isTrue);
      expect(flareA.remove, isFalse,
          reason: "Confirmed flare stays active to animate INCOMING! airstrike beacon");
      // Flush network keyframe so client B receives strikeConfirmed = true AND newly spawned pigeons!
      for (int i = 0; i < 2; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }
      expect(flareB.strikeConfirmed, isTrue);
      flareB.draw(canvas.context2D, false);

      List<BomberPigeonProjectile> pigeonsA = worldA.spriteIndex
          .spriteIds()
          .map((id) => worldA.spriteIndex[id])
          .whereType<BomberPigeonProjectile>()
          .toList();
      List<BomberPigeonProjectile> pigeonsB = worldB.spriteIndex
          .spriteIds()
          .map((id) => worldB.spriteIndex[id])
          .whereType<BomberPigeonProjectile>()
          .toList();
      expect(pigeonsA.length, equals(PigeonStrikeFlare.PIGEON_COUNT));
      expect(pigeonsB.length, equals(PigeonStrikeFlare.PIGEON_COUNT));
      // Verify pigeons spawn far away from their drop column (> 200px upwind)!
      for (final BomberPigeonProjectile p in pigeonsA) {
        expect((p.centerPoint().x - p.dropX).abs(), greaterThan(200.0));
      }
      pigeonsB.first.draw(canvas.context2D, false);

      // Step flight so pigeons fly in from afar, cross dropX across the wider carpet spread, and drop all 5 bird droppings!
      bool sawDroppingOnClient = false;
      final int initialHealthB = playerBOnA.health;
      for (int i = 0; i < 65; i++) {
        worldA.frameDraw(0.06);
        worldB.frameDraw(0.06);
        for (int id in worldB.spriteIndex.spriteIds()) {
          final Sprite? s = worldB.spriteIndex[id];
          if (s is PigeonDroppingBomb) {
            sawDroppingOnClient = true;
            s.draw(canvas.context2D, false);
          }
          if (s is PigeonSplatEffect || s is FlareDestroyedFizzleEffect) {
            s!.draw(canvas.context2D, false);
          }
        }
      }
      expect(sawDroppingOnClient, isTrue,
          reason: "Expected bird droppings (PigeonDroppingBomb) to sync and render on client B");
      expect(flareA.remove, isTrue,
          reason: "Confirmed flare beacon should expire cleanly once airstrike finishes");
      expect(playerBOnA.health, lessThan(initialHealthB),
          reason: "Enemy standing in Pigeon Strike target zone should take bomb damage");

      // Verify kill & self-kill messages for all 4 new Mods!
      for (final Mod m in [Mod.HEDGEHOG, Mod.MOLE, Mod.BEEHIVE, Mod.PIGEON]) {
        expect(killedMessage("Bob", "Alice", m), isNotEmpty);
        expect(selfKillMessage("Bob", m), isNotEmpty);
      }
    });
  });
}

Weapon findBananaWeapons(LocalPlayerSprite sprite) {
  for (Weapon w in sprite.weaponState!.weapons) {
    if (w.name.contains("Banana")) {
      return w;
    }
  }
  throw new StateError("Didn't find banana weapons in ${sprite.weaponState!.weapons}!");
}

class _TestDamageProjectile extends WorldDamageProjectile {
  _TestDamageProjectile(WormWorld world, LocalPlayerSprite owner, int damage, [MovingSprite? positionBase])
      : super.createWithOwner(world, owner, damage, positionBase: positionBase) {
    radius = 99.0;
  }

  collide(MovingSprite? other, ByteWorld? world, int? direction) {
    print("_TestDamageProjectile collide ${other} ${world} ${direction}");
  }

  verifyAgainst(Sprite? other) {
    expect(other is WorldDamageProjectile, isTrue, reason: "Wrong sprite type!");
    if (other is WorldDamageProjectile) {
      expect(radius, equals(other.radius));
      expect(damage, equals(other.damage));
      expect(showCounter, equals(other.showCounter));
      expect(owner?.networkId, equals(other.owner?.networkId));
    }
  }
}