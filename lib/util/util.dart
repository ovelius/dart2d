library util;

import 'package:di/di.dart';
import "util.dart";

export 'fps_counter.dart';
export 'hud_messages.dart';
export 'keystate.dart';
export 'mobile_controls.dart';
export 'gamestate.dart';

class UtilModule extends Module {
  UtilModule() {
    bind(GameState);
    bind(FpsCounter);
    bind(HudMessages);
    bind(MobileControls);
  }
}