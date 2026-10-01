import request from 'supertest';
import { db } from '../src/prisma/db.js';
import {
  auth,
  http,
  register,
  registerOwnerWithStore,
  startApp,
  stopApp,
  type Account,
} from './support.js';

beforeAll(startApp);
afterAll(stopApp);

const tomatoes = {
  name: 'Tomates',
  saleUnit: 'KG',
  priceMillimes: 1800,
  minQuantity: 500,
  quantityStep: 500,
  maxQuantity: 10_000,
};

interface ProductBody {
  id: number;
  storeId: number;
  categoryId: number | null;
  name: string;
  saleUnit: string;
  priceMillimes: number;
  minQuantity: number;
  quantityStep: number;
  maxQuantity: number | null;
  isAvailable: boolean;
  archivedAt: string | null;
}

async function createProduct(owner: Account, body: object = tomatoes) {
  const response = await request(http())
    .post('/owner/products')
    .set(auth(owner))
    .send(body)
    .expect(201);
  return response.body as ProductBody;
}

async function createCategory(owner: Account, name: string) {
  const response = await request(http())
    .post('/owner/categories')
    .set(auth(owner))
    .send({ name })
    .expect(201);
  return response.body as { id: number };
}

async function listNames(owner: Account, query = ''): Promise<string[]> {
  const response = await request(http())
    .get(`/owner/products${query}`)
    .set(auth(owner))
    .expect(200);
  return response.body.map((product: ProductBody) => product.name);
}

const patch = (owner: Account, id: number, body: object) =>
  request(http()).patch(`/owner/products/${id}`).set(auth(owner)).send(body);

describe('access control', () => {
  const routes = [
    ['GET', 'get', '/owner/products'],
    ['POST', 'post', '/owner/products'],
    ['GET', 'get', '/owner/products/1'],
    ['PATCH', 'patch', '/owner/products/1'],
    ['PATCH', 'patch', '/owner/products/1/availability'],
    ['DELETE', 'delete', '/owner/products/1'],
  ] as const;

  it.each(routes)('%s %s without a token is 401', async (_l, verb, path) => {
    await request(http())[verb](path).send(tomatoes).expect(401);
  });

  it.each(routes)('a CLIENT gets 403 on %s %s', async (_l, verb, path) => {
    const client = await register('CLIENT');
    await request(http())
      [verb](path)
      .set(auth(client))
      .send(tomatoes)
      .expect(403);
  });

  it('an OWNER without a store gets a clear 404', async () => {
    const owner = await register('OWNER');
    const response = await request(http())
      .get('/owner/products')
      .set(auth(owner))
      .expect(404);
    expect(response.body.message).toBe('This owner has no store yet');
    await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send(tomatoes)
      .expect(404);
  });
});

