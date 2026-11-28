import 'dart:io';

/// Appends `?v=<PROTOCOL_VERSION>` to `wormworld.dart.js` in
/// `build/wormworld.html`, reading `PROTOCOL_VERSION` from
/// `lib/util/gamestate.dart`.
///
/// Usage: `dart run tool/bust_cache.dart [build_dir]`
void main(List<String> args) {
  final String buildDir = args.isNotEmpty ? args[0] : 'build';
  final File gameStateFile = File('lib/util/gamestate.dart');
  final File htmlFile = File('$buildDir/wormworld.html');

  if (!gameStateFile.existsSync()) {
    stderr.writeln('Error: ${gameStateFile.path} not found.');
    exit(1);
  }
  if (!htmlFile.existsSync()) {
    stderr.writeln('Error: ${htmlFile.path} not found.');
    exit(1);
  }

  final RegExp versionRegex =
      RegExp(r'static\s+const\s+int\s+PROTOCOL_VERSION\s*=\s*(\d+)\s*;');
  final Match? match =
      versionRegex.firstMatch(gameStateFile.readAsStringSync());
  if (match == null) {
    stderr.writeln(
        'Error: PROTOCOL_VERSION not found in ${gameStateFile.path}.');
    exit(1);
  }
  final String version = match.group(1)!;

  final String html = htmlFile.readAsStringSync();
  final RegExp pattern = RegExp(r'wormworld\.dart\.js(?:\?v=[^\s"]+)?');

  if (!pattern.hasMatch(html)) {
    stderr.writeln('Error: wormworld.dart.js reference not found in ${htmlFile.path}.');
    exit(1);
  }

  final String updated = html.replaceAll(pattern, 'wormworld.dart.js?v=$version');
  htmlFile.writeAsStringSync(updated);
  stdout.writeln('Updated ${htmlFile.path} -> wormworld.dart.js?v=$version');
}
