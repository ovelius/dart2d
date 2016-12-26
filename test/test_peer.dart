library test_peer;

import 'test_connection.dart';
import 'package:dart2d/hud_messages.dart';
import 'package:dart2d/worlds/world.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/worlds/loader.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'fake_canvas.dart';
import 'test_env.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/res/imageindex.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:di/di.dart';

WormWorld testWorld(String id, {var canvasElement}) {
  Injector injector = createWorldInjector(id);
  WormWorld world = injector.get(WormWorld);
  world.playerName = "name${id.toUpperCase()}";
  world.loader.setStateForTest(LoaderState.LOADING_GAMESTATE_COMPLETED);
  world.initByteWorld();
  return world;
}

Map testPeers = {};

class FakeJsCallbacksWrapper implements JsCallbacksWrapper {
  void bindOnFunction(var jsObject, String methodName, dynamic callback) {
    jsObject.callMethod(
        'on',
        [methodName, callback]);
  }
  dynamic connectToPeer(var jsPeer, String id) {
    return jsPeer.callMethod('connect', [id]);
  }
}

class TestPeer extends PeerMarker {
  String id;
  var eventHandlers = {};
  Set<String> failConnectionsTo = new Set();
  List<TestConnection> connections = [];

  TestPeer(this.id) {
    assert(!testPeers.containsKey(id));
    testPeers[id] = this;
  }

  callMethod(String methodName, var jsonObject) {
    if ("connect" == methodName) {
      var otherId = jsonObject[0];
      if (!testPeers.containsKey(otherId)
          && !failConnectionsTo.contains(otherId)) {
        throw new ArgumentError("No peer with id ${otherId} in this test! (and not set to fail!)");
      }
      TestConnection localConnection = new TestConnection(otherId);
      connections.add(localConnection);
      if (failConnectionsTo.contains(otherId)) {
        print("Simulating failing connection to ${otherId}");
        localConnection.signalOpen = false;
        return localConnection;
      }
      TestConnection remoteConnection = new TestConnection(id);
      remoteConnection.setOtherEnd(localConnection);
      localConnection.setOtherEnd(remoteConnection);
      testPeers[otherId].eventHandlers["connection"](this, remoteConnection);
      return localConnection;
    }
    if (methodName == "on" && bindOnHandler(jsonObject[0], jsonObject[1])) {
      return "OK";
    }
    print("TestPeer Can't handle ${jsonObject}");
    return "Not supported";
  }

  bool bindOnHandler(String methodName, var jsFunction) {
    eventHandlers[methodName] = jsFunction;
    if (methodName == "open") {
      // Signal an open connection right away.
      jsFunction(this, id);
    }
    return true;
  }

  void receiveActivePeer(List<String> peers) {
    assert(eventHandlers['receiveActivePeers'] != null);
    eventHandlers['receiveActivePeers'](this, peers);
  }

  void signalErrorAllConnections() {
    connections.forEach((c) {
      c.eventHandlers['error'](c, "Simulated error");
    });
  }

  void signalCloseOnAllConnections() {
    connections.forEach((c) {
      c.eventHandlers['close'](c);
    });
  }
}

class TestHudMessage extends HudMessages {
  
  TestHudMessage(World w) : super(w);

  void displayAndSendToNetwork(String message, [double period]) {
     print("HUD(${world.peer.id})_NET: $message");
     world.network.sendMessage(message);
   }

   void display(String message, [double period]) {
     print("HUD(${world.peer.id}): $message");
   }
}
