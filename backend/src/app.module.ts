import { Module } from '@nestjs/common';
import { createObserveModule } from '@nestjs/observe';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';
import { UsersModule } from './users/users.module.js';
import { StoresModule } from './stores/stores.module.js';
import { AuthModule } from './auth/auth.module.js';
import { CatalogModule } from './catalog/catalog.module.js';
import { StoreProductsModule } from './store-products/store-products.module.js';
import { CustomerCatalogModule } from './customer-catalog/customer-catalog.module.js';
import { OrdersModule } from './orders/orders.module.js';

export const { ObserveModule, ObserveInstrument } = createObserveModule();

@Module({
  imports: [
    // Distributed tracing, auto-correlated logs, request/job metrics, error
    // telemetry, alarms, and more — out of the box. Sign up at https://observe.nestjs.com
    ObserveModule.forRoot({
      appKey: 'YOUR_APP_KEY',
      appSecret: 'YOUR_APP_SECRET',
      serviceId: 'backend',
    }),
    UsersModule,
    StoresModule,
    AuthModule,
    CatalogModule,
    StoreProductsModule,
    OrdersModule,
    CustomerCatalogModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
