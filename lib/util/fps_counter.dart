library fps_counter;

import 'package:injectable/injectable.dart';

/** The target FPS of the main game loop */
const GAME_TARGET_FPS = 47;
const int TIMEOUT_MILLIS = 1000  ~/ GAME_TARGET_FPS;
const Duration TIMEOUT = const Duration(milliseconds: TIMEOUT_MILLIS);

@Singleton(scope: 'world')
class FpsCounter extends _FrameTrigger {
  FpsCounter() : super(1.0);
}

class _FrameTrigger {
  double _period = 1.0;
  double _fps = 0.0;
  double? _fpsForTest = null;

  double _nextTriggerIn = 1.0;
  int frames = 0;

  _FrameTrigger(double period) {
    this._period = period;
    this._nextTriggerIn = period;
  }

  bool timeWithFrames(double time, int framesPassed) {
    this.frames += framesPassed;
    _nextTriggerIn -= time;
    if (_nextTriggerIn < 0.0) {
      _fps = frames / (1.0 - _nextTriggerIn);
      frames = 0;
      _nextTriggerIn += _period;
      return true;
    }
    return false;
  }
  
  String toString() {
    return _fps.toStringAsFixed(2);
  }

  double fps() => _fpsForTest == null ? _fps : _fpsForTest!;

  setFpsForTest(double fps) {
    _fpsForTest = fps;
  }
}
