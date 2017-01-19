library fps_counter;

import 'package:di/di.dart';

@Injectable()
class FpsCounter extends _FrameTrigger {
  FpsCounter() : super(1.0);
}

class _FrameTrigger {
  double period = 1.0;
  double fps = 0.0;

  double nextTriggerIn = 1.0;
  int frames = 0;

  _FrameTrigger(double period) {
    this.period = period;
    this.nextTriggerIn = period;
  }

  bool timeWithFrames(double time, int framesPassed) {
    this.frames += framesPassed;
    nextTriggerIn -= time;
    if (nextTriggerIn < 0.0) {
      fps = frames / (1.0 - nextTriggerIn); 
      frames = 0;
      nextTriggerIn += period;
      return true;
    }
    return false;
  }
  
  String toString() {
    return fps.toStringAsFixed(2);
  }
}
