import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { OwnerStoreController } from './owner-store.controller.js';
import { StoresService } from './stores.service.js';

@Module({
  imports: [AuthModule],
  controllers: [OwnerStoreController],
  providers: [StoresService],
  exports: [StoresService],
})
export class StoresModule {}
