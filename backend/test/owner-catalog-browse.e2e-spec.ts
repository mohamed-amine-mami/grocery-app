import request from 'supertest';
import { foldSearchText } from '../src/catalog/catalog-browse.js';
import { db } from '../src/prisma/db.js';
import {
  addTaggedProduct,
  archiveCategory,
  archiveProduct,
  removeCatalog,
  seedCatalog,
} from './catalog-helpers.js';
import {
  auth,
  http,
  register,
  registerOwnerWithStore,
  startApp,
  stopApp,
} from './support.js';

/**
 * `GET /owner/catalog/browse` and `GET /owner/catalog/products/:id`: the paged,
 * searchable catalog the owner picker uses. Every tagged name contains the tag,
 * so `q=<tag>` isolates a suite's rows in a database other suites share.
 */

const tag = `e2ebrowse${Date.now()}`;
let catalog: Awaited<ReturnType<typeof seedCatalog>>;

interface Item {
  id: number;
  slug: string;
  name: string;
  category: { id: number; slug: string; name: string };
  brand: { slug: string; name: string } | null;
  inMyStore: boolean;
  storeProductId: number | null;
  storeProductArchived: boolean;
}
interface Page {
  items: Item[];
  total: number;
  nextCursor: string | null;
}

const browse = (
  owner: Parameters<typeof auth>[0],
  query: Record<string, string | number> = {},
) =>
  request(http())
    .get('/owner/catalog/browse')
    .query({ q: tag, ...query })
    .set(auth(owner));

async function walk(
  owner: Parameters<typeof auth>[0],
  query: Record<string, string | number>,
): Promise<{ items: Item[]; pages: Page[] }> {
  const items: Item[] = [];
  const pages: Page[] = [];
  let cursor: string | null = null;
  do {
    const response = await browse(owner, {
      ...query,
      ...(cursor ? { cursor } : {}),
    }).expect(200);
    const page = response.body as Page;
    pages.push(page);
    items.push(...page.items);
    cursor = page.nextCursor;
    expect(pages.length).toBeLessThan(1000); // never loops
  } while (cursor);
  return { items, pages };
}

/** The order the API promises: folded name (C collation), then id. */
const expectedOrder = (rows: { id: number; name: string }[]) =>
  [...rows]
    .sort((a, b) => {
      const ka = foldSearchText(a.name);
      const kb = foldSearchText(b.name);
      return ka < kb ? -1 : ka > kb ? 1 : a.id - b.id;
    })
    .map((row) => row.id);

const BULK = 237;
const bulkIds: number[] = [];
const bulkRows: { id: number; name: string; brandKey: string | null }[] = [];

beforeAll(async () => {
  await startApp();
  catalog = await seedCatalog(tag);
  // A large result set: many ties on the name (told apart by brand, which the
  // database requires, and by id), accents, a ligature, and characters LIKE
  // would treat as wildcards. Six name families × five variants repeat every
  // 30 rows, and each repeat gets another brand (or none).
  const families = [
    (v: number) => `Pâtes ${tag} n°${v}`,
    (v: number) => `Crème fraîche ${tag} ${v}`,
    (v: number) => `Œufs ${tag} calibre ${v}`,
    (v: number) => `Épices ${tag} mix ${v}`,
    (v: number) => `Biscuit ${tag} 100% cacao ${v}`,
    (v: number) => `Sauce ${tag} piment_fort ${v}`,
  ];
  const brandKeys: (string | null)[] = [
    null,
    'maison',
    'ferme',
    'delice',
    'sicam',
    'tanit',
    'aziza',
    'bio',
  ];
  for (let i = 0; i < BULK; i++) {
    const name = families[i % 6]!(Math.floor(i / 6) % 5);
    const brandKey = brandKeys[Math.floor(i / 30) % brandKeys.length]!;
    const row = await addTaggedProduct(
      tag,
      catalog.categoryId(i % 2 === 0 ? 'fruits' : 'laitiers'),
      `bulk-${i}`,
      name,
      brandKey,
    );
    bulkRows.push({ id: row.id, name, brandKey });
    bulkIds.push(row.id);
  }
});

