import 'package:dart2d/bindings/annotations.dart';
import 'package:di/di.dart';

enum ConfigParam {
  MAX_FRAGS,
  EXPLICIT_PEERS,
}

@Injectable()
class ConfigParams {
  static Map<ConfigParam, String> _names = {
    ConfigParam.MAX_FRAGS: "maxFrags",
    ConfigParam.EXPLICIT_PEERS: "connectTo",
  };
  static Map<ConfigParam, Object> _defaults = {
    ConfigParam.MAX_FRAGS: 10,
    ConfigParam.EXPLICIT_PEERS: [],
  };

  Map<String, List<String>> _uriParams;
  ConfigParams(@UriParameters() Map _uriParams) {
    this._uriParams = _uriParams;
  }

  int getInt(ConfigParam p) {
    List<String> data = _uriParams[_names[p]];
    if (data.length > 0 && data[0].isNotEmpty) {
      return int.parse(data[0]);
    }
    return _defaults[p];
  }

  List<String> getStringList(ConfigParam p) {
    List<String> data = _uriParams[_names[p]];
    if (data.length > 0 && data[0].isNotEmpty) {
      return data;
    }
    return _defaults[p];
  }
}