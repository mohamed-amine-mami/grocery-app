import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { CreateProductDto } from './create-product.dto.js';
import { UpdateProductDto } from './update-product.dto.js';

const valid = { name: 'Tomates', saleUnit: 'KG', priceMillimes: 1800 };
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

describe('CreateProductDto', () => {
  it('accepts the minimal payload', async () => {
    expect(await propertiesWithErrors(CreateProductDto, valid)).toEqual([]);
  });

  it('bounds text and validates the photo URL', async () => {
    expect(
      await propertiesWithErrors(CreateProductDto, {
        ...valid,
        name: 'x'.repeat(101),
      }),
    ).toEqual(['name']);
    expect(
      await propertiesWithErrors(CreateProductDto, {
        ...valid,
        description: 'x'.repeat(1001),
      }),
    ).toEqual(['description']);
    expect(
      await propertiesWithErrors(CreateProductDto, {
        ...valid,
        photo: 'javascript:alert(1)',
      }),
    ).toEqual(['photo']);
    expect(
      await propertiesWithErrors(CreateProductDto, {
        ...valid,
        photo: 'https://x.test/t.jpg',
      }),
    ).toEqual([]);
  });

  it.each(['storeId', 'archivedAt', 'isAvailable', 'id'])(
    'rejects the protected field %s',
    async (field) => {
      expect(
        await propertiesWithErrors(CreateProductDto, { ...valid, [field]: 1 }),
      ).toEqual([field]);
    },
  );
});

describe('UpdateProductDto', () => {
  it('allows any subset and null to clear optional fields', async () => {
    expect(await propertiesWithErrors(UpdateProductDto, {})).toEqual([]);
    expect(
      await propertiesWithErrors(UpdateProductDto, {
        description: null,
        photo: null,
        categoryId: null,
      }),
    ).toEqual([]);
  });

  it('still rejects protected fields', async () => {
    expect(
      await propertiesWithErrors(UpdateProductDto, { storeId: 2 }),
    ).toEqual(['storeId']);
  });
});