afterAll(async () => {
  await stopApp();
  await removeCatalog(tag);
});

describe('authorization', () => {
  it('requires a token, an owner, and a store', async () => {
    await request(http()).get('/owner/catalog/browse').expect(401);
    await request(http()).get('/owner/catalog/products/1').expect(401);
    const client = await register('CLIENT');
    await browse(client).expect(403);
    await request(http())
      .get('/owner/catalog/products/1')
      .set(auth(client))
      .expect(403);
    const noStore = await register('OWNER');
    await browse(noStore).expect(404);
    await request(http())
      .get('/owner/catalog/products/1')
      .set(auth(noStore))
      .expect(404);
  });
});

describe('validation', () => {
  it.each([
    ['limit=0', { limit: 0 }],
    ['limit=101', { limit: 101 }],
    ['limit=abc', { limit: 'abc' }],
    ['limit=1.5', { limit: 1.5 }],
    ['categoryId=abc', { categoryId: 'abc' }],
    ['categoryId=0', { categoryId: 0 }],
    ['an undecodable cursor', { cursor: 'not-a-cursor' }],
    ['a too long search', { q: 'x'.repeat(101) }],
  ])('rejects %s', async (_label, query) => {
    const { owner } = await registerOwnerWithStore();
    await browse(owner, query as Record<string, string | number>).expect(400);
  });
});

describe('what a page contains', () => {
  it('has the same fields as the picker list, and the page envelope', async () => {
    const { owner } = await registerOwnerWithStore();
    await db.orm.public.Product.where({
      id: catalog.productId('banane'),
    }).update({
      description: 'Jaune et sucrée',
      photo: 'https://cdn.example.com/banane.jpg',
    });

    const response = await browse(owner, { q: `banane ${tag}` }).expect(200);

    expect(response.body.total).toBe(1);
    expect(response.body.nextCursor).toBeNull();
    expect(response.body.items[0]).toEqual({
      id: catalog.productId('banane'),
      slug: `${tag}-banane`,
      name: `Banane ${tag}`,
      description: 'Jaune et sucrée',
      photo: 'https://cdn.example.com/banane.jpg',
      defaultSaleUnit: 'KG',
      allowedSaleUnits: ['KG', 'PIECE'],
      defaultMinQuantity: 100,
      defaultQuantityStep: 100,
      defaultMaxQuantity: 10_000,
      category: {
        id: catalog.categoryId('fruits'),
        slug: `${tag}-fruits`,
        name: `Fruits ${tag}`,
      },
      brand: null,
      inMyStore: false,
      storeProductId: null,
      storeProductArchived: false,
    });
  });

  it('defaults to 50 per page', async () => {
    const { owner } = await registerOwnerWithStore();
    const response = await browse(owner).expect(200);
    expect(response.body.items).toHaveLength(50);
    expect(response.body.total).toBe(BULK + 3);
    expect(response.body.nextCursor).toEqual(expect.any(String));
  });
});

