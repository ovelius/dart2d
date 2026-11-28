import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:dart2d/net/chunk_helper.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/res/crc32.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/res/sounds.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'lib/test_factories.dart';
import 'lib/test_injector.dart';
import 'lib/test_lib.dart';
import 'lib/test_mocks.mocks.dart';

void main() {
  setUpAll(() {
    configureDependencies();
  });

  group('P2P sound loading via ChunkHelper', () {
    late TestConnectionWrapper connA;
    late TestConnectionWrapper connB;
    late PacketListenerBindings bindingsA;
    late PacketListenerBindings bindingsB;
    late MockImageIndex mockImageIndexA;
    late MockImageIndex mockImageIndexB;
    late MockByteWorld mockByteWorld;
    late TestLocalStorage storageA;
    late TestLocalStorage storageB;
    late FakeSoundFactory soundFactoryA;
    late FakeSoundFactory soundFactoryB;
    late Sounds soundsA;
    late Sounds soundsB;
    late ChunkHelper chunkHelperA;
    late ChunkHelper chunkHelperB;

    setUp(() {
      logOutputForTest();
      final MockPeerWrapper mockPeer = MockPeerWrapper();
      when(mockPeer.id).thenReturn('peer');
      final MockNetwork mockNet = MockNetwork();
      when(mockNet.getPeer()).thenReturn(mockPeer);

      connA = TestConnectionWrapper('a', mockNet, Clock());
      connB = TestConnectionWrapper('b', mockNet, Clock());
      bindingsA = PacketListenerBindings();
      bindingsB = PacketListenerBindings();
      mockImageIndexA = MockImageIndex();
      mockImageIndexB = MockImageIndex();
      mockByteWorld = MockByteWorld();
      storageA = TestLocalStorage();
      storageB = TestLocalStorage();
      soundFactoryA = FakeSoundFactory();
      soundFactoryB = FakeSoundFactory();

      final ConfigParams config = ConfigParams({});
      soundsA = Sounds(soundFactoryA, storageA, config)
        ..verifySoundHashes = false;
      soundsB = Sounds(soundFactoryB, storageB, config)
        ..verifySoundHashes = false;

      chunkHelperA =
          ChunkHelper(mockImageIndexA, mockByteWorld, bindingsA, soundsA)
            ..setChunkSizeForTest(64);
      chunkHelperB =
          ChunkHelper(mockImageIndexB, mockByteWorld, bindingsB, soundsB)
            ..setChunkSizeForTest(64);
    });

    tearDown(() {
      assertNoLoggedWarnings();
    });

    test('Transfers sound over P2P chunks and caches in LocalStorage', () async {
      // Peer B preloads TEST_SOUND data URL so it can serve it.
      soundsB.preloadSounds();
      await soundFactoryB.loadAllAudio();
      expect(soundsB.finishedLoadingSounds(), isTrue);
      expect(soundsA.finishedLoadingSounds(), isFalse);

      // requestNetworkData only fetches images (so sounds never block images/join).
      when(mockImageIndexA.orderedImageIds()).thenReturn([]);
      chunkHelperA.requestNetworkData({connB.id: connB}, 0.01);
      expect(connB.sendCount, equals(0));

      // requestSoundNetworkData fetches Sound.DEATH over P2P chunks.
      final int deathId = Sounds.resourceIdForSound(Sound.DEATH);
      chunkHelperA.requestSpecificNetworkData(
          {connB.id: connB}, 0.01, [deathId]);
      expect(connB.sendCount, equals(1));

      for (int i = 0; i < 100; i++) {
        if (soundsA.resourceIsLoading(deathId)) break;
        final ResourceRequest req =
            connB.lastDataSent!.stateUpdate[0].resourceRequest;
        chunkHelperB.replyWithImageData(req, connB);
        chunkHelperA.parseImageChunkResponse(
            connB.lastDataSent!.stateUpdate[0].resourceResponse, connB);
        if (chunkHelperA.getImageBuffer().containsKey(deathId)) {
          chunkHelperA.requestSpecificNetworkData(
              {connB.id: connB}, 0.01, [deathId]);
        }
      }

      await soundFactoryA.loadAllAudio();
      expect(soundsA.isLoaded(Sound.DEATH), isTrue);
      expect(storageA.containsKey('snd${Sound.DEATH.url}'), isTrue);
    });

    test('CRC32 mismatch on sound denylists corrupt peer and uses healthy peer',
        () async {
      final int buzzId = Sounds.resourceIdForSound(Sound.BUZZ);
      final String validBytes = TEST_SOUND.substring('data:audio/ogg;base64,'.length);
      final int validCrc = crc32Bytes(base64Decode(validBytes));
      soundsA.verifySoundHashes = true;
      soundsA.expectedSoundHashes = {Sound.BUZZ.url: validCrc};

      // Peer A sends corrupt audio.
      expectWarningContaining('CRC32 mismatch');
      chunkHelperA.requestSpecificNetworkData(
          {connA.id: connA}, 0.01, [buzzId]);
      const String corruptAudio = 'data:audio/ogg;base64,AAAA';
      chunkHelperA.parseImageChunkResponse(
          ResourceResponse()
            ..resourceIndex = buzzId
            ..startByte = 0
            ..data = utf8.encode(corruptAudio)
            ..size = corruptAudio.length,
          connA);

      expect(soundsA.isLoaded(Sound.BUZZ), isFalse);
      expect(chunkHelperA.isPeerDenylisted(buzzId, connA.id), isTrue);

      // Next request with {connA, connB} skips denylisted connA and uses connB.
      chunkHelperA.requestSpecificNetworkData(
          {connA.id: connA, connB.id: connB}, 0.01, [buzzId]);
      expect(chunkHelperA.pinnedPeerForImage(buzzId), equals(connB.id));
    });

    test('Loader does not block on sounds; WormWorld loads sounds in background',
        () async {
      final WormWorld world = await createTestWorld('snd1');
      final Sounds sounds = getIt<Sounds>();
      expect(sounds.finishedLoadingSounds(), isFalse);

      // Simulate server start + marking loader completed without preloading sounds.
      world.startAsServer();
      world.loader.markCompleted();
      expect(world.loader.completed(), isTrue);

      // Background sound tick starts loading sounds once in-game.
      world.frameDraw(0.016);
      final int deathId = Sounds.resourceIdForSound(Sound.DEATH);
      expect(sounds.resourceIsLoading(deathId) || sounds.isLoaded(Sound.DEATH),
          isTrue);
    });

    test('Loads valid cached sound from LocalStorage and evicts corrupt/expired',
        () async {
      final int thudId = Sounds.resourceIdForSound(Sound.THUD);
      final int buzzId = Sounds.resourceIdForSound(Sound.BUZZ);
      final int jumpId = Sounds.resourceIdForSound(Sound.JUMP);
      final String testPayload =
          TEST_SOUND.substring('data:audio/ogg;base64,'.length);
      final int validCrc = crc32Bytes(base64Decode(testPayload));

      storageA['snd${Sound.THUD.url}'] = TEST_SOUND;
      storageA['tsnd${Sound.THUD.url}'] =
          DateTime.now().millisecondsSinceEpoch.toString();

      // Corrupt CRC entry must be evicted.
      storageA['snd${Sound.BUZZ.url}'] = 'data:audio/ogg;base64,AAAA';
      storageA['tsnd${Sound.BUZZ.url}'] =
          DateTime.now().millisecondsSinceEpoch.toString();

      // Expired entry (> 7 days) must be evicted.
      storageA['snd${Sound.JUMP.url}'] = TEST_SOUND;
      storageA['tsnd${Sound.JUMP.url}'] = DateTime.now()
          .subtract(const Duration(days: 8))
          .millisecondsSinceEpoch
          .toString();

      soundsA.verifySoundHashes = true;
      soundsA.expectedSoundHashes = {
        Sound.THUD.url: validCrc,
        Sound.BUZZ.url: validCrc,
        Sound.JUMP.url: validCrc,
      };
      soundsA.loadSoundsFromNetwork();
      await soundFactoryA.loadAllAudio();

      expect(soundsA.resourceIsLoaded(thudId), isTrue);
      expect(soundsA.resourceIsLoaded(buzzId), isFalse);
      expect(storageA.containsKey('snd${Sound.BUZZ.url}'), isFalse);
      expect(soundsA.resourceIsLoaded(jumpId), isFalse);
      expect(storageA.containsKey('snd${Sound.JUMP.url}'), isFalse);
    });

    test('Falls back to server when all peers are denylisted for a sound',
        () async {
      final int buzzId = Sounds.resourceIdForSound(Sound.BUZZ);
      const String corruptAudio = 'data:audio/ogg;base64,AAAA';
      soundsA.verifySoundHashes = true;
      soundsA.expectedSoundHashes = {Sound.BUZZ.url: 0x12345678};

      expectWarningContaining('CRC32 mismatch');
      expectWarningContaining('falling back to server');

      // Corrupt response from connA denylists connA for Sound.BUZZ.
      chunkHelperA.requestSpecificNetworkData(
          {connA.id: connA}, 0.01, [buzzId]);
      chunkHelperA.parseImageChunkResponse(
          ResourceResponse()
            ..resourceIndex = buzzId
            ..startByte = 0
            ..data = utf8.encode(corruptAudio)
            ..size = corruptAudio.length,
          connA);
      expect(chunkHelperA.isPeerDenylisted(buzzId, connA.id), isTrue);

      // With only denylisted connA remaining, next tick falls back to server.
      chunkHelperA.requestSpecificNetworkData(
          {connA.id: connA}, 0.01, [buzzId]);
      await soundFactoryA.loadAllAudio();
      expect(soundsA.isLoaded(Sound.BUZZ), isTrue);
    });

    test('Serving peer ignores request gracefully if sound is not loaded yet',
        () {
      final int deathId = Sounds.resourceIdForSound(Sound.DEATH);
      expect(soundsB.isLoaded(Sound.DEATH), isFalse);

      final int sendsBefore = connB.sendCount;
      chunkHelperB.replyWithImageData(
          ResourceRequest()
            ..resourceIndex = deathId
            ..startByte = 0
            ..endByte = 64,
          connB);
      expect(connB.sendCount, equals(sendsBefore));
      expect(soundsB.resourceIsLoading(deathId) || soundsB.isLoaded(Sound.DEATH),
          isTrue);
    });
  });
}
