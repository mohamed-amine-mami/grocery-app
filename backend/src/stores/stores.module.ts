import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { ImagesModule } from '../images/images.module.js';
import { OwnerStoreController } from './owner-store.controller.js';
import { StoresService } from './stores.service.js';

@Module({
  imports: [AuthModule, ImagesModule],
  controllers: [OwnerStoreController],
  providers: [StoresService],
  exports: [StoresService],
})
export class StoresModule {}