describe('pagination', () => {
  it('walks a large set exactly once, in the promised order', async () => {
    const { owner } = await registerOwnerWithStore();
    const { items, pages } = await walk(owner, { limit: 25 });

    const ids = items.map((item) => item.id);
    expect(new Set(ids).size).toBe(ids.length); // no duplicate
    const everyId = [
      ...bulkIds,
      catalog.productId('banane'),
      catalog.productId('lait-delice-1l'),
      catalog.productId('yaourt'),
    ];
    expect([...ids].sort((a, b) => a - b)).toEqual(
      [...everyId].sort((a, b) => a - b),
    ); // no skip
    expect(ids).toEqual(
      expectedOrder(items.map((item) => ({ id: item.id, name: item.name }))),
    );
    expect(pages).toHaveLength(Math.ceil((BULK + 3) / 25));
    expect(pages.map((p) => p.total)).toEqual(pages.map(() => BULK + 3));
    expect(pages.at(-1)!.nextCursor).toBeNull();
    expect(pages.slice(0, -1).every((p) => p.items.length === 25)).toBe(true);
  });

  it('gives the same pages whatever the page size', async () => {
    const { owner } = await registerOwnerWithStore();
    const small = await walk(owner, { limit: 7 });
    const large = await walk(owner, { limit: 100 });
    expect(small.items.map((i) => i.id)).toEqual(large.items.map((i) => i.id));
  });

  it('is exact at the boundaries', async () => {
    const { owner } = await registerOwnerWithStore();
    const total = BULK + 3;

    // limit == total is not possible (max 100): use a filtered set instead.
    const one = await browse(owner, { limit: 1 }).expect(200);
    expect(one.body.items).toHaveLength(1);
    expect(one.body.nextCursor).not.toBeNull();

    // A set whose size is an exact multiple of the limit ends with no phantom page.
    const q = `banane ${tag}`;
    const exact = await browse(owner, { q, limit: 1 }).expect(200);
    expect(exact.body.items).toHaveLength(1);
    expect(exact.body.total).toBe(1);
    expect(exact.body.nextCursor).toBeNull();

    // limit larger than the matches.
    const wide = await browse(owner, { q: `yaourt ${tag}`, limit: 100 }).expect(
      200,
    );
    expect(wide.body.items).toHaveLength(1);
    expect(wide.body.nextCursor).toBeNull();

    const everything = await walk(owner, { limit: 100 });
    expect(everything.items).toHaveLength(total);
    expect(everything.pages).toHaveLength(3); // 100 + 100 + 40
    expect(everything.pages[2]!.items).toHaveLength(total - 200);
  });

  it('an exact multiple of the limit has no empty trailing page', async () => {
    const { owner } = await registerOwnerWithStore();
    // 'calibre' matches the Œufs rows only; count them from the fixture.
    const oeufs = bulkRows.filter((r) => r.name.startsWith('Œufs')).length;
    const { pages } = await walk(owner, { q: `calibre ${tag}`, limit: oeufs });
    expect(pages).toHaveLength(1);
    expect(pages[0]!.items).toHaveLength(oeufs);
    expect(pages[0]!.nextCursor).toBeNull();
  });

  it('a cursor past the last row returns an empty page with the total', async () => {
    const { owner } = await registerOwnerWithStore();
    const { pages } = await walk(owner, { limit: 100 });
    const last = pages.at(-1)!.items.at(-1)!;
    const afterEnd = Buffer.from(
      JSON.stringify({ k: '￿', i: last.id }),
    ).toString('base64url');
    const response = await browse(owner, { cursor: afterEnd }).expect(200);
    expect(response.body).toEqual({
      items: [],
      total: BULK + 3,
      nextCursor: null,
    });
  });

  it('repeating a request returns the same page', async () => {
    const { owner } = await registerOwnerWithStore();
    const first = await browse(owner, { limit: 20 }).expect(200);
    const cursor = first.body.nextCursor as string;
    const a = await browse(owner, { limit: 20, cursor }).expect(200);
    const b = await browse(owner, { limit: 20, cursor }).expect(200);
    expect(b.body).toEqual(a.body);
    expect((await browse(owner, { limit: 20 }).expect(200)).body).toEqual(
      first.body,
    );
  });

  it('keeps paging when products are added or archived mid-walk: unchanged rows are neither repeated nor skipped', async () => {
    const { owner } = await registerOwnerWithStore();
    const first = await browse(owner, { limit: 30 }).expect(200);
    const seen = (first.body as Page).items.map((i) => i.id);

    // A product sorted before the cursor appears; one after it is archived.
    const before = await addTaggedProduct(
      tag,
      catalog.categoryId('fruits'),
      'late-before',
      `Aaa ${tag} nouveau`,
      null,
    );
    const rest = await walk(owner, {
      limit: 30,
      cursor: (first.body as Page).nextCursor!,
    });
    const archivedId = rest.items[5]!.id;
    await archiveProduct(archivedId);
    const afterArchive = await walk(owner, {
      limit: 30,
      cursor: (first.body as Page).nextCursor!,
    });

    const all = [...seen, ...afterArchive.items.map((i) => i.id)];
    expect(new Set(all).size).toBe(all.length); // no duplicate
    expect(all).not.toContain(before.id); // sorted before the cursor: not injected mid-walk
    expect(all).not.toContain(archivedId);
    // Everything else after the cursor is still there.
    const expectedRest = rest.items
      .map((i) => i.id)
      .filter((id) => id !== archivedId);
    expect(afterArchive.items.map((i) => i.id)).toEqual(expectedRest);

    // Put the shared fixture back for the tests that follow.
    await db.orm.public.Product.where({ id: archivedId }).update({
      archivedAt: null,
    });
    await archiveProduct(before.id);
  });
});

