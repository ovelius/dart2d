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

void main() {
  late MockNetwork mockNetwork;
  late ConfigParams testConfigParams;
  late MockHudMessages mockHudMessages;
  late PacketListenerBindings packetListenerBindings;
  late ConnectionWrapper connection;
  late TestConnection testConnection;


  setUp(() {
    logOutputForTest();
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
        testConfigParams, new ConnectionFrameHandler(new ConfigParams({})), Clock());
    connection.setRtcConnection(testConnection);
    connection.readyDataChannel(testConnection);
  });

  tearDown(() {
    assertNoLoggedWarnings();
  });

  test('TestReliableDataSend', () {
    GameStateUpdates data = GameStateUpdates()
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

    expectWarningContaining("Data receipt 123456789");
    GameStateUpdates receipt = GameStateUpdates()
      ..stateUpdate.add(StateUpdate()..dataReceipt = 123);
    connection.receiveData(receipt.writeToBuffer());

    expect(connection.reliableHelper().reliableDataBuffer, equals({}));
  });

  /*
  test('TestReliableDataReSend', () {
    connection.sendData({
      REMOVE_KEY: [1, 2]
    });
    expect(
        testConnection.nativeBufferedDataAt(0),
        equals({
          REMOVE_KEY: [1, 2],
          KEY_FRAME_KEY: 0,
          CONTAINED_DATA_RECEIPTS: [613796826],
        }));
    connection.sendData({
      IS_KEY_FRAME_KEY: 2,
      REMOVE_KEY: [3],
      CLIENT_PLAYER_SPEC: "test client",
    });

    // Data got added again.
    expect(
        testConnection.nativeBufferedDataAt(1),
        equals({
          REMOVE_KEY: [3, 1, 2],
          IS_KEY_FRAME_KEY: 2,
          CLIENT_PLAYER_SPEC: "test client",
          KEY_FRAME_KEY: 0,
          CONTAINED_DATA_RECEIPTS: [325444850, 560726420, 613796826]
        }));

    expect(
        connection.reliableHelper().reliableDataBuffer,
        equals({
          325444850: [
            REMOVE_KEY,
            [3]
          ],
          613796826: [
            REMOVE_KEY,
            [1, 2]
          ],
          560726420: [CLIENT_PLAYER_SPEC, 'test client']
        }));

    connection.sendData({
      IS_KEY_FRAME_KEY: 2,
    });

    // Data got added yet again.
    expect(
        testConnection.nativeBufferedDataAt(2),
        equals({
          REMOVE_KEY: [1, 2, 3],
          IS_KEY_FRAME_KEY: 2,
          CLIENT_PLAYER_SPEC: "test client",
          KEY_FRAME_KEY: 0,
          CONTAINED_DATA_RECEIPTS: [613796826, 325444850, 560726420],
        }));
  });

  test('TestReceiveReliableDataAndSendVerification', () {
    String reliableKey = RELIABLE_KEYS.keys.first;
    packetListenerBindings.bindHandler(
        reliableKey, (ConnectionWrapper c, Object o) {});
    connection.receiveData(jsonEncode({
      KEY_FRAME_KEY: 0,
      reliableKey: "test",
      CONTAINED_DATA_RECEIPTS: [123, 456]
    }));

    List expected = [123, 456];
    expect(connection.reliableHelper().reliableDataToVerify, equals(expected));

    connection.sendData({KEY_FRAME_KEY: 0});

    expect(testConnection.nativeBufferedDataAt(0),
        equals({DATA_RECEIPTS: expected, KEY_FRAME_KEY: 0}));
  });

  test('TestTickConnect', () {
    connection.setHandshakeReceived();
    connection.tick(0.01, {}, {}, []);

    expect(testConnection.nativeBufferedDataAt(0), equals({IS_KEY_FRAME_KEY: 0, KEY_FRAME_KEY: 0}));

    connection.tick(KEY_FRAME_DEFAULT + 0.1, {}, {}, []);

    expect(testConnection.dataBuffer.length, 2);
    expect(testConnection.nativeBufferedDataAt(1), equals({IS_KEY_FRAME_KEY: 1, KEY_FRAME_KEY: 0}));
  });

  test('TestKeyFrameAck', () {
    connection.setHandshakeReceived();
    connection.receiveData(jsonEncode({KEY_FRAME_KEY: 10, IS_KEY_FRAME_KEY: 99}));
    expect(connection.lastRemoteKeyFrame, equals(99));
    expect(connection.lastDeliveredKeyFrame, equals(10));
    connection.sendData({});

    Map receivedData = testConnection.nativeBufferedDataAt(0);
    receivedData.remove(KEY_FRAME_DELAY);
    expect(receivedData, equals({KEY_FRAME_KEY: 99}));
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
  }); */
}
