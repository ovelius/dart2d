import 'package:dart2d/net/net.dart';

abstract class JsCallbacksWrapper {
  void bindOnFunction(var jsObject, String methodName, dynamic callback);
  void callJsMethod(var jsObject, String methodName);
  dynamic connectToPeer(var jsPeer, String id);
}
