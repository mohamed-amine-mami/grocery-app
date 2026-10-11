import request from 'supertest';
import { IMAGE_MAX_BYTES } from '../src/images/image-file.pipe.js';
import { db } from '../src/prisma/db.js';
import {
  type Account,
  auth,
  http,
  imageStorage,
  register,
  registerOwnerWithStore,
  startApp,
  stopApp,
} from './support.js';

beforeAll(startApp);
afterAll(stopApp);
beforeEach(() => {
  imageStorage.failUploads = false;
  imageStorage.failDeletes = false;
  imageStorage.deleted.length = 0;
});

const jpeg = (extra = 64) =>
  Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(extra)]);
const png = () =>
  Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    Buffer.alloc(64),
  ]);
const webp = () =>
  Buffer.concat([
    Buffer.from('RIFF'),
    Buffer.from([0x24, 0, 0, 0]),
    Buffer.from('WEBPVP8 '),
    Buffer.alloc(64),
  ]);

const put = (account: Account, file: Buffer = jpeg(), type = 'image/jpeg') =>
  request(http())
    .put('/owner/store/photo')
    .set(auth(account))
    .attach('file', file, { filename: 'photo.jpg', contentType: type });

const del = (account: Account) =>
  request(http()).delete('/owner/store/photo').set(auth(account));

const row = (ownerId: number) =>
  db.orm.public.Store.select('id', 'photo', 'photoPublicId', 'name').first({
    ownerId,
  });

const setPhotoColumns = (
  ownerId: number,
  photo: string | null,
  photoPublicId: string | null,
) => db.orm.public.Store.where({ ownerId }).update({ photo, photoPublicId });

const SECRET_WORDS = /cloudinary|secret|api_key/i;

describe('authorization', () => {
  it('a customer gets 403 on both endpoints and nothing changes', async () => {
    const { store } = await registerOwnerWithStore();
    const customer = await register('CLIENT');
    const uploads = imageStorage.uploaded.length;
    await put(customer).expect(403);
    await del(customer).expect(403);
    expect(await row(store.ownerId)).toMatchObject({
      photo: null,
      photoPublicId: null,
    });
    expect(imageStorage.uploaded).toHaveLength(uploads);
  });

  it('requires authentication', async () => {
    await request(http())
      .put('/owner/store/photo')
      .attach('file', jpeg(), 'photo.jpg')
      .expect(401);
    await request(http()).delete('/owner/store/photo').expect(401);
    await request(http())
      .put('/owner/store/photo')
      .set({ Authorization: 'Bearer forged' })
      .attach('file', jpeg(), 'photo.jpg')
      .expect(401);
  });

  it('an owner without a store gets 404 and nothing is uploaded', async () => {
    const owner = await register('OWNER');
    const uploads = imageStorage.uploaded.length;
    await put(owner).expect(404);
    await del(owner).expect(404);
    expect(imageStorage.uploaded).toHaveLength(uploads);
    expect(imageStorage.deleted).toEqual([]);
  });

  it('only ever changes the caller’s own store: no id in the path, none in the body', async () => {
    const mine = await registerOwnerWithStore();
    const theirs = await registerOwnerWithStore();
    await request(http())
      .put(`/owner/store/${theirs.store.id}/photo`)
      .set(auth(mine.owner))
      .attach('file', jpeg(), 'photo.jpg')
      .expect(404);
    await request(http())
      .put('/owner/store/photo')
      .query({ storeId: theirs.store.id, ownerId: theirs.owner.id })
      .set(auth(mine.owner))
      .field('storeId', String(theirs.store.id))
      .field('ownerId', String(theirs.owner.id))
      .attach('file', jpeg(), 'photo.jpg')
      .expect(200);
    expect((await row(mine.owner.id))!.photo).not.toBeNull();
    expect(await row(theirs.owner.id)).toMatchObject({
      photo: null,
      photoPublicId: null,
    });

    await put(theirs.owner).expect(200);
    await del(mine.owner).expect(200);
    expect((await row(theirs.owner.id))!.photo).not.toBeNull();
  });
});

