import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import {
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
import { ListCatalogProductsQuery } from './dto/list-catalog-products.query.js';
import {
  CatalogCategoryEntity,
  CatalogProductEntity,
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
    summary: 'Active catalog products for the picker, sorted by name',
    description:
      'Each product says whether this owner’s store already has it (`inMyStore`, `storeProductId`, `storeProductArchived`). The whole catalog is returned (a few hundred items) so the app can search and filter locally.',
  })
  @ApiOkResponse({ type: CatalogProductEntity, isArray: true })
  @ApiNotFoundResponse({ description: 'The owner has no store yet' })
  products(
    @CurrentUser() currentUser: JwtPayload,
    @Query() query: ListCatalogProductsQuery,
  ) {
    return this.catalogService.products(currentUser.sub, query);
  }
}
