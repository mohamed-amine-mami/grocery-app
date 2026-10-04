import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { OrderQueriesService } from './order-queries.service.js';
import { OrderTransitionsService } from './order-transitions.service.js';
import { OrdersController } from './orders.controller.js';
import { OrdersService } from './orders.service.js';
import { OwnerOrdersController } from './owner-orders.controller.js';

@Module({
  imports: [AuthModule],
  controllers: [OrdersController, OwnerOrdersController],
  providers: [OrdersService, OrderTransitionsService, OrderQueriesService],
})
export class OrdersModule {}