const INT4_MAX = 2_147_483_647;
const cursorOf = (value: unknown) =>
  Buffer.from(JSON.stringify(value)).toString('base64url');

describe('out-of-range and unsafe input is a client error, never a 500', () => {
  it('categoryId: the integer maximum is accepted, one above is a 400', async () => {
    const { owner } = await registerOwnerWithStore();
    const ok = await browse(owner, { categoryId: INT4_MAX }).expect(200);
    expect(ok.body).toEqual({ items: [], total: 0, nextCursor: null });
    await browse(owner, { categoryId: INT4_MAX + 1 }).expect(400);
    await browse(owner, { categoryId: 99_999_999_999 }).expect(400);
  });

  it('cursor id: the integer maximum is accepted, one above is a 400', async () => {
    const { owner } = await registerOwnerWithStore();
    // A key past every name: the page is empty, with the total.
    const ok = await browse(owner, {
      cursor: cursorOf({ k: '\uffff', i: INT4_MAX }),
    }).expect(200);
    expect(ok.body.items).toEqual([]);
    expect(ok.body.total).toBe(BULK + 3);
    await browse(owner, {
      cursor: cursorOf({ k: 'a', i: INT4_MAX + 1 }),
    }).expect(400);
    await browse(owner, {
      cursor: cursorOf({ k: 'a', i: 99_999_999_999 }),
    }).expect(400);
    await browse(owner, { cursor: cursorOf({ k: 'a', i: 0 }) }).expect(400);
  });

  it('cursor key with a NUL byte is a 400; a long or empty key is fine', async () => {
    const { owner } = await registerOwnerWithStore();
    await browse(owner, { cursor: cursorOf({ k: 'a\u0000b', i: 1 }) }).expect(
      400,
    );
    await browse(owner, { cursor: cursorOf({ k: '', i: 1 }) }).expect(200);
    await browse(owner, {
      cursor: cursorOf({ k: 'x'.repeat(250), i: 1 }),
    }).expect(200);
  });

  it('search text with a NUL byte is a 400', async () => {
    const { owner } = await registerOwnerWithStore();
    const response = await request(http())
      .get('/owner/catalog/browse')
      .query({ q: 'to\u0000mate' })
      .set(auth(owner))
      .expect(400);
    expect(JSON.stringify(response.body)).toContain('NUL');
    // Other unusual text is still just a search.
    await browse(owner, { q: `🍅 ${tag}` }).expect(200);
    await browse(owner, { q: `"quotes" 'and' \\ ${tag}` }).expect(200);
  });

  it('product id: the integer range is accepted, outside it is a 400', async () => {
    const { owner } = await registerOwnerWithStore();
    const get = (id: string | number) =>
      request(http()).get(`/owner/catalog/products/${id}`).set(auth(owner));
    await get(INT4_MAX).expect(404); // valid, unknown
    await get(0).expect(404);
    await get(-1).expect(404);
    await get(-INT4_MAX - 1).expect(404);
    await get(INT4_MAX + 1).expect(400);
    await get(-INT4_MAX - 2).expect(400);
    await get(99_999_999_999).expect(400);
    await get('abc').expect(400);
    await get(catalog.productId('yaourt')).expect(200);
  });

  it('valid requests are unchanged by the stricter validation', async () => {
    const { owner } = await registerOwnerWithStore();
    const first = await browse(owner, {
      categoryId: catalog.categoryId('laitiers'),
      limit: 100,
    }).expect(200);
    expect(first.body.total).toBeGreaterThan(0);
    const next = await browse(owner, { limit: 10 }).expect(200);
    await browse(owner, {
      limit: 10,
      cursor: next.body.nextCursor,
    }).expect(200);
  });
});

