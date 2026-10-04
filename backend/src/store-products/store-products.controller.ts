import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiForbiddenResponse,
  ApiNoContentResponse,
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
import { CreateStoreProductDto } from './dto/create-store-product.dto.js';
import { ListStoreProductsQuery } from './dto/list-store-products.query.js';
import { SetAvailabilityDto } from './dto/set-availability.dto.js';
import { UpdateStoreProductDto } from './dto/update-store-product.dto.js';
import {
  StockChangedEntity,
  StoreProductEntity,
} from './entities/store-product.entity.js';
import { StoreProductsService } from './store-products.service.js';

/**
 * The authenticated owner's offerings of global catalog products. The store
 * comes from the JWT; no request field selects a store, and nothing here can
 * change the global catalog.
 */
@ApiTags('owner-store-products')
@ApiBearerAuth()
@ApiUnauthorizedResponse({ description: 'Missing or invalid token' })
@ApiForbiddenResponse({ description: 'Authenticated user is not an OWNER' })
@ApiNotFoundResponse({
  description:
    'The owner has no store yet, or (for :id routes) the store product is not in their store',
})
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.OWNER)
@Controller('owner/store-products')
export class StoreProductsController {
  constructor(private readonly storeProductsService: StoreProductsService) {}

  @Get()
  @ApiOperation({
    summary:
      'List the store’s products (active ones by default), sorted by name',
  })
  @ApiOkResponse({ type: StoreProductEntity, isArray: true })
  findAll(
    @CurrentUser() currentUser: JwtPayload,
    @Query() query: ListStoreProductsQuery,
  ) {
    return this.storeProductsService.findAll(currentUser.sub, query);
  }

  @Post()
  @ApiOperation({
    summary: 'Add a catalog product to the store',
    description:
      'Creation only: a product the store already has — active or archived — is a 409 (use restore for an archived one). The unit is the product’s default or PIECE; omitted quantity rules default from the catalog.',
  })
  @ApiCreatedResponse({ type: StoreProductEntity })
  @ApiBadRequestResponse({
    description:
      'Invalid payload, unit not allowed for this product, quantity rules or stock, or a global field (name, description, photo, categoryId, slug) was sent',
  })
  @ApiNotFoundResponse({ description: 'No such catalog product' })
  @ApiConflictResponse({
    description:
      'The store already has this product (active or archived), or the catalog product is archived',
  })
  create(
    @CurrentUser() currentUser: JwtPayload,
    @Body() dto: CreateStoreProductDto,
  ) {
    return this.storeProductsService.create(currentUser.sub, dto);
  }

  @Get(':id')
  @ApiOperation({ summary: 'One store product, archived or not' })
  @ApiOkResponse({ type: StoreProductEntity })
  findOne(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.storeProductsService.findOne(currentUser.sub, id);
  }

  @Patch(':id')
  @ApiOperation({
    summary: 'Edit price, unit, quantity rules and stock',
    description:
      'Changing saleUnit requires priceMillimes, minQuantity, quantityStep (and maxQuantity when one is set, stockQuantity while stock is tracked) in the same request. Sending trackStock or stockQuantity requires expectedStockQuantity — the stock the client loaded, or null if untracked — and nothing is applied if the stock changed meanwhile.',
  })
  @ApiOkResponse({ type: StoreProductEntity })
  @ApiBadRequestResponse({
    description:
      'Invalid payload, unit not allowed, quantity rules or stock, missing expectedStockQuantity, or a global field was sent',
  })
  @ApiConflictResponse({
    type: StockChangedEntity,
    description:
      'STOCK_CHANGED (the body carries currentStockQuantity), or the store product is archived',
  })
  update(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateStoreProductDto,
  ) {
    return this.storeProductsService.update(currentUser.sub, id, dto);
  }

  @Patch(':id/availability')
  @ApiOperation({
    summary: 'Switch a product on / off',
    description:
      'The owner’s manual switch. Independent of stock: tracked stock reaching zero makes the product unorderable on its own.',
  })
  @ApiOkResponse({ type: StoreProductEntity })
  @ApiConflictResponse({ description: 'The store product is archived' })
  setAvailability(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: SetAvailabilityDto,
  ) {
    return this.storeProductsService.setAvailability(
      currentUser.sub,
      id,
      dto.isAvailable,
    );
  }

  @Post(':id/restore')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Restore an archived store product',
    description:
      'Brings it back exactly as it was left (price, rules, stock). Idempotent.',
  })
  @ApiOkResponse({ type: StoreProductEntity })
  restore(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.storeProductsService.restore(currentUser.sub, id);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: 'Archive a store product',
    description:
      'DELETE archives: the offering is hidden but kept for history. Idempotent.',
  })
  @ApiNoContentResponse()
  archive(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.storeProductsService.archive(currentUser.sub, id);
  }
}
