import 'package:clock/clock.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/negotiator.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/util/util.dart';
import 'dart:convert';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

class PeerWrapper {
  final Logger log = new Logger('Peer');
  static const MAX_AUTO_CONNECTIONS = 5;
  static const MAX_CONNECTION = 8;
  Network _network;
  ConnectionFactory _connectionFactory;
  ServerChannel serverChannel;
  GaReporter _gaReporter;
  HudMessages _hudMessages;
  ConfigParams _configParams;
  PacketListenerBindings _packetListenerBindings;
  String? id = null;
  bool _connectedToServer = false;
  Map<String, ConnectionWrapper> connections = {};
  var _error;

  // Store active ids from the server to connect to.
  List<String>? _activeIds = null;
  List<String>? get activeIds =>
      _activeIds;

  Set<String> _blackListedIds = new Set();
  // Peers which we have has a connection to, but is now closed.
  Set<String> _closedConnectionPeers = new Set();

  PeerWrapper(this._connectionFactory, this._network, this._hudMessages, this._configParams, this.serverChannel, this._packetListenerBindings, this._gaReporter) {
    serverChannel.dataStream().listen((data) => _onServerMessage(data));
    serverChannel.openAndReadExistingPeers().then((peers) {
      _openPeer(peers[0]);
      _receivePeers(peers);
    });
  }

  /**
   * Called to establish a connection to another peer.
   */
  ConnectionWrapper connectTo(String id) {
    log.info("Creating connection to '${id}'");
    if (this.id == null) {
      throw "Can't create connection until ID is assigned!";
    }
    _gaReporter.reportEvent("connection_created", "Connection");
    ConnectionWrapper? existingConnection = connections[id];
    if (existingConnection != null) {
      log.warning("Already a connection to ${id}!");
      return existingConnection;
    }
    ConnectionWrapper connectionWrapper = new ConnectionWrapper(
        _network, _hudMessages,
        id, _packetListenerBindings, _configParams, new ConnectionFrameHandler(_configParams), Clock());
    connectionWrapper.negotiator.onNegotiationComplete((WebRtcDanceProto proto){
      _sendNegotiatorPayload(connectionWrapper.negotiator, proto, 'OFFER');
    });
    _connectionFactory.connectTo(connectionWrapper, connectionWrapper.negotiator);
    connections[id] = connectionWrapper;
    return connectionWrapper;
  }

  void _sendNegotiatorPayload(Negotiator negotiator, WebRtcDanceProto proto, String type) {
    String base64Proto = base64Encode(negotiator.buildProto().writeToBuffer());
    serverChannel.sendData(negotiator.otherId, type, base64Proto);
  }

  /**
   * Disconnect this peer from the server.
   */
  void disconnect() {
    _connectedToServer = false;
    serverChannel.disconnect();
  }

  /**
   * Re-connect this peer to the server.
   */
  void reconnect() {
    serverChannel.reconnect(id!)
        .listen((dynamic data) => _onServerMessage(data));
    _connectedToServer = true;
  }

  void error(unusedThis, e) {
    _error = e;
    _hudMessages.display("Peer error: ${e}");
  }

  void _openPeer(id) {
    this.id = id;
    // We blacklist from connection to self.
    _blackListedIds.add(id);
    _connectedToServer = true;
    log.info("Got id ${id}");
  }
  
  /**
   * Receive list of peers from server. Automatically connect. 
   */
  void _receivePeers(List<String> ids) {
    List<String> configIds = _configParams.getStringList(ConfigParam.EXPLICIT_PEERS);
    if (configIds.isEmpty) {
      Set<String> idSets = Set.from(ids);
      idSets.remove(this.id);
      log.info("Received active peers of $idSets");
      _activeIds = List.of(idSets);
    } else {
      log.info("Using peerIds from URL parameters $configIds");
      _activeIds = configIds;
    }
    autoConnectToPeers();
  }

  bool hasMaxAutoConnections() => connections.length >= MAX_AUTO_CONNECTIONS;

