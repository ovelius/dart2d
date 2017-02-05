import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/net/net.dart';
import 'dart:convert';
import 'package:mockito/mockito.dart';

void main() {
  MockNetwork mockNetwork;
  MockHudMessages mockHudMessages;
  MockJsCallbacksWrapper mockJsCallbacksWrapper;
  PacketListenerBindings packetListenerBindings;
  ConnectionWrapper connection;
  TestConnection testConnection;

  setUp(() {
    logOutputForTest();
    remapKeyNamesForTest();
    mockNetwork = new MockNetwork();
    when(mockNetwork.getPeer()).thenReturn(new Mock());
    when(mockNetwork.isCommander()).thenReturn(false);
    mockHudMessages = new MockHudMessages();
    mockJsCallbacksWrapper = new MockJsCallbacksWrapper();
    packetListenerBindings = new PacketListenerBindings();
    testConnection = new TestConnection("a");
    testConnection.buffer = true;
    connection = new ConnectionWrapper(mockNetwork, mockHudMessages, "a",
        testConnection, packetListenerBindings, mockJsCallbacksWrapper);
  });

  tearDown(() {
    assertNoLoggedWarnings();
  });

  test('TestReliableDataSend', () {
    String reliableKey = RELIABLE_KEYS.keys.first;
    connection.sendData({
      reliableKey: ["test"]
    });
    expect(
        testConnection.nativeBufferedDataAt(0),
        equals({
          reliableKey: ['test'],
          KEY_FRAME_KEY: 0
        }));
    expect(connection.keyFrameData, equals({reliableKey: ['test']}));

    connection.receiveData(null, JSON.encode({KEY_FRAME_KEY: 1}));

    expect(connection.keyFrameData, equals({}));
  });

  test('TestReliableDataReSend', () {
    String reliableKey = RELIABLE_KEYS.keys.first;
    connection.sendData({
      reliableKey: ["test"]
    });
    expect(
        testConnection.nativeBufferedDataAt(0),
        equals({
          reliableKey: ['test'],
          KEY_FRAME_KEY: 0
        }));
    connection.sendData({
      IS_KEY_FRAME_KEY: 2,
    });

    // Data got added again.
    expect(
        testConnection.nativeBufferedDataAt(0),
        equals({
          reliableKey: ['test'],
          KEY_FRAME_KEY: 0
        }));
  });
}
