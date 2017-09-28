import 'package:test/test.dart';
import 'lib/test_lib.dart';
import 'package:dart2d/net/net.dart';
import 'dart:convert';
import 'package:mockito/mockito.dart';

void main() {
  MockNetwork mockNetwork;
  MockHudMessages mockHudMessages;
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
    packetListenerBindings = new PacketListenerBindings();
    testConnection = new TestConnection("a", null);
    testConnection.buffer = true;
    connection = new ConnectionWrapper(mockNetwork, mockHudMessages, "a",
        packetListenerBindings);
    connection.setRtcConnection(testConnection);
    connection.readyDataChannel(testConnection);
  });

  tearDown(() {
    assertNoLoggedWarnings();
  });

  // No tests?
}
