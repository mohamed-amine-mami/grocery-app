import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { ImagesModule } from '../images/images.module.js';
import { UserPhotoController } from './user-photo.controller.js';
import { UsersModule } from './users.module.js';

/** Its own module because `AuthModule` imports `UsersModule`: the guard can't be imported back into it. */
@Module({
  imports: [AuthModule, UsersModule, ImagesModule],
  controllers: [UserPhotoController],
})
export class UserPhotoModule {}
