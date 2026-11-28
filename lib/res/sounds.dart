import 'dart:async';
import 'dart:js_interop';

import 'package:dart2d/res/crc32.dart';
import 'package:dart2d/res/resources.dart';
import 'package:dart2d/res/sound_hashes.dart';
import 'package:dart2d/util/util.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart' show Logger;
import 'package:web/web.dart';

import '../bindings/annotations.dart';

const SOUND_BASE_URL = "./snd/";

// NOTE: Whenever you add, remove, or modify a Sound entry (or its file in
// `web/snd/`), run:
//   dart run tool/generate_sound_hashes.dart
// to regenerate `lib/res/sound_hashes.dart`.
enum Sound {
  SILENCE("silenece.ogg"),
  DEATH("boom.mp3"),
  THUD("thud.mp3"),
  DARTGUN("dartgun.ogg"),
  EXPLOSION("explosion.ogg"),
  ZOOKA("zooka.ogg"),
  // morganpurkis of freesound.
  SHOTGUN("shotgun.ogg"),
  HYPER("hyper.ogg"),
  // bumpelsnake of freesound.
  BUZZ("buzz.ogg"),
  // https://freesound.org/people/Geoff-Bremner-Audio/
  WHIP("whip.mp3"),
  // https://freesound.org/people/kwahmah_02/
  SWOSH("swosh.mp3"),
  // Oh comes from https://freesound.org/people/balloonhead/
  OW("ow.ogg"),
  // Coin sound from https://freesound.org/people/Phenala/.
  POWERUP("powerup.mp3"),
  // From https://freesound.org/people/jwsoundfoley/
  FIZZ("fizz.ogg"),
  // From https://freesound.org/people/kyles/.
  BURN("burn.ogg"),
  // A version of a sound from
  // https://freesound.org/people/BlueSiren/
  BLUBB("blubb.ogg"),
  // This is a version of the powerup sound from
  // https://freesound.org/people/AbbasGamez/
  JUMP("jump.mp3"),
  // AI generated.
  KILL("kill.wav"),
  SPAWN("spawn.wav"),
  ROULETTE_TICK("roulette_tick.wav"),
  ROULETTE_WIN("roulette_win.wav"),
  EXTRA_BINGO("extra_bingo.wav"),
  SUPER_BINGO("super_bingo.wav");

  const Sound(this.url);

  final String url;
}

@Singleton(scope: 'world')
class Sounds implements NetworkResourceStore {
  static const int SOUND_INDEX_OFFSET = 1000;
  static final Duration CACHE_TIME = Duration(days: 7);

  final Logger log = Logger('Sounds');
  final Map<String, List<HTMLAudioElement>> _loadedSounds = {};
  final Map<String, Future> _loadingSounds = {};
  final Map<String, HTMLAudioElement> _uniquePlays = {};
  final Map<int, Sound> _soundByIndex = {};
  final Map<Sound, int> _indexBySound = {};
  final Map<int, String> _rawSoundDataUrls = {};
  final List<int> _orderedSoundIds = [];

  Map<String, int> expectedSoundHashes = SOUND_CRC32_HASHES;
  bool verifySoundHashes = true;

  final SoundFactory _soundFactory;
  final LocalStorage? _localStorage;
  final ConfigParams? _configParams;
  bool _indexed = false;

  bool soundEnabled = true;

  Sounds(this._soundFactory, [this._localStorage, this._configParams]) {
    _indexSounds();
  }

  static int resourceIdForSound(Sound sound) => SOUND_INDEX_OFFSET + sound.index;

  void _indexSounds() {
    if (_indexed) return;
    _indexed = true;
    for (Sound sound in Sound.values) {
      if (sound == Sound.SILENCE) continue;
      final int id = resourceIdForSound(sound);
      _soundByIndex[id] = sound;
      _indexBySound[sound] = id;
      _orderedSoundIds.add(id);
    }
  }

  Future playSound(Sound sound,
      {double volume = 1.0, bool multiPlay = false, String? playId = null}) {
    if (!soundEnabled) return Future.value(null);

    HTMLAudioElement? audioElement = _getSound(sound, multiPlay);
    if (audioElement != null) {
      if (playId != null) {
        stopPlayId(playId);
        _uniquePlays[playId] = audioElement;
      }
      return _playElement(audioElement, volume);
    }
    return Future.value(null);
  }

