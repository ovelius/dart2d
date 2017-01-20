library net;

import 'package:di/di.dart';
import "net.dart";

export 'network.dart';
export 'peer.dart';
export 'connection.dart';
export 'state_updates.dart';
export 'chunk_helper.dart';

class NetModule extends Module {
 NetModule() {
   bind(Network);
   bind(ChunkHelper);
 }
}