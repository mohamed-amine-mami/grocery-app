import request from 'supertest';
import { db } from '../src/prisma/db.js';
import {
  auth,
  http,
  register,
  registerOwnerWithStore,
  startApp,
  stopApp,
  trackUser,
  validStore,
} from './support.js';

beforeAll(startApp);
afterAll(stopApp);

describe('authentication', () => {
  it.each([
    ['GET', 'get'],
    ['POST', 'post'],
    ['PATCH', 'patch'],
  ] as const)(
    '%s /owner/store without a token is 401',
    async (_label, verb) => {
      await request(http())[verb]('/owner/store').send(validStore).expect(401);
    },
  );

  it('rejects a malformed or forged token with 401', async () => {
    await request(http())
      .get('/owner/store')
      .set('Authorization', 'Bearer not-a-real-token')
      .expect(401);
  });
});

describe('authorization', () => {
  it.each([
    ['GET', 'get'],
    ['POST', 'post'],
    ['PATCH', 'patch'],
  ] as const)('a CLIENT gets 403 on %s /owner/store', async (_label, verb) => {
    const client = await register('CLIENT');
    await request(http())
      [verb]('/owner/store')
      .set(auth(client))
      .send(validStore)
      .expect(403);
  });

  it('a CLIENT cannot create a store by spoofing an owner id either', async () => {
    const client = await register('CLIENT');
    await request(http())
      .post('/owner/store')
      .set(auth(client))
      .send({ ...validStore, ownerId: client.id })
      .expect(403);
    expect(await db.orm.public.Store.first({ ownerId: client.id })).toBeNull();
  });

  it('an OWNER can reach the owner routes', async () => {
    const owner = await register('OWNER');
    await request(http()).get('/owner/store').set(auth(owner)).expect(404); // allowed, just no store yet
    await request(http())
      .post('/owner/store')
      .set(auth(owner))
      .send(validStore)
      .expect(201);
    await request(http()).get('/owner/store').set(auth(owner)).expect(200);
  });
});

describe('owner without a store', () => {
  it('GET /owner/store is a clear 404, even when other stores exist', async () => {
    await registerOwnerWithStore();
    const storeless = await register('OWNER');
    const response = await request(http())
      .get('/owner/store')
      .set(auth(storeless))
      .expect(404);
    expect(response.body.message).toBe('This owner has no store yet');
  });

  it('PATCH /owner/store is 404 and never touches another owner’s store', async () => {
    const { store } = await registerOwnerWithStore();
    const storeless = await register('OWNER');
    await request(http())
      .patch('/owner/store')
      .set(auth(storeless))
      .send({ name: 'Hijacked' })
      .expect(404);
    const untouched = await db.orm.public.Store.first({ id: store.id });
    expect(untouched?.name).toBe(validStore.name);
  });
});

