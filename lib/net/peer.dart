import 'package:di/di.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/util/hud_messages.dart';
import 'dart:convert';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

@Injectable() // TODO: Make Injectable.
class PeerWrapper {
  final Logger log = new Logger('Peer');
  static const MAX_AUTO_CONNECTIONS = 5;
  static const MAX_CONNECTION = 8;
  Network _network;
  ConnectionFactory _connectionFactory;
  ServerChannel _serverChannel;
  GaReporter _gaReporter;
  HudMessages _hudMessages;
  ConfigParams _configParams;
  PacketListenerBindings _packetListenerBindings;
  String id = null;
  bool _connectedToServer = false;
  Map<String, ConnectionWrapper> connections = {};
  var _error;

  // Store active ids from the server to connect to.
  List<String> _activeIds = null;
  // Peers we've never been able to connect to.
  Set<String> _blackListedIds = new Set();
  // Peers which we have has a connection to, but is now closed.
  Set<String> _closedConnectionPeers = new Set();

  PeerWrapper(this._connectionFactory, this._network, this._hudMessages, this._configParams, this._serverChannel, this._packetListenerBindings, this._gaReporter) {
    assert(_serverChannel != null);
    _serverChannel.dataStream().listen((dynamic data) => _onServerMessage(data));
  }

  /**
   * Called to establish a connection to another peer.
   */
  ConnectionWrapper connectTo(id) {
    _gaReporter.reportEvent("connection_created", "Connection");
    assert(id != null);
    if (connections.containsKey(id)) {
      log.warning("Already a connection to ${id}!");
      return connections[id];
    }
    ConnectionWrapper connectionWrapper = new ConnectionWrapper(
        _network, _hudMessages,
        id, _packetListenerBindings, _configParams);
    _connectionFactory.connectTo(connectionWrapper, this.id, id);
    connections[id] = connectionWrapper;
    return connectionWrapper;
  }

  /**
   * Disconnect this peer from the server.
   */
  void disconnect() {
    _connectedToServer = false;
    _serverChannel.disconnect();
  }

