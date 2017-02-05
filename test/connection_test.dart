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
    expect(
        connection.reliableDataBuffer,
        equals({
          743729159: [
            'remove_sprite',
            ['test']
          ]
        }));

    connection.receiveData(
        null,
        JSON.encode({
          KEY_FRAME_KEY: 1,
          DATA_RECEIPTS: [1, 2, 743729159]
        }));

    expect(connection.reliableDataBuffer, equals({}));
  });

  test('TestReliableDataReSend', () {
    connection.sendData({
      REMOVE_KEY: [1, 2]
    });
    expect(
        testConnection.nativeBufferedDataAt(0),
        equals({
          REMOVE_KEY: [1, 2],
          KEY_FRAME_KEY: 0
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
          KEY_FRAME_KEY: 0
        }));

    expect(connection.reliableDataBuffer, equals({
      726483626: [REMOVE_KEY, [3, 1, 2]],
      560726420: [CLIENT_PLAYER_SPEC, 'test client']
    }));

    connection.sendData({
      IS_KEY_FRAME_KEY: 2,
    });

    // Data got added yet again.
    expect(
        testConnection.nativeBufferedDataAt(2),
        equals({
          REMOVE_KEY: [3, 1, 2],
          IS_KEY_FRAME_KEY: 2,
          CLIENT_PLAYER_SPEC: "test client",
          KEY_FRAME_KEY: 0
        }));
  });

  test('TestReceiveReliableDataAndSendVerification', () {
    String reliableKey = RELIABLE_KEYS.keys.first;
    packetListenerBindings.bindHandler(reliableKey, (ConnectionWrapper c, Object o) {});
    connection.receiveData(null, JSON.encode({KEY_FRAME_KEY:0, reliableKey: "test"}));

    int expected = JSON.encode("test").hashCode;
    expect(connection.reliableDataToVerify, equals([expected]));

    connection.sendData({KEY_FRAME_KEY: 0});

    expect(
        testConnection.nativeBufferedDataAt(0),
        equals({
          DATA_RECEIPTS: [expected],
          KEY_FRAME_KEY: 0
        }));
  });
}
