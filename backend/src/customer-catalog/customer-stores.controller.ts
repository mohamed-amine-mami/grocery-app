import {
  Controller,
  Get,
  Param,
  ParseIntPipe,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiForbiddenResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/jwt-auth.guard.js';
import { Roles } from '../auth/roles.decorator.js';
import { RolesGuard } from '../auth/roles.guard.js';
import { UserRole } from '../users/user-role.enum.js';
import { CustomerCatalogService } from './customer-catalog.service.js';
import {
  CustomerCatalogItemEntity,
  CustomerStoreEntity,
} from './entities/customer-catalog.entity.js';

/** Read-only browsing for signed-in customers. Nothing here writes. */
@ApiTags('stores')
@ApiBearerAuth()
@ApiUnauthorizedResponse({ description: 'Missing or invalid token' })
@ApiForbiddenResponse({ description: 'Authenticated user is not a CLIENT' })
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.CLIENT)
@Controller('stores')
export class CustomerStoresController {
  constructor(private readonly catalog: CustomerCatalogService) {}

  @Get()
  @ApiOperation({
    summary: 'The stores, by name',
    description:
      'Customer-safe fields only (no owner data). Closed stores are listed too: they can be browsed, they just do not accept new orders (`isOpen`).',
  })
  @ApiOkResponse({ type: CustomerStoreEntity, isArray: true })
  findAll(): Promise<CustomerStoreEntity[]> {
    return this.catalog.listStores();
  }

  @Get(':id/products')
  @ApiOperation({
    summary: 'A store’s catalogue, by category then name',
    description:
      'Only this store’s own offerings, with this store’s price, unit and quantity rules. Offerings the store removed and products archived in the catalog are not listed. Every listed product carries `isOrderable`, derived by the canonical rule, and a reason when it is false; stock levels are never returned. The list is for browsing: `POST /orders` revalidates every line and is the final authority.',
  })
  @ApiParam({ name: 'id', description: 'Store id' })
  @ApiOkResponse({ type: CustomerCatalogItemEntity, isArray: true })
  @ApiNotFoundResponse({ description: 'No such store' })
  findProducts(
    @Param('id', ParseIntPipe) id: number,
  ): Promise<CustomerCatalogItemEntity[]> {
    return this.catalog.listStoreProducts(id);
  }
}
