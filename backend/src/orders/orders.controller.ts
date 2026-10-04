import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Post,
  Query,
  Res,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiForbiddenResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import type { Response } from 'express';
import { CurrentUser } from '../auth/current-user.decorator.js';
import { JwtAuthGuard } from '../auth/jwt-auth.guard.js';
import type { JwtPayload } from '../auth/jwt-payload.interface.js';
import { Roles } from '../auth/roles.decorator.js';
import { RolesGuard } from '../auth/roles.guard.js';
import { UserRole } from '../users/user-role.enum.js';
import { CancelOrderDto } from './dto/cancel-order.dto.js';
import { CreateOrderDto } from './dto/create-order.dto.js';
import { ListOrdersQuery } from './dto/list-orders.query.js';
import {
  CustomerOrderEntity,
  CustomerOrderPageEntity,
  CustomerOrderTransitionEntity,
  OrderErrorEntity,
} from './entities/order.entity.js';
import { toCustomerOrder } from './order.mapper.js';
import { OrderQueriesService } from './order-queries.service.js';
import { OrderTransitionsService } from './order-transitions.service.js';
import { OrdersService } from './orders.service.js';

/**
 * The authenticated customer's orders. The customer comes from the JWT; no
 * request field selects whose orders these are. Business rules live in the
 * order services; this controller only authenticates, validates and maps.
 */
@ApiTags('orders')
@ApiBearerAuth()
@ApiUnauthorizedResponse({ description: 'Missing or invalid token' })
@ApiForbiddenResponse({ description: 'Authenticated user is not a CLIENT' })
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.CLIENT)
@Controller('orders')
export class OrdersController {
  constructor(
    private readonly orders: OrdersService,
    private readonly transitions: OrderTransitionsService,
    private readonly queries: OrderQueriesService,
  ) {}

  @Post()
  @ApiOperation({
    summary: 'Place an order',
    description:
      'The server computes prices, line totals and the total, and takes tracked stock atomically. 201 when the order is created. Retrying the same `idempotencyKey` with the same request returns the original order with 200 and creates nothing; the same key with a different request is 409 `IDEMPOTENCY_KEY_REUSED`.',
  })
  @ApiCreatedResponse({
    type: CustomerOrderEntity,
    description: 'Order created.',
  })
  @ApiOkResponse({
    type: CustomerOrderEntity,
    description: 'Replay of an earlier request with the same idempotency key.',
  })
  @ApiBadRequestResponse({
    type: OrderErrorEntity,
    description:
      'Malformed body (plain validation error), or business error `INVALID_QUANTITY` (`lines`) / `INVALID_PICKUP_TIME`. Also: empty order, duplicate lines (`storeProductIds`), bad total.',
  })
  @ApiNotFoundResponse({
    description:
      'Unknown store, or store products that are not in that store (`storeProductIds`)',
  })
  @ApiConflictResponse({
    type: OrderErrorEntity,
    description:
      '`STORE_CLOSED`, `PRODUCT_UNAVAILABLE` (`lines` with a reason, no stock figures), `INSUFFICIENT_STOCK` (`storeProductId`), or `IDEMPOTENCY_KEY_REUSED`.',
  })
  async create(
    @CurrentUser() currentUser: JwtPayload,
    @Body() dto: CreateOrderDto,
    @Res({ passthrough: true }) response: Response,
  ): Promise<CustomerOrderEntity> {
    const { order, created } = await this.orders.createOrder({
      customerId: currentUser.sub,
      storeId: dto.storeId,
      lines: dto.lines.map((line) => ({
        storeProductId: line.storeProductId,
        quantity: line.quantity,
      })),
      requestedPickupAt: new Date(dto.requestedPickupAt),
      idempotencyKey: dto.idempotencyKey,
    });
    response.status(created ? HttpStatus.CREATED : HttpStatus.OK);
    return toCustomerOrder(
      await this.queries.getForCustomer(currentUser.sub, order.id),
    );
  }

  @Get()
  @ApiOperation({
    summary: 'My orders, newest first',
    description: 'Paginated: `page` from 1, `limit` up to 50 (default 20).',
  })
  @ApiOkResponse({ type: CustomerOrderPageEntity })
  async findAll(
    @CurrentUser() currentUser: JwtPayload,
    @Query() query: ListOrdersQuery,
  ): Promise<CustomerOrderPageEntity> {
    const page = await this.queries.listForCustomer(currentUser.sub, query);
    return { ...page, items: page.items.map(toCustomerOrder) };
  }

  @Get(':id')
  @ApiOperation({ summary: 'One of my orders, with its status history' })
  @ApiParam({ name: 'id', description: 'Order id' })
  @ApiOkResponse({ type: CustomerOrderEntity })
  @ApiNotFoundResponse({
    description: 'No such order, or it is not mine (indistinguishable)',
  })
  async findOne(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<CustomerOrderEntity> {
    return toCustomerOrder(
      await this.queries.getForCustomer(currentUser.sub, id),
    );
  }

  @Post(':id/cancel')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Cancel my PENDING or CONFIRMED order',
    description:
      'Gives reserved stock back. An order already CANCELLED is returned as is with `changed: false`.',
  })
  @ApiParam({ name: 'id', description: 'Order id' })
  @ApiOkResponse({ type: CustomerOrderTransitionEntity })
  @ApiBadRequestResponse({ description: 'Invalid reason' })
  @ApiNotFoundResponse({
    description: 'No such order, or it is not mine (indistinguishable)',
  })
  @ApiConflictResponse({
    type: OrderErrorEntity,
    description:
      '`ORDER_STATE_CHANGED`: the order is READY_FOR_PICKUP, COMPLETED or NO_SHOW (or moved meanwhile); `currentStatus` says where it is.',
  })
  async cancel(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: CancelOrderDto,
  ): Promise<CustomerOrderTransitionEntity> {
    const { changed } = await this.transitions.cancelByCustomer(
      id,
      currentUser.sub,
      dto.reason,
    );
    return {
      changed,
      order: toCustomerOrder(
        await this.queries.getForCustomer(currentUser.sub, id),
      ),
    };
  }
}
