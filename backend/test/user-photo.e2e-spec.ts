import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { setupApp } from '../src/app.setup.js';
import { IMAGE_MAX_BYTES } from '../src/images/image-file.pipe.js';
import { db } from '../src/prisma/db.js';
import {
  type Account,
  auth,
  http,
  imageStorage,
  register,
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
    .put('/users/me/photo')
    .set(auth(account))
    .attach('file', file, { filename: 'photo.jpg', contentType: type });

const row = (id: number) =>
  db.orm.public.User.select('photo', 'photoPublicId', 'name').first({ id });

/** Gives the user a photo directly in the database (what an earlier upload leaves). */
const setPhotoColumns = (
  id: number,
  photo: string | null,
  photoPublicId: string | null,
) => db.orm.public.User.where({ id }).update({ photo, photoPublicId });

describe('PUT /users/me/photo', () => {
  it.each(['CLIENT', 'OWNER'] as const)(
    'a %s can set their own photo',
    async (role) => {
      const account = await register(role);
      const response = await put(account).expect(200);

      const saved = await row(account.id);
      expect(saved!.photoPublicId).toMatch(
        new RegExp(`^users/${account.id}/profile-[0-9a-f]{16}$`),
      );
      expect(saved!.photo).toBe(response.body.photo);
      expect(response.body.photo).toContain('/f_auto,q_auto/');
      expect(response.body.id).toBe(account.id);
      expect(response.body).not.toHaveProperty('photoPublicId');
      expect(response.body).not.toHaveProperty('password');
      expect(imageStorage.has(saved!.photoPublicId!)).toBe(true);
    },
  );

  it('stores the avatar profile and the file bytes through the storage abstraction', async () => {
    const account = await register('CLIENT');
    await put(account).expect(200);
    const saved = await row(account.id);
    const stored = imageStorage.uploaded.find(
      (image) => image.publicId === saved!.photoPublicId,
    );
    expect(stored!.options).toMatchObject({
      folder: `users/${account.id}`,
      name: 'profile',
      profile: { uploadTransformation: 'c_fill,g_auto,w_512,h_512' },
    });
    expect(stored!.file.equals(jpeg())).toBe(true);
  });

  it.each([
    ['JPEG', jpeg, 'image/jpeg'],
    ['PNG', png, 'image/png'],
    ['WebP', webp, 'image/webp'],
  ])('accepts a %s', async (_name, make, type) => {
    const account = await register('CLIENT');
    await put(account, make(), type).expect(200);
  });

  it('accepts exactly 5 MB and refuses more with 413, changing nothing', async () => {
    const account = await register('CLIENT');
    const atLimit = Buffer.concat([
      Buffer.from([0xff, 0xd8, 0xff]),
      Buffer.alloc(IMAGE_MAX_BYTES - 3),
    ]);
    await put(account, atLimit).expect(200);
    const before = await row(account.id);
    const uploads = imageStorage.uploaded.length;

    await put(account, Buffer.concat([atLimit, Buffer.alloc(1)])).expect(413);
    expect(await row(account.id)).toEqual(before);
    expect(imageStorage.uploaded).toHaveLength(uploads);
  });

  it('refuses a missing file, a wrong field, and a non-image — whatever the client claims', async () => {
    const account = await register('CLIENT');
    await request(http()).put('/users/me/photo').set(auth(account)).expect(400);
    await request(http())
      .put('/users/me/photo')
      .set(auth(account))
      .attach('picture', jpeg(), 'photo.jpg')
      .expect(400);
    await put(
      account,
      Buffer.from('plain text, not an image'),
      'image/jpeg',
    ).expect(400);
    await put(
      account,
      Buffer.from('GIF89a' + 'x'.repeat(64)),
      'image/gif',
    ).expect(400);
    await put(account, Buffer.from('<svg></svg>'), 'image/svg+xml').expect(400);
    expect(await row(account.id)).toMatchObject({
      photo: null,
      photoPublicId: null,
    });
    expect(
      imageStorage.uploaded.some((i) =>
        i.publicId.startsWith(`users/${account.id}/`),
      ),
    ).toBe(false);
  });

  it('requires authentication', async () => {
    await request(http())
      .put('/users/me/photo')
      .attach('file', jpeg(), 'photo.jpg')
      .expect(401);
    await request(http())
      .put('/users/me/photo')
      .set({ Authorization: 'Bearer forged' })
      .attach('file', jpeg(), 'photo.jpg')
      .expect(401);
  });

  it('only ever changes the caller: no id in the path, and none in the body', async () => {
    const caller = await register('CLIENT');
    const other = await register('CLIENT');
    await request(http())
      .put(`/users/${other.id}/photo`)
      .set(auth(caller))
      .attach('file', jpeg(), 'photo.jpg')
      .expect(404);
    await request(http())
      .put('/users/me/photo')
      .query({ userId: other.id })
      .set(auth(caller))
      .field('userId', String(other.id))
      .attach('file', jpeg(), 'photo.jpg')
      .expect(200);
    expect((await row(caller.id))!.photo).not.toBeNull();
    expect(await row(other.id)).toMatchObject({
      photo: null,
      photoPublicId: null,
    });
  });

  describe('replacing a managed photo', () => {
    it('uploads the new image, switches the database, then deletes the old one', async () => {
      const account = await register('CLIENT');
      await put(account).expect(200);
      const first = (await row(account.id))!.photoPublicId!;
      expect(imageStorage.deleted).toEqual([]);

      const response = await put(account, png(), 'image/png').expect(200);
      const second = (await row(account.id))!;
      expect(second.photoPublicId).not.toBe(first);
      expect(second.photo).toBe(response.body.photo);
      expect(imageStorage.has(second.photoPublicId!)).toBe(true);
      expect(imageStorage.has(first)).toBe(false);
      expect(imageStorage.deleted).toEqual([first]);
    });

    it('still succeeds when removing the old image fails (an orphan, not an error)', async () => {
      const account = await register('CLIENT');
      await put(account).expect(200);
      imageStorage.failDeletes = true;
      const response = await put(account).expect(200);
      expect((await row(account.id))!.photo).toBe(response.body.photo);
    });

    it('keeps the old database values and removes the new image when the database step fails', async () => {
      const account = await register('CLIENT');
      await put(account).expect(200);
      const before = (await row(account.id))!;

      // A real database failure: a trigger refuses photo writes for this user.
      await db.orm.public.User.where({ id: account.id }).update({
        name: 'e2e-photo-db-failure',
      });
      await createFailureTrigger();
      try {
        const uploadsBefore = imageStorage.uploaded.length;
        const response = await put(account, png(), 'image/png').expect(500);
        expect(JSON.stringify(response.body)).not.toMatch(
          /forced failure|cloudinary/i,
        );

        const after = (await row(account.id))!;
        expect(after.photo).toBe(before.photo);
        expect(after.photoPublicId).toBe(before.photoPublicId);
        expect(imageStorage.has(before.photoPublicId!)).toBe(true); // old image kept
        expect(imageStorage.uploaded).toHaveLength(uploadsBefore); // new one removed
        expect(imageStorage.deleted).toHaveLength(1);
        expect(imageStorage.deleted[0]).toMatch(
          new RegExp(`^users/${account.id}/profile-[0-9a-f]{16}$`),
        );
        expect(imageStorage.deleted[0]).not.toBe(before.photoPublicId);
      } finally {
        await dropFailureTrigger();
      }
    });
  });

  describe('replacing a legacy URL', () => {
    it('replaces it and never asks storage to delete it', async () => {
      const account = await register('CLIENT');
      await setPhotoColumns(account.id, 'https://legacy.example/me.jpg', null);

      const response = await put(account).expect(200);
      expect(response.body.photo).not.toBe('https://legacy.example/me.jpg');
      expect((await row(account.id))!.photoPublicId).toMatch(/^users\//);
      expect(imageStorage.deleted).toEqual([]);
    });
  });

  describe('storage failures', () => {
    it('answers 503, without leaking details, and changes nothing when the upload fails', async () => {
      const account = await register('CLIENT');
      await put(account).expect(200);
      const before = await row(account.id);
      imageStorage.failUploads = true;
      const response = await put(account).expect(503);
      expect(JSON.stringify(response.body)).not.toMatch(
        /cloudinary|secret|api_key/i,
      );
      expect(await row(account.id)).toEqual(before);
    });
  });
});

describe('DELETE /users/me/photo', () => {
  it('clears both columns and deletes the managed image', async () => {
    const account = await register('OWNER');
    await put(account).expect(200);
    const { photoPublicId } = (await row(account.id))!;

    const response = await request(http())
      .delete('/users/me/photo')
      .set(auth(account))
      .expect(200);
    expect(response.body.photo).toBeNull();
    expect(response.body.id).toBe(account.id);
    expect(response.body).not.toHaveProperty('photoPublicId');
    expect(await row(account.id)).toMatchObject({
      photo: null,
      photoPublicId: null,
    });
    expect(imageStorage.has(photoPublicId!)).toBe(false);
    expect(imageStorage.deleted).toEqual([photoPublicId]);
  });

  it('is idempotent: no photo is a 200 and storage is not called', async () => {
    const account = await register('CLIENT');
    for (let i = 0; i < 2; i++) {
      const response = await request(http())
        .delete('/users/me/photo')
        .set(auth(account))
        .expect(200);
      expect(response.body.photo).toBeNull();
    }
    expect(imageStorage.deleted).toEqual([]);
  });

  it('clears a legacy URL without touching storage', async () => {
    const account = await register('CLIENT');
    await setPhotoColumns(account.id, 'https://legacy.example/me.jpg', null);
    await request(http())
      .delete('/users/me/photo')
      .set(auth(account))
      .expect(200);
    expect(await row(account.id)).toMatchObject({
      photo: null,
      photoPublicId: null,
    });
    expect(imageStorage.deleted).toEqual([]);
  });

  it('keeps the database cleared when deleting the stored image fails (503)', async () => {
    const account = await register('CLIENT');
    await put(account).expect(200);
    const { photoPublicId } = (await row(account.id))!;
    imageStorage.failDeletes = true;

    const response = await request(http())
      .delete('/users/me/photo')
      .set(auth(account))
      .expect(503);
    expect(JSON.stringify(response.body)).not.toMatch(
      /cloudinary|secret|api_key/i,
    );
    expect(await row(account.id)).toMatchObject({
      photo: null,
      photoPublicId: null,
    });
    expect(imageStorage.has(photoPublicId!)).toBe(true); // an orphan, but unreferenced
  });

  it('requires authentication and takes no user id', async () => {
    await request(http()).delete('/users/me/photo').expect(401);
    const caller = await register('CLIENT');
    await request(http())
      .delete('/users/1/photo')
      .set(auth(caller))
      .expect(404);
  });

  it('only clears the caller’s photo', async () => {
    const caller = await register('CLIENT');
    const other = await register('CLIENT');
    await put(caller).expect(200);
    await put(other).expect(200);
    await request(http())
      .delete('/users/me/photo')
      .set(auth(caller))
      .expect(200);
    expect((await row(other.id))!.photo).not.toBeNull();
  });
});

describe('the photo never exposes its storage reference', () => {
  it('is absent from every user-facing response', async () => {
    const account = await register('CLIENT');
    await put(account).expect(200);
    const { photo } = (await row(account.id))!;

    const me = await request(http())
      .get('/auth/me')
      .set(auth(account))
      .expect(200);
    expect(me.body.photo).toBe(photo);
    expect(me.body).not.toHaveProperty('photoPublicId');

    const login = await request(http())
      .post('/auth/login')
      .send({ phoneNumber: account.phoneNumber, password: 'changeme123' })
      .expect(200);
    expect(login.body.user.photo).toBe(photo);
    expect(login.body.user).not.toHaveProperty('photoPublicId');
    // (The URL itself contains the image's path; the stored reference is the field.)
    expect(JSON.stringify(login.body)).not.toContain('photoPublicId');
    expect(JSON.stringify(me.body)).not.toContain('photoPublicId');
  });
});

describe('without image storage configured', () => {
  let bare: INestApplication;
  const names = [
    'CLOUDINARY_CLOUD_NAME',
    'CLOUDINARY_API_KEY',
    'CLOUDINARY_API_SECRET',
    'CLOUDINARY_FOLDER_PREFIX',
  ];
  const saved = Object.fromEntries(names.map((n) => [n, process.env[n]]));

  beforeAll(async () => {
    for (const name of names) delete process.env[name];
    // The real storage provider, with no credentials: it must not be able to call out.
    const moduleFixture = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    bare = moduleFixture.createNestApplication();
    setupApp(bare);
    await bare.init();
  });
  afterAll(async () => {
    await bare.close();
    for (const name of names) {
      if (saved[name] === undefined) delete process.env[name];
      else process.env[name] = saved[name];
    }
  });

  it('starts, answers 503 to an upload, and leaves the profile untouched', async () => {
    const account = await register('CLIENT');
    const response = await request(bare.getHttpServer())
      .put('/users/me/photo')
      .set(auth(account))
      .attach('file', jpeg(), {
        filename: 'photo.jpg',
        contentType: 'image/jpeg',
      })
      .expect(503);
    expect(response.body.message).toBe('Image storage is not configured');
    expect(await row(account.id)).toMatchObject({
      photo: null,
      photoPublicId: null,
    });
  });

  it('still lets a user without a managed photo clear it', async () => {
    const account = await register('CLIENT');
    await request(bare.getHttpServer())
      .delete('/users/me/photo')
      .set(auth(account))
      .expect(200);
  });
});

/** Raw statements take literal SQL only, so each trigger statement is spelled out. */
type Transaction = Parameters<Parameters<typeof db.transaction>[0]>[0];

async function execute(plan: Parameters<Transaction['execute']>[0]) {
  await db.transaction(async (tx) => {
    await tx.execute(plan);
  });
}

async function createFailureTrigger() {
  await execute(
    db.raw
      .sql`CREATE OR REPLACE FUNCTION e2e_user_photo_fail() RETURNS trigger AS $$ BEGIN IF NEW."name" = 'e2e-photo-db-failure' THEN RAISE EXCEPTION 'forced failure'; END IF; RETURN NEW; END $$ LANGUAGE plpgsql`
      .affectedCount()
      .build(),
  );
  await execute(
    db.raw
      .sql`CREATE TRIGGER e2e_user_photo_fail BEFORE UPDATE ON "User" FOR EACH ROW EXECUTE FUNCTION e2e_user_photo_fail()`
      .affectedCount()
      .build(),
  );
}

async function dropFailureTrigger() {
  await execute(
    db.raw.sql`DROP TRIGGER IF EXISTS e2e_user_photo_fail ON "User"`
      .affectedCount()
      .build(),
  );
  await execute(
    db.raw.sql`DROP FUNCTION IF EXISTS e2e_user_photo_fail()`
      .affectedCount()
      .build(),
  );
}

afterAll(dropFailureTrigger);
