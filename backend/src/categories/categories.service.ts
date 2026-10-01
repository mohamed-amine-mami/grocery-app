import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { db } from '../prisma/db.js';
import { ProductsService } from '../products/products.service.js';
import { StoresService } from '../stores/stores.service.js';
import { CreateCategoryDto } from './dto/create-category.dto.js';
import { UpdateCategoryDto } from './dto/update-category.dto.js';

function sqlState(error: unknown): string | undefined {
  return typeof error === 'object' && error !== null
    ? (error as { sqlState?: string }).sqlState
    : undefined;
}

function handleWriteError(error: unknown): never {
  if (sqlState(error) === '23505') {
    throw new ConflictException(
      'A category with this name already exists in your store',
    );
  }
  throw error;
}

/**
 * Categories belong to a store. The store is resolved from the authenticated
 * owner, and every query is filtered by that `storeId` — a category id from
 * another store is indistinguishable from one that doesn't exist (404).
 */
@Injectable()
export class CategoriesService {
  constructor(
    private readonly storesService: StoresService,
    private readonly productsService: ProductsService,
  ) {}

  private async storeIdFor(ownerId: number): Promise<number> {
    return (await this.storesService.findByOwner(ownerId)).id;
  }

  async findAll(ownerId: number) {
    const storeId = await this.storeIdFor(ownerId);
    return await db.orm.public.Category.where({ storeId })
      .orderBy((category) => category.name.asc())
      .all();
  }

  async create(ownerId: number, dto: CreateCategoryDto) {
    const storeId = await this.storeIdFor(ownerId);
    try {
      return await db.orm.public.Category.create({ name: dto.name, storeId });
    } catch (error) {
      handleWriteError(error);
    }
  }

  async update(ownerId: number, id: number, dto: UpdateCategoryDto) {
    const storeId = await this.storeIdFor(ownerId);
    try {
      const category = await db.orm.public.Category.where({
        id,
        storeId,
      }).update({
        name: dto.name,
      });
      if (!category) {
        throw new NotFoundException(`Category ${id} not found`);
      }
      return category;
    } catch (error) {
      if (error instanceof NotFoundException) {
        throw error;
      }
      handleWriteError(error);
    }
  }

  /**
   * Refuses (409) while any **non-archived** product uses the category. Archived
   * products never block: the `Product.categoryId` FK is `ON DELETE SET NULL`, so
   * they simply lose their category. (The check and the delete are not one
   * transaction; a product created in between would be uncategorized rather than
   * lost, which is acceptable for a single-owner store.)
   */
  async remove(ownerId: number, id: number): Promise<void> {
    const storeId = await this.storeIdFor(ownerId);
    if (await this.productsService.hasActiveProductsInCategory(storeId, id)) {
      throw new ConflictException(
        'This category still has products — move or archive them first',
      );
    }
    const deleted = await db.orm.public.Category.select('id')
      .where({ id, storeId })
      .delete();
    if (!deleted) {
      throw new NotFoundException(`Category ${id} not found`);
    }
  }
}