describe('search', () => {
  it('ignores case and accents: "oeuf" finds Œufs, "creme" finds Crème', async () => {
    const { owner } = await registerOwnerWithStore();
    const oeufs = bulkRows.filter((r) => r.name.startsWith('Œufs')).length;
    const creme = bulkRows.filter((r) => r.name.startsWith('Crème')).length;

    expect(
      (await browse(owner, { q: `OEUF ${tag}` }).expect(200)).body.total,
    ).toBe(oeufs);
    expect(
      (await browse(owner, { q: `œufs ${tag}` }).expect(200)).body.total,
    ).toBe(oeufs);
    expect(
      (await browse(owner, { q: `creme fraiche ${tag}` }).expect(200)).body
        .total,
    ).toBe(creme);
    expect(
      (await browse(owner, { q: `CRÈME ${tag}` }).expect(200)).body.total,
    ).toBe(creme);
  });

  it('needs every word, in any order', async () => {
    const { owner } = await registerOwnerWithStore();
    const a = await browse(owner, { q: `fraiche ${tag} creme` }).expect(200);
    const b = await browse(owner, { q: `creme ${tag} fraiche` }).expect(200);
    expect(a.body.total).toBeGreaterThan(0);
    expect(a.body.total).toBe(b.body.total);
    const none = await browse(owner, { q: `creme ${tag} zzzzzz` }).expect(200);
    expect(none.body).toEqual({ items: [], total: 0, nextCursor: null });
  });

  it('also matches the brand and the category name', async () => {
    const { owner } = await registerOwnerWithStore();
    const byBrand = await browse(owner, {
      q: `maison ${tag}`,
      limit: 100,
    }).expect(200);
    expect(byBrand.body.total).toBe(
      bulkRows.filter((r) => r.brandKey === 'maison').length,
    );
    expect(
      (byBrand.body as Page).items.every(
        (i) => i.brand?.slug === `${tag}-maison`,
      ),
    ).toBe(true);

    const byCategory = await browse(owner, {
      q: `produits laitiers ${tag}`,
    }).expect(200);
    expect(byCategory.body.total).toBeGreaterThan(0);
    expect(
      (byCategory.body as Page).items.every(
        (i) => i.category.slug === `${tag}-laitiers`,
      ),
    ).toBe(true);
  });

  it('treats % and _ as plain characters', async () => {
    const { owner } = await registerOwnerWithStore();
    const percent = bulkRows.filter((r) => r.name.includes('100%')).length;
    const underscore = bulkRows.filter((r) =>
      r.name.includes('piment_fort'),
    ).length;
    expect(
      (await browse(owner, { q: `100% ${tag}` }).expect(200)).body.total,
    ).toBe(percent);
    expect(
      (await browse(owner, { q: `piment_fort ${tag}` }).expect(200)).body.total,
    ).toBe(underscore);
    // '_' must not match any character, '%' must not match everything.
    expect(
      (await browse(owner, { q: `piment%fort ${tag}` }).expect(200)).body.total,
    ).toBe(0);
    expect(
      (await browse(owner, { q: `piment fort_ ${tag}` }).expect(200)).body
        .total,
    ).toBe(0);
  });

  it('is not an injection surface', async () => {
    const { owner } = await registerOwnerWithStore();
    const response = await browse(owner, {
      q: `'; drop table "Product"; -- ${tag}`,
    }).expect(200);
    expect(response.body.total).toBe(0);
    expect(
      (await browse(owner, { q: `banane ${tag}` }).expect(200)).body.total,
    ).toBe(1);
  });

  it('a blank search lists everything', async () => {
    const { owner } = await registerOwnerWithStore();
    const response = await request(http())
      .get('/owner/catalog/browse')
      .query({ q: '   ', limit: 1 })
      .set(auth(owner))
      .expect(200);
    expect(response.body.total).toBeGreaterThanOrEqual(BULK + 3);
  });

  it('pages through a search without repeating', async () => {
    const { owner } = await registerOwnerWithStore();
    const { items, pages } = await walk(owner, { q: `pates ${tag}`, limit: 4 });
    const expected = bulkRows.filter((r) => r.name.startsWith('Pâtes')).length;
    expect(items).toHaveLength(expected);
    expect(new Set(items.map((i) => i.id)).size).toBe(expected);
    expect(pages.every((p) => p.total === expected)).toBe(true);
  });
});

