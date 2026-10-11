import { BadRequestException } from '@nestjs/common';
import { INT4_MAX } from './dto/browse-catalog.query.js';

/**
 * Search folding and paging cursor for `GET /owner/catalog/browse`.
 *
 * French product names carry accents and ligatures ("Œufs", "Crème"), and
 * people rarely type them: `oeuf` must find `Œufs`. The same folding runs in
 * SQL (over name / brand / category) and in TypeScript (over the typed words),
 * so both sides always agree. The mobile app's `SearchText.fold` is the same
 * table.
 */
export const FOLD_FROM = 'ÀÁÂÄÇÈÉÊËÍÎÏÑÓÔÖÙÚÛÜàáâäçèéêëíîïñóôöùúûüÿ';
export const FOLD_TO = 'aaaaceeeeiiinooouuuuaaaaceeeeiiinooouuuuy';

/** Ligatures fold to two letters, which `translate` cannot express. */
const LIGATURES: ReadonlyArray<readonly [string, string]> = [
  ['Œ', 'oe'],
  ['œ', 'oe'],
  ['Æ', 'ae'],
  ['æ', 'ae'],
];

/** Lower-cased, accents removed, runs of whitespace collapsed. */
export function foldSearchText(text: string): string {
  let out = text;
  for (const [from, to] of LIGATURES) out = out.replaceAll(from, to);
  let folded = '';
  for (const char of out) {
    const at = FOLD_FROM.indexOf(char);
    folded += at === -1 ? char : FOLD_TO[at];
  }
  return folded.toLowerCase().trim().replace(/\s+/g, ' ');
}

/** The words a product must all contain, folded; an empty search has none. */
export function searchTerms(q: string | undefined): string[] {
  return q === undefined ? [] : foldSearchText(q).split(' ').filter(Boolean);
}

export interface CatalogCursor {
  /** The folded sort key of the last row of the previous page. */
  key: string;
  /** Its id: the tie-break that makes the order total. */
  id: number;
}

/** Opaque to clients: base64url of `{ k, i }`. */
export function encodeCursor(cursor: CatalogCursor): string {
  return Buffer.from(JSON.stringify({ k: cursor.key, i: cursor.id })).toString(
    'base64url',
  );
}

export function decodeCursor(raw: string): CatalogCursor {
  try {
    const parsed: unknown = JSON.parse(
      Buffer.from(raw, 'base64url').toString('utf8'),
    );
    if (
      typeof parsed === 'object' &&
      parsed !== null &&
      'k' in parsed &&
      'i' in parsed &&
      typeof parsed.k === 'string' &&
      typeof parsed.i === 'number' &&
      Number.isInteger(parsed.i) &&
      parsed.i > 0 &&
      // A product id is a PostgreSQL `integer`; a text value cannot hold NUL.
      parsed.i <= INT4_MAX &&
      !parsed.k.includes('\u0000')
    ) {
      return { key: parsed.k, id: parsed.i };
    }
  } catch {
    // Falls through to the 400 below.
  }
  throw new BadRequestException('cursor is not valid');
}