describe('create and read', () => {
  it('creates the spec examples exactly as given', async () => {
    const { owner, store } = await registerOwnerWithStore();

    const created = await createProduct(owner);
    expect(created).toMatchObject({
      storeId: store.id, // resolved from the JWT
      categoryId: null,
      name: 'Tomates',
      saleUnit: 'KG',
      priceMillimes: 1800,
      minQuantity: 500,
      quantityStep: 500,
      maxQuantity: 10_000,
      isAvailable: true,
      archivedAt: null,
    });

    const cheese = await createProduct(owner, {
      name: 'Fromage',
      saleUnit: 'KG',
      priceMillimes: 28_000,
      quantityStep: 100,
    });
    expect(cheese).toMatchObject({
      minQuantity: 100,
      quantityStep: 100,
      maxQuantity: null,
    });

    const eggs = await createProduct(owner, {
      name: 'Œufs',
      saleUnit: 'PIECE',
      priceMillimes: 350,
    });
    expect(eggs).toMatchObject({ minQuantity: 1, quantityStep: 1 });

    const milk = await createProduct(owner, {
      name: 'Lait 1 L',
      saleUnit: 'PIECE',
      priceMillimes: 1350,
    });
    expect(milk).toMatchObject({ saleUnit: 'PIECE', priceMillimes: 1350 });

    const juice = await createProduct(owner, {
      name: 'Jus',
      saleUnit: 'L',
      priceMillimes: 2400,
      quantityStep: 250,
    });
    expect(juice).toMatchObject({ minQuantity: 250, quantityStep: 250 });
  });

  it('lists sorted by name and reads one by id', async () => {
    const { owner } = await registerOwnerWithStore();
    const pommes = await createProduct(owner, { ...tomatoes, name: 'Pommes' });
    await createProduct(owner, { ...tomatoes, name: 'Bananes' });

    expect(await listNames(owner)).toEqual(['Bananes', 'Pommes']);
    const one = await request(http())
      .get(`/owner/products/${pommes.id}`)
      .set(auth(owner))
      .expect(200);
    expect(one.body).toMatchObject({ id: pommes.id, name: 'Pommes' });
  });

  it('trims the name and stores description and photo', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send({
        ...tomatoes,
        name: '  Tomates  ',
        description: 'Fraîches',
        photo: 'https://x.test/t.jpg',
      })
      .expect(201);
    expect(product.body).toMatchObject({
      name: 'Tomates',
      description: 'Fraîches',
      photo: 'https://x.test/t.jpg',
    });
  });

  it('rejects storeId and archivedAt in the body', async () => {
    const a = await registerOwnerWithStore();
    const b = await registerOwnerWithStore();
    await request(http())
      .post('/owner/products')
      .set(auth(a.owner))
      .send({ ...tomatoes, storeId: b.store.id })
      .expect(400);
    await request(http())
      .post('/owner/products')
      .set(auth(a.owner))
      .send({ ...tomatoes, archivedAt: new Date().toISOString() })
      .expect(400);
    expect(await listNames(b.owner)).toEqual([]);
  });
});

describe('store isolation', () => {
  it('each owner only sees their own products', async () => {
    const a = await registerOwnerWithStore();
    const b = await registerOwnerWithStore();
    await createProduct(a.owner, { ...tomatoes, name: 'Only A' });
    await createProduct(b.owner, { ...tomatoes, name: 'Only B' });
    expect(await listNames(a.owner)).toEqual(['Only A']);
    expect(await listNames(b.owner)).toEqual(['Only B']);
  });

  it("another store's product cannot be read, edited, toggled or archived (404, untouched)", async () => {
    const a = await registerOwnerWithStore();
    const b = await registerOwnerWithStore();
    const inA = await createProduct(a.owner);

    await request(http())
      .get(`/owner/products/${inA.id}`)
      .set(auth(b.owner))
      .expect(404);
    await patch(b.owner, inA.id, { name: 'Hijacked' }).expect(404);
    await request(http())
      .patch(`/owner/products/${inA.id}/availability`)
      .set(auth(b.owner))
      .send({ isAvailable: false })
      .expect(404);
    await request(http())
      .delete(`/owner/products/${inA.id}`)
      .set(auth(b.owner))
      .expect(404);

    const untouched = await request(http())
      .get(`/owner/products/${inA.id}`)
      .set(auth(a.owner))
      .expect(200);
    expect(untouched.body).toMatchObject({
      name: 'Tomates',
      isAvailable: true,
      archivedAt: null,
    });
  });

  it('a missing id is a 404 and a non-numeric id a 400', async () => {
    const { owner } = await registerOwnerWithStore();
    await request(http())
      .get('/owner/products/999999999')
      .set(auth(owner))
      .expect(404);
    await request(http())
      .get('/owner/products/abc')
      .set(auth(owner))
      .expect(400);
  });
});

