import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { CreateStoreDto } from './create-store.dto.js';
import { UpdateStoreDto } from './update-store.dto.js';

const validStore = { name: 'Menzah Market', address: '12 Rue de la Liberté' };

// Same options as the app-wide ValidationPipe (see app.setup.ts).
const pipeOptions = { whitelist: true, forbidNonWhitelisted: true };

async function propertiesWithErrors(
  dtoClass: new () => object,
  payload: Record<string, unknown>,
) {
  const errors = await validate(
    plainToInstance(dtoClass, payload),
    pipeOptions,
  );
  return errors.map((error) => error.property);
}

describe('CreateStoreDto', () => {
  it('accepts a store with only the required fields', async () => {
    expect(await propertiesWithErrors(CreateStoreDto, validStore)).toEqual([]);
  });

  it('requires name and address', async () => {
    expect(await propertiesWithErrors(CreateStoreDto, {})).toEqual(
      expect.arrayContaining(['name', 'address']),
    );
    expect(
      await propertiesWithErrors(CreateStoreDto, {
        ...validStore,
        address: '  ',
      }),
    ).toEqual(['address']);
  });

  it('rejects ownerId — the owner comes from the JWT, never the body', async () => {
    expect(
      await propertiesWithErrors(CreateStoreDto, {
        ...validStore,
        ownerId: 99,
      }),
    ).toEqual(['ownerId']);
  });

  it('rejects isOpen — new stores always start closed', async () => {
    expect(
      await propertiesWithErrors(CreateStoreDto, {
        ...validStore,
        isOpen: true,
      }),
    ).toEqual(['isOpen']);
  });

  describe('coordinates', () => {
    it('accepts both together', async () => {
      expect(
        await propertiesWithErrors(CreateStoreDto, {
          ...validStore,
          latitude: 36.8,
          longitude: 10.18,
        }),
      ).toEqual([]);
    });

    it('rejects latitude without longitude', async () => {
      expect(
        await propertiesWithErrors(CreateStoreDto, {
          ...validStore,
          latitude: 36.8,
        }),
      ).toEqual(['longitude']);
    });

    it('rejects longitude without latitude', async () => {
      expect(
        await propertiesWithErrors(CreateStoreDto, {
          ...validStore,
          longitude: 10.1,
        }),
      ).toEqual(['latitude']);
    });

    it('rejects out-of-range values', async () => {
      expect(
        await propertiesWithErrors(CreateStoreDto, {
          ...validStore,
          latitude: 91,
          longitude: 181,
        }),
      ).toEqual(expect.arrayContaining(['latitude', 'longitude']));
    });
  });
});

describe('UpdateStoreDto', () => {
  it('accepts a partial update, including isOpen', async () => {
    expect(
      await propertiesWithErrors(UpdateStoreDto, { isOpen: true }),
    ).toEqual([]);
    expect(
      await propertiesWithErrors(UpdateStoreDto, { name: 'New name' }),
    ).toEqual([]);
  });

  it('still rejects ownerId', async () => {
    expect(await propertiesWithErrors(UpdateStoreDto, { ownerId: 2 })).toEqual([
      'ownerId',
    ]);
  });

  it('rejects a non-boolean isOpen', async () => {
    expect(
      await propertiesWithErrors(UpdateStoreDto, { isOpen: 'yes' }),
    ).toEqual(['isOpen']);
  });
});

describe('store text limits', () => {
  it('rejects over-long text', async () => {
    expect(
      await propertiesWithErrors(CreateStoreDto, {
        ...validStore,
        name: 'x'.repeat(101),
      }),
    ).toEqual(['name']);
    expect(
      await propertiesWithErrors(CreateStoreDto, {
        ...validStore,
        address: 'x'.repeat(201),
      }),
    ).toEqual(['address']);
    expect(
      await propertiesWithErrors(CreateStoreDto, {
        ...validStore,
        description: 'x'.repeat(1001),
      }),
    ).toEqual(['description']);
  });

  it('accepts text at the limit', async () => {
    expect(
      await propertiesWithErrors(CreateStoreDto, {
        name: 'x'.repeat(100),
        address: 'x'.repeat(200),
        description: 'x'.repeat(1000),
      }),
    ).toEqual([]);
  });

  it('does not accept a client-supplied photo (set only by the photo upload)', async () => {
    for (const dtoClass of [CreateStoreDto, UpdateStoreDto]) {
      expect(
        await propertiesWithErrors(dtoClass, {
          ...validStore,
          photo: 'https://cdn.example.com/s.jpg',
        }),
      ).toEqual(['photo']);
      expect(
        await propertiesWithErrors(dtoClass, {
          ...validStore,
          photoPublicId: 'stores/1/photo',
        }),
      ).toEqual(['photoPublicId']);
    }
  });
});