describe('PUT /owner/store/photo', () => {
  it('stores the image under stores/{storeId}/photo-… with the store profile', async () => {
    const { owner, store } = await registerOwnerWithStore();
    const response = await put(owner).expect(200);

    const saved = (await row(owner.id))!;
    expect(saved.photoPublicId).toMatch(
      new RegExp(`^stores/${store.id}/photo-[0-9a-f]{16}$`),
    );
    expect(saved.photo).toBe(response.body.photo);
    expect(response.body.photo).toContain('/f_auto,q_auto/');
    expect(response.body.id).toBe(store.id);
    expect(response.body.name).toBe(store.name);
    expect(response.body).not.toHaveProperty('photoPublicId');

    const stored = imageStorage.uploaded.find(
      (i) => i.publicId === saved.photoPublicId,
    );
    expect(stored!.options).toMatchObject({
      folder: `stores/${store.id}`,
      name: 'photo',
      profile: { uploadTransformation: 'c_limit,w_1200' },
    });
    expect(stored!.file.equals(jpeg())).toBe(true);
  });

  it.each([
    ['JPEG', jpeg, 'image/jpeg'],
    ['PNG', png, 'image/png'],
    ['WebP', webp, 'image/webp'],
  ])('accepts a %s', async (_name, make, type) => {
    const { owner } = await registerOwnerWithStore();
    await put(owner, make(), type).expect(200);
  });

  it('accepts exactly 5 MB and refuses more with 413, changing nothing', async () => {
    const { owner } = await registerOwnerWithStore();
    const atLimit = Buffer.concat([
      Buffer.from([0xff, 0xd8, 0xff]),
      Buffer.alloc(IMAGE_MAX_BYTES - 3),
    ]);
    await put(owner, atLimit).expect(200);
    const before = await row(owner.id);
    const uploads = imageStorage.uploaded.length;
    await put(owner, Buffer.concat([atLimit, Buffer.alloc(1)])).expect(413);
    expect(await row(owner.id)).toEqual(before);
    expect(imageStorage.uploaded).toHaveLength(uploads);
  });

  it('refuses a missing file, a wrong field, and a non-image — whatever the client claims', async () => {
    const { owner, store } = await registerOwnerWithStore();
    await request(http())
      .put('/owner/store/photo')
      .set(auth(owner))
      .expect(400);
    await request(http())
      .put('/owner/store/photo')
      .set(auth(owner))
      .attach('picture', jpeg(), 'photo.jpg')
      .expect(400);
    await put(
      owner,
      Buffer.from('plain text, not an image'),
      'image/jpeg',
    ).expect(400);
    await put(
      owner,
      Buffer.from('GIF89a' + 'x'.repeat(64)),
      'image/gif',
    ).expect(400);
    await put(owner, Buffer.from('<svg></svg>'), 'image/svg+xml').expect(400);
    expect(await row(owner.id)).toMatchObject({
      photo: null,
      photoPublicId: null,
    });
    expect(
      imageStorage.uploaded.some((i) =>
        i.publicId.startsWith(`stores/${store.id}/`),
      ),
    ).toBe(false);
  });

  it('leaves the rest of the store alone', async () => {
    const { owner, store } = await registerOwnerWithStore({
      description: 'Fresh produce',
    });
    await request(http())
      .patch('/owner/store')
      .set(auth(owner))
      .send({ isOpen: true })
      .expect(200);
    const response = await put(owner).expect(200);
    expect(response.body).toMatchObject({
      id: store.id,
      name: store.name,
      address: store.address,
      description: 'Fresh produce',
      isOpen: true,
      ownerId: owner.id,
    });
  });
});