describe('category ↔ store validation', () => {
  it('accepts a category from the same store', async () => {
    const { owner } = await registerOwnerWithStore();
    const category = await createCategory(owner, 'Légumes');
    const product = await createProduct(owner, {
      ...tomatoes,
      categoryId: category.id,
    });
    expect(product.categoryId).toBe(category.id);
  });

  it("rejects another store's category on create (400) and creates nothing", async () => {
    const a = await registerOwnerWithStore();
    const b = await registerOwnerWithStore();
    const foreign = await createCategory(b.owner, 'Légumes');
    const response = await request(http())
      .post('/owner/products')
      .set(auth(a.owner))
      .send({ ...tomatoes, categoryId: foreign.id })
      .expect(400);
    expect(response.body.message).toBe('Category not found in your store');
    expect(await listNames(a.owner)).toEqual([]);
  });

  it('rejects a missing category id (400)', async () => {
    const { owner } = await registerOwnerWithStore();
    await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send({ ...tomatoes, categoryId: 999999999 })
      .expect(400);
  });

  it("rejects moving a product into another store's category on update", async () => {
    const a = await registerOwnerWithStore();
    const b = await registerOwnerWithStore();
    const foreign = await createCategory(b.owner, 'Légumes');
    const product = await createProduct(a.owner);
    await patch(a.owner, product.id, { categoryId: foreign.id }).expect(400);
    const after = await request(http())
      .get(`/owner/products/${product.id}`)
      .set(auth(a.owner))
      .expect(200);
    expect(after.body.categoryId).toBeNull();
  });

  it('moves a product between categories and back to none', async () => {
    const { owner } = await registerOwnerWithStore();
    const veg = await createCategory(owner, 'Légumes');
    const fruit = await createCategory(owner, 'Fruits');
    const product = await createProduct(owner, {
      ...tomatoes,
      categoryId: veg.id,
    });

    expect(
      (await patch(owner, product.id, { categoryId: fruit.id }).expect(200))
        .body.categoryId,
    ).toBe(fruit.id);
    expect(
      (await patch(owner, product.id, { categoryId: null }).expect(200)).body
        .categoryId,
    ).toBeNull();
  });

  it('filters the list by category', async () => {
    const { owner } = await registerOwnerWithStore();
    const veg = await createCategory(owner, 'Légumes');
    const fruit = await createCategory(owner, 'Fruits');
    await createProduct(owner, {
      ...tomatoes,
      name: 'Tomates',
      categoryId: veg.id,
    });
    await createProduct(owner, {
      ...tomatoes,
      name: 'Pommes',
      categoryId: fruit.id,
    });
    await createProduct(owner, { ...tomatoes, name: 'Sel' });

    expect(await listNames(owner, `?categoryId=${veg.id}`)).toEqual([
      'Tomates',
    ]);
    expect(await listNames(owner, `?categoryId=${fruit.id}`)).toEqual([
      'Pommes',
    ]);
    expect(await listNames(owner)).toEqual(['Pommes', 'Sel', 'Tomates']);
  });
});

describe('category deletion vs products', () => {
  it('refuses while an active product uses the category (409, category kept)', async () => {
    const { owner } = await registerOwnerWithStore();
    const category = await createCategory(owner, 'Légumes');
    await createProduct(owner, { ...tomatoes, categoryId: category.id });

    await request(http())
      .delete(`/owner/categories/${category.id}`)
      .set(auth(owner))
      .expect(409);
    const categories = await request(http())
      .get('/owner/categories')
      .set(auth(owner))
      .expect(200);
    expect(categories.body).toHaveLength(1);
  });

  it('archived products do not block deletion and lose their category', async () => {
    const { owner } = await registerOwnerWithStore();
    const category = await createCategory(owner, 'Légumes');
    const product = await createProduct(owner, {
      ...tomatoes,
      categoryId: category.id,
    });
    await request(http())
      .delete(`/owner/products/${product.id}`)
      .set(auth(owner))
      .expect(204);

    await request(http())
      .delete(`/owner/categories/${category.id}`)
      .set(auth(owner))
      .expect(204);
    const archived = await request(http())
      .get(`/owner/products/${product.id}`)
      .set(auth(owner))
      .expect(200);
    expect(archived.body.categoryId).toBeNull();
    expect(archived.body.archivedAt).not.toBeNull();
  });

  it('works once the blocking product is moved to another category', async () => {
    const { owner } = await registerOwnerWithStore();
    const veg = await createCategory(owner, 'Légumes');
    const fruit = await createCategory(owner, 'Fruits');
    const product = await createProduct(owner, {
      ...tomatoes,
      categoryId: veg.id,
    });
    await patch(owner, product.id, { categoryId: fruit.id }).expect(200);
    await request(http())
      .delete(`/owner/categories/${veg.id}`)
      .set(auth(owner))
      .expect(204);
  });
});

