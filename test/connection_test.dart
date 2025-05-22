import 'dart:js_interop';

import 'package:clock/clock.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:test/test.dart';
import 'package:web/helpers.dart';
import 'lib/test_lib.dart';
import 'package:fixnum/fixnum.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/util/util.dart';
import 'package:mockito/mockito.dart';
import 'dart:io';
import 'lib/test_mocks.mocks.dart';

class FakeClock extends Clock {
  DateTime testTime = DateTime.now();
  DateTime now() {
    return testTime;
  }
}

void main() {
  late MockNetwork mockNetwork;
  late ConfigParams testConfigParams;
  late MockHudMessages mockHudMessages;
  late PacketListenerBindings packetListenerBindings;
  late ConnectionWrapper connection;
  late TestConnection testConnection;
  late FakeClock fakeClock;


  setUp(() {
    logOutputForTest();
    fakeClock = FakeClock();
    mockNetwork = new MockNetwork();
    MockPeerWrapper mockPeerWrapper = MockPeerWrapper();
    MockGameState mockGameState = MockGameState();
    when(mockNetwork.getGameState()).thenReturn(mockGameState);
    when(mockPeerWrapper.id).thenReturn("b");
    when(mockNetwork.getPeer()).thenReturn(mockPeerWrapper);
    when(mockNetwork.isCommander()).thenReturn(false);
    mockHudMessages = new MockHudMessages();
    testConfigParams = new ConfigParams({});
    packetListenerBindings = new PacketListenerBindings();
    testConnection = new TestConnection("a", null);
    testConnection.buffer = true;
    connection = new ConnectionWrapper(
        mockNetwork, mockHudMessages, "a", packetListenerBindings,
        testConfigParams, new ConnectionFrameHandler(new ConfigParams({})), fakeClock);

    var jsTestConnection = createJSInteropWrapper<TestConnection>(testConnection) as RTCPeerConnection;
    var jsTestDataChannel = createJSInteropWrapper<TestConnection>(testConnection) as RTCDataChannel;
    connection.setRtcConnection(jsTestConnection);
    connection.readyDataChannel(jsTestDataChannel);
  });

  tearDown(() {
   // assertNoLoggedWarnings();
  });

  test('TestConnectionOpenTimeout', () {
    expect(connection.isActiveConnection(), isFalse);
    fakeClock.testTime = fakeClock.testTime.add(ConnectionStats.OPEN_TIMEOUT);
    fakeClock.testTime = fakeClock.testTime.add(Duration(milliseconds: 1));
    // Now closed since never open.
    expect(connection.isClosedConnection(), isTrue);
  });

  test('TestCompleteNegotiation',() {
    WebRtcDanceProto? webRtcDanceProto = null;
    connection.negotiator.onNegotiationComplete(
            (WebRtcDanceProto proto) => webRtcDanceProto = proto);
    connection.negotiator.sdpReceived("sdp", "offer");
    connection.negotiator.onIceCandidate("candidate1");
    connection.negotiator.onIceCandidate("candidate2");
    connection.negotiator.onIceCandidate(null);

    expect(webRtcDanceProto, WebRtcDanceProto()
        ..sdp = "sdp"
        ..sdpType = "offer"
        ..candidates.add("candidate1")
        ..candidates.add("candidate2"));
  });

  test('TesRestartIce',() {
    WebRtcDanceProto? webRtcDanceProto = null;
    connection.negotiator.onNegotiationComplete(
            (WebRtcDanceProto proto) => webRtcDanceProto = proto);
    connection.negotiator.sdpReceived("sdp", "offer");
    connection.negotiator.onIceCandidate("candidate1");
    connection.negotiator.onIceCandidate("candidate2");
    connection.negotiator.onIceCandidate(null);

    connection.restartIceWithTurn();

    expect(testConnection.iceRestarts, 1);
    expect(testConnection.setConfigurations, 1);

    connection.negotiator.onIceCandidate("candidate3");
    connection.negotiator.onIceCandidate("candidate4");
    connection.negotiator.onIceCandidate(null);

    expect(webRtcDanceProto, WebRtcDanceProto()
      ..sdp = "sdp"
      ..sdpType = "offer"
      ..candidates.add("candidate3")
      ..candidates.add("candidate4"));
  });

  test('TestConnectionMarkedOpenThenClosed', () {
    expect(connection.isActiveConnection(), isFalse);
    connection.open();
    expect(connection.isActiveConnection(), isTrue);
    expect(connection.isClosedConnection(), isFalse);
    connection.close("test!");
    expect(connection.isActiveConnection(), isFalse);
    expect(connection.isClosedConnection(), isTrue);
  });

  test('TestReliableDataSend', () {
    GameStateUpdates data = GameStateUpdates()
        ..lastFrameSeen = 1
        ..stateUpdate.add(StateUpdate()
        ..dataReceipt = 123
        ..userMessage = "t");
    connection.sendData(data);
    expect(
        testConnection.nativeBufferedDataAt(0),
        equals(data));
    expect(
        connection.reliableHelper().reliableDataBuffer,
        equals({
          123: data.stateUpdate[0]
        }));

    GameStateUpdates receipt = GameStateUpdates()
        ..lastFrameSeen = 1
        ..stateUpdate.add(StateUpdate()..ackedDataReceipts = 123);
    connection.receiveData(PacketWrapper(receipt.writeToBuffer()));

    expect(connection.reliableHelper().reliableDataBuffer, equals({}));
  });

  test('TestReliableDataReSend', () {
    StateUpdate reliableUpdate =
        StateUpdate()
            ..dataReceipt = 123
            ..spriteRemoval = 111;

    connection.sendSingleUpdate(reliableUpdate);
    connection.sendData(
      GameStateUpdates()
          ..keyFrame = 2
    );

    // Data got added again.
    expect(
        testConnection.nativeBufferedDataAt(1),
        equals(GameStateUpdates()
          ..lastFrameSeen = 0
          ..keyFrame = 2
          ..stateUpdate.add(reliableUpdate)));

    expect(
        connection.reliableHelper().reliableDataBuffer,
        equals({
          123: reliableUpdate,
        }));

    connection.sendData(GameStateUpdates()
      ..keyFrame = 3);

    // Data got added yet again.
    expect(
        testConnection.nativeBufferedDataAt(2),
        equals(GameStateUpdates()
          ..lastFrameSeen = 0
          ..keyFrame = 3
          ..stateUpdate.add(reliableUpdate)));
  });

  test('TestVerifiesReliableData', () {
    StateUpdate reliableUpdate =
    StateUpdate()
      ..dataReceipt = 123
      ..spriteRemoval = 111;

    connection.sendSingleUpdate(reliableUpdate);
    connection.sendData(
        GameStateUpdates()
          ..keyFrame = 2
    );

    GameStateUpdates ackData = GameStateUpdates()
      ..lastFrameSeen = 1
      ..stateUpdate.add(StateUpdate()..ackedDataReceipts = 123);
    connection.receiveData(PacketWrapper(ackData.writeToBuffer()));

    connection.sendData(
        GameStateUpdates()
          ..keyFrame = 2
    );

    // No resend was performed.
    expect(
        testConnection.nativeBufferedDataAt(2),
        equals(GameStateUpdates()
          ..lastFrameSeen = 0
          ..keyFrame = 2));
  });


  test('TestReliableData_addsAck', () {
    StateUpdate reliableUpdate =
        StateUpdate()
          ..dataReceipt = 123
          ..spriteRemoval = 111;

    PacketWrapper p = PacketWrapper((GameStateUpdates()
      ..stateUpdate.add(reliableUpdate)
      ..lastFrameSeen = 10
      ..frame = 2).writeToBuffer());

    packetListenerBindings.bindHandler(StateUpdate_Update.spriteRemoval, (_, StateUpdate update) {});

    connection.receiveData(p);

    connection.tick(KEY_FRAME_DEFAULT / 5, []);

    // Data receipt was added to ticked data.
    expect(
        testConnection.nativeBufferedDataAt(0),
        equals(GameStateUpdates()
          ..stateUpdate.add(StateUpdate()..ackedDataReceipts = 123)
          ..frame = 0
          ..lastFrameSeen = 2
          ..keyFrame = 0));
  });

  test('ReliableDataOutsideGame_IsResent', () {
    StateUpdate reliableUpdate =
        StateUpdate()
          ..dataReceipt = 123
          ..spriteRemoval = 111;
    connection.sendSingleUpdate(reliableUpdate);

    // Not a valid game connection.
    expect(connection.isValidGameConnection(), isFalse);
    expect(testConnection.dataBuffer.length, 1);

    for (int i = 0; i < 20; i++) {
      connection.tick(KEY_FRAME_DEFAULT / 5, []);
      if (testConnection.dataBuffer.length > 1) {
        break;
      }
    }
    expect(testConnection.dataBuffer.length, 2);

    // Data is resent anyway.
    expect(
        testConnection.nativeBufferedDataAt(1),
        equals(GameStateUpdates()
          ..stateUpdate.add(reliableUpdate)
          ..frame = 0
          ..lastFrameSeen = 0
          ..keyFrame = 0));
  });

  test('ReceivesNewFrames_IncrementsFrameCounters', () {
    PacketWrapper p = PacketWrapper((GameStateUpdates()
      ..lastFrameSeen = 10
      ..frame = 2).writeToBuffer());
    connection.receiveData(p);

    expect(connection.lastSeenRemoteFrame, equals(2));
    expect(connection.lastDeliveredFrame, equals(10));
  });

  test('SendPingGetReply_setsLatency', () {
    connection.sendPing();

    Int64 expectedPing = Int64(fakeClock.now().millisecondsSinceEpoch);

    expect(testConnection.nativeBufferedDataAt(0), equals(GameStateUpdates()
      ..lastFrameSeen = 0
      ..stateUpdate.add(StateUpdate()..ping = expectedPing)));

    fakeClock.testTime = DateTime.fromMillisecondsSinceEpoch(
        fakeClock.testTime.millisecondsSinceEpoch + 500);

    PacketWrapper p = PacketWrapper((GameStateUpdates()
      ..lastFrameSeen = 1
      ..frame = 2
      ..stateUpdate.add(StateUpdate()..pong = expectedPing)).writeToBuffer());
    connection.receiveData(p);

    expect(connection.expectedLatency(), Duration(milliseconds: 500));
  });

  test('SpriteDataNoKeyFrame_ignoresIt', () {
    SpriteUpdate spriteUpdate = SpriteUpdate()
      ..spriteId = 111;
    PacketWrapper p = PacketWrapper((GameStateUpdates()
       ..spriteUpdates.add(spriteUpdate)
      ..lastFrameSeen = 10
      ..frame = 2).writeToBuffer());
    connection.setHandshakeReceived();
    connection.receiveData(p);

    verifyNever(mockNetwork.parseBundle(any, any));
  });

  test('SpriteDataWithFirstKeyFrame_handlesIt', () {
    SpriteUpdate spriteUpdate = SpriteUpdate()
      ..spriteId = 111;
    GameStateUpdates g = GameStateUpdates()
      ..keyFrame = 1
      ..spriteUpdates.add(spriteUpdate)
      ..lastFrameSeen = 10
      ..frame = 2;
    PacketWrapper p = PacketWrapper(g.writeToBuffer());
    connection.setHandshakeReceived();
    connection.receiveData(p);

    verify(mockNetwork.parseBundle(connection, g));
  });

  test('OldSpriteData_isIgnored', () {
    SpriteUpdate spriteUpdate = SpriteUpdate()
      ..spriteId = 111;
    GameStateUpdates g = GameStateUpdates()
      ..keyFrame = 1
      ..spriteUpdates.add(spriteUpdate)
      ..lastFrameSeen = 10
      ..frame = 2;
    PacketWrapper p = PacketWrapper(g.writeToBuffer());
    connection.setHandshakeReceived();

    connection.receiveData(p);
    g.frame = g.frame - 1;
    connection.receiveData(p);

    // Old data wasn't handled.
    verifyNever(mockNetwork.parseBundle(connection, g));
  });

  test('TicConnection_IncrementsFrameCounters', () {
    connection.setHandshakeReceived();
    connection.tick(0.01, []);

    expect(testConnection.nativeBufferedDataAt(0), equals(GameStateUpdates()
       ..frame = 0
       ..lastFrameSeen = 0
       ..keyFrame = 0));

    connection.tick(KEY_FRAME_DEFAULT + 0.1, []);

    expect(testConnection.dataBuffer.length, 2);
    expect(testConnection.nativeBufferedDataAt(1), equals(GameStateUpdates()
      ..frame = 1
      ..lastFrameSeen = 0
      ..keyFrame = 1));
    expect(connection.lastSentFrameTime, equals(fakeClock.testTime));
  });

  test('TickConnection_sendsPingDueToInactivity', () {
    // Long time ago!
    fakeClock.testTime = DateTime.fromMillisecondsSinceEpoch(fakeClock.testTime.millisecondsSinceEpoch +
        ConnectionWrapper.KEEP_ALIVE_DURATION.inMilliseconds + 1);
    connection.tick(0.1, []);

    Int64 time = Int64(fakeClock.now().millisecondsSinceEpoch);
    expect(testConnection.nativeBufferedDataAt(0), equals(GameStateUpdates()
      ..lastFrameSeen = 0
      ..stateUpdate.add(StateUpdate()..ping = time)));

  });

  test('TickConnection_incrementsFrameCount', () {
    // Long time ago!
    connection.setHandshakeReceived();
    connection.tick(ConnectionFrameHandler.BASE_FRAMERATE_INTERVAL + 0.001 , []);
    connection.tick(ConnectionFrameHandler.BASE_FRAMERATE_INTERVAL + 0.001 , []);
    connection.tick(ConnectionFrameHandler.BASE_FRAMERATE_INTERVAL + 0.001 , []);

    expect(testConnection.dataBuffer.length, 3);

    expect(testConnection.nativeBufferedDataAt(0), equals(GameStateUpdates()
      ..frame = 0
      ..lastFrameSeen = 0
      ..keyFrame = 0));

    expect(testConnection.nativeBufferedDataAt(1), equals(GameStateUpdates()
      ..frame = 1
      ..lastFrameSeen = 0));

    expect(testConnection.nativeBufferedDataAt(2), equals(GameStateUpdates()
      ..frame = 2
      ..lastFrameSeen = 0));

    expect(connection.recipientFramesBehind(), 2);
  });

  test('TickConnectionWithRemovals_alwaysSent', () {
    connection.setHandshakeReceived();

    connection.tick(0.001, []);
    // Removal always sent immediately.
    connection.tick(0.001 , [134]);

    expect(testConnection.dataBuffer.length, 2);

    expect(testConnection.nativeBufferedDataAt(1), equals(GameStateUpdates()
      ..frame = 1
      ..lastFrameSeen = 0
    ..stateUpdate.add(StateUpdate()
        ..dataReceipt = 91834543
        ..spriteRemoval = 134)));
  });

  test('TestConnectionFrameHandler', () {
    ConnectionFrameHandler handler = new ConnectionFrameHandler(new ConfigParams({}));
    expect(handler.tick(0.00001), isTrue);
    expect(handler.keyFrame(), isTrue);
    expect(handler.currentKeyFrame(), 0);

    expect(handler.tick(0.00001), isFalse);
    expect(handler.keyFrame(), isFalse);

    expect(handler.tick(0.1), isTrue);
    expect(handler.keyFrame(), isFalse);

    expect(handler.tick(ConnectionFrameHandler.BASE_KEY_FRAME_RATE_INTERVAL), isTrue);
    expect(handler.keyFrame(), isTrue);
    expect(handler.currentKeyFrame(), 1);
  });

  test('TestConnectionFrameHandlerAdjustFrameRate', () {
    ConnectionFrameHandler handler =
        new ConnectionFrameHandler(new ConfigParams({}));
    expect(handler.currentFrameRate(), ConnectionFrameHandler.MAX_FRAMERATE);

    handler.reportFrameRates(99.0, 88.0);
    expect(handler.currentFrameRate(), ConnectionFrameHandler.MAX_FRAMERATE);

    handler.reportFrameRates(1.0, 88.0);
    expect(handler.currentFrameRate(), ConnectionFrameHandler.MIN_FRAMERATE);

    handler.reportFrameRates(98.0, 30.0);
    expect(handler.currentFrameRate(), 9);

    handler.reportFrameRates(98.0, 25.0);
    expect(handler.currentFrameRate(), 7);
  });
}
