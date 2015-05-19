library rtc;

import 'dart:js';
import 'dart:html';
import 'package:dart2d/worlds/world.dart';
import 'net.dart';
import 'connection.dart';
import 'state_updates.dart';

createLocalHostPeerJs() {
  return new JsObject(context['Peer'], [new JsObject.jsify({
      'key': 'peerconfig', // TODO: Change this.
      'host': 'localhost',
      'port': 8089,
      'debug': 7,
      'config': {
        // TODO: Use list of public ICE servers instead.
        'iceServers': [{ 'url': 'stun:stun.l.google.com:19302' }]
      }
     })]);
}

createPeerJs() {
  return new JsObject(context['Peer'], [new JsObject.jsify({
    'key': 'peerconfig', // TODO: Change this.
    'host': 'ng.locutus.se',
    'port': 8089,
    'debug': 7,
    'config': {
      // TODO: Use list of public ICE servers instead.
      'iceServers': [{ 'url': 'stun:stun.l.google.com:19302' }]
    }
   })]);
}

createPeerJsOrig() {
  return new JsObject(context['Peer'], [new JsObject.jsify({
    'key': 'lwjd5qra8257b9', // TODO: Change this.
    'debug': 7,
    'config': {
      // TODO: Use list of public ICE servers instead.
      'iceServers': [{ 'url': 'stun:stun.l.google.com:19302' }]
    }
   })]);
}

class PeerWrapper {
  World world;
  bool autoConnect = true;
  var peer;
  var id = null;
  Map connections = {};

  PeerWrapper(this.world, this.peer) {
    peer.callMethod('on', new JsObject.jsify(['open', new JsFunction.withThis(this.openPeer)]));
    peer.callMethod('on', new JsObject.jsify(['receiveActivePeers', new JsFunction.withThis(this.receivePeers)]));
    peer.callMethod('on', new JsObject.jsify(['connection', new JsFunction.withThis(this.connectPeer)]));
    peer.callMethod('on', new JsObject.jsify(['error', new JsFunction.withThis(this.error)]));
  }

  /**
   * Called to establish a connection to another peer.
   */
  void connectTo(id, [ConnectionType connectionType = ConnectionType.CLIENT_TO_SERVER]) {
    assert(id != null);
    var metaData = new JsObject.jsify({
      'label': 'dart2d',
      'reliable': 'false',
      'metadata': {},
      'serialization': 'none',
    });
    var connection = peer.callMethod('connect', [id, metaData]);
    var peerId = connection['peer'];
    ConnectionWrapper connectionWrapper = new ConnectionWrapper(world, peerId, connection, connectionType);
    connections[peerId] = connectionWrapper;
  }

  void error(e) {
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