  /**
   * Connect to peers. Maintain connectios.
   */
  bool autoConnectToPeers() {
    List<String>? peerIds = _activeIds;
    if (peerIds == null) {
      throw "Can't execute autoconnect without PeerIds set";
    }
    bool addedConnection = false;
    for (String id in peerIds) {
      // Don't connect to too many peers...
      if (connections.length >= MAX_AUTO_CONNECTIONS) {
        return addedConnection;
      }
      if (connections.containsKey(id) ||
          _closedConnectionPeers.contains(id) || _blackListedIds.contains(id)) {
        continue;
      }
      addedConnection = true;
      log.info("Auto connecting to id ${id}");
      connectTo(id);
    }
    return addedConnection;
  }

  bool hasConnections() {
    return connections.length > 0;
  }
  
  bool hasConnectionTo(var id) {
    return this.id == id || connections.containsKey(id);
  }

  bool hasHadConnectionTo(String id) {
    return _closedConnectionPeers.contains(id);
  }
  /**
   * Callback for a peer connecting to us.
   */
  ConnectionWrapper _createWrapper(String otherPeerId) {
    _gaReporter.reportEvent("connection_received", "Connection");
    log.info("Got connection from ${otherPeerId}");
    _hudMessages.display("Got connection from ${otherPeerId}");
    if (connections.containsKey(otherPeerId)) {
      log.warning("Already a connection to ${otherPeerId}!");
    }
    ConnectionWrapper wrapper = new ConnectionWrapper(_network, _hudMessages,
        otherPeerId, _packetListenerBindings, _configParams, new ConnectionFrameHandler(_configParams), Clock());
    if (!_network.isCommander()
        && _network.gameState.playerInfoByConnectionId(otherPeerId) != null) {
      wrapper.markAsClientToClientConnection();
    }
    return wrapper;
  }

  void tickConnections(double duration, List<int> removals) {
    List<String> closedConnections = [];
    for (String key in connections.keys) {
      ConnectionWrapper? connection = connections[key];
      if (connection == null) {
        // Can actually happen! How fun.
        continue;
      }
      if (connection.isClosedConnection()) {
        closedConnections.add(key);
        continue;
      }
      if (!connection.isActiveConnection()) {
        continue;
      }
      connection.tick(duration, removals);
    }
    if (closedConnections.length > 0) {
      for (String id in closedConnections) {
        removeClosedConnection(id);
      }
    }
  }

  void sendSingleStateUpdate(StateUpdate data,
      [String? dontSendTo, String? onlySendTo]) {
    GameStateUpdates g = GameStateUpdates();
    g.stateUpdate.add(data);
    sendDataWithKeyFramesToAll(g, dontSendTo, onlySendTo);
  }

