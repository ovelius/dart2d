import 'dart:io';

import 'package:dart2d/res/crc32.dart';
import 'package:dart2d/worlds/world_data.dart';

/// Regenerates `lib/res/image_hashes.dart` from the PNG files in `web/img/`.
///
/// Run with: `dart run tool/generate_image_hashes.dart`
void main() {
  final Directory imgDir = Directory('web/img');
  if (!imgDir.existsSync()) {
    stderr.writeln('Error: web/img directory not found. Run from repo root.');
    exitCode = 1;
    return;
  }

  // Keep in sync with PLAYER_SOURCES, GAME_SOURCES, WORLD_SOURCES, and WORLDS.values.
  final Set<String> assetNames = <String>{
    // PLAYER_SOURCES
    'lion88.png',
    'sheep98.png',
    'sheep_black58.png',
    'ele96.png',
    'donkey98.png',
    'goat93.png',
    'cock77.png',
    'dra98.png',
    'turtle96.png',
    // GAME_SOURCES
    'cake.png',
    'banana.png',
    'dart.png',
    'shield.png',
    'powerup.png',
    'powerup_swiwel.png',
    'soda.png',
    'snails.png',
    'shieldi02.png',
    'health02.png',
    'weapon_icons.png',
    'zooka.png',
    'box.png',
    'gun.png',
    'shark.png',
    // WORLD_SOURCES (thumbnails) & full-size maps
    ...WORLDS.keys,
    ...WORLDS.values,
  };

  final List<String> sortedNames = assetNames.toList()..sort();
  final StringBuffer out = StringBuffer()
    ..writeln('// GENERATED FILE - DO NOT EDIT BY HAND.')
    ..writeln('// Regenerate with: dart run tool/generate_image_hashes.dart')
    ..writeln('')
    ..writeln('/// Precomputed IEEE 802.3 CRC32 hashes of raw PNG files in `web/img/`.')
    ..writeln('const Map<String, int> IMAGE_CRC32_HASHES = <String, int>{');

  for (final String name in sortedNames) {
    final File file = File('web/img/$name');
    if (!file.existsSync()) {
      stderr.writeln('Error: missing asset file ${file.path}');
      exitCode = 1;
      return;
    }
    final int hash = crc32Bytes(file.readAsBytesSync());
    final String hex = '0x${hash.toRadixString(16).padLeft(8, '0').toUpperCase()}';
    out.writeln("  '$name': $hex,");
  }
  out.writeln('};');

  File('lib/res/image_hashes.dart').writeAsStringSync(out.toString());
  stdout.writeln('Wrote lib/res/image_hashes.dart (${sortedNames.length} images).');
}