describe('price validation', () => {
  it.each([
    ['zero', 0],
    ['negative', -5],
    ['fractional', 1.5],
    ['a string', '1800'],
    ['null', null],
    ['above the ceiling', 10_000_001],
  ])('rejects a %s price', async (_l, priceMillimes) => {
    const { owner } = await registerOwnerWithStore();
    await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send({ ...tomatoes, priceMillimes })
      .expect(400);
    expect(await listNames(owner)).toEqual([]);
  });

  it('requires a price', async () => {
    const { owner } = await registerOwnerWithStore();
    const { priceMillimes: _omit, ...withoutPrice } = tomatoes;
    await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send(withoutPrice)
      .expect(400);
  });

  it('accepts the smallest and largest price', async () => {
    const { owner } = await registerOwnerWithStore();
    await createProduct(owner, {
      ...tomatoes,
      name: 'Cheap',
      priceMillimes: 1,
    });
    await createProduct(owner, {
      ...tomatoes,
      name: 'Dear',
      priceMillimes: 10_000_000,
    });
  });

  it('rejects a bad price on update, leaving the product unchanged', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner);
    await patch(owner, product.id, { priceMillimes: 0 }).expect(400);
    await patch(owner, product.id, { priceMillimes: null }).expect(400);
    const after = await request(http())
      .get(`/owner/products/${product.id}`)
      .set(auth(owner))
      .expect(200);
    expect(after.body.priceMillimes).toBe(1800);
  });
});

describe('unit and quantity validation', () => {
  it.each(['G', 'ML', 'BOTTLE', 'kg', '', 5, null])(
    'rejects the sale unit %j',
    async (saleUnit) => {
      const { owner } = await registerOwnerWithStore();
      await request(http())
        .post('/owner/products')
        .set(auth(owner))
        .send({ ...tomatoes, saleUnit })
        .expect(400);
    },
  );

  it('requires a sale unit', async () => {
    const { owner } = await registerOwnerWithStore();
    const { saleUnit: _omit, ...withoutUnit } = tomatoes;
    await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send(withoutUnit)
      .expect(400);
  });

  it.each([
    ['a zero minimum', { minQuantity: 0 }],
    ['a negative step', { quantityStep: -500 }],
    ['a zero step', { quantityStep: 0 }],
    ['a fractional minimum', { minQuantity: 500.5 }],
    ['a minimum that is not a multiple of the step', { minQuantity: 600 }],
    ['a max below the min', { minQuantity: 1000, maxQuantity: 500 }],
    ['a max that is not a multiple of the step', { maxQuantity: 1250 }],
    ['a max above the kg ceiling', { maxQuantity: 100_500 }],
  ])('rejects %s (KG)', async (_l, overrides) => {
    const { owner } = await registerOwnerWithStore();
    await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send({ ...tomatoes, ...overrides })
      .expect(400);
    expect(await listNames(owner)).toEqual([]);
  });

  it('reports every violated quantity rule in one response', async () => {
    const { owner } = await registerOwnerWithStore();
    const response = await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send({ ...tomatoes, minQuantity: 600, maxQuantity: 100 })
      .expect(400);
    expect(response.body.message.length).toBeGreaterThanOrEqual(2);
  });

  it('catches typing 1 for one kilo (= 1 gram) — the unit mix-up', async () => {
    const { owner } = await registerOwnerWithStore();
    const response = await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send({
        name: 'Riz',
        saleUnit: 'KG',
        priceMillimes: 3000,
        minQuantity: 1,
        quantityStep: 1,
      })
      .expect(400);
    expect(JSON.stringify(response.body.message)).toContain(
      'multiple of 10 grams',
    );
  });

  it('applies the litre granularity and the piece ceiling', async () => {
    const { owner } = await registerOwnerWithStore();
    await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send({
        name: 'Huile',
        saleUnit: 'L',
        priceMillimes: 9000,
        minQuantity: 5,
        quantityStep: 5,
      })
      .expect(400);
    await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send({
        name: 'Œufs',
        saleUnit: 'PIECE',
        priceMillimes: 350,
        maxQuantity: 1001,
      })
      .expect(400);
  });

  it('accepts a max equal to the min, and a minimum of several steps', async () => {
    const { owner } = await registerOwnerWithStore();
    await createProduct(owner, {
      ...tomatoes,
      name: 'A',
      minQuantity: 500,
      maxQuantity: 500,
    });
    await createProduct(owner, {
      ...tomatoes,
      name: 'B',
      minQuantity: 1500,
      quantityStep: 500,
    });
  });

  it('validates the merged result on update, not just the changed fields', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner); // min 500 step 500 max 10000
    // New step 300 leaves min 500 (and max 10000) unaligned.
    await patch(owner, product.id, { quantityStep: 300 }).expect(400);
    // Raising the minimum above the existing max.
    await patch(owner, product.id, { minQuantity: 20_000 }).expect(400);
    const ok = await patch(owner, product.id, {
      minQuantity: 1000,
      quantityStep: 250,
      maxQuantity: 5000,
    }).expect(200);
    expect(ok.body).toMatchObject({
      minQuantity: 1000,
      quantityStep: 250,
      maxQuantity: 5000,
    });
  });

  it('clears the maximum with null', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner);
    const cleared = await patch(owner, product.id, {
      maxQuantity: null,
    }).expect(200);
    expect(cleared.body.maxQuantity).toBeNull();
  });

  it('the database backstops the rules even when the service is bypassed', async () => {
    const { store } = await registerOwnerWithStore();
    const base = {
      storeId: store.id,
      saleUnit: 'KG',
      priceMillimes: 1800,
      minQuantity: 500,
      quantityStep: 500,
    };
    const insert = (name: string, overrides: object) =>
      db.orm.public.Product.create({ ...base, name, ...overrides } as never);

    await expect(insert('p1', { priceMillimes: 0 })).rejects.toMatchObject({
      sqlState: '23514',
    });
    await expect(insert('p2', { minQuantity: 0 })).rejects.toMatchObject({
      sqlState: '23514',
    });
    await expect(insert('p3', { quantityStep: 0 })).rejects.toMatchObject({
      sqlState: '23514',
    });
    await expect(insert('p4', { minQuantity: 600 })).rejects.toMatchObject({
      sqlState: '23514',
    });
    await expect(insert('p5', { maxQuantity: 100 })).rejects.toMatchObject({
      sqlState: '23514',
    });
    await expect(insert('p6', { maxQuantity: 1250 })).rejects.toMatchObject({
      sqlState: '23514',
    });
    await expect(insert('p7', { saleUnit: 'G' })).rejects.toMatchObject({
      sqlState: '23514',
    });
    await expect(insert('   ', {})).rejects.toMatchObject({
      sqlState: '23514',
    });
  });
});

