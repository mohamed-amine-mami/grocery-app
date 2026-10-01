import { Body, Controller, Get, Patch, Post, UseGuards } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiForbiddenResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator.js';
import { JwtAuthGuard } from '../auth/jwt-auth.guard.js';
import type { JwtPayload } from '../auth/jwt-payload.interface.js';
import { Roles } from '../auth/roles.decorator.js';
import { RolesGuard } from '../auth/roles.guard.js';
import { UserRole } from '../users/user-role.enum.js';
import { CreateStoreDto } from './dto/create-store.dto.js';
import { UpdateStoreDto } from './dto/update-store.dto.js';
import { StoreEntity } from './entities/store.entity.js';
import { StoresService } from './stores.service.js';

/**
 * The authenticated owner's own store. The owner always comes from the JWT
 * (`sub`); no request field or path parameter can point at another store.
 */
@ApiTags('owner-store')
@ApiBearerAuth()
@ApiUnauthorizedResponse({ description: 'Missing or invalid token' })
@ApiForbiddenResponse({ description: 'Authenticated user is not an OWNER' })
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.OWNER)
@Controller('owner/store')
export class OwnerStoreController {
  constructor(private readonly storesService: StoresService) {}

  @Get()
  @ApiOkResponse({ type: StoreEntity })
  @ApiNotFoundResponse({
    description:
      'The owner has not created a store yet — the app routes to store creation.',
  })
  findMine(@CurrentUser() currentUser: JwtPayload) {
    return this.storesService.findByOwner(currentUser.sub);
  }

  @Post()
  @ApiCreatedResponse({ type: StoreEntity })
  @ApiBadRequestResponse({ description: 'Invalid payload' })
  @ApiConflictResponse({ description: 'This owner already has a store' })
  create(
    @CurrentUser() currentUser: JwtPayload,
    @Body() createStoreDto: CreateStoreDto,
  ) {
    return this.storesService.createForOwner(currentUser.sub, createStoreDto);
  }

  @Patch()
  @ApiOkResponse({ type: StoreEntity })
  @ApiBadRequestResponse({ description: 'Invalid payload' })
  @ApiNotFoundResponse({ description: 'The owner has no store yet' })
  update(
    @CurrentUser() currentUser: JwtPayload,
    @Body() updateStoreDto: UpdateStoreDto,
  ) {
    return this.storesService.updateForOwner(currentUser.sub, updateStoreDto);
  }
}