describe('store creation', () => {
  it('derives the owner from the JWT and starts the store closed', async () => {
    const { owner, store } = await registerOwnerWithStore();
    expect(store.ownerId).toBe(owner.id);
    expect(store.isOpen).toBe(false);
    expect(store).toMatchObject({
      name: validStore.name,
      address: validStore.address,
      description: null,
      photo: null,
      latitude: null,
      longitude: null,
    });
  });

  it('rejects a spoofed ownerId (400) and creates nothing', async () => {
    const attacker = await register('OWNER');
    const victim = await register('OWNER');
    await request(http())
      .post('/owner/store')
      .set(auth(attacker))
      .send({ ...validStore, ownerId: victim.id })
      .expect(400);
    expect(await db.orm.public.Store.first({ ownerId: victim.id })).toBeNull();
    expect(
      await db.orm.public.Store.first({ ownerId: attacker.id }),
    ).toBeNull();
  });

  it('rejects isOpen on creation — stores always start closed', async () => {
    const owner = await register('OWNER');
    await request(http())
      .post('/owner/store')
      .set(auth(owner))
      .send({ ...validStore, isOpen: true })
      .expect(400);
  });

  it('rejects a second store for the same owner with 409', async () => {
    const { owner, store } = await registerOwnerWithStore();
    const response = await request(http())
      .post('/owner/store')
      .set(auth(owner))
      .send({ ...validStore, name: 'Second store' })
      .expect(409);
    expect(response.body.message).toBe('This owner already has a store');
    const current = await request(http())
      .get('/owner/store')
      .set(auth(owner))
      .expect(200);
    expect(current.body.id).toBe(store.id);
  });

  it('requires an address', async () => {
    const owner = await register('OWNER');
    await request(http())
      .post('/owner/store')
      .set(auth(owner))
      .send({ name: 'No address' })
      .expect(400);
  });

  it('accepts coordinates given together', async () => {
    const { store } = await registerOwnerWithStore({
      latitude: 36.8065,
      longitude: 10.1815,
    });
    expect(store).toMatchObject({ latitude: 36.8065, longitude: 10.1815 });
  });

  it.each([{ latitude: 36.8 }, { longitude: 10.1 }])(
    'rejects a lone coordinate %j with 400',
    async (coordinates) => {
      const owner = await register('OWNER');
      await request(http())
        .post('/owner/store')
        .set(auth(owner))
        .send({ ...validStore, ...coordinates })
        .expect(400);
    },
  );
});

describe('reading and updating the own store', () => {
  it('each owner only ever sees their own store', async () => {
    const a = await registerOwnerWithStore({ name: 'Store A' });
    const b = await registerOwnerWithStore({ name: 'Store B' });

    const seenByA = await request(http())
      .get('/owner/store')
      .set(auth(a.owner))
      .expect(200);
    const seenByB = await request(http())
      .get('/owner/store')
      .set(auth(b.owner))
      .expect(200);

    expect(seenByA.body).toMatchObject({ id: a.store.id, name: 'Store A' });
    expect(seenByB.body).toMatchObject({ id: b.store.id, name: 'Store B' });
  });

  it('PATCH only changes the caller’s store', async () => {
    const a = await registerOwnerWithStore({ name: 'Store A' });
    const b = await registerOwnerWithStore({ name: 'Store B' });

    await request(http())
      .patch('/owner/store')
      .set(auth(a.owner))
      .send({ name: 'Store A renamed' })
      .expect(200);

    expect((await db.orm.public.Store.first({ id: a.store.id }))?.name).toBe(
      'Store A renamed',
    );
    expect((await db.orm.public.Store.first({ id: b.store.id }))?.name).toBe(
      'Store B',
    );
  });

  it('PATCH cannot reassign the store to another owner', async () => {
    const a = await registerOwnerWithStore();
    const b = await register('OWNER');
    await request(http())
      .patch('/owner/store')
      .set(auth(a.owner))
      .send({ ownerId: b.id })
      .expect(400);
    expect((await db.orm.public.Store.first({ id: a.store.id }))?.ownerId).toBe(
      a.owner.id,
    );
  });

  it('the owner can open and close the store', async () => {
    const { owner } = await registerOwnerWithStore();
    const opened = await request(http())
      .patch('/owner/store')
      .set(auth(owner))
      .send({ isOpen: true })
      .expect(200);
    expect(opened.body.isOpen).toBe(true);
    const closed = await request(http())
      .patch('/owner/store')
      .set(auth(owner))
      .send({ isOpen: false })
      .expect(200);
    expect(closed.body.isOpen).toBe(false);
  });

  it('an empty PATCH is a no-op that returns the store', async () => {
    const { owner, store } = await registerOwnerWithStore();
    const response = await request(http())
      .patch('/owner/store')
      .set(auth(owner))
      .send({})
      .expect(200);
    expect(response.body.id).toBe(store.id);
  });

  it('PATCH keeps latitude and longitude together', async () => {
    const { owner } = await registerOwnerWithStore({
      latitude: 36.8,
      longitude: 10.1,
    });

    await request(http())
      .patch('/owner/store')
      .set(auth(owner))
      .send({ latitude: 35 })
      .expect(400);
    await request(http())
      .patch('/owner/store')
      .set(auth(owner))
      .send({ longitude: 9 })
      .expect(400);

    const moved = await request(http())
      .patch('/owner/store')
      .set(auth(owner))
      .send({ latitude: 35, longitude: 9 })
      .expect(200);
    expect(moved.body).toMatchObject({ latitude: 35, longitude: 9 });

    const cleared = await request(http())
      .patch('/owner/store')
      .set(auth(owner))
      .send({ latitude: null, longitude: null })
      .expect(200);
    expect(cleared.body).toMatchObject({ latitude: null, longitude: null });
  });

  it.each(['name', 'address'])(
    'PATCH { %s: null } is a 400, not a 500',
    async (field) => {
      const { owner } = await registerOwnerWithStore();
      await request(http())
        .patch('/owner/store')
        .set(auth(owner))
        .send({ [field]: null })
        .expect(400);
    },
  );
});