describe('changing the sale unit', () => {
  it('refuses a unit change that does not restate price and quantity rules', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner); // KG with a max
    const response = await patch(owner, product.id, {
      saleUnit: 'PIECE',
    }).expect(400);
    expect(response.body.message).toContain(
      'priceMillimes, minQuantity, quantityStep, maxQuantity',
    );

    await patch(owner, product.id, {
      saleUnit: 'PIECE',
      priceMillimes: 350,
    }).expect(400);
    const after = await request(http())
      .get(`/owner/products/${product.id}`)
      .set(auth(owner))
      .expect(200);
    expect(after.body).toMatchObject({
      saleUnit: 'KG',
      priceMillimes: 1800,
      minQuantity: 500,
    });
  });

  it('does not require maxQuantity when the product has none', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner, {
      name: 'Œufs',
      saleUnit: 'PIECE',
      priceMillimes: 350,
    });
    const changed = await patch(owner, product.id, {
      saleUnit: 'KG',
      priceMillimes: 1800,
      minQuantity: 500,
      quantityStep: 500,
    }).expect(200);
    expect(changed.body).toMatchObject({
      saleUnit: 'KG',
      priceMillimes: 1800,
      minQuantity: 500,
    });
  });

  it('accepts a full restatement in the new unit', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner);
    const changed = await patch(owner, product.id, {
      saleUnit: 'PIECE',
      priceMillimes: 350,
      minQuantity: 1,
      quantityStep: 1,
      maxQuantity: 30,
    }).expect(200);
    expect(changed.body).toMatchObject({
      saleUnit: 'PIECE',
      priceMillimes: 350,
      minQuantity: 1,
      quantityStep: 1,
      maxQuantity: 30,
    });
  });

  it('still validates the new unit’s rules', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner);
    await patch(owner, product.id, {
      saleUnit: 'PIECE',
      priceMillimes: 350,
      minQuantity: 1,
      quantityStep: 1,
      maxQuantity: 5000, // above the 1000-piece ceiling
    }).expect(400);
  });

  it('re-sending the same unit is not a unit change', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner);
    await patch(owner, product.id, {
      saleUnit: 'KG',
      name: 'Tomates rondes',
    }).expect(200);
  });
});