describe('category filter', () => {
  it('narrows the page and the total, and combines with the search', async () => {
    const { owner } = await registerOwnerWithStore();
    const inFruits = (
      await browse(owner, {
        categoryId: catalog.categoryId('fruits'),
        limit: 100,
      }).expect(200)
    ).body as Page;
    expect(
      inFruits.items.every((i) => i.category.slug === `${tag}-fruits`),
    ).toBe(true);
    const inLaitiers = (
      await browse(owner, {
        categoryId: catalog.categoryId('laitiers'),
        limit: 100,
      }).expect(200)
    ).body as Page;
    expect(inFruits.total + inLaitiers.total).toBe(BULK + 3);

    const both = (
      await browse(owner, {
        categoryId: catalog.categoryId('fruits'),
        q: `oeufs ${tag}`,
      }).expect(200)
    ).body as Page;
    const expected = bulkRows.filter(
      (r) =>
        r.name.startsWith('Œufs') && inFruits.items.some((i) => i.id === r.id),
    ).length;
    expect(both.total).toBe(expected);
  });

  it('an unknown category has no products', async () => {
    const { owner } = await registerOwnerWithStore();
    const response = await browse(owner, { categoryId: 2_000_000_000 }).expect(
      200,
    );
    expect(response.body).toEqual({ items: [], total: 0, nextCursor: null });
  });
});

describe('active catalog only', () => {
  it('hides archived products and products of archived categories', async () => {
    const localTag = `${tag}hide`;
    const local = await seedCatalog(localTag);
    const { owner } = await registerOwnerWithStore();
    await archiveProduct(local.productId('yaourt'));
    await archiveCategory(local.categoryId('fruits'));

    const response = await request(http())
      .get('/owner/catalog/browse')
      .query({ q: localTag })
      .set(auth(owner))
      .expect(200);
    const slugs = (response.body as Page).items.map((i) => i.slug);

    expect(slugs).toEqual([`${localTag}-lait-delice-1l`]);
    expect(response.body.total).toBe(1);

    await request(http())
      .get(`/owner/catalog/products/${local.productId('yaourt')}`)
      .set(auth(owner))
      .expect(404);
    await request(http())
      .get(`/owner/catalog/products/${local.productId('banane')}`)
      .set(auth(owner))
      .expect(404);
    await removeCatalog(localTag);
  });
});

