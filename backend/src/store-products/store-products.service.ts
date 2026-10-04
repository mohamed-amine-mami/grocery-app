import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { db } from '../prisma/db.js';
import {
  quantityRuleErrors,
  saleUnitErrors,
  stockErrors,
  storeProductDefaults,
} from '../products/product-rules.js';
import type { SaleUnit } from '../products/sale-unit.enum.js';
import { StoresService } from '../stores/stores.service.js';
import { CreateStoreProductDto } from './dto/create-store-product.dto.js';
import type { ListStoreProductsQuery } from './dto/list-store-products.query.js';
import { UpdateStoreProductDto } from './dto/update-store-product.dto.js';
import {
  toStoreProductEntity,
  type OfferingWithCatalog,
} from './store-product.mapper.js';

function sqlState(error: unknown): string | undefined {
  return typeof error === 'object' && error !== null
    ? (error as { sqlState?: string }).sqlState
    : undefined;
}

function handleWriteError(error: unknown): never {
  switch (sqlState(error)) {
    case '23505': // unique_violation — (storeId, productId)
      throw new ConflictException('Your store already sells this product');
    case '23502': // not_null_violation — e.g. PATCH { "priceMillimes": null }
      throw new BadRequestException('Required fields cannot be null');
    case '23514': // check_violation — the DB backstop for the price/quantity/stock rules
      throw new BadRequestException('Invalid price, quantity or stock values');
    default:
      throw error;
  }
}

/** Fields that cannot be cleared with `null`. */
const NON_NULL_FIELDS = [
  'priceMillimes',
  'saleUnit',
  'minQuantity',
  'quantityStep',
  'trackStock',
] as const;

/**
 * A store's offerings of global catalog products. The store is resolved from
 * the authenticated owner and every query filters by that `storeId`, so another
 * store's id is indistinguishable from a missing one (404). Nothing here can
 * write the global catalog.
 */
@Injectable()
export class StoreProductsService {
  constructor(private readonly storesService: StoresService) {}

  private async storeIdFor(ownerId: number): Promise<number> {
    return (await this.storesService.findByOwner(ownerId)).id;
  }

  private offerings(storeId: number) {
    return db.orm.public.StoreProduct.where({ storeId }).include(
      'product',
      (product) => product.include('category'),
    );
  }

  private async findRow(
    storeId: number,
    id: number,
  ): Promise<OfferingWithCatalog> {
    const row = await db.orm.public.StoreProduct.where({ id, storeId })
      .include('product', (product) => product.include('category'))
      .first();
    if (!row) {
      throw new NotFoundException(`Store product ${id} not found`);
    }
    return row as OfferingWithCatalog;
  }

  async findAll(ownerId: number, filters: ListStoreProductsQuery) {
    const storeId = await this.storeIdFor(ownerId);
    const status = filters.status ?? 'active';

    let query = this.offerings(storeId);
    if (status === 'active') {
      query = query.where((row) => row.archivedAt.isNull());
    } else if (status === 'archived') {
      query = query.where((row) => row.archivedAt.isNotNull());
    }
    const rows = (await query.all()) as OfferingWithCatalog[];

    return rows
      .filter(
        (row) =>
          filters.categoryId === undefined ||
          row.product?.category?.id === filters.categoryId,
      )
      .sort((a, b) =>
        (a.product?.name ?? '').localeCompare(b.product?.name ?? '', 'fr'),
      )
      .map(toStoreProductEntity);
  }

  async findOne(ownerId: number, id: number) {
    return toStoreProductEntity(
      await this.findRow(await this.storeIdFor(ownerId), id),
    );
  }

