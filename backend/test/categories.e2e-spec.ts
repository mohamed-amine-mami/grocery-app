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

async function createCategory(owner: Account, name: string) {
  const response = await request(http())
    .post('/owner/categories')
    .set(auth(owner))
    .send({ name })
    .expect(201);
  return response.body as { id: number; storeId: number; name: string };
}

async function namesFor(owner: Account): Promise<string[]> {
  const response = await request(http())
    .get('/owner/categories')
    .set(auth(owner))
    .expect(200);
  return response.body.map((category: { name: string }) => category.name);
}

describe('access control', () => {
  it.each([
    ['GET', 'get', '/owner/categories'],
    ['POST', 'post', '/owner/categories'],
    ['PATCH', 'patch', '/owner/categories/1'],
    ['DELETE', 'delete', '/owner/categories/1'],
  ] as const)('%s %s without a token is 401', async (_label, verb, path) => {
    await request(http())[verb](path).send({ name: 'Dairy' }).expect(401);
  });

  it.each([
    ['GET', 'get', '/owner/categories'],
    ['POST', 'post', '/owner/categories'],
    ['PATCH', 'patch', '/owner/categories/1'],
    ['DELETE', 'delete', '/owner/categories/1'],
  ] as const)('a CLIENT gets 403 on %s %s', async (_label, verb, path) => {
    const client = await register('CLIENT');
    await request(http())
      [verb](path)
      .set(auth(client))
      .send({ name: 'Dairy' })
      .expect(403);
  });

  it('an OWNER without a store gets a clear 404', async () => {
    const owner = await register('OWNER');
    const response = await request(http())
      .get('/owner/categories')
      .set(auth(owner))
      .expect(404);
    expect(response.body.message).toBe('This owner has no store yet');
    await request(http())
      .post('/owner/categories')
      .set(auth(owner))
      .send({ name: 'Dairy' })
      .expect(404);
  });
});

describe('category CRUD', () => {
  it('starts empty', async () => {
    const { owner } = await registerOwnerWithStore();
    expect(await namesFor(owner)).toEqual([]);
  });

  it('creates, lists (sorted by name), renames and deletes', async () => {
    const { owner, store } = await registerOwnerWithStore();

    const dairy = await createCategory(owner, 'Dairy');
    await createCategory(owner, 'Drinks');
    await createCategory(owner, 'Canned food');

    expect(dairy.storeId).toBe(store.id); // resolved from the JWT, not the body
    expect(await namesFor(owner)).toEqual(['Canned food', 'Dairy', 'Drinks']);

    const renamed = await request(http())
      .patch(`/owner/categories/${dairy.id}`)
      .set(auth(owner))
      .send({ name: 'Crèmerie' })
      .expect(200);
    expect(renamed.body).toMatchObject({ id: dairy.id, name: 'Crèmerie' });
    expect(await namesFor(owner)).toEqual([
      'Canned food',
      'Crèmerie',
      'Drinks',
    ]);

    await request(http())
      .delete(`/owner/categories/${dairy.id}`)
      .set(auth(owner))
      .expect(204);
    expect(await namesFor(owner)).toEqual(['Canned food', 'Drinks']);
  });

  it('trims the name', async () => {
    const { owner } = await registerOwnerWithStore();
    const created = await createCategory(owner, '   Snacks  ');
    expect(created.name).toBe('Snacks');
  });

  it('renaming a category to its own name is fine', async () => {
    const { owner } = await registerOwnerWithStore();
    const snacks = await createCategory(owner, 'Snacks');
    await request(http())
      .patch(`/owner/categories/${snacks.id}`)
      .set(auth(owner))
      .send({ name: 'Snacks' })
      .expect(200);
  });
});

