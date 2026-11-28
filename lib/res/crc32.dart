import 'dart:convert';
import 'dart:typed_data';

const String PNG_DATA_URL_PREFIX = 'data:image/png;base64,';

final Uint32List _crc32Table = _buildCrc32Table();

Uint32List _buildCrc32Table() {
  final Uint32List table = Uint32List(256);
  for (int i = 0; i < 256; i++) {
    int c = i;
    for (int j = 0; j < 8; j++) {
      if ((c & 1) != 0) {
        c = 0xEDB88320 ^ (c >>> 1);
      } else {
        c = c >>> 1;
      }
    }
    table[i] = c;
  }
  return table;
}

/// Computes the standard IEEE 802.3 unsigned 32-bit CRC32 of [bytes].
int crc32Bytes(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (int i = 0; i < bytes.length; i++) {
    crc = _crc32Table[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Decodes a `data:image/png;base64,...` string and returns the CRC32 of its
/// raw PNG bytes, or `null` if the prefix or base64 payload is invalid.
int? crc32FromPngDataUrl(String dataUrl) {
  return crc32FromDataUrl(dataUrl, PNG_DATA_URL_PREFIX);
}

/// Decodes a base64 `data:` URL starting with [requiredPrefix] and returns the
/// CRC32 of its raw bytes, or `null` if invalid.
int? crc32FromDataUrl(String dataUrl, [String requiredPrefix = 'data:']) {
  if (!dataUrl.startsWith(requiredPrefix)) {
    return null;
  }
  final int marker = dataUrl.indexOf(';base64,');
  if (marker < 0) {
    return null;
  }
  try {
    final Uint8List bytes =
        base64Decode(dataUrl.substring(marker + ';base64,'.length));
    return crc32Bytes(bytes);
  } on FormatException {
    return null;
  }
}
