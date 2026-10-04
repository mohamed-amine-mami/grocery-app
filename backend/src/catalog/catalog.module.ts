import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { StoresModule } from '../stores/stores.module.js';
import { CatalogController } from './catalog.controller.js';
import { CatalogService } from './catalog.service.js';

@Module({
  imports: [AuthModule, StoresModule],
  controllers: [CatalogController],
  providers: [CatalogService],
})
export class CatalogModule {}
