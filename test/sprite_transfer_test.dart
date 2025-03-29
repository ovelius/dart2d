import 'package:test/test.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/worlds.dart';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:dart2d/weapons/abstractweapon.dart';
import 'package:dart2d/weapons/weapon_state.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';
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
    remapKeyNamesForTest();
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
      expect(worldB.isCommander(), isTrue);
      expect(worldB.spriteIndex.count(), equals(2));
      expect(worldB, hasExactSprites([
          hasSpriteWithNetworkId(playerId(1))
              .andNetworkType(NetworkType.LOCAL),
          hasSpriteWithNetworkId(playerId(2))
              .andNetworkType(NetworkType.REMOTE_FORWARD),
      ]));
      expect(worldB.spriteIndex[playerId(1)],
          hasType('LocalPlayerSprite'));
      expect(worldB.spriteIndex[playerId(2)],
          hasType('LocalPlayerSprite'));
      
      expect(worldC.spriteIndex.count(), equals(2));
          expect(worldC, hasExactSprites([
              hasSpriteWithNetworkId(playerId(1))
                  .andNetworkType(NetworkType.REMOTE),
              hasSpriteWithNetworkId(playerId(2))
                  .andNetworkType(NetworkType.LOCAL),
          ]));
      expect(worldC.spriteIndex[playerId(1)],
          hasType('LocalPlayerSprite'));
      expect(worldC.spriteIndex[playerId(2)],
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
            .andNetworkType(NetworkType.REMOTE_FORWARD)
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
             .andNetworkType(NetworkType.REMOTE)
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
      
      expect(recentReceviedDataFrom("b", 1),
          new MapKeyMatcher.doesNotContain(REMOVE_KEY));
      expect(recentReceviedDataFrom("c", 1),
          new MapKeyMatcher.doesNotContain(REMOVE_KEY));
    }, skip: "Disabled");

    /*
    test('TestKillDormantSprites', () {
      Logger.root.level = Level.FINE;
      WormWorld worldA = testWorld('a');
      WormWorld worldB = testWorld('b');
      WormWorld worldC = testWorld('c');
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

      LocalPlayerSprite playerSprite = worldB.spriteIndex[playerId(0)] as LocalPlayerSprite;
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

      for (int i = 0; i < 3; i++) {
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

    test('TestGameStateTransferKillPlayer', () {
      WormWorld worldA = testWorld("a");
      WormWorld worldB = testWorld("b");
      worldA.startAsServer("nameA");
     
      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();

      logConnectionData = true;
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
      playerBSprite = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      expect(playerASprite.info.name, equals("nameA"));
      
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
      while (playerBSprite.spawnIn > LocalPlayerSprite.RESPAWN_TIME / 2 + 0.01) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }
      // Now look how worldB views this sprite.
      expect(playerBSprite.inGame(), equals(false));
      // Position got updates to random before spawning.
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
      playerBSprite = worldA.spriteIndex[playerId(1)]  as LocalPlayerSprite;
      expect(playerBSprite.collision, equals(true));
      playerBSprite.takeDamage(playerBSprite.health, playerBSprite, Mod.UNKNOWN);

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

      // Player should be back in game now in both worlds.
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

      // Now switchs back.
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

    test('TestPlayerDeath', () {
      WormWorld worldA = testWorld("a");
      WormWorld worldB = testWorld("b");
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
      int healthRemaining = playerBSprite.health;

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


      expect(recentReceviedDataFrom("a"), 
          new MapKeysMatcher.containsKeys([GAME_STATE]));
    });

    test('TestParticleTransfer', () {
      WormWorld worldA = testWorld("a");
      WormWorld worldB = testWorld("b");
      worldA.startAsServer("nameA");

      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();

      // Give it some frames.
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      Particles p = new Particles(worldA,
          null, Vec2.ONE, new Vec2(50, 50),
          Vec2.ONE, 10.0, 20, 100000, 0.8, Particles.SODA);
      p.sendToNetwork = true;
      worldA.addSprite(p);

      worldA.frameDraw();
      worldB.frameDraw();

      expect(worldA.spriteIndex.count(), equals(3));
      expect(worldB.spriteIndex.count(), equals(3));
    });

    test('TestPlayerFireBasicGun', () {
      WorldDamageProjectile.random = new Random(1);
      WeaponState.random = new Random(1);
      WormWorld worldA = testWorld("a");
      WormWorld worldB = testWorld("b");
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
      // Set a deterministic position for player B.
      bSelfSprite.position.x = worldB.width() / 2;
      bSelfSprite.position.y = worldB.height() - bSelfSprite.size.y;

      // Aim up!
      int aimUp = bSelfSprite.getControls()['Aim up']!;
      worldB.localKeyState.onKeyDown(aimUp);

      LocalPlayerSprite aSelfSprite = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      // Place A very close to B.
      aSelfSprite.position = new Vec2.copy(bSelfSprite.position);
      aSelfSprite.position.x += aSelfSprite.getRadius() * 10;

      // Give it some frames.
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      int fireKey = bSelfSprite.getControls()['Fire']!;
      worldB.localKeyState.onKeyDown(fireKey);
      // This got send to worldA right away, since A decides when to fire.
      expect(recentSentDataTo("a"),
          new MapKeyMatcher.containsKeyWithValue(KEY_STATE_KEY, containsPair(fireKey.toString(), true)));

      for (int i = 0; i < 2; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      // This should give us 10 bullets right now.
      expect(worldA.spriteIndex.count(), 10);
      expect(worldB.spriteIndex.count(), 10);
    });

    test('TestPlayerFireGunExplosionsAndKill', () {
      // Use a seeded random here. This is important to make the test pass.
      WorldDamageProjectile.random = new Random(1);
      WeaponState.random = new Random(1);
      WormWorld worldA = testWorld("a");
      WormWorld worldB = testWorld("b");
      worldA.startAsServer("nameA");

      worldB.connectTo("a", "nameB");
      worldB.network().getServerConnection()!.sendClientEnter();

      // Give it some frames.
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      LocalPlayerSprite bSelfSprite = worldB.spriteIndex[playerId(1)] as LocalPlayerSprite;
      bSelfSprite.position.x = worldB.width() / 2;
      bSelfSprite.position.y = worldB.height() - bSelfSprite.size.y;
      LocalPlayerSprite aSelfSprite = worldA.spriteIndex[playerId(0)] as LocalPlayerSprite;
      LocalPlayerSprite aBSprite = worldA.spriteIndex[playerId(1)] as LocalPlayerSprite;
      // Place A very close to B.
      aSelfSprite.position = new Vec2.copy(bSelfSprite.position);
      aSelfSprite.position.x += aSelfSprite.getRadius() * 2;

      // Give it some frames to propagate positions.
      for (int i = 0; i < 5; i++) {
        worldA.frameDraw(KEY_FRAME_DEFAULT);
        worldB.frameDraw(KEY_FRAME_DEFAULT);
      }

      // Now switch weapons.
      int nextWeaponKey = bSelfSprite.getControls()["Next weapon"]!;
      Weapon bananaWeapons = findBananaWeapons(bSelfSprite);
      while (bSelfSprite.weaponState!.selectedWeaponName != bananaWeapons.name) {
        worldB.localKeyState.onKeyDown(nextWeaponKey);
        expect(recentSentDataTo("a"),
            new MapKeyMatcher.containsKeyWithValue(KEY_STATE_KEY, containsPair(nextWeaponKey.toString(), true)));
        worldB.localKeyState.onKeyUp(nextWeaponKey);
      }

      // Propagate selected weapon to A.
      worldB.frameDraw(KEY_FRAME_DEFAULT);
      expect(bSelfSprite.weaponState!.selectedWeaponName, equals(bananaWeapons.name));
      expect(aBSprite.weaponState!.selectedWeaponName, equals(bananaWeapons.name));

      // Aim up!
      int aimUp = bSelfSprite.getControls()['Aim up']!;
      worldB.localKeyState.onKeyDown(aimUp);
      worldB.frameDraw(1.0);
      worldB.frameDraw(1.0);

      // Now fire our weapon!
      int fireKey = bSelfSprite.getControls()['Fire']!;
      worldB.localKeyState.onKeyDown(fireKey);

      expect(worldA.spriteIndex.count(), equals(2));
      expect(worldB.spriteIndex.count(), equals(2));
      // The banana weapon produces one shot.
      worldA.frameDraw();
      worldA.frameDraw();
      expect(worldA.spriteIndex.count(), equals(3));
      // Find the projectile.
      WorldDamageProjectile projectile = worldA.spriteIndex[0] as WorldDamageProjectile;
      expect(projectile, isNotNull, reason: "Expected a projectile in ${worldA.spriteIndex}");

      worldA.frameDraw(KEY_FRAME_DEFAULT);
      worldB.frameDraw(0.1);
      expect(worldA.spriteIndex.count(), equals(3));
      expect(worldB.spriteIndex.count(), equals(3));

      // Tick do explode it.
      expect(projectile.velocity.y < 0.0, isTrue, reason: "Aim up so upward velocity!");
      worldA.frameDraw(projectile.explodeAfter! + 0.1);
      // Bring this back!
      // expect(recentSentDataTo("b"),
      //    new MapKeyMatcher.containsKey(WORLD_DESTRUCTION));
      expect(projectile.remove, isTrue);
      worldA.frameDraw(KEY_FRAME_DEFAULT);

      expect(worldA.spriteIndex.count() > 3, isTrue);
      // Based on the setup, this kills player a.
      // TODO this is flaky! Bring back expectations.
      // expect(aSelfSprite.inGame(), isFalse);
      // PlayerB is the killer!
      // expect(aSelfSprite.killer.connectionId, equals("b"));
      });
*/
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
      : super.createWithOwner(world, owner, damage, positionBase) {
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
      expect(owner.networkId, equals(other.owner.networkId));
    }
  }
}