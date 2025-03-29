import 'package:logging/logging.dart' show Logger, Level, LogRecord;

Map<Level, List<String>> _logged = {};
List<String> _expected = [];

logOutputForTest() {
  _logged.clear();
  _expected.clear();
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    String msg = '${rec.loggerName}: ${rec.level.name}: ${rec.time}: ${rec.message}';
    bool expectedWarning = false;
    if (rec.level >= Level.WARNING) {
      for (String expected in _expected) {
        if (rec.message.contains(expected)) {
          expectedWarning = true;
        }
      }
    }
    if (!expectedWarning) {
      if (!_logged.containsKey(rec.level)) {
        _logged[rec.level] = [];
      }
      _logged[rec.level]!.add(msg);
    }
    print(msg);
  });
}

assertNoLoggedWarnings() {
  if (_logged.containsKey(Level.WARNING)) {
    throw new StateError("Logged warning when shouldn't! ${_logged[Level.WARNING]}. Use expectWarningContaining() if expected!");
  }
  if (_logged.containsKey(Level.SEVERE)) {
    throw new StateError("Logged severe but no warning! ${_logged[Level.SEVERE]}!");
  }
  _expected.clear();
}

expectWarningContaining(String msg) {
  _expected.add(msg);
}