describe('update', () => {
  it('edits fields independently and clears the optional ones', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send({
        ...tomatoes,
        description: 'Fraîches',
        photo: 'https://x.test/t.jpg',
      })
      .expect(201);

    const renamed = await patch(owner, product.body.id, {
      name: 'Tomates cerises',
      priceMillimes: 2500,
    }).expect(200);
    expect(renamed.body).toMatchObject({
      name: 'Tomates cerises',
      priceMillimes: 2500,
      description: 'Fraîches',
    });

    const cleared = await patch(owner, product.body.id, {
      description: null,
      photo: null,
    }).expect(200);
    expect(cleared.body).toMatchObject({ description: null, photo: null });
  });

  it.each(['name', 'saleUnit', 'minQuantity', 'quantityStep'])(
    'PATCH { %s: null } is a 400, not a 500',
    async (field) => {
      const { owner } = await registerOwnerWithStore();
      const product = await createProduct(owner);
      await patch(owner, product.id, { [field]: null }).expect(400);
    },
  );

  it('rejects blank names, unknown fields and protected fields', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner);
    await patch(owner, product.id, { name: '   ' }).expect(400);
    await patch(owner, product.id, { storeId: 1 }).expect(400);
    await patch(owner, product.id, { isAvailable: false }).expect(400); // has its own endpoint
    await patch(owner, product.id, {
      archivedAt: new Date().toISOString(),
    }).expect(400);
  });

  it('an empty PATCH is a no-op that returns the product', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner);
    const response = await patch(owner, product.id, {}).expect(200);
    expect(response.body.id).toBe(product.id);
  });
});

describe('duplicate names', () => {
  it('rejects a duplicate active name in the same store, ignoring case and spaces (409)', async () => {
    const { owner } = await registerOwnerWithStore();
    await createProduct(owner);
    const response = await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send({ ...tomatoes, name: '  tOMATES ' })
      .expect(409);
    expect(response.body.message).toBe(
      'A product with this name already exists in your store',
    );
    expect(await listNames(owner)).toEqual(['Tomates']);
  });

  it('rejects renaming onto another active product', async () => {
    const { owner } = await registerOwnerWithStore();
    await createProduct(owner);
    const other = await createProduct(owner, { ...tomatoes, name: 'Pommes' });
    await patch(owner, other.id, { name: 'tomates' }).expect(409);
  });

  it('allows the same name in different stores', async () => {
    const a = await registerOwnerWithStore();
    const b = await registerOwnerWithStore();
    await createProduct(a.owner);
    await createProduct(b.owner);
  });

  it('frees the name once the product is archived', async () => {
    const { owner } = await registerOwnerWithStore();
    const first = await createProduct(owner);
    await request(http())
      .delete(`/owner/products/${first.id}`)
      .set(auth(owner))
      .expect(204);
    const second = await createProduct(owner);
    expect(second.id).not.toBe(first.id);
  });

  it('allows the same name with a different unit only if the name differs', async () => {
    const { owner } = await registerOwnerWithStore();
    await createProduct(owner, {
      name: 'Lait 1 L',
      saleUnit: 'PIECE',
      priceMillimes: 1350,
    });
    await createProduct(owner, {
      name: 'Lait 1,5 L',
      saleUnit: 'PIECE',
      priceMillimes: 1900,
    });
    await request(http())
      .post('/owner/products')
      .set(auth(owner))
      .send({ name: 'lait 1 l', saleUnit: 'L', priceMillimes: 1400 })
      .expect(409);
  });
});