describe('phone number', () => {
  it('registration requires a phone number', async () => {
    await request(http())
      .post('/auth/register')
      .send({
        name: 'No Phone',
        email: `nophone-${Date.now()}@example.com`,
        password: 'changeme123',
        role: 'CLIENT',
      })
      .expect(400);
  });

  it.each(['abc', '123', '', '+1234567890123456'])(
    'registration rejects %j',
    async (phoneNumber) => {
      await request(http())
        .post('/auth/register')
        .send({
          name: 'Bad Phone',
          email: `badphone-${Date.now()}@example.com`,
          password: 'changeme123',
          phoneNumber,
          role: 'CLIENT',
        })
        .expect(400);
    },
  );

  it('a number typed with separators registers and logs in as the same number', async () => {
    const digits = `${Date.now()}`.slice(-8);
    const spaced = `+216 ${digits.slice(0, 2)} ${digits.slice(2, 5)} ${digits.slice(5)}`;
    const registered = await request(http())
      .post('/auth/register')
      .send({
        name: 'Spaced Phone',
        email: `spaced-${Date.now()}@example.com`,
        password: 'changeme123',
        phoneNumber: spaced,
        role: 'CLIENT',
      })
      .expect(201);
    trackUser(registered.body.user.id);
    expect(registered.body.user.phoneNumber).toBe(`+216${digits}`);

    await request(http())
      .post('/auth/login')
      .send({ phoneNumber: `+216${digits}`, password: 'changeme123' })
      .expect(200);
    await request(http())
      .post('/auth/login')
      .send({ phoneNumber: spaced, password: 'changeme123' })
      .expect(200);
  });

  it('the database itself refuses a user without a phone number', async () => {
    await expect(
      db.orm.public.User.create({
        name: 'Raw insert',
        email: `raw-${Date.now()}@example.com`,
        password: 'x',
      } as never),
    ).rejects.toMatchObject({ sqlState: '23502' });
  });
});

describe('database constraints (defence in depth)', () => {
  it('a store inserted directly still defaults to closed', async () => {
    const owner = await register('OWNER');
    const store = await db.orm.public.Store.create({
      name: 'Raw store',
      address: 'Somewhere',
      ownerId: owner.id,
    });
    expect(store.isOpen).toBe(false);
  });

  it('the database refuses a lone coordinate', async () => {
    const owner = await register('OWNER');
    await expect(
      db.orm.public.Store.create({
        name: 'Raw store',
        address: 'Somewhere',
        latitude: 36.8,
        ownerId: owner.id,
      }),
    ).rejects.toMatchObject({ sqlState: '23514' });
  });

  it('the database enforces one store per owner', async () => {
    const { owner } = await registerOwnerWithStore();
    await expect(
      db.orm.public.Store.create({
        name: 'Another',
        address: 'Somewhere',
        ownerId: owner.id,
      }),
    ).rejects.toMatchObject({ sqlState: '23505' });
  });
});