  void sendDataWithKeyFramesToAll(GameStateUpdates data,
      [String? dontSendTo, String? onlySendTo]) {
    List<String> closedConnections = [];
    for (String key in onlySendTo == null ?  connections.keys : [onlySendTo]) {
      ConnectionWrapper? connection = connections[key];
      assert(connection != null);
      if (dontSendTo != null && dontSendTo == connection!.id) {
        continue;
      }
      if (connection!.isClosedConnection()) {
        closedConnections.add(key);
        continue;
      }
      if (!connection.isActiveConnection()) {
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
    ConnectionWrapper? wrapper = connections[id];
    if (wrapper != null && wrapper.isClosedConnection()) {
      removeClosedConnection(id);
    }
  }

  /**
   * Remove connection with this ID.
   */
  void removeClosedConnection(String id) {
    // Start with a copy.
    Map<String, ConnectionWrapper> connectionsCopy = new Map.from(this.connections);
    ConnectionWrapper? wrapper = connectionsCopy[id];
    log.info("Removing connection for ${id}");
    connectionsCopy.remove(id);
    if (_network.isCommander()) {
      log.info("Removing GameState for ${id}");
      _network.gameState.removeByConnectionId(_network.world, id);
      // The crucial step of verifying we still have a server.
    } else {
      String? commanderId = _network.findNewCommander(connectionsCopy);
      if (commanderId != null) {
        // We got elected the new commander, first task is to remove the old.
        if (commanderId == this.id) {
          log.info("Server ${this.id}: Removing GameState for ${id}");
          PlayerInfoProto? info = _network.gameState.removeByConnectionId(_network.world, id);
          if (info != null) {
            _network.convertToCommander(connectionsCopy, info);
            _network.gameState.markAsUrgent();
          }
        } else {
          PlayerInfoProto info = _network.gameState.playerInfoByConnectionId(commanderId)!;
          // Start treating the other peer as server.
          _network.gameState.gameStateProto.actingCommanderId = commanderId;
          log.info("Commander is now ${commanderId}");
          _hudMessages.display("Elected new commander ${info.name}");
        }
      } else {
        log.info("Not switching commander after dropping ${id}");
      }
    }
    // Reconnect peer to server to allow receiving connections yet again.
    if (!connectedToServer()) {
      reconnect();
    }
    // Connection was never open, blacklist the id.
    if (wrapper != null && !wrapper.wasOpen()) {
      _blackListedIds.add(id);
      _closedConnectionPeers.add(id);
      _gaReporter.reportEvent("closed_never_open", "Connection");
    } else {
      _closedConnectionPeers.add(id);
      _gaReporter.reportEvent("closed_after_open", "Connection");
    }
    // Close the underlying WebRTC connection.
    try {
      wrapper?.rtcConnection()?.close();
    } catch (e, s) {
      log.warning("Failed to close RTCConnection ${e}");
    }
    // Assign back.
    connections = connectionsCopy;
  }

  /**
   * Return true if we have tried all possible ways of getting a connection
   * and should retort to being server ourselves.
   */
  bool connectionsExhausted() {
    print("${_activeIds} exhausted ${_closedConnectionPeers}");
    if (_activeIds == null) {
      return false;
    }
    return _closedConnectionPeers.containsAll(_activeIds!);
  }

  bool noMoreConnectionsAvailable() {
    Set<String> activeAndClosedConnections = new Set.from(_closedConnectionPeers)
        ..addAll(connections.keys);
    return activeAndClosedConnections.containsAll(_activeIds!);
  }

  /**
   * See if we've received a list of active peers.
   */
  bool hasReceivedActiveIds() {
    return _activeIds != null;
  }

  /**
   * Callback for receiving a message from signaling server.
   */
  _onServerMessage(Map<String, String> json) {
    log.fine("Got ServerChannel data ${json}");
    String? type = json['type']!;
    String? payload = json['payload'];
    String? src = json['src'];
    String? dst = json['dst'];

    WebRtcDanceProto? proto = null;
    if (payload != null) {
      proto = WebRtcDanceProto.fromBuffer(base64Decode(payload));
    }

    switch (type) {
      case 'ERROR':
        log.severe("Got error from server ${payload}");
        break;
      case 'LEAVE':
      // Someone left, fixme...
        break;
      case 'EXPIRE': // The offer sent to a peer has expired without response.
        log.warning("Could not connect to peer ${src}");
        break;
      case 'OFFER':
        if (src == null || dst == null || proto == null) {
          log.severe("Received malformed message of type $type, missing src or dst");
          return;
        }
        ConnectionWrapper? connection = connections[src];
        if (connection != null) {
          log.warning(
              "Received offer from peer that has connection? ${src} Existing connection: ${connection}");
        } else {
          log.info("Handling offer from ${src} offer: ${proto.toDebugString()}");
          ConnectionWrapper wrapper = _createWrapper(src);
          wrapper.negotiator.onNegotiationComplete((WebRtcDanceProto proto) {
            _sendNegotiatorPayload(wrapper.negotiator, proto, 'ANSWER');
          });
          _connectionFactory.createInboundConnection(wrapper, wrapper.negotiator, proto);
          connections[src] = wrapper;
        }
        break;
      case 'ANSWER':
        if (src == null || dst == null || proto == null) {
          log.severe("Received malformed message of type $type, missing src or dst");
          return;
        }
        log.info("Handling answer from ${src} offer: ${proto.toDebugString()}");
        ConnectionWrapper? connection = connections[src];
        if (connection == null) {
          log.warning("Received answer from unknown connection '$src'!");
        } else {
          _connectionFactory.handleGotAnswer(connection.rtcConnection(), proto);
        }
        break;
      default:
        log.severe("Unhandled message ${json}");
        break;
    }
  }

  getLastError() => this._error;
  getId() => this.id;

  bool connectedToServer() {
    return _connectedToServer && id != null;
  }
}
