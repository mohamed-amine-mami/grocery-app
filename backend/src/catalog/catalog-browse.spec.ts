import { BadRequestException } from '@nestjs/common';
import {
  decodeCursor,
  encodeCursor,
  foldSearchText,
  FOLD_FROM,
  FOLD_TO,
  searchTerms,
} from './catalog-browse.js';

describe('foldSearchText', () => {
  it('has a one-to-one fold table', () => {
    // All characters are in the BMP, so length counts characters.
    expect(FOLD_FROM).toHaveLength(FOLD_TO.length);
  });

  it('lower-cases, removes accents and collapses spaces', () => {
    expect(foldSearchText('  Crème   FRAÎCHE ')).toBe('creme fraiche');
    expect(foldSearchText('Épicerie')).toBe('epicerie');
    expect(foldSearchText('Ça')).toBe('ca');
  });

  it('expands ligatures to two letters', () => {
    expect(foldSearchText('Œufs')).toBe('oeufs');
    expect(foldSearchText('œuf')).toBe('oeuf');
    expect(foldSearchText('Cæsar')).toBe('caesar');
  });

  it('leaves digits, punctuation and other letters alone', () => {
    expect(foldSearchText('Lait 1/2 écrémé 1 L')).toBe('lait 1/2 ecreme 1 l');
  });
});

describe('searchTerms', () => {
  it('splits on whitespace and drops empties', () => {
    expect(searchTerms('  Œufs   frais ')).toEqual(['oeufs', 'frais']);
  });

  it('has no term for a blank or missing query', () => {
    expect(searchTerms(undefined)).toEqual([]);
    expect(searchTerms('   ')).toEqual([]);
  });
});

describe('cursor', () => {
  it('round-trips', () => {
    const cursor = { key: 'creme fraiche 20 cl', id: 4217 };
    expect(decodeCursor(encodeCursor(cursor))).toEqual(cursor);
  });

  it('is url-safe', () => {
    expect(encodeCursor({ key: 'a/b+c?', id: 1 })).toMatch(/^[A-Za-z0-9_-]+$/);
  });

  const raw = (value: unknown) =>
    Buffer.from(JSON.stringify(value)).toString('base64url');

  it('accepts the largest integer id', () => {
    expect(decodeCursor(raw({ k: 'a', i: 2_147_483_647 }))).toEqual({
      key: 'a',
      id: 2_147_483_647,
    });
  });

  it('accepts an empty key and a long key', () => {
    expect(decodeCursor(raw({ k: '', i: 1 }))).toEqual({ key: '', id: 1 });
    expect(decodeCursor(raw({ k: 'x'.repeat(250), i: 1 })).key).toHaveLength(
      250,
    );
  });

  it.each([
    ['an id above the integer range', raw({ k: 'a', i: 2_147_483_648 })],
    ['a huge id', raw({ k: 'a', i: 9_007_199_254_740_991 })],
    ['a negative id', raw({ k: 'a', i: -1 })],
    ['a key with a NUL byte', raw({ k: 'a\u0000b', i: 1 })],
    ['a key that is only a NUL byte', raw({ k: '\u0000', i: 1 })],
  ])('rejects %s', (_label, value) => {
    expect(() => decodeCursor(value)).toThrow(BadRequestException);
  });

  it.each([
    ['not base64 json', '%%%'],
    [
      'json of the wrong shape',
      Buffer.from('{"k":1,"i":"x"}').toString('base64url'),
    ],
    ['a non-positive id', Buffer.from('{"k":"a","i":0}').toString('base64url')],
    ['a fractional id', Buffer.from('{"k":"a","i":1.5}').toString('base64url')],
    ['an array', Buffer.from('[1,2]').toString('base64url')],
  ])('rejects %s', (_label, raw) => {
    expect(() => decodeCursor(raw)).toThrow(BadRequestException);
  });
});