  bool isLoaded(Sound sound) {
    return _loadedSounds[sound.url]?.isNotEmpty == true;
  }

  bool finishedLoadingSounds() {
    for (int id in _orderedSoundIds) {
      final Sound? s = _soundByIndex[id];
      if (s != null && !isLoaded(s)) {
        return false;
      }
    }
    return true;
  }

  stopPlayId(String playId) {
    if (!soundEnabled) return;

    HTMLAudioElement? existing = _uniquePlays[playId];
    if (existing != null) {
      if (!existing.paused) {
        existing.pause();
      }
      _uniquePlays.remove(playId);
    }
  }

  Future _playElement(HTMLAudioElement element, double volume) {
    if (!element.paused) {
      element.pause();
    }
    element.volume = volume;
    element.currentTime = 0;
    if (element.readyState == HTMLMediaElement.HAVE_NOTHING) {
      return element.onCanPlay.first
          .then((_) => element.play().toDart.catchError((_) => null));
    } else {
      return element.play().toDart.catchError((_) => null);
    }
  }

  preloadSounds() {
    for (Sound sound in Sound.values) {
      if (sound != Sound.SILENCE) {
        _getSound(sound, false);
      }
    }
  }

  void loadSoundsFromNetwork() {
    _indexSounds();
    _loadFromCacheInLocalStorage();
  }

  HTMLAudioElement? _getSound(Sound sound, bool multiPlay) {
    if (!_loadedSounds.containsKey(sound.url)) {
      _loadedSounds[sound.url] = [];
    }
    List<HTMLAudioElement> sounds = _loadedSounds[sound.url]!;
    if (sounds.isEmpty) {
      Future? loading = _loadingSounds[sound.url];
      if (loading == null) {
        _startServerLoad(sound, allowCaching: true);
      }
      return null;
    }
    if (!multiPlay) {
      return sounds[0];
    }
    for (HTMLAudioElement element in sounds) {
      if (element.paused) {
        return element;
      }
    }
    HTMLAudioElement newElement = _soundFactory.clone(sounds[0], sound);
    sounds.add(newElement);
    return newElement;
  }

  Future _startServerLoad(Sound sound, {bool allowCaching = true}) {
    final String url = SOUND_BASE_URL + sound.url;
    final int id = _indexBySound[sound] ?? resourceIdForSound(sound);
    if (_soundFactory.supportsRawFetch) {
      final Future future = _fetchAndLoadSound(sound, id, url, allowCaching);
      _loadingSounds[sound.url] = future;
      return future;
    }
    HTMLAudioElement audioElement = _soundFactory.createWithSrc(url, sound);
    if (audioElement.src.startsWith('data:')) {
      _rawSoundDataUrls[id] = audioElement.src;
    }
    final Future future = audioElement.onCanPlay.first.then((Event _) {
      _loadedSounds.putIfAbsent(sound.url, () => []).add(audioElement);
      _loadingSounds.remove(sound.url);
    });
    _loadingSounds[sound.url] = future;
    return future;
  }

  Future _fetchAndLoadSound(
      Sound sound, int id, String url, bool allowCaching) async {
    String? dataUrl = await _soundFactory.fetchSoundDataUrl(url, sound);
    if (dataUrl != null) {
      await addFromSoundData(id, dataUrl, allowCaching);
      return;
    }
    HTMLAudioElement audioElement = _soundFactory.createWithSrc(url, sound);
    await audioElement.onCanPlay.first;
    _loadedSounds.putIfAbsent(sound.url, () => []).add(audioElement);
    _loadingSounds.remove(sound.url);
  }

  int? expectedSoundHash(int index) {
    final Sound? sound = _soundByIndex[index];
    if (sound == null) return null;
    return expectedSoundHashes[sound.url];
  }

  @override
  bool verifyResourceDataHash(int index, String data) {
    if (!verifySoundHashes) {
      return true;
    }
    final int? expected = expectedSoundHash(index);
    if (expected == null) {
      return true;
    }
    final int? actual = crc32FromDataUrl(data, 'data:audio/');
    return actual != null && actual == expected;
  }

