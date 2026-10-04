import 'package:flutter_test/flutter_test.dart';

import 'package:grocery_mobile/ui/core/utils/search_text.dart';

void main() {
  group('SearchText.fold', () {
    test('lowercases and removes French accents', () {
      expect(SearchText.fold('Épicerie'), 'epicerie');
      expect(SearchText.fold('Crème fraîche'), 'creme fraiche');
      expect(SearchText.fold('Garçon à côté'), 'garcon a cote');
      expect(SearchText.fold('Noël, ça'), 'noel, ca');
    });

    test('expands the ligatures', () {
      expect(SearchText.fold('Œufs'), 'oeufs');
      expect(SearchText.fold('cœur'), 'coeur');
      expect(SearchText.fold('Æ'), 'ae');
    });

    test('collapses and trims whitespace', () {
      expect(SearchText.fold('  pomme   de  terre '), 'pomme de terre');
    });

    test('leaves digits and unrelated characters alone', () {
      expect(SearchText.fold('Lait 1,5 L'), 'lait 1,5 l');
    });

    test('handles the empty string', () {
      expect(SearchText.fold(''), '');
      expect(SearchText.fold('   '), '');
    });
  });

  group('SearchText.matches', () {
    test('an empty or blank query matches everything', () {
      expect(SearchText.matches('Tomate', ''), isTrue);
      expect(SearchText.matches('Tomate', '   '), isTrue);
    });

    test('ignores case and accents on both sides', () {
      expect(SearchText.matches('Œufs frais', 'OEUF'), isTrue);
      expect(SearchText.matches('Oeufs frais', 'œuf'), isTrue);
      expect(SearchText.matches('Épicerie', 'epic'), isTrue);
    });

    test('needs every word, in any order', () {
      expect(SearchText.matches('Pomme de terre', 'terre pomme'), isTrue);
      expect(SearchText.matches('Pomme', 'terre pomme'), isFalse);
    });

    test('matches inside a word, not only at its start', () {
      expect(SearchText.matches('Tomate cerise', 'mate'), isTrue);
    });

    test('rejects what is not there', () {
      expect(SearchText.matches('Tomate', 'banane'), isFalse);
    });
  });
}
