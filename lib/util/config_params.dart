import 'package:dart2d/bindings/annotations.dart';
import 'package:injectable/injectable.dart';

enum ConfigParam {
  MAX_FRAGS,
  EXPLICIT_PEERS,
  BOT_ENABLED,
  INGRESS_BANDWIDTH,
  EGRESS_BANDWIDTH,
  DISABLE_CACHE,
  MAX_NETWORK_FRAMERATE,
  BLOOD,
}

@Singleton(scope: 'world')
class ConfigParams {
  static Map<ConfigParam, String> _names = {
    ConfigParam.MAX_FRAGS: "maxFrags",
    ConfigParam.EXPLICIT_PEERS: "connectTo",
    ConfigParam.BOT_ENABLED: "bot",
    // Ingress bandwidth in kB/s.
    ConfigParam.INGRESS_BANDWIDTH: "ingress",
    // Egress bandwidth in kB/s.
    ConfigParam.EGRESS_BANDWIDTH: "egress",
    // Disabled explicit image caching.
    ConfigParam.DISABLE_CACHE: "nocache",
    ConfigParam.BLOOD: "blood",
    // How often to send data to network.
    ConfigParam.MAX_NETWORK_FRAMERATE: "max_net_frame",
  };
  static Map<ConfigParam, dynamic> _defaults = {
    ConfigParam.MAX_FRAGS: 10,
    ConfigParam.EXPLICIT_PEERS: [],
    ConfigParam.BOT_ENABLED: "",
    ConfigParam.INGRESS_BANDWIDTH: -1,
    ConfigParam.EGRESS_BANDWIDTH: -1,
    ConfigParam.DISABLE_CACHE: false,
    ConfigParam.BLOOD: -1,
    ConfigParam.MAX_NETWORK_FRAMERATE: -1,
  };

  late Map<String, List<String>> _uriParams;

  ConfigParams(@Named(URI_PARAMS_MAP) Map<String, List<String>> _uriParams) {
    this._uriParams = _uriParams;
  }

  int getInt(ConfigParam p) {
    List<String>? data = _uriParams[_names[p]];
    if (data != null && data.length > 0 && data[0].isNotEmpty) {
      return int.parse(data[0]);
    }
    return _defaults[p]!;
  }

  String getString(ConfigParam p) {
    List<String>? data = _uriParams[_names[p]];
    if (data != null && data.length > 0 && data[0].isNotEmpty) {
      return data[0];
    }
    return _defaults[p];
  }

  List<String> getStringList(ConfigParam p) {
    List<String>? data = _uriParams[_names[p]];
    if (data != null && data.length > 0 && data[0].isNotEmpty) {
      return data;
    }
    return List<String>.from(_defaults[p]);
  }

  bool getBool(ConfigParam p) {
    List<String>? data = _uriParams[_names[p]];
    if (data != null && data.length > 0) {
      return true;
    }
    return _defaults[p];
  }
}