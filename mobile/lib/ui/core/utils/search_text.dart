/// Local-search helpers. French product names carry accents and ligatures
/// ("Œufs", "Épicerie", "Crème"), and people rarely type them: a search for
/// `oeuf` or `epicerie` must still find them.
abstract final class SearchText {
  static const _folds = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'í': 'i',
    'ô': 'o',
    'ö': 'o',
    'ó': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'ç': 'c',
    'ñ': 'n',
    'œ': 'oe',
    'æ': 'ae',
  };

  /// Lower-cased, accents removed, runs of whitespace collapsed.
  static String fold(String text) {
    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_folds[char] ?? char);
    }
    return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Whether [haystack] contains every word of [query], in any order, ignoring
  /// case and accents. An empty query matches everything.
  static bool matches(String haystack, String query) {
    final words = fold(query).split(' ').where((w) => w.isNotEmpty);
    final folded = fold(haystack);
    return words.every(folded.contains);
  }
}