  async create(ownerId: number, dto: CreateStoreProductDto) {
    const storeId = await this.storeIdFor(ownerId);

    const product = await db.orm.public.Product.where({ id: dto.productId })
      .include('category')
      .first();
    if (!product) {
      throw new NotFoundException(`Catalog product ${dto.productId} not found`);
    }
    if (product.archivedAt !== null || product.category?.archivedAt !== null) {
      throw new ConflictException(
        'This catalog product is archived and cannot be added',
      );
    }

    const existing = await db.orm.public.StoreProduct.first({
      storeId,
      productId: product.id,
    });
    if (existing) {
      throw new ConflictException(
        existing.archivedAt === null
          ? 'Your store already sells this product'
          : `This product is archived in your store (store product ${existing.id}) — restore it instead`,
      );
    }

    const defaultSaleUnit = product.defaultSaleUnit as SaleUnit;
    const saleUnit = dto.saleUnit ?? defaultSaleUnit;
    const unitErrors = saleUnitErrors(defaultSaleUnit, saleUnit);
    if (unitErrors.length > 0) {
      throw new BadRequestException(unitErrors);
    }

    // Omitted rules come from the catalog (or the chosen unit's own defaults).
    const defaults = storeProductDefaults(
      {
        defaultSaleUnit,
        defaultMinQuantity: product.defaultMinQuantity,
        defaultQuantityStep: product.defaultQuantityStep,
        defaultMaxQuantity: product.defaultMaxQuantity,
      },
      saleUnit,
    );
    const rules = {
      saleUnit,
      minQuantity: dto.minQuantity ?? defaults.minQuantity,
      quantityStep: dto.quantityStep ?? defaults.quantityStep,
      maxQuantity:
        dto.maxQuantity === undefined ? defaults.maxQuantity : dto.maxQuantity,
    };
    const trackStock = dto.trackStock ?? false;
    const stockQuantity = dto.stockQuantity ?? null;
    const errors = [
      ...quantityRuleErrors(rules),
      ...stockErrors({ saleUnit, trackStock, stockQuantity }),
    ];
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }

