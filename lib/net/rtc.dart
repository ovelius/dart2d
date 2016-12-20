library rtc;

import 'package:dart2d/worlds/worm_world.dart';
import 'net.dart';
import 'connection.dart';
import 'package:di/di.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/js_interop/callbacks.dart';
import 'package:dart2d/net/chunk_helper.dart';

@Injectable() // TODO: Make Injectable.
class PeerWrapper {
  WormWorld _world;
  JsCallbacksWrapper _peerWrapperCallbacks;
  ChunkHelper chunkHelper;
  bool autoConnect = true;
  var peer;
  var id = null;
  Map connections = {};
  var _error;

  PeerWrapper(this._world, @PeerMarker() Object jsPeer,
      JsCallbacksWrapper peerWrapperCallbacks) {
    this.peer = jsPeer;
    this.chunkHelper = new ChunkHelper(this._world.imageIndex);
    this._peerWrapperCallbacks = peerWrapperCallbacks;
    peerWrapperCallbacks
      ..bindOnFunction(jsPeer, 'open', openPeer)
      ..bindOnFunction(jsPeer, 'receiveActivePeers', receivePeers)
      ..bindOnFunction(jsPeer, 'connection', connectPeer)
      ..bindOnFunction(jsPeer, 'error', error);
  }

  /**
   * Called to establish a connection to another peer.
   */
  void connectTo(id, [ConnectionType connectionType = ConnectionType.CLIENT_TO_SERVER]) {
    assert(id != null);
    var connection = _peerWrapperCallbacks.connectToPeer(peer, id);
    var peerId = connection['peer'];
    ConnectionWrapper connectionWrapper = new ConnectionWrapper(
        _world, peerId, connection, connectionType, this._peerWrapperCallbacks);
    connections[peerId] = connectionWrapper;
  }

  void error(unusedThis, e) {
    _error = e;
    _world.hudMessages.display("Peer error: ${e}");
  }

  void openPeer(unusedThis, id) {
    this.id = id;
    log.info("Got id ${id}");
  }
  
  /**
   * Receive list of peers from server. Automatically connect. 
   */
  void receivePeers(unusedThis, List<String> ids) {
    ids.remove(this.id);
    log.info("Received active peers of $ids");
    this._world.network.activeIds = ids;
    ids.forEach((String id) {
      if (autoConnect) {
        log.info("Auto connecting to id ${id}");
        this._world.restart = true;
        // Do no start game !
        this._world.connectTo(id, "Auto connect name", false);
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
    _world.hudMessages.display("Got connection from ${peerId}");
    if (_world.network.isServer()) {
      connections[peerId] = new ConnectionWrapper(_world, peerId, connection,  ConnectionType.SERVER_TO_CLIENT,
          this._peerWrapperCallbacks);
    } else {
      // We are a client. This must be another client connecting to us.
      connections[peerId] = new ConnectionWrapper(_world, peerId, connection,  ConnectionType.CLIENT_TO_CLIENT,
          this._peerWrapperCallbacks);
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
          _world.network.gameState.removeByConnectionId(key);
        // The crucial step of verifying we still have a server.
        } else if (_world.network.verifyOrTransferServerRole(connectionsCopy)) {
          // We got eleceted the new server, first task is to remove the old.
          print("Removing Gamestate for $key");
          _world.network.gameState.removeByConnectionId(key);
          _world.network.gameState.convertToServer(this.id);
        }
      }
      this.connections = connectionsCopy;
    }
  }

  getLastError() => this._error;
}
