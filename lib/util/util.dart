library util;

import 'package:injectable/injectable.dart';

import 'package:dart2d/net/net.dart';
import 'gamestate.dart';
export 'fps_counter.dart';
export 'hud_messages.dart';
export 'keystate.dart';
export 'mobile_controls.dart';
export 'bot.dart';
export 'gamestate.dart';
export 'config_params.dart';

@Singleton(scope: 'world')
class SelfPlayerInfoProvider {
  Network _network;
  SelfPlayerInfoProvider(this._network);

  PlayerInfo? getSelfInfo() {
    String peerId = _network.getPeer().getId();
    return _network.getGameState().playerInfoByConnectionId(peerId);
  }
}

T checkNotNull<T>(T t) {
  if (t == null) {
    throw new ArgumentError.notNull("Null not allowed!");
  }
  return t;
}

String formatBytes(int bytes) {
  if (bytes > 4 * 1024 * 1024) {
    return "${bytes ~/ (1024 * 1024)} MB";
  }
  if (bytes > 4 * 1024) {
    return "${bytes ~/ 1024} kB";
  }
  return "${bytes} B";
}