  Future addFromSoundData(int index, String data, bool allowCaching) {
    final Sound? sound = _soundByIndex[index];
    if (sound == null) {
      return Future.value();
    }
    if (!data.startsWith('data:audio/')) {
      log.warning(
          "Dropping corrupted sound data for ${sound.url}, fallback to server.");
      return _startServerLoad(sound, allowCaching: true);
    }
    if (!verifyResourceDataHash(index, data)) {
      log.warning(
          "Dropping corrupted sound data (CRC32 mismatch) for ${sound.url}, fallback to server.");
      _removeFromLocalStorage(sound.url);
      return _startServerLoad(sound, allowCaching: true);
    }
    _rawSoundDataUrls[index] = data;
    HTMLAudioElement audioElement = _soundFactory.createWithSrc(data, sound);
    final Future future = audioElement.onCanPlay.first.then((Event _) {
      _loadedSounds.putIfAbsent(sound.url, () => []).add(audioElement);
      _loadingSounds.remove(sound.url);
      if (allowCaching) {
        _cacheInLocalStorage(index, sound.url, data);
      }
    });
    _loadingSounds[sound.url] = future;
    return future;
  }

  void _loadFromCacheInLocalStorage() {
    final LocalStorage? storage = _localStorage;
    if (storage == null) return;
    if (_configParams?.getBool(ConfigParam.DISABLE_CACHE) == true) {
      return;
    }
    final DateTime now = DateTime.now();
    for (int index in _orderedSoundIds) {
      final Sound? sound = _soundByIndex[index];
      if (sound == null || resourceIsLoading(index)) continue;
      final String key = "snd${sound.url}";
      if (storage.containsKey(key) && storage.containsKey("t$key")) {
        final String millis = storage["t$key"];
        final DateTime cacheTime =
            DateTime.fromMillisecondsSinceEpoch(int.parse(millis));
        if (cacheTime.add(CACHE_TIME).isAfter(now)) {
          final String data = storage[key];
          if (!verifyResourceDataHash(index, data)) {
            log.info("Evicting cached sound ${sound.url} due to CRC32 mismatch.");
            _removeFromLocalStorage(sound.url);
            continue;
          }
          addFromSoundData(index, data, false);
        } else {
          _removeFromLocalStorage(sound.url);
        }
      }
    }
  }

  void _cacheInLocalStorage(int index, String soundName, String data) {
    final LocalStorage? storage = _localStorage;
    if (storage == null) return;
    if (!verifyResourceDataHash(index, data)) {
      return;
    }
    final String key = "snd$soundName";
    if (!storage.containsKey(key)) {
      storage[key] = data;
      storage["t$key"] = DateTime.now().millisecondsSinceEpoch.toString();
    }
  }

  void _removeFromLocalStorage(String soundName) {
    final LocalStorage? storage = _localStorage;
    if (storage == null) return;
    final String key = "snd$soundName";
    storage.remove(key);
    storage.remove("t$key");
  }

  @override
  bool resourceIsLoaded(int index) {
    final Sound? sound = _soundByIndex[index];
    if (sound == null) return false;
    return isLoaded(sound);
  }

  @override
  bool resourceIsLoading(int index) {
    final Sound? sound = _soundByIndex[index];
    if (sound == null) return false;
    return isLoaded(sound) || _loadingSounds.containsKey(sound.url);
  }

  @override
  String getResourceDataUrl(int index) {
    final String? raw = _rawSoundDataUrls[index];
    if (raw == null) {
      throw StateError("Sound data URL not available for $index");
    }
    return raw;
  }

  @override
  Future addFromResourceData(int index, String data, bool allowCaching) =>
      addFromSoundData(index, data, allowCaching);

  @override
  Future addSingleResourceByIndex(int index) {
    final Sound? sound = _soundByIndex[index];
    if (sound == null) return Future.value();
    return _startServerLoad(sound, allowCaching: true);
  }

  @override
  String resourceNameFromIndex(int index) {
    final Sound? sound = _soundByIndex[index];
    if (sound == null) {
      throw "Missing sound with index $index";
    }
    return sound.url;
  }

  @override
  List<int> orderedResourceIds() => _orderedSoundIds;

  @override
  void ensureIndexedForNetwork() {
    loadSoundsFromNetwork();
  }

  @override
  void loadAllFromServer() {
    preloadSounds();
  }
}