describe('photo columns (contract preparation)', () => {
  const photo = 'https://res.cloudinary.example/stores/1/photo.jpg';

  it('no client can supply a photo or a photo reference', async () => {
    const photoPayload = { photo };
    const referencePayload = { photoPublicId: 'stores/1/photo' };
    const owner = await register('OWNER');
    for (const extra of [photoPayload, referencePayload]) {
      await request(http())
        .post('/owner/store')
        .set(auth(owner))
        .send({ ...validStore, ...extra })
        .expect(400);
      await request(http())
        .post('/auth/register')
        .send({
          name: 'Photo Client',
          email: `photo-${Date.now()}@example.com`,
          password: 'changeme123',
          phoneNumber: '+21699999999',
          role: 'CLIENT',
          ...extra,
        })
        .expect(400);
    }
    expect(await db.orm.public.Store.first({ ownerId: owner.id })).toBeNull();
  });

  it('PATCH /owner/store rejects a photo and leaves the store alone', async () => {
    const { owner, store } = await registerOwnerWithStore();
    await request(http())
      .patch('/owner/store')
      .set(auth(owner))
      .send({ photo })
      .expect(400);
    await request(http())
      .patch('/owner/store')
      .set(auth(owner))
      .send({ photoPublicId: 'stores/1/photo' })
      .expect(400);
    const row = await db.orm.public.Store.first({ id: store.id });
    expect(row).toMatchObject({ photo: null, photoPublicId: null });
  });

  it('a stored photo is still returned, and its reference never is', async () => {
    const { owner, store } = await registerOwnerWithStore();
    await db.orm.public.Store.where({ id: store.id }).update({
      photo,
      photoPublicId: 'stores/1/photo',
    });
    await db.orm.public.User.where({ id: owner.id }).update({
      photo: 'https://res.cloudinary.example/users/1/me.jpg',
      photoPublicId: 'users/1/me',
    });

    const mine = await request(http())
      .get('/owner/store')
      .set(auth(owner))
      .expect(200);
    expect(mine.body.photo).toBe(photo);
    expect(mine.body).not.toHaveProperty('photoPublicId');

    const patched = await request(http())
      .patch('/owner/store')
      .set(auth(owner))
      .send({ name: 'Renamed' })
      .expect(200);
    expect(patched.body.photo).toBe(photo);
    expect(patched.body).not.toHaveProperty('photoPublicId');

    const me = await request(http())
      .get('/auth/me')
      .set(auth(owner))
      .expect(200);
    expect(me.body.photo).toBe('https://res.cloudinary.example/users/1/me.jpg');
    expect(me.body).not.toHaveProperty('photoPublicId');

    const login = await request(http())
      .post('/auth/login')
      .send({ phoneNumber: owner.phoneNumber, password: 'changeme123' })
      .expect(200);
    expect(login.body.user.photo).toBe(
      'https://res.cloudinary.example/users/1/me.jpg',
    );
    expect(login.body.user).not.toHaveProperty('photoPublicId');

    const customer = await register('CLIENT');
    const stores = await request(http())
      .get('/stores')
      .set(auth(customer))
      .expect(200);
    const listed = stores.body.find((s: { id: number }) => s.id === store.id);
    expect(listed.photo).toBe(photo);
    expect(listed).not.toHaveProperty('photoPublicId');
  });

  it('the database refuses a photo reference without a photo (store and user)', async () => {
    const { owner, store } = await registerOwnerWithStore();
    await expect(
      db.orm.public.Store.where({ id: store.id }).update({
        photoPublicId: 'stores/1/photo',
      }),
    ).rejects.toMatchObject({ sqlState: '23514' });
    await expect(
      db.orm.public.User.where({ id: owner.id }).update({
        photoPublicId: 'users/1/me',
      }),
    ).rejects.toMatchObject({ sqlState: '23514' });
    // A photo without a reference (an existing plain URL) stays valid.
    await db.orm.public.Store.where({ id: store.id }).update({ photo });
    expect(await db.orm.public.Store.first({ id: store.id })).toMatchObject({
      photo,
      photoPublicId: null,
    });
  });
});
