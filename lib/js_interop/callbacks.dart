import 'package:dart2d/net/rtc.dart';

abstract class JsCallbacksWrapper {
  void bindOnFunction(var jsObject, String methodName, dynamic callback);
  dynamic connectToPeer(var jsPeer, String id);
}