describe('name uniqueness', () => {
  it('rejects a duplicate name inside the same store with 409', async () => {
    const { owner } = await registerOwnerWithStore();
    await createCategory(owner, 'Dairy');
    const response = await request(http())
      .post('/owner/categories')
      .set(auth(owner))
      .send({ name: 'Dairy' })
      .expect(409);
    expect(response.body.message).toBe(
      'A category with this name already exists in your store',
    );
    expect(await namesFor(owner)).toEqual(['Dairy']);
  });

  it('treats letter case and surrounding spaces as the same name', async () => {
    const { owner } = await registerOwnerWithStore();
    await createCategory(owner, 'Dairy');
    await request(http())
      .post('/owner/categories')
      .set(auth(owner))
      .send({ name: '  dAIRY ' })
      .expect(409);
  });

  it('rejects renaming onto another category of the same store', async () => {
    const { owner } = await registerOwnerWithStore();
    await createCategory(owner, 'Dairy');
    const drinks = await createCategory(owner, 'Drinks');
    await request(http())
      .patch(`/owner/categories/${drinks.id}`)
      .set(auth(owner))
      .send({ name: 'dairy' })
      .expect(409);
  });

  it('allows the same name in different stores', async () => {
    const a = await registerOwnerWithStore();
    const b = await registerOwnerWithStore();
    const inA = await createCategory(a.owner, 'Dairy');
    const inB = await createCategory(b.owner, 'Dairy');
    expect(inA.id).not.toBe(inB.id);
    expect(inA.storeId).toBe(a.store.id);
    expect(inB.storeId).toBe(b.store.id);
  });

  it('frees the name once the category is deleted', async () => {
    const { owner } = await registerOwnerWithStore();
    const dairy = await createCategory(owner, 'Dairy');
    await request(http())
      .delete(`/owner/categories/${dairy.id}`)
      .set(auth(owner))
      .expect(204);
    await createCategory(owner, 'Dairy');
  });

  it('the database enforces it too, case-insensitively', async () => {
    const { store } = await registerOwnerWithStore();
    await db.orm.public.Category.create({ name: 'Dairy', storeId: store.id });
    await expect(
      db.orm.public.Category.create({ name: 'DAIRY', storeId: store.id }),
    ).rejects.toMatchObject({ sqlState: '23505' });
  });
});

describe('store scoping', () => {
  it('each owner only sees their own categories', async () => {
    const a = await registerOwnerWithStore();
    const b = await registerOwnerWithStore();
    await createCategory(a.owner, 'Only in A');
    await createCategory(b.owner, 'Only in B');
    expect(await namesFor(a.owner)).toEqual(['Only in A']);
    expect(await namesFor(b.owner)).toEqual(['Only in B']);
  });

  it("another store's category cannot be renamed or deleted (404, untouched)", async () => {
    const a = await registerOwnerWithStore();
    const b = await registerOwnerWithStore();
    const inA = await createCategory(a.owner, 'Dairy');

    await request(http())
      .patch(`/owner/categories/${inA.id}`)
      .set(auth(b.owner))
      .send({ name: 'Hijacked' })
      .expect(404);
    await request(http())
      .delete(`/owner/categories/${inA.id}`)
      .set(auth(b.owner))
      .expect(404);

    expect(await namesFor(a.owner)).toEqual(['Dairy']);
  });

  it('a missing id is a 404', async () => {
    const { owner } = await registerOwnerWithStore();
    await request(http())
      .patch('/owner/categories/999999999')
      .set(auth(owner))
      .send({ name: 'Nope' })
      .expect(404);
    await request(http())
      .delete('/owner/categories/999999999')
      .set(auth(owner))
      .expect(404);
  });

  it('rejects storeId in the body — the store is never client-chosen', async () => {
    const a = await registerOwnerWithStore();
    const b = await registerOwnerWithStore();
    await request(http())
      .post('/owner/categories')
      .set(auth(a.owner))
      .send({ name: 'Dairy', storeId: b.store.id })
      .expect(400);
    expect(await namesFor(b.owner)).toEqual([]);
  });

  it('rejects storeId on rename too', async () => {
    const a = await registerOwnerWithStore();
    const b = await registerOwnerWithStore();
    const inA = await createCategory(a.owner, 'Dairy');
    await request(http())
      .patch(`/owner/categories/${inA.id}`)
      .set(auth(a.owner))
      .send({ name: 'Dairy', storeId: b.store.id })
      .expect(400);
  });
});

describe('input validation', () => {
  it.each([
    ['missing', {}],
    ['empty', { name: '' }],
    ['blank', { name: '   ' }],
    ['not a string', { name: 42 }],
    ['null', { name: null }],
    ['too long', { name: 'x'.repeat(51) }],
  ])('rejects a %s name on create with 400', async (_label, body) => {
    const { owner } = await registerOwnerWithStore();
    await request(http())
      .post('/owner/categories')
      .set(auth(owner))
      .send(body)
      .expect(400);
    expect(await namesFor(owner)).toEqual([]);
  });

  it('accepts a name of exactly the maximum length', async () => {
    const { owner } = await registerOwnerWithStore();
    await createCategory(owner, 'x'.repeat(50));
  });

  it.each([
    ['missing', {}],
    ['blank', { name: '  ' }],
    ['too long', { name: 'x'.repeat(51) }],
  ])('rejects a %s name on rename with 400', async (_label, body) => {
    const { owner } = await registerOwnerWithStore();
    const dairy = await createCategory(owner, 'Dairy');
    await request(http())
      .patch(`/owner/categories/${dairy.id}`)
      .set(auth(owner))
      .send(body)
      .expect(400);
    expect(await namesFor(owner)).toEqual(['Dairy']);
  });

  it('rejects a non-numeric id with 400', async () => {
    const { owner } = await registerOwnerWithStore();
    await request(http())
      .delete('/owner/categories/abc')
      .set(auth(owner))
      .expect(400);
  });
});
