import { Module } from '@nestjs/common';
import { ImagesModule } from '../images/images.module.js';
import { UsersService } from './users.service.js';

/** No CRUD controller on purpose: users are created through `/auth/register` and read through `/auth/me`; the only own-record write is the photo (`UserPhotoModule`). */
@Module({
  imports: [ImagesModule],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