    try {
      const created = await db.orm.public.StoreProduct.create({
        storeId,
        productId: product.id,
        saleUnit,
        priceMillimes: dto.priceMillimes,
        minQuantity: rules.minQuantity,
        quantityStep: rules.quantityStep,
        maxQuantity: rules.maxQuantity,
        trackStock,
        stockQuantity,
        isAvailable: dto.isAvailable ?? true,
        archivedAt: null,
      });
      return toStoreProductEntity(await this.findRow(storeId, created.id));
    } catch (error) {
      handleWriteError(error);
    }
  }

  async update(ownerId: number, id: number, dto: UpdateStoreProductDto) {
    const storeId = await this.storeIdFor(ownerId);
    const existing = await this.findRow(storeId, id);
    if (existing.archivedAt !== null) {
      throw new ConflictException('Archived products cannot be modified');
    }
    const product = existing.product!;

    // Transformed DTOs carry undefined-valued keys: only defined ones count.
    const sent: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(dto)) {
      if (value !== undefined) sent[key] = value;
    }
    if (Object.keys(sent).length === 0) {
      return toStoreProductEntity(existing);
    }
    for (const field of NON_NULL_FIELDS) {
      if (sent[field] === null) {
        throw new BadRequestException(`${field} cannot be null`);
      }
    }

    const touchesStock =
      dto.trackStock !== undefined || dto.stockQuantity !== undefined;
    if (touchesStock && dto.expectedStockQuantity === undefined) {
      throw new BadRequestException(
        'expectedStockQuantity is required when changing trackStock or stockQuantity — send the stock you loaded, or null if it was not tracked',
      );
    }
    if (!touchesStock && dto.expectedStockQuantity !== undefined) {
      throw new BadRequestException(
        'expectedStockQuantity is only allowed together with trackStock or stockQuantity',
      );
    }

    const finalTrackStock = dto.trackStock ?? existing.trackStock;

    // A unit change re-defines what price, quantities and stock mean, so the
    // old values must not be carried over silently.
    const unitChanged =
      dto.saleUnit !== undefined && dto.saleUnit !== existing.saleUnit;
    if (unitChanged) {
      const unitErrors = saleUnitErrors(
        product.defaultSaleUnit,
        dto.saleUnit as SaleUnit,
      );
      if (unitErrors.length > 0) {
        throw new BadRequestException(unitErrors);
      }
      const missing = [
        'priceMillimes',
        'minQuantity',
        'quantityStep',
        ...(existing.maxQuantity !== null ? ['maxQuantity'] : []),
        ...(existing.trackStock && finalTrackStock ? ['stockQuantity'] : []),
      ].filter((field) => sent[field] === undefined);
      if (missing.length > 0) {
        throw new BadRequestException(
          `Changing saleUnit requires sending ${missing.join(', ')} for the new unit`,
        );
      }
    }

    const saleUnit = dto.saleUnit ?? existing.saleUnit;
    const rules = {
      saleUnit,
      minQuantity: dto.minQuantity ?? existing.minQuantity,
      quantityStep: dto.quantityStep ?? existing.quantityStep,
      maxQuantity:
        dto.maxQuantity === undefined ? existing.maxQuantity : dto.maxQuantity,
    };
    // Turning tracking off clears the quantity; otherwise it only changes when sent.
    const finalStockQuantity =
      dto.stockQuantity !== undefined
        ? dto.stockQuantity
        : dto.trackStock === false
          ? null
          : existing.stockQuantity;
    const errors = [
      ...quantityRuleErrors(rules),
      ...stockErrors({
        saleUnit,
        trackStock: finalTrackStock,
        stockQuantity: finalStockQuantity,
      }),
    ];
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }

    const columns: Record<string, unknown> = { ...sent };
    delete columns['expectedStockQuantity']; // a concurrency token, never stored
    if (touchesStock) {
      columns['stockQuantity'] = finalStockQuantity;
    }

    // One conditional UPDATE: when stock is part of the write it only applies if
    // the stock is still what the client loaded, so a concurrent order's
    // decrement is never overwritten — and a stale request changes nothing.
    let query = db.orm.public.StoreProduct.where({ id, storeId }).where((row) =>
      row.archivedAt.isNull(),
    );
    if (touchesStock) {
      const expected = dto.expectedStockQuantity;
      query = query.where((row) =>
        expected === null || expected === undefined
          ? row.stockQuantity.isNull()
          : row.stockQuantity.eq(expected),
      );
    }
    try {
      // `updateAndCount`, not `update`: the ORM's single-row `update()` picks the
      // row first and then updates it by id, so after waiting for a concurrent
      // writer it would apply the edit even though the stock check no longer
      // holds. `updateAndCount` is one conditional UPDATE the database
      // re-checks, so a stale edit changes nothing.
      const updated = await query.updateAndCount(columns);
      if (updated > 0) {
        return toStoreProductEntity(await this.findRow(storeId, id));
      }
    } catch (error) {
      handleWriteError(error);
    }

    // Nothing matched: find out why.
    const current = await db.orm.public.StoreProduct.first({ id, storeId });
    if (!current) {
      throw new NotFoundException(`Store product ${id} not found`);
    }
    if (current.archivedAt !== null) {
      throw new ConflictException('Archived products cannot be modified');
    }
    throw new ConflictException({
      statusCode: 409,
      error: 'Conflict',
      code: 'STOCK_CHANGED',
      message: 'Stock changed since it was loaded',
      currentStockQuantity: current.stockQuantity,
    });
  }

  async setAvailability(ownerId: number, id: number, isAvailable: boolean) {
    const storeId = await this.storeIdFor(ownerId);
    const existing = await this.findRow(storeId, id);
    if (existing.archivedAt !== null) {
      throw new ConflictException('Archived products cannot be modified');
    }
    await db.orm.public.StoreProduct.where({ id, storeId }).update({
      isAvailable,
    });
    return toStoreProductEntity(await this.findRow(storeId, id));
  }

  /** "Delete" from the owner's point of view: hides the offering, keeps the row. Idempotent. */
  async archive(ownerId: number, id: number): Promise<void> {
    const storeId = await this.storeIdFor(ownerId);
    const existing = await this.findRow(storeId, id);
    if (existing.archivedAt !== null) {
      return;
    }
    await db.orm.public.StoreProduct.where({ id, storeId }).update({
      archivedAt: new Date().toISOString(),
    });
  }

  /** Brings an archived offering back exactly as it was left. Idempotent. */
  async restore(ownerId: number, id: number) {
    const storeId = await this.storeIdFor(ownerId);
    const existing = await this.findRow(storeId, id);
    if (existing.archivedAt !== null) {
      await db.orm.public.StoreProduct.where({ id, storeId }).update({
        archivedAt: null,
      });
    }
    return toStoreProductEntity(await this.findRow(storeId, id));
  }
}
