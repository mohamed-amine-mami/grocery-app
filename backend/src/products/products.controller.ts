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
import { CreateProductDto } from './dto/create-product.dto.js';
import { ListProductsQuery } from './dto/list-products.query.js';
import { SetAvailabilityDto } from './dto/set-availability.dto.js';
import { UpdateProductDto } from './dto/update-product.dto.js';
import { ProductEntity } from './entities/product.entity.js';
import { ProductsService } from './products.service.js';

/**
 * The authenticated owner's catalog. The store comes from the JWT; no request
 * field selects a store.
 */
@ApiTags('owner-products')
@ApiBearerAuth()
@ApiUnauthorizedResponse({ description: 'Missing or invalid token' })
@ApiForbiddenResponse({ description: 'Authenticated user is not an OWNER' })
@ApiNotFoundResponse({
  description:
    'The owner has no store yet, or (for :id routes) the product is not in their store',
})
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.OWNER)
@Controller('owner/products')
export class ProductsController {
  constructor(private readonly productsService: ProductsService) {}

  @Get()
  @ApiOperation({
    summary: 'List products (active ones by default), sorted by name',
  })
  @ApiOkResponse({ type: ProductEntity, isArray: true })
  findAll(
    @CurrentUser() currentUser: JwtPayload,
    @Query() query: ListProductsQuery,
  ) {
    return this.productsService.findAll(currentUser.sub, query);
  }

  @Post()
  @ApiCreatedResponse({ type: ProductEntity })
  @ApiBadRequestResponse({
    description:
      'Invalid payload, quantity rules, or category not in this store',
  })
  @ApiConflictResponse({ description: 'Another active product has this name' })
  create(
    @CurrentUser() currentUser: JwtPayload,
    @Body() dto: CreateProductDto,
  ) {
    return this.productsService.create(currentUser.sub, dto);
  }

  @Get(':id')
  @ApiOperation({ summary: 'One product, archived or not' })
  @ApiOkResponse({ type: ProductEntity })
  findOne(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.productsService.findOne(currentUser.sub, id);
  }

  @Patch(':id')
  @ApiOperation({
    summary: 'Edit a product',
    description:
      'Changing saleUnit requires priceMillimes, minQuantity, quantityStep (and maxQuantity when one is set) in the same request.',
  })
  @ApiOkResponse({ type: ProductEntity })
  @ApiBadRequestResponse({
    description:
      'Invalid payload, quantity rules, or category not in this store',
  })
  @ApiConflictResponse({
    description: 'Duplicate name, or the product is archived',
  })
  update(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateProductDto,
  ) {
    return this.productsService.update(currentUser.sub, id, dto);
  }

  @Patch(':id/availability')
  @ApiOperation({
    summary: 'Mark a product available / temporarily unavailable',
  })
  @ApiOkResponse({ type: ProductEntity })
  @ApiConflictResponse({ description: 'The product is archived' })
  setAvailability(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: SetAvailabilityDto,
  ) {
    return this.productsService.setAvailability(
      currentUser.sub,
      id,
      dto.isAvailable,
    );
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: 'Archive a product',
    description:
      'DELETE archives: the product is hidden from the catalog but kept for history. Idempotent.',
  })
  @ApiNoContentResponse()
  archive(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.productsService.archive(currentUser.sub, id);
  }
}
