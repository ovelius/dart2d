library util;

import 'package:di/di.dart';
import "util.dart";
import 'package:dart2d/net/net.dart';

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
    bind(SelfPlayerInfoProvider);
  }
}

@Injectable()
class SelfPlayerInfoProvider {
  Network _network;
  SelfPlayerInfoProvider(this._network);

  PlayerInfo getSelfInfo() {
    String peerId = _network.getPeer().getId();
    return _network.getGameState().playerInfoByConnectionId(peerId);
  }
}