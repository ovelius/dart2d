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
  Map<String, ConnectionWrapper> connections = {};
  var _error;

  // Store active ids from the server to connect to.
  List<String> _activeIds = null;
  // Peers we've never been able to connect to.
  Set<String> _blackListedIds = new Set();
  // Peers which we have has a connection to, but is now closed.
  Set<String> _closedConnectionPeers = new Set();

  PeerWrapper(this._world, @PeerMarker() Object jsPeer,
      this.chunkHelper,
      this._peerWrapperCallbacks) {
    this.peer = jsPeer;
    _peerWrapperCallbacks
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
        _world, _world.network, _world.hudMessages, this.chunkHelper, peerId, connection, connectionType, this._peerWrapperCallbacks);
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
    _activeIds = ids;
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
    ConnectionType type;
    if (_world.network.isServer()) {
      type = ConnectionType.SERVER_TO_CLIENT;
    } else {
      // We are a client. This must be another client connecting to us.
      type = ConnectionType.CLIENT_TO_CLIENT;
    }
    connections[peerId] = new ConnectionWrapper(_world, _world.network, _world.hudMessages, this.chunkHelper,
        peerId, connection,  type,
        this._peerWrapperCallbacks);
  }

  void sendDataWithKeyFramesToAll(data, [var dontSendTo]) {
    List<String> closedConnections = [];
    for (var key in connections.keys) {
      ConnectionWrapper connection = connections[key];
      if (!connection.isValidConnection()) {
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
      for (String id in closedConnections) {
        removeClosedConnection(id);
      }
    }
  }

  /**
   * See if connection with this ID is healthy.
   */
  void healthCheckConnection(String id) {
    ConnectionWrapper wrapper = connections[id];
    if (wrapper != null && !wrapper.isValidConnection()) {
      removeClosedConnection(id);
    }
  }

  /**
   * Remove connection with this ID.
   */
  void removeClosedConnection(String id) {
    // Start with a copy.
    Map connectionsCopy = new Map.from(this.connections);
    ConnectionWrapper wrapper = connectionsCopy[id];
    print("${this.id}: Removing connection for $id");
    connectionsCopy.remove(id);
    if (wrapper.connectionType == ConnectionType.SERVER_TO_CLIENT) {
      print("Removing Gamestate for $id");
      _world.network.gameState.removeByConnectionId(id);
      // The crucial step of verifying we still have a server.
    } else if (_world.network.verifyOrTransferServerRole(connectionsCopy)) {
      // We got eleceted the new server, first task is to remove the old.
      print("Removing Gamestate for $id");
      _world.network.gameState.removeByConnectionId(id);
      _world.network.gameState.convertToServer(this.id);
    }
    // Connection was never open, blacklist the id.
    if (!wrapper.opened) {
      _blackListedIds.add(id);
      _closedConnectionPeers.add(id);
    } else {
      _closedConnectionPeers.add(id);
      print("Not blacklisting ${this.id} was opened!");
    }
    // Assign back.
    connections = connectionsCopy;
  }

  /**
   * Return true if we have tried all possible ways of getting a connection
   * and should retort to being server ourselves.
   */
  bool connectionsExhausted() {
    if (_activeIds == null) {
      return false;
    }
    return _closedConnectionPeers.containsAll(_activeIds);
  }

  /**
   * See if we've received a list of active peers.
   */
  bool hasReceivedActiveIds() {
    return _activeIds != null;
  }

  getLastError() => this._error;
}
