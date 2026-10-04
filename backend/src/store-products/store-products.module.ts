import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { StoresModule } from '../stores/stores.module.js';
import { StoreProductsController } from './store-products.controller.js';
import { StoreProductsService } from './store-products.service.js';

@Module({
  imports: [AuthModule, StoresModule],
  controllers: [StoreProductsController],
  providers: [StoreProductsService],
})
export class StoreProductsModule {}
