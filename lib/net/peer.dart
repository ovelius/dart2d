import 'package:clock/clock.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/negotiator.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/util/util.dart';
import 'dart:convert';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;
import 'package:web/web.dart';

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
    _packetListenerBindings.bindHandler(StateUpdate_Update.negotiation, (_, StateUpdate update) {

      WebRtcNegotiationProto proto = update.negotiation;
      if (proto.dst != this.id) {
        if (hasConnectionTo(proto.dst)) {
          log.info("Forwarding signaling message ${proto}");
          sendSingleStateUpdate(update, onlySendTo:proto.dst);
        } else {
          log.warning("Received signaling message to ${proto.dst} which we aren't connected to!");
        }
      } else {
        log.info("Received channel signaling message of ${proto}");
        Map<String, String> data = {
          'src': proto.src,
          'dst': proto.dst,
          'type': proto.type.value.toString()
        };
        _onServerMessage(data, explicitPayload: proto.danceProto);
      }
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
      _sendNegotiatorPayload(connectionWrapper.negotiator, proto, WebRtcNegotiationProto_Type.OFFER);
    });
    connectionWrapper.negotiator.onIceRestartCompleted((WebRtcDanceProto proto){
      _sendNegotiatorPayload(connectionWrapper.negotiator, proto, WebRtcNegotiationProto_Type.CANDIDATES);
    });
    connections[id] = connectionWrapper;
    _connectionFactory.connectTo(connectionWrapper, connectionWrapper.negotiator);
    return connectionWrapper;
  }

  void _sendNegotiatorPayload(Negotiator negotiator, WebRtcDanceProto proto, WebRtcNegotiationProto_Type type) {
    // Check if commander can route us.
    String commanderId = _network.getGameState().gameStateProto.actingCommanderId;
    if (_network.getGameState().isConnected(commanderId, negotiator.otherId)
      || !serverChannel.isConnected()) {
      WebRtcNegotiationProto negotiationProto = WebRtcNegotiationProto()
        ..type = type
        ..danceProto = proto
        ..src = this.id!
        ..dst = negotiator.otherId;
      sendSingleStateUpdate(StateUpdate()
          ..negotiation = negotiationProto
          ..attachDataReceipt(negotiator.otherId)
          , onlySendTo: commanderId);
    } else {
      String base64Proto = base64Encode(
          negotiator.buildProto().writeToBuffer());
      serverChannel.sendData(negotiator.otherId, type.value.toString(), base64Proto);
    }
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
    serverChannel.reconnect(id!);
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
      {String? dontSendTo = null, String? onlySendTo = null}) {
    GameStateUpdates g = GameStateUpdates();
    g.stateUpdate.add(data);
    sendDataWithKeyFramesToAll(g, dontSendTo:dontSendTo, onlySendTo:onlySendTo);
  }

  void sendDataWithKeyFramesToAll(GameStateUpdates data,
      {String? dontSendTo, String? onlySendTo}) {
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
      data.frame = connection.getCurrentFrame();
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
          // crash here..
          PlayerInfoProto info = _network.gameState.playerInfoByConnectionId(commanderId)!;
          // Start treating the other peer as commander.
          _network.gameState.gameStateProto.actingCommanderId = commanderId;
          log.info("Commander is now ${commanderId}");
          _hudMessages.display("Elected new commander ${info.name}");
          sendSingleStateUpdate(StateUpdate()
            ..commanderSwitchFromClosedConnection = commanderId
            ..attachSingleTonUniqueDataReceipt());
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
    } catch (e, _) {
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
  _onServerMessage(Map<String, String> json, {WebRtcDanceProto? explicitPayload = null}) {
    WebRtcNegotiationProto_Type? type = WebRtcNegotiationProto_Type.valueOf(int.parse(json['type']!));
    log.info("Got ServerChannel type ${type} data ${json}");
    if (type == null) {
      throw ArgumentError("Received message of unknown type ${json['type']}");
    }
    String? payload = json['payload'];
    String? src = json['src'];
    String? dst = json['dst'];

    WebRtcDanceProto? proto = explicitPayload;
    if (proto == null && payload != null) {
      proto = WebRtcDanceProto.fromBuffer(base64Decode(payload));
    }

    if (src == null || dst == null || proto == null) {
      log.severe("Received malformed message of type $type, missing src or dst");
      return;
    }

    switch (type) {
      case WebRtcNegotiationProto_Type.OFFER:
        ConnectionWrapper? connection = connections[src];
        if (connection != null) {
          log.warning(
              "Received offer from peer that has connection? ${src} Existing connection: ${connection}");
        } else {
          log.info("Handling offer from ${src} offer: ${proto.toDebugString()}");
          ConnectionWrapper wrapper = _createWrapper(src);
          wrapper.negotiator.onNegotiationComplete((WebRtcDanceProto proto) {
            _sendNegotiatorPayload(wrapper.negotiator, proto, WebRtcNegotiationProto_Type.ANSWER);
          });
          wrapper.negotiator.onIceRestartCompleted((WebRtcDanceProto proto) {
            _sendNegotiatorPayload(wrapper.negotiator, proto, WebRtcNegotiationProto_Type.CANDIDATES);
          });
          _connectionFactory.createInboundConnection(wrapper, wrapper.negotiator, proto);
          connections[src] = wrapper;
        }
        break;
      case WebRtcNegotiationProto_Type.ANSWER:
        ConnectionWrapper? connection = connections[src];
        if (connection == null) {
          log.warning("Received answer from unknown connection '$src'! Connections: ${connections.keys}");
        } else {
          log.info("Handling answer from ${src} offer: ${proto.toDebugString()}");
          _connectionFactory.handleGotAnswer(connection.rtcConnection(), proto);
        }
        break;
      case WebRtcNegotiationProto_Type.CANDIDATES:
        ConnectionWrapper? connection = connections[src];
        if (connection == null) {
          log.warning("Received candidates from unknown connection '$src'! Connections: ${connections.keys}");
          return;
        }
        for (String candidate in proto.candidates) {
          RTCIceCandidateInit init = new RTCIceCandidateInit(candidate:candidate, sdpMLineIndex:0);
          connection.rtcConnection()?.addIceCandidate(init);
        }
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
