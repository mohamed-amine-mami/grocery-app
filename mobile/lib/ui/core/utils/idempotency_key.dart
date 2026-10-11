import 'dart:math';

/// Makes the key that identifies one order submission attempt: a random
/// version-4 UUID. A key is created when an attempt starts and reused for its
/// retries; it is never stored beyond the attempt.
typedef IdempotencyKeyGenerator = String Function();

String generateIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  String hex(int from, int to) => [
    for (final byte in bytes.sublist(from, to))
      byte.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
