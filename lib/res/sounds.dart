import 'dart:js_interop';

import 'package:injectable/injectable.dart';
import 'package:web/web.dart';

import '../bindings/annotations.dart';

const SOUND_BASE_URL = "./snd/";

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
  JUMP("jump.mp3");

  const Sound(this.url);

  final String url;
}

@Singleton(scope: 'world')
class Sounds {
  Map<String, List<HTMLAudioElement>> _loadedSounds = {};
  Map<String, Future> _loadingSounds = {};
  Map<String, HTMLAudioElement> _uniquePlays = {};
  SoundFactory _soundFactory;

  Sounds(this._soundFactory);

  Future playSound(Sound sound, {double volume = 1.0, bool multiPlay = false, String? playId = null}) {
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

  stopPlayId(String playId) {
    HTMLAudioElement? existing = _uniquePlays[playId];
    if (existing != null) {
      if (!existing.paused) {
        existing.pause();
      }
      _uniquePlays.remove(playId);
    }
  }

  Future _playElement(HTMLAudioElement element, double volume) {
    element.pause();
    element.volume = volume;
    element.currentTime = 0;
    if (element.readyState == HTMLMediaElement.HAVE_NOTHING) {
      return element.onCanPlay.first.then((_) => element.play().toDart);
    } else {
      return element.play().toDart;
    }
  }

  preloadSounds() {
    for (Sound sound in Sound.values) {
      if (sound != Sound.SILENCE) {
        _getSound(sound, false);
      }
    }
  }

  HTMLAudioElement? _getSound(Sound sound, bool multiPlay) {
    if (!_loadedSounds.containsKey(sound.url)) {
      _loadedSounds[sound.url] = [];
    }
    List<HTMLAudioElement> sounds = _loadedSounds[sound.url]!;
    if (sounds.isEmpty) {
      Future? loading = _loadingSounds[sound];
      if (loading == null) {
        HTMLAudioElement audioElement = _soundFactory.createWithSrc(
              SOUND_BASE_URL + sound.url, sound);
        audioElement.onCanPlay.first.then((Event e) {
          sounds.add(audioElement);
          _loadingSounds.remove(sound);
        });
        _loadingSounds[sound.url] = audioElement.onCanPlay.first;
      }
      return null;
    }
    // Only one sound can play at a time..
    if (!multiPlay) {
      return sounds[0];
    }
    // Look for available element.
    for (HTMLAudioElement element in sounds) {
      if (element.paused) {
        return element;
      }
    }
    // We didn't find any existing unused element create a new one.
    HTMLAudioElement newElement = _soundFactory.clone(sounds[0], sound);
    sounds.add(newElement);
    return newElement;
  }
}
