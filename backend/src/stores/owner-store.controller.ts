import {
  Body,
  Controller,
  Delete,
  Get,
  Patch,
  Post,
  Put,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiConflictResponse,
  ApiBody,
  ApiConsumes,
  ApiOperation,
  ApiPayloadTooLargeResponse,
  ApiServiceUnavailableResponse,
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
import {
  IMAGE_MAX_BYTES,
  ImageFilePipe,
  type ValidatedImage,
} from '../images/image-file.pipe.js';
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

  @Put('photo')
  @UseInterceptors(
    FileInterceptor('file', {
      limits: { fileSize: IMAGE_MAX_BYTES, files: 1 },
    }),
  )
  @ApiOperation({
    summary: 'Set or replace the owner’s store photo',
    description:
      'Send a JPEG, PNG or WebP of at most 5 MB as the multipart field `file`. The previous photo, if any, is replaced.',
  })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      required: ['file'],
      properties: { file: { type: 'string', format: 'binary' } },
    },
  })
  @ApiOkResponse({ type: StoreEntity })
  @ApiBadRequestResponse({
    description: 'No file, or not a JPEG, PNG or WebP image',
  })
  @ApiPayloadTooLargeResponse({ description: 'The image exceeds 5 MB' })
  @ApiNotFoundResponse({ description: 'The owner has no store yet' })
  @ApiServiceUnavailableResponse({
    description: 'Image storage is not configured or temporarily unavailable',
  })
  setPhoto(
    @CurrentUser() currentUser: JwtPayload,
    @UploadedFile(ImageFilePipe) image: ValidatedImage,
  ) {
    return this.storesService.setPhoto(currentUser.sub, image);
  }

  @Delete('photo')
  @ApiOperation({
    summary: 'Remove the owner’s store photo',
    description: 'Idempotent: a store without a photo is returned unchanged.',
  })
  @ApiOkResponse({ type: StoreEntity })
  @ApiNotFoundResponse({ description: 'The owner has no store yet' })
  @ApiServiceUnavailableResponse({
    description:
      'The photo is removed from the store, but deleting the stored image failed',
  })
  removePhoto(@CurrentUser() currentUser: JwtPayload) {
    return this.storesService.removePhoto(currentUser.sub);
  }
}
