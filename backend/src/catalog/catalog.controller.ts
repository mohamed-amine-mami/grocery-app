import {
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiForbiddenResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator.js';
import { JwtAuthGuard } from '../auth/jwt-auth.guard.js';
import type { JwtPayload } from '../auth/jwt-payload.interface.js';
import { Roles } from '../auth/roles.decorator.js';
import { RolesGuard } from '../auth/roles.guard.js';
import { UserRole } from '../users/user-role.enum.js';
import { CatalogService } from './catalog.service.js';
import { BrowseCatalogQuery } from './dto/browse-catalog.query.js';
import { Int4RangePipe } from './int4-range.pipe.js';
import { ListCatalogProductsQuery } from './dto/list-catalog-products.query.js';
import {
  CatalogCategoryEntity,
  CatalogProductEntity,
  CatalogProductPageEntity,
} from './entities/catalog.entity.js';

/**
 * The global catalog, read-only for owners (browse / search / "already in my
 * store"). It is curated through the catalog importer, not through the API.
 */
@ApiTags('owner-catalog')
@ApiBearerAuth()
@ApiUnauthorizedResponse({ description: 'Missing or invalid token' })
@ApiForbiddenResponse({ description: 'Authenticated user is not an OWNER' })
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.OWNER)
@Controller('owner/catalog')
export class CatalogController {
  constructor(private readonly catalogService: CatalogService) {}

  @Get('categories')
  @ApiOperation({
    summary: 'Active catalog categories, sorted by name',
  })
  @ApiOkResponse({ type: CatalogCategoryEntity, isArray: true })
  categories() {
    return this.catalogService.categories();
  }

  @Get('products')
  @ApiOperation({
    summary: 'The whole active catalog as one array, sorted by name',
    deprecated: true,
    description:
      'Kept for existing consumers. Returns every active product in one response, which does not scale to a full grocery catalog: use `GET /owner/catalog/browse` (paged, searchable) instead. Each product says whether this owner’s store already has it (`inMyStore`, `storeProductId`, `storeProductArchived`).',
  })
  @ApiOkResponse({ type: CatalogProductEntity, isArray: true })
  @ApiNotFoundResponse({ description: 'The owner has no store yet' })
  products(
    @CurrentUser() currentUser: JwtPayload,
    @Query() query: ListCatalogProductsQuery,
  ) {
    return this.catalogService.products(currentUser.sub, query);
  }

  @Get('browse')
  @ApiOperation({
    summary: 'Browse and search the catalog, one page at a time',
    description:
      'Active products in active categories, ordered by name (accents and case ignored) and then id. `q` keeps products whose name, brand or category name contains every word; `categoryId` narrows to one category. Paging is keyset: pass the previous response’s `nextCursor` as `cursor`. Walking every page of an unchanging catalog returns each matching product exactly once. There is no snapshot: if products are added, renamed, archived or moved to another category/brand while a client is paging, a product whose sort or filter fields changed can be missed or returned twice — start again from the first page to be sure. `total` counts the current matches over all pages, including those before the cursor, and can change between requests. Each product carries the same store flags as `GET /owner/catalog/products`.',
  })
  @ApiOkResponse({ type: CatalogProductPageEntity })
  @ApiBadRequestResponse({ description: 'Invalid filter, limit or cursor' })
  @ApiNotFoundResponse({ description: 'The owner has no store yet' })
  browse(
    @CurrentUser() currentUser: JwtPayload,
    @Query() query: BrowseCatalogQuery,
  ) {
    return this.catalogService.browse(currentUser.sub, query);
  }

  @Get('products/:id')
  @ApiOperation({
    summary: 'One active catalog product, with this owner’s store flags',
  })
  @ApiOkResponse({ type: CatalogProductEntity })
  @ApiBadRequestResponse({
    description: 'The id is not an integer within the PostgreSQL integer range',
  })
  @ApiNotFoundResponse({
    description:
      'The owner has no store yet, or the product does not exist or is archived',
  })
  product(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe, new Int4RangePipe('id')) id: number,
  ) {
    return this.catalogService.product(currentUser.sub, id);
  }
}
