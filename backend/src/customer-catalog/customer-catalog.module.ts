import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { CustomerCatalogService } from './customer-catalog.service.js';
import { CustomerStoresController } from './customer-stores.controller.js';

@Module({
  imports: [AuthModule],
  controllers: [CustomerStoresController],
  providers: [CustomerCatalogService],
})
export class CustomerCatalogModule {}
