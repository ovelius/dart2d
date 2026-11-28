import 'dart:io';

import 'package:dart2d/res/crc32.dart';

/// Regenerates `lib/res/sound_hashes.dart` from the audio files in `web/snd/`.
///
/// Run with: `dart run tool/generate_sound_hashes.dart`
void main() {
  final Directory sndDir = Directory('web/snd');
  if (!sndDir.existsSync()) {
    stderr.writeln('Error: web/snd directory not found. Run from repo root.');
    exitCode = 1;
    return;
  }

  // Keep in sync with Sound enum URLs in lib/res/sounds.dart.
  final File soundsFile = File('lib/res/sounds.dart');
  final RegExp urlRegex = RegExp(r'\("([^"]+)"\)');
  final Set<String> soundNames = <String>{};
  for (final Match m in urlRegex.allMatches(soundsFile.readAsStringSync())) {
    final String url = m.group(1)!;
    if (url != 'silenece.ogg') {
      soundNames.add(url);
    }
  }

  final List<String> sortedNames = soundNames.toList()..sort();
  final StringBuffer out = StringBuffer()
    ..writeln('// GENERATED FILE - DO NOT EDIT BY HAND.')
    ..writeln('// Regenerate with: dart run tool/generate_sound_hashes.dart')
    ..writeln('')
    ..writeln('/// Precomputed IEEE 802.3 CRC32 hashes of raw audio files in `web/snd/`.')
    ..writeln('const Map<String, int> SOUND_CRC32_HASHES = <String, int>{');

  for (final String name in sortedNames) {
    final File file = File('web/snd/$name');
    if (!file.existsSync()) {
      stderr.writeln('Error: missing sound asset file ${file.path}');
      exitCode = 1;
      return;
    }
    final int hash = crc32Bytes(file.readAsBytesSync());
    final String hex = '0x${hash.toRadixString(16).padLeft(8, '0').toUpperCase()}';
    out.writeln("  '$name': $hex,");
  }
  out.writeln('};');

  File('lib/res/sound_hashes.dart').writeAsStringSync(out.toString());
  stdout.writeln('Wrote lib/res/sound_hashes.dart (${sortedNames.length} sounds).');
}
