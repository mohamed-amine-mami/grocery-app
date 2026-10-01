import { Module } from '@nestjs/common';
import { UsersService } from './users.service.js';

/** No controller on purpose: users are created through `/auth/register` and read through `/auth/me`. */
@Module({
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
