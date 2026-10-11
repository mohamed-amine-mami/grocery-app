import {
  Controller,
  Delete,
  Put,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiBody,
  ApiConsumes,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiPayloadTooLargeResponse,
  ApiServiceUnavailableResponse,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator.js';
import { JwtAuthGuard } from '../auth/jwt-auth.guard.js';
import type { JwtPayload } from '../auth/jwt-payload.interface.js';
import {
  IMAGE_MAX_BYTES,
  ImageFilePipe,
  type ValidatedImage,
} from '../images/image-file.pipe.js';
import { UserEntity } from './entities/user.entity.js';
import { UsersService } from './users.service.js';

/**
 * The authenticated user's own photo, any role. The user always comes from the
 * JWT (`sub`); no request field or path parameter can point at another user.
 */
@ApiTags('users')
@ApiBearerAuth()
@ApiUnauthorizedResponse({ description: 'Missing or invalid token' })
@UseGuards(JwtAuthGuard)
@Controller('users/me/photo')
export class UserPhotoController {
  constructor(private readonly usersService: UsersService) {}

  @Put()
  @UseInterceptors(
    FileInterceptor('file', {
      limits: { fileSize: IMAGE_MAX_BYTES, files: 1 },
    }),
  )
  @ApiOperation({
    summary: 'Set or replace the authenticated user’s photo',
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
  @ApiOkResponse({ type: UserEntity })
  @ApiBadRequestResponse({
    description: 'No file, or not a JPEG, PNG or WebP image',
  })
  @ApiPayloadTooLargeResponse({ description: 'The image exceeds 5 MB' })
  @ApiNotFoundResponse({ description: 'The token’s user no longer exists' })
  @ApiServiceUnavailableResponse({
    description: 'Image storage is not configured or temporarily unavailable',
  })
  set(
    @CurrentUser() currentUser: JwtPayload,
    @UploadedFile(ImageFilePipe) image: ValidatedImage,
  ) {
    return this.usersService.setPhoto(currentUser.sub, image);
  }

  @Delete()
  @ApiOperation({
    summary: 'Remove the authenticated user’s photo',
    description:
      'Idempotent: a user without a photo gets their profile back unchanged.',
  })
  @ApiOkResponse({ type: UserEntity })
  @ApiNotFoundResponse({ description: 'The token’s user no longer exists' })
  @ApiServiceUnavailableResponse({
    description:
      'The photo is removed from the profile, but deleting the stored image failed',
  })
  remove(@CurrentUser() currentUser: JwtPayload) {
    return this.usersService.removePhoto(currentUser.sub);
  }
}
