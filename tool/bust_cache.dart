import 'dart:io';

/// Appends a content-hash query parameter (`?v=<hash>`) to `wormworld.dart.js`
/// in `build/wormworld.html` so browsers fetch the new JS bundle on deploy.
///
/// Usage: `dart run tool/bust_cache.dart [build_dir]`
void main(List<String> args) {
  final String buildDir = args.isNotEmpty ? args[0] : 'build';
  final File jsFile = File('$buildDir/wormworld.dart.js');
  final File htmlFile = File('$buildDir/wormworld.html');

  if (!jsFile.existsSync()) {
    stderr.writeln('Error: ${jsFile.path} not found. Run build_runner first.');
    exit(1);
  }
  if (!htmlFile.existsSync()) {
    stderr.writeln('Error: ${htmlFile.path} not found.');
    exit(1);
  }

  final String hash = _fnv1a32Hex(jsFile.readAsBytesSync());
  final String html = htmlFile.readAsStringSync();
  final RegExp pattern = RegExp(r'wormworld\.dart\.js(?:\?v=[0-9a-f]+)?');

  if (!pattern.hasMatch(html)) {
    stderr.writeln('Error: wormworld.dart.js reference not found in ${htmlFile.path}.');
    exit(1);
  }

  final String updated = html.replaceAll(pattern, 'wormworld.dart.js?v=$hash');
  htmlFile.writeAsStringSync(updated);
  stdout.writeln('Updated ${htmlFile.path} -> wormworld.dart.js?v=$hash');
}

String _fnv1a32Hex(List<int> bytes) {
  int hash = 0x811c9dc5;
  for (final int b in bytes) {
    hash ^= b;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