describe('replacing a managed photo', () => {
  it('uploads the new image, switches the database, then deletes the old one', async () => {
    const { owner } = await registerOwnerWithStore();
    await put(owner).expect(200);
    const first = (await row(owner.id))!.photoPublicId!;
    expect(imageStorage.deleted).toEqual([]);

    const response = await put(owner, png(), 'image/png').expect(200);
    const second = (await row(owner.id))!;
    expect(second.photoPublicId).not.toBe(first);
    expect(second.photo).toBe(response.body.photo);
    expect(imageStorage.has(second.photoPublicId!)).toBe(true);
    expect(imageStorage.has(first)).toBe(false);
    expect(imageStorage.deleted).toEqual([first]);
  });

  it('still succeeds when removing the old image fails (an orphan, not an error)', async () => {
    const { owner } = await registerOwnerWithStore();
    await put(owner).expect(200);
    imageStorage.failDeletes = true;
    const response = await put(owner).expect(200);
    expect((await row(owner.id))!.photo).toBe(response.body.photo);
  });

  it('keeps the old database values and old image, and removes the new image, when the database step fails', async () => {
    const { owner } = await registerOwnerWithStore();
    await put(owner).expect(200);
    const before = (await row(owner.id))!;

    // A real database failure: a trigger refuses updates to this store.
    await db.orm.public.Store.where({ ownerId: owner.id }).update({
      name: 'e2e-store-photo-db-failure',
    });
    await createFailureTrigger();
    try {
      const uploadsBefore = imageStorage.uploaded.length;
      const response = await put(owner, png(), 'image/png').expect(500);
      expect(JSON.stringify(response.body)).not.toMatch(
        /forced failure|cloudinary/i,
      );

      const after = (await row(owner.id))!;
      expect(after.photo).toBe(before.photo);
      expect(after.photoPublicId).toBe(before.photoPublicId);
      expect(imageStorage.has(before.photoPublicId!)).toBe(true); // old image kept
      expect(imageStorage.uploaded).toHaveLength(uploadsBefore); // new one removed
      expect(imageStorage.deleted).toHaveLength(1);
      expect(imageStorage.deleted[0]).toMatch(
        new RegExp(`^stores/${before.id}/photo-[0-9a-f]{16}$`),
      );
      expect(imageStorage.deleted[0]).not.toBe(before.photoPublicId);
    } finally {
      await dropFailureTrigger();
    }
  });

  it('replaces a legacy URL and never asks storage to delete it', async () => {
    const { owner } = await registerOwnerWithStore();
    await setPhotoColumns(owner.id, 'https://legacy.example/store.jpg', null);
    const response = await put(owner).expect(200);
    expect(response.body.photo).not.toBe('https://legacy.example/store.jpg');
    expect((await row(owner.id))!.photoPublicId).toMatch(/^stores\//);
    expect(imageStorage.deleted).toEqual([]);
  });

  it('answers 503, without leaking details, and changes nothing when the upload fails', async () => {
    const { owner } = await registerOwnerWithStore();
    await put(owner).expect(200);
    const before = await row(owner.id);
    imageStorage.failUploads = true;
    const response = await put(owner).expect(503);
    expect(JSON.stringify(response.body)).not.toMatch(SECRET_WORDS);
    expect(await row(owner.id)).toEqual(before);
  });
});

describe('DELETE /owner/store/photo', () => {
  it('clears both columns and deletes the managed image', async () => {
    const { owner, store } = await registerOwnerWithStore();
    await put(owner).expect(200);
    const { photoPublicId } = (await row(owner.id))!;

    const response = await del(owner).expect(200);
    expect(response.body.photo).toBeNull();
    expect(response.body.id).toBe(store.id);
    expect(response.body).not.toHaveProperty('photoPublicId');
    expect(await row(owner.id)).toMatchObject({
      photo: null,
      photoPublicId: null,
    });
    expect(imageStorage.has(photoPublicId!)).toBe(false);
    expect(imageStorage.deleted).toEqual([photoPublicId]);
  });

  it('is idempotent: no photo is a 200 and storage is not called', async () => {
    const { owner } = await registerOwnerWithStore();
    for (let i = 0; i < 2; i++) {
      const response = await del(owner).expect(200);
      expect(response.body.photo).toBeNull();
    }
    expect(imageStorage.deleted).toEqual([]);
  });

  it('clears a legacy URL without touching storage', async () => {
    const { owner } = await registerOwnerWithStore();
    await setPhotoColumns(owner.id, 'https://legacy.example/store.jpg', null);
    await del(owner).expect(200);
    expect(await row(owner.id)).toMatchObject({
      photo: null,
      photoPublicId: null,
    });
    expect(imageStorage.deleted).toEqual([]);
  });

  it('keeps the database cleared when deleting the stored image fails (503)', async () => {
    const { owner } = await registerOwnerWithStore();
    await put(owner).expect(200);
    const { photoPublicId } = (await row(owner.id))!;
    imageStorage.failDeletes = true;

    const response = await del(owner).expect(503);
    expect(JSON.stringify(response.body)).not.toMatch(SECRET_WORDS);
    expect(await row(owner.id)).toMatchObject({
      photo: null,
      photoPublicId: null,
    });
    expect(imageStorage.has(photoPublicId!)).toBe(true); // an orphan, but unreferenced
  });
});

describe('the photo never exposes its storage reference', () => {
  it('is returned as `photo`, and `photoPublicId` is absent from every store response', async () => {
    const { owner, store } = await registerOwnerWithStore();
    const uploaded = await put(owner).expect(200);
    const { photo } = (await row(owner.id))!;
    expect(photo).toBe(uploaded.body.photo);

    const mine = await request(http())
      .get('/owner/store')
      .set(auth(owner))
      .expect(200);
    expect(mine.body.photo).toBe(photo);
    const patched = await request(http())
      .patch('/owner/store')
      .set(auth(owner))
      .send({ name: 'Renamed' })
      .expect(200);
    expect(patched.body.photo).toBe(photo);
    const created = await request(http())
      .post('/owner/store')
      .set(auth(await register('OWNER')))
      .send({ name: 'Another', address: 'Somewhere' })
      .expect(201);
    expect(created.body.photo).toBeNull();
    for (const body of [uploaded.body, mine.body, patched.body, created.body]) {
      expect(body).not.toHaveProperty('photoPublicId');
      expect(JSON.stringify(body)).not.toContain('photoPublicId');
    }

    // What customers see.
    const customer = await register('CLIENT');
    const list = await request(http())
      .get('/stores')
      .set(auth(customer))
      .expect(200);
    const listed = list.body.find((s: { id: number }) => s.id === store.id);
    expect(listed.photo).toBe(photo);
    expect(listed).not.toHaveProperty('photoPublicId');
    expect(JSON.stringify(list.body)).not.toContain('photoPublicId');

    await del(owner).expect(200);
    const after = await request(http())
      .get('/stores')
      .set(auth(customer))
      .expect(200);
    expect(
      after.body.find((s: { id: number }) => s.id === store.id).photo,
    ).toBeNull();
  });
});

type Transaction = Parameters<Parameters<typeof db.transaction>[0]>[0];

async function execute(plan: Parameters<Transaction['execute']>[0]) {
  await db.transaction(async (tx) => {
    await tx.execute(plan);
  });
}

/** Raw statements take literal SQL only, so each trigger statement is spelled out. */
async function createFailureTrigger() {
  await execute(
    db.raw
      .sql`CREATE OR REPLACE FUNCTION e2e_store_photo_fail() RETURNS trigger AS $$ BEGIN IF NEW."name" = 'e2e-store-photo-db-failure' THEN RAISE EXCEPTION 'forced failure'; END IF; RETURN NEW; END $$ LANGUAGE plpgsql`
      .affectedCount()
      .build(),
  );
  await execute(
    db.raw
      .sql`CREATE TRIGGER e2e_store_photo_fail BEFORE UPDATE ON "Store" FOR EACH ROW EXECUTE FUNCTION e2e_store_photo_fail()`
      .affectedCount()
      .build(),
  );
}

async function dropFailureTrigger() {
  await execute(
    db.raw.sql`DROP TRIGGER IF EXISTS e2e_store_photo_fail ON "Store"`
      .affectedCount()
      .build(),
  );
  await execute(
    db.raw.sql`DROP FUNCTION IF EXISTS e2e_store_photo_fail()`
      .affectedCount()
      .build(),
  );
}

afterAll(dropFailureTrigger);
