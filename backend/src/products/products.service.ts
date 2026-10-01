import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { db } from '../prisma/db.js';
import { StoresService } from '../stores/stores.service.js';
import { CreateProductDto } from './dto/create-product.dto.js';
import type { ListProductsQuery } from './dto/list-products.query.js';
import { UpdateProductDto } from './dto/update-product.dto.js';
import { quantityRuleErrors, withQuantityDefaults } from './product-rules.js';
import type { SaleUnit } from './sale-unit.enum.js';

function sqlState(error: unknown): string | undefined {
  return typeof error === 'object' && error !== null
    ? (error as { sqlState?: string }).sqlState
    : undefined;
}

function handleWriteError(error: unknown): never {
  switch (sqlState(error)) {
    case '23505': // unique_violation — active product name per store
      throw new ConflictException(
        'A product with this name already exists in your store',
      );
    case '23502': // not_null_violation — e.g. PATCH { "name": null }
      throw new BadRequestException('Required fields cannot be null');
    case '23514': // check_violation — the DB backstop for the quantity/price rules
      throw new BadRequestException('Invalid price or quantity rules');
    default:
      throw error;
  }
}

/** Fields that cannot be cleared with `null` (the others — description, photo, categoryId, maxQuantity — can). */
const NON_NULL_FIELDS = [
  'name',
  'saleUnit',
  'priceMillimes',
  'minQuantity',
  'quantityStep',
] as const;

/**
 * Products belong to a **store** (not to a category). The store is resolved
 * from the authenticated owner; every query filters by that `storeId`, so a
 * product id from another store is indistinguishable from a missing one (404).
 * A referenced category must belong to the same store.
 */
@Injectable()
export class ProductsService {
  constructor(private readonly storesService: StoresService) {}

  private async storeIdFor(ownerId: number): Promise<number> {
    return (await this.storesService.findByOwner(ownerId)).id;
  }

  private async assertCategoryInStore(storeId: number, categoryId: number) {
    const category = await db.orm.public.Category.first({
      id: categoryId,
      storeId,
    });
    if (!category) {
      throw new BadRequestException('Category not found in your store');
    }
  }

  private async findInStore(storeId: number, id: number) {
    const product = await db.orm.public.Product.first({ id, storeId });
    if (!product) {
      throw new NotFoundException(`Product ${id} not found`);
    }
    return product;
  }

  async findAll(ownerId: number, filters: ListProductsQuery) {
    const storeId = await this.storeIdFor(ownerId);
    const status = filters.status ?? 'active';

    let query = db.orm.public.Product.where({ storeId });
    if (filters.categoryId !== undefined) {
      query = query.where({ categoryId: filters.categoryId });
    }
    if (status === 'active') {
      query = query.where((product) => product.archivedAt.isNull());
    } else if (status === 'archived') {
      query = query.where((product) => product.archivedAt.isNotNull());
    }
    return await query.orderBy((product) => product.name.asc()).all();
  }

  async findOne(ownerId: number, id: number) {
    return await this.findInStore(await this.storeIdFor(ownerId), id);
  }

  async create(ownerId: number, dto: CreateProductDto) {
    const storeId = await this.storeIdFor(ownerId);

    const rules = withQuantityDefaults(dto);
    const errors = quantityRuleErrors(rules);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }
    if (dto.categoryId !== undefined && dto.categoryId !== null) {
      await this.assertCategoryInStore(storeId, dto.categoryId);
    }

    try {
      return await db.orm.public.Product.create({
        storeId,
        categoryId: dto.categoryId ?? null,
        name: dto.name,
        description: dto.description ?? null,
        photo: dto.photo ?? null,
        saleUnit: rules.saleUnit,
        priceMillimes: dto.priceMillimes,
        minQuantity: rules.minQuantity,
        quantityStep: rules.quantityStep,
        maxQuantity: rules.maxQuantity,
      });
    } catch (error) {
      handleWriteError(error);
    }
  }

  async update(ownerId: number, id: number, dto: UpdateProductDto) {
    const storeId = await this.storeIdFor(ownerId);
    const existing = await this.findInStore(storeId, id);
    if (existing.archivedAt !== null) {
      throw new ConflictException('Archived products cannot be modified');
    }

    const fields: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(dto)) {
      if (value !== undefined) {
        fields[key] = value;
      }
    }
    if (Object.keys(fields).length === 0) {
      return existing;
    }

    for (const field of NON_NULL_FIELDS) {
      if (fields[field] === null) {
        throw new BadRequestException(`${field} cannot be null`);
      }
    }

    // A unit change re-defines what price and quantities mean, so the old
    // values must not be carried over silently.
    if (dto.saleUnit !== undefined && dto.saleUnit !== existing.saleUnit) {
      const missing = [
        'priceMillimes',
        'minQuantity',
        'quantityStep',
        ...(existing.maxQuantity !== null ? ['maxQuantity'] : []),
      ].filter((field) => fields[field] === undefined);
      if (missing.length > 0) {
        throw new BadRequestException(
          `Changing saleUnit requires sending ${missing.join(', ')} for the new unit`,
        );
      }
    }

    const merged = withQuantityDefaults({
      saleUnit: (dto.saleUnit ?? existing.saleUnit) as SaleUnit,
      minQuantity: dto.minQuantity ?? existing.minQuantity,
      quantityStep: dto.quantityStep ?? existing.quantityStep,
      maxQuantity:
        dto.maxQuantity === undefined ? existing.maxQuantity : dto.maxQuantity,
    });
    const errors = quantityRuleErrors(merged);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }

    if (typeof dto.categoryId === 'number') {
      await this.assertCategoryInStore(storeId, dto.categoryId);
    }

    try {
      const product = await db.orm.public.Product.where({ id, storeId }).update(
        fields,
      );
      if (!product) {
        throw new NotFoundException(`Product ${id} not found`);
      }
      return product;
    } catch (error) {
      if (error instanceof NotFoundException) {
        throw error;
      }
      handleWriteError(error);
    }
  }

  async setAvailability(ownerId: number, id: number, isAvailable: boolean) {
    const storeId = await this.storeIdFor(ownerId);
    const existing = await this.findInStore(storeId, id);
    if (existing.archivedAt !== null) {
      throw new ConflictException('Archived products cannot be modified');
    }
    const product = await db.orm.public.Product.where({ id, storeId }).update({
      isAvailable,
    });
    if (!product) {
      throw new NotFoundException(`Product ${id} not found`);
    }
    return product;
  }

  /** "Delete" from the owner's point of view: hides the product, keeps the row. Idempotent. */
  async archive(ownerId: number, id: number): Promise<void> {
    const storeId = await this.storeIdFor(ownerId);
    const existing = await this.findInStore(storeId, id);
    if (existing.archivedAt !== null) {
      return;
    }
    await db.orm.public.Product.where({ id, storeId }).update({
      archivedAt: new Date().toISOString(),
    });
  }

  /** Used by the categories module: does any non-archived product use this category? */
  async hasActiveProductsInCategory(
    storeId: number,
    categoryId: number,
  ): Promise<boolean> {
    const product = await db.orm.public.Product.where({ storeId, categoryId })
      .where((p) => p.archivedAt.isNull())
      .first();
    return product !== null;
  }
}
