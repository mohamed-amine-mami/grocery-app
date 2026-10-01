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
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator.js';
import { JwtAuthGuard } from '../auth/jwt-auth.guard.js';
import type { JwtPayload } from '../auth/jwt-payload.interface.js';
import { Roles } from '../auth/roles.decorator.js';
import { RolesGuard } from '../auth/roles.guard.js';
import { UserRole } from '../users/user-role.enum.js';
import { CategoriesService } from './categories.service.js';
import { CreateCategoryDto } from './dto/create-category.dto.js';
import { UpdateCategoryDto } from './dto/update-category.dto.js';
import { CategoryEntity } from './entities/category.entity.js';

/**
 * The authenticated owner's store categories. The store comes from the JWT;
 * no request field selects a store.
 */
@ApiTags('owner-categories')
@ApiBearerAuth()
@ApiUnauthorizedResponse({ description: 'Missing or invalid token' })
@ApiForbiddenResponse({ description: 'Authenticated user is not an OWNER' })
@ApiNotFoundResponse({
  description:
    'The owner has no store yet, or (for :id routes) the category is not in their store',
})
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.OWNER)
@Controller('owner/categories')
export class CategoriesController {
  constructor(private readonly categoriesService: CategoriesService) {}

  @Get()
  @ApiOkResponse({
    type: CategoryEntity,
    isArray: true,
    description: 'Sorted by name.',
  })
  findAll(@CurrentUser() currentUser: JwtPayload) {
    return this.categoriesService.findAll(currentUser.sub);
  }

  @Post()
  @ApiCreatedResponse({ type: CategoryEntity })
  @ApiBadRequestResponse({ description: 'Invalid name' })
  @ApiConflictResponse({ description: 'Name already used in this store' })
  create(
    @CurrentUser() currentUser: JwtPayload,
    @Body() createCategoryDto: CreateCategoryDto,
  ) {
    return this.categoriesService.create(currentUser.sub, createCategoryDto);
  }

  @Patch(':id')
  @ApiOkResponse({ type: CategoryEntity })
  @ApiBadRequestResponse({ description: 'Invalid name' })
  @ApiConflictResponse({ description: 'Name already used in this store' })
  update(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() updateCategoryDto: UpdateCategoryDto,
  ) {
    return this.categoriesService.update(
      currentUser.sub,
      id,
      updateCategoryDto,
    );
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiNoContentResponse()
  remove(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.categoriesService.remove(currentUser.sub, id);
  }
}