describe('availability', () => {
  it('toggles off and on without touching anything else', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner);
    const toggle = (isAvailable: boolean) =>
      request(http())
        .patch(`/owner/products/${product.id}/availability`)
        .set(auth(owner))
        .send({ isAvailable });

    const off = await toggle(false).expect(200);
    expect(off.body).toMatchObject({
      isAvailable: false,
      name: 'Tomates',
      archivedAt: null,
    });
    expect(await listNames(owner)).toEqual(['Tomates']); // unavailable ≠ removed

    const on = await toggle(true).expect(200);
    expect(on.body.isAvailable).toBe(true);
  });

  it.each([
    {},
    { isAvailable: 'yes' },
    { isAvailable: null },
    { isAvailable: true, name: 'x' },
  ])('rejects the payload %j', async (body) => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner);
    await request(http())
      .patch(`/owner/products/${product.id}/availability`)
      .set(auth(owner))
      .send(body)
      .expect(400);
  });
});

describe('archiving', () => {
  it('DELETE archives: the row is kept, hidden from the active list, readable by id', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner);
    await createProduct(owner, { ...tomatoes, name: 'Pommes' });

    await request(http())
      .delete(`/owner/products/${product.id}`)
      .set(auth(owner))
      .expect(204);

    expect(await listNames(owner)).toEqual(['Pommes']);
    expect(await listNames(owner, '?status=active')).toEqual(['Pommes']);
    expect(await listNames(owner, '?status=archived')).toEqual(['Tomates']);
    expect(await listNames(owner, '?status=all')).toEqual([
      'Pommes',
      'Tomates',
    ]);

    const row = await db.orm.public.Product.first({ id: product.id });
    expect(row?.archivedAt).not.toBeNull(); // never hard-deleted

    const byId = await request(http())
      .get(`/owner/products/${product.id}`)
      .set(auth(owner))
      .expect(200);
    expect(byId.body.archivedAt).not.toBeNull();
  });

  it('is idempotent and keeps the first archive time', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner);
    await request(http())
      .delete(`/owner/products/${product.id}`)
      .set(auth(owner))
      .expect(204);
    const first = (await db.orm.public.Product.first({ id: product.id }))
      ?.archivedAt;
    await request(http())
      .delete(`/owner/products/${product.id}`)
      .set(auth(owner))
      .expect(204);
    expect(
      (await db.orm.public.Product.first({ id: product.id }))?.archivedAt,
    ).toBe(first);
  });

  it('archived products cannot be edited or toggled (409)', async () => {
    const { owner } = await registerOwnerWithStore();
    const product = await createProduct(owner);
    await request(http())
      .delete(`/owner/products/${product.id}`)
      .set(auth(owner))
      .expect(204);
    await patch(owner, product.id, { name: 'Nope' }).expect(409);
    await request(http())
      .patch(`/owner/products/${product.id}/availability`)
      .set(auth(owner))
      .send({ isAvailable: false })
      .expect(409);
  });

  it('filters combine: category + status', async () => {
    const { owner } = await registerOwnerWithStore();
    const veg = await createCategory(owner, 'Légumes');
    const tom = await createProduct(owner, { ...tomatoes, categoryId: veg.id });
    await createProduct(owner, {
      ...tomatoes,
      name: 'Carottes',
      categoryId: veg.id,
    });
    await request(http())
      .delete(`/owner/products/${tom.id}`)
      .set(auth(owner))
      .expect(204);

    expect(await listNames(owner, `?categoryId=${veg.id}`)).toEqual([
      'Carottes',
    ]);
    // archiving keeps the category link until the category itself is deleted
    expect(
      await listNames(owner, `?categoryId=${veg.id}&status=archived`),
    ).toEqual(['Tomates']);
  });

  it.each(['?status=deleted', '?status=', '?categoryId=abc'])(
    'rejects the bad filter %s',
    async (query) => {
      const { owner } = await registerOwnerWithStore();
      await request(http())
        .get(`/owner/products${query}`)
        .set(auth(owner))
        .expect(400);
    },
  );
});