describe('store flags', () => {
  it('follow the store product through add, archive and restore — per store', async () => {
    const a = await registerOwnerWithStore();
    const b = await registerOwnerWithStore();
    const productId = catalog.productId('yaourt');
    const flags = async (owner: Parameters<typeof auth>[0]) => {
      const response = await browse(owner, { q: `yaourt ${tag}` }).expect(200);
      const row = (response.body as Page).items[0]!;
      return {
        inMyStore: row.inMyStore,
        storeProductId: row.storeProductId,
        storeProductArchived: row.storeProductArchived,
      };
    };
    expect(await flags(a.owner)).toEqual({
      inMyStore: false,
      storeProductId: null,
      storeProductArchived: false,
    });

    const created = await request(http())
      .post('/owner/store-products')
      .set(auth(a.owner))
      .send({ productId, priceMillimes: 4500 })
      .expect(201);
    expect(await flags(a.owner)).toEqual({
      inMyStore: true,
      storeProductId: created.body.id,
      storeProductArchived: false,
    });
    expect(await flags(b.owner)).toEqual({
      inMyStore: false,
      storeProductId: null,
      storeProductArchived: false,
    });

    await request(http())
      .delete(`/owner/store-products/${created.body.id}`)
      .set(auth(a.owner))
      .expect(204);
    expect(await flags(a.owner)).toEqual({
      inMyStore: false,
      storeProductId: created.body.id,
      storeProductArchived: true,
    });
  });

  it('a page flags only the rows the store has, without touching its offering', async () => {
    const { owner } = await registerOwnerWithStore();
    const created = await request(http())
      .post('/owner/store-products')
      .set(auth(owner))
      .send({ productId: bulkIds[3]!, priceMillimes: 1234 })
      .expect(201);
    const { items } = await walk(owner, { limit: 100 });
    const mine = items.filter((i) => i.inMyStore);
    expect(mine.map((i) => i.id)).toEqual([bulkIds[3]]);
    expect(mine[0]!.storeProductId).toBe(created.body.id);

    const stored = await request(http())
      .get(`/owner/store-products/${created.body.id}`)
      .set(auth(owner))
      .expect(200);
    expect(stored.body.priceMillimes).toBe(1234);
  });
});

describe('GET /owner/catalog/products/:id', () => {
  it('returns the product with this store’s flags', async () => {
    const { owner } = await registerOwnerWithStore();
    const id = catalog.productId('yaourt');
    const before = await request(http())
      .get(`/owner/catalog/products/${id}`)
      .set(auth(owner))
      .expect(200);
    expect(before.body).toMatchObject({
      id,
      slug: `${tag}-yaourt`,
      defaultMaxQuantity: 24,
      inMyStore: false,
      storeProductId: null,
      storeProductArchived: false,
    });

    const created = await request(http())
      .post('/owner/store-products')
      .set(auth(owner))
      .send({ productId: id, priceMillimes: 900 })
      .expect(201);
    const after = await request(http())
      .get(`/owner/catalog/products/${id}`)
      .set(auth(owner))
      .expect(200);
    expect(after.body).toMatchObject({
      inMyStore: true,
      storeProductId: created.body.id,
    });
  });

  it('is a 404 for an unknown id and a 400 for a malformed one', async () => {
    const { owner } = await registerOwnerWithStore();
    await request(http())
      .get('/owner/catalog/products/2000000000')
      .set(auth(owner))
      .expect(404);
    await request(http())
      .get('/owner/catalog/products/abc')
      .set(auth(owner))
      .expect(400);
  });
});

describe('the legacy list is unchanged', () => {
  it('still returns the whole catalog as an array', async () => {
    const { owner } = await registerOwnerWithStore();
    const response = await request(http())
      .get('/owner/catalog/products')
      .set(auth(owner))
      .expect(200);
    expect(Array.isArray(response.body)).toBe(true);
    const mine = (response.body as Item[]).filter((p) =>
      p.slug.startsWith(`${tag}-`),
    );
    expect(mine).toHaveLength(BULK + 3);
  });
});

describe('categories', () => {
  it('counts active products per category with one grouped query', async () => {
    const { owner } = await registerOwnerWithStore();
    const response = await request(http())
      .get('/owner/catalog/categories')
      .set(auth(owner))
      .expect(200);
    const fruits = (
      response.body as { slug: string; productCount: number }[]
    ).find((c) => c.slug === `${tag}-fruits`)!;
    const laitiers = (
      response.body as { slug: string; productCount: number }[]
    ).find((c) => c.slug === `${tag}-laitiers`)!;
    expect(fruits.productCount + laitiers.productCount).toBe(BULK + 3 - 0);
  });
});
