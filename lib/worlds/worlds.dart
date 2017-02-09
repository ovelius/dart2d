library worlds;

import 'package:di/di.dart';
import "worlds.dart";

export 'byteworld.dart';
export 'loader.dart';
export 'world.dart';
export 'player_world_selector.dart';
export 'world_listener.dart';
export 'worm_world.dart';

class WorldModule extends Module {
  WorldModule() {
    bind(WormWorld);
    bind(Loader);
    bind(ByteWorld);
    bind(PlayerWorldSelector);
    bind(WorldListener);
  }
}