library rtc;

import 'dart:html';
import 'package:dart2d/worlds/world.dart';
import 'net.dart';
import 'connection.dart';
import 'package:di/di.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'package:dart2d/net/chunk_helper.dart';

@Injectable() // TODO: Make Injectable.
class PeerWrapper {
  World world;
  ChunkHelper chunkHelper = new ChunkHelper();
  bool autoConnect = true;
  var peer;
  var id = null;
  Map connections = {};

  PeerWrapper(this.world, PeerMarker jsPeer) {
    this.peer = jsPeer;
    new PeerWrapperCallbacks().registerPeerCallbacks(jsPeer, this);
  }

  /**
   * Called to establish a connection to another peer.
   */
  void connectTo(id, [ConnectionType connectionType = ConnectionType.CLIENT_TO_SERVER]) {
    assert(id != null);
    var connection = new PeerWrapperCallbacks().connectToPeer(peer, id);
    var peerId = connection['peer'];
    ConnectionWrapper connectionWrapper = new ConnectionWrapper(world, peerId, connection, connectionType);
    connections[peerId] = connectionWrapper;
  }

  void error(unusedThis, e) {
    world.hudMessages.display("Peer error: ${e}");
  }

  void openPeer(unusedThis, id) {
    this.id = id;
    var item = querySelector("#peerId");
    if (item != null) {
      querySelector("#peerId").innerHtml = "Your id is: " + id;
      var name = (querySelector("#nameInput") as InputElement).value;
      log.info("Got id ${id}");
    }
  }
  
  /**
   * Receive list of peers from server. Automatically connect. 
   */
  void receivePeers(unusedThis, List<String> ids) {
    ids.remove(this.id);
    this.world.network.activeIds = ids;        
    ids.forEach((String id) {
      if (autoConnect) {
        log.info("Auto connecting to id ${id}");
        this.world.restart = true;
        this.world.connectTo(id, "Auto connect name");
        return;
      }
    });
  }

  bool hasConnections() {
    return connections.length > 0;
  }
  
  bool hasConnectionTo(var id) {
    return this.id == id || connections.containsKey(id);
  }

  /**
   * Callback for a peer connecting to us.
   */
  void connectPeer(unusedThis, connection) {
    var peerId = connection['peer'];
    assert(peerId != null);
    world.hudMessages.display("Got connection from ${peerId}");
    if (world.network.isServer()) {
      connections[peerId] = new ConnectionWrapper(world, peerId, connection,  ConnectionType.SERVER_TO_CLIENT);
    } else {
      // We are a client. This must be another client connecting to us.
      connections[peerId] = new ConnectionWrapper(world, peerId, connection,  ConnectionType.CLIENT_TO_CLIENT);
    }
  }

  void sendDataWithKeyFramesToAll(data, [var dontSendTo]) {
    List closedConnections = [];
    for (var key in connections.keys) {
      ConnectionWrapper connection = connections[key];
      if (connection.closed) {
        closedConnections.add(key);
        continue;
      }
      if (!connection.opened) {
        continue;
      }
      if (dontSendTo != null && dontSendTo == connection.id) {
        continue;
      }
      connection.sendData(data);
    }
    if (closedConnections.length > 0) {
      Map connectionsCopy = new Map.from(this.connections);
      for (var key in closedConnections) {
        ConnectionWrapper wrapper = connectionsCopy[key];
        print("${id}: Removing connection for $key");
        connectionsCopy.remove(key);
        if (wrapper.connectionType == ConnectionType.SERVER_TO_CLIENT) {
          print("Removing Gamestate for $key");
          world.network.gameState.removeByConnectionId(key);
        // The crucial step of verifying we still have a server.
        } else if (world.network.verifyOrTransferServerRole(connectionsCopy)) {
          // We got eleceted the new server, first task is to remove the old.
          print("Removing Gamestate for $key");
          world.network.gameState.removeByConnectionId(key);
          world.network.gameState.convertToServer(this.id);
        }
      }
      this.connections = connectionsCopy;
    }
  }
}
