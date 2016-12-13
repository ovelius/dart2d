import 'package:dart2d/net/rtc.dart';
import 'dart:js';

class PeerWrapperCallbacks {
  void registerPeerCallbacks(var jsPeer, PeerWrapper wrapper) {
    jsPeer.callMethod(
        'on',
        new JsObject.jsify(
            ['open', new JsFunction.withThis(wrapper.openPeer)]));
    jsPeer.callMethod(
        'on',
        new JsObject.jsify([
          'receiveActivePeers',
          new JsFunction.withThis(wrapper.receivePeers)
        ]));
    jsPeer.callMethod(
        'on',
        new JsObject.jsify(
            ['connection', new JsFunction.withThis(wrapper.connectPeer)]));
    jsPeer.callMethod('on',
        new JsObject.jsify(['error', new JsFunction.withThis(wrapper.error)]));
  }

  dynamic connectToPeer(var jsPeer, string id) {
    var metaData = new JsObject.jsify({
      'label': 'dart2d',
      'reliable': 'false',
      'metadata': {},
      'serialization': 'none',
    });
    return jsPeer.callMethod('connect', [id, metaData]);
  }
}
