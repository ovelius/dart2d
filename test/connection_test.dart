import 'package:clock/clock.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/util/util.dart';
import 'package:mockito/mockito.dart';
import 'dart:convert';
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
    when(mockNetwork.getPeer()).thenReturn(MockPeerWrapper());
    when(mockNetwork.isCommander()).thenReturn(false);
    mockHudMessages = new MockHudMessages();
    testConfigParams = new ConfigParams({});
    packetListenerBindings = new PacketListenerBindings();
    testConnection = new TestConnection("a", null);
    testConnection.buffer = true;
    connection = new ConnectionWrapper(
        mockNetwork, mockHudMessages, "a", packetListenerBindings,
        testConfigParams, new ConnectionFrameHandler(new ConfigParams({})), fakeClock);
    connection.setRtcConnection(testConnection);
    connection.readyDataChannel(testConnection);
  });

  tearDown(() {
    assertNoLoggedWarnings();
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
    connection.receiveData(receipt.writeToBuffer());

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
    connection.receiveData(ackData.writeToBuffer());

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

  test('ReceivesNewFrames_IncrementsFrameCounters', () {
    connection.receiveData(
        (GameStateUpdates()
          ..lastFrameSeen = 10
          ..frame = 2).writeToBuffer());

    expect(connection.lastSeenRemoteFrame, equals(2));
    expect(connection.lastDeliveredFrame, equals(10));
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

  test('TicConnection_sendFrameAndSetsRttOnFeedback', () {
    connection.setHandshakeReceived();

    connection.tick(0.1, []);
    connection.tick(KEY_FRAME_DEFAULT + 0.1, []);

    expect(testConnection.nativeBufferedDataAt(1), equals(GameStateUpdates()
      ..frame = 1
      ..lastFrameSeen = 0
      ..keyFrame = 1));

    fakeClock.testTime = fakeClock.testTime.add(Duration(milliseconds: 10));

    GameStateUpdates ackData = GameStateUpdates()
      ..lastFrameSeen = 1
      ..stateUpdate.add(StateUpdate()..ackedDataReceipts = 123);
    connection.receiveData(ackData.writeToBuffer());

    expect(connection.expectedLatency(), Duration(milliseconds: 10));
  });


  test('TestLeakyBucket', () {
    LeakyBucket leakyBucket = new LeakyBucket(1);
    expect(leakyBucket.removeTokens(1), isTrue);
    sleep(new Duration(milliseconds: 10));
    expect(leakyBucket.removeTokens(10), isTrue);
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
    handler.reportFramesBehind(1, 1);
    expect(handler.currentFrameRate(), ConnectionFrameHandler.MAX_FRAMERATE);
    handler.reportFramesBehind(2, 1);
    expect(handler.currentFrameRate(), ConnectionFrameHandler.MAX_FRAMERATE - 2);
    handler.reportFramesBehind(3, 1);
    expect(handler.currentFrameRate(), ConnectionFrameHandler.MAX_FRAMERATE - 5);

    // Now pretend we are stable.
    for (int i = 0; i < ConnectionFrameHandler.STABLE_FRAME_RATE_TUNING_INTERVAL; i++) {
      handler.reportFramesBehind(1, 0);
    }
    handler.reportFramesBehind(1, 0);
    // We increased the framerate again.
    expect(handler.currentFrameRate(), ConnectionFrameHandler.MAX_FRAMERATE - 4);
  });
}