  /**
   * Re-connect this peer to the server.
   */
  void reconnect() {
    _serverChannel.reconnect(id)
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
      ids.remove(this.id);
      log.info("Received active peers of $ids");
      _activeIds = ids;
      autoConnectToPeers();
    } else {
      log.info("Using peersIds from URL parameters $configIds");
      _activeIds = configIds;
      autoConnectToPeers();
    }
  }

  bool hasMaxAutoConnections() => connections.length >= MAX_AUTO_CONNECTIONS;

  /**
   * Connect to peers. Maintain connectios.
   */
  bool autoConnectToPeers() {
    bool addedConnection = false;
    for (String id in _activeIds) {
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
    assert(otherPeerId != null);
    log.info("Got connection from ${otherPeerId}");
    _hudMessages.display("Got connection from ${otherPeerId}");
    if (connections.containsKey(otherPeerId)) {
      log.warning("Already a connection to ${otherPeerId}!");
    }
    ConnectionWrapper wrapper = new ConnectionWrapper(_network, _hudMessages,
        otherPeerId, _packetListenerBindings, _configParams);
    if (!_network.isCommander()
        && _network.gameState.playerInfoByConnectionId(otherPeerId) != null) {
      wrapper.markAsClientToClientConnection();
    }
    return wrapper;
  }

  void sendDataWithKeyFramesToAll(Map data,
      [String dontSendTo, String onlySendTo]) {
    List<String> closedConnections = [];
    for (var key in onlySendTo == null ?  connections.keys : [onlySendTo]) {
      ConnectionWrapper connection = connections[key];
      assert(connection != null);
      if (dontSendTo != null && dontSendTo == connection.id) {
        continue;
      }
      if (connection.isClosedConnection()) {
        closedConnections.add(key);
        continue;
      }
      if (!connection.isActiveConnection()) {
        continue;
      }
      connection.sendData(data);
      if (data.containsKey(IS_KEY_FRAME_KEY)) {
        int keyFrame = data[IS_KEY_FRAME_KEY];
        // Send a ping every 6th keyframe to determine connection latency.
        if ((connection.id.hashCode + keyFrame) % 6 == 0) {
          connection.sendPing();
        }
      }
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
    if (wrapper != null && wrapper.isClosedConnection()) {
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
    log.info("Removing connection for ${id}");
    connectionsCopy.remove(id);
    if (_network.isCommander()) {
      log.info("Removing GameState for ${id}");
      _network.gameState.removeByConnectionId(_network.world, id);
      // The crucial step of verifying we still have a server.
    } else {
      String commanderId = _network.findNewCommander(connectionsCopy);
      if (commanderId != null) {
        // We got elected the new server, first task is to remove the old.
        if (commanderId == this.id) {
          log.info("Server ${this.id}: Removing GameState for ${id}");
          PlayerInfo info = _network.gameState.removeByConnectionId(_network.world, id);
          log.info("Info is ${info} i am ${this.id}");
          _network.convertToCommander(connectionsCopy, info);
          _network.gameState.markAsUrgent();
        } else {
          PlayerInfo info = _network.gameState.playerInfoByConnectionId(commanderId);
          // Start treating the other peer as server.
          ConnectionWrapper connection = connections[commanderId];
          _network.gameState.actingCommanderId = commanderId;
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
    if (!wrapper.wasOpen()) {
      _blackListedIds.add(id);
      _closedConnectionPeers.add(id);
      _gaReporter.reportEvent("closed_never_open", "Connection");
    } else {
      _closedConnectionPeers.add(id);
      _gaReporter.reportEvent("closed_after_open", "Connection");
    }
    // Close the underlying WebRTC connection.
    try {
      wrapper.rtcConnection().close();
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
    if (_activeIds == null) {
      return false;
    }
    return _closedConnectionPeers.containsAll(_activeIds);
  }

  bool noMoreConnectionsAvailable() {
    Set<String> activeAndClosedConnections = new Set.from(_closedConnectionPeers)
        ..addAll(connections.keys);
    return activeAndClosedConnections.containsAll(_activeIds);
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
  _onServerMessage(Map<dynamic, dynamic> json) {
    log.fine("Got ServerChannel data ${json}");
    String type = json['type'];
    dynamic payload = json['payload'];
    String src = json['src'];
    String dst = json['dst'];

    switch (type) {
      case 'ACTIVE_IDS':
        _openPeer(json['id']);
        _receivePeers(json['ids']);
        break;
      case 'ERROR':
        log.severe("Got error from server ${payload}");
        break;
      case 'CANDIDATE':
        ConnectionWrapper connection = connections[src];
        if (connection == null) {
          log.warning(
              "Missing connection for candidate data ${payload}");
        } else {
          _connectionFactory.handleIceCandidateReceived(
              connection.rtcConnection(), payload['candidate']);
          log.info("Added ICE candidate ${payload}");
        }
        break;
      case 'LEAVE':
      // Someone left, fixme...
        break;
      case 'EXPIRE': // The offer sent to a peer has expired without response.
        log.warning("Could not connect to peer ${src}");
        break;
      case 'OFFER':
        ConnectionWrapper connection = connections[src];
        if (connection != null) {
          log.warning(
              "Received offer from peer that has connection? ${src} Existing connection: ${connection}");
        } else {
          log.info("Handling offer from ${src} offer: ${payload}");
          ConnectionWrapper wrapper = _createWrapper(src);
          dynamic connection = _connectionFactory.createInboundConnection(
              wrapper, payload['sdp'], src, dst);
          connections[src] = wrapper;
          _connectionFactory.handleCreateAnswer(connection, src, dst);
        }
        break;
      case 'ANSWER':
        log.info("Handling answer from ${src} offer: ${payload}");
        ConnectionWrapper connection = connections[src];
        _connectionFactory.handleGotAnswer(connection.rtcConnection(), payload['sdp']);
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
