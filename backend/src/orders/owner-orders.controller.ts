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
  UseGuards,
} from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiConflictResponse,
  ApiForbiddenResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator.js';
import { JwtAuthGuard } from '../auth/jwt-auth.guard.js';
import type { JwtPayload } from '../auth/jwt-payload.interface.js';
import { Roles } from '../auth/roles.decorator.js';
import { RolesGuard } from '../auth/roles.guard.js';
import { UserRole } from '../users/user-role.enum.js';
import { OwnerCancelOrderDto } from './dto/cancel-order.dto.js';
import { ConfirmOrderDto } from './dto/confirm-order.dto.js';
import { ListOwnerOrdersQuery } from './dto/list-orders.query.js';
import {
  OrderErrorEntity,
  OwnerOrderEntity,
  OwnerOrderPageEntity,
  OwnerOrderTransitionEntity,
} from './entities/order.entity.js';
import { toOwnerOrder } from './order.mapper.js';
import { OrderQueriesService } from './order-queries.service.js';
import {
  OrderTransitionsService,
  type OrderTransitionResult,
} from './order-transitions.service.js';

const STATE_CONFLICT =
  '`ORDER_STATE_CHANGED`: the move is not allowed from the order’s current status (or it moved meanwhile); `currentStatus` says where it is.';

/**
 * The orders of the authenticated owner's store. The store comes from the JWT
 * (the owner's only store); no request field selects a store, and an order of
 * another store is a 404. Business rules live in the order services.
 */
@ApiTags('owner-orders')
@ApiBearerAuth()
@ApiUnauthorizedResponse({ description: 'Missing or invalid token' })
@ApiForbiddenResponse({ description: 'Authenticated user is not an OWNER' })
@ApiNotFoundResponse({
  description:
    'The owner has no store yet, or (for :id routes) the order is not an order of their store',
})
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.OWNER)
@Controller('owner/orders')
export class OwnerOrdersController {
  constructor(
    private readonly transitions: OrderTransitionsService,
    private readonly queries: OrderQueriesService,
  ) {}

  @Get()
  @ApiOperation({
    summary: 'The store’s orders, newest first',
    description:
      'Paginated: `page` from 1, `limit` up to 50 (default 20). `status` is the only filter.',
  })
  @ApiOkResponse({ type: OwnerOrderPageEntity })
  async findAll(
    @CurrentUser() currentUser: JwtPayload,
    @Query() query: ListOwnerOrdersQuery,
  ): Promise<OwnerOrderPageEntity> {
    const page = await this.queries.listForOwner(currentUser.sub, query);
    return { ...page, items: page.items.map(toOwnerOrder) };
  }

  @Get(':id')
  @ApiOperation({ summary: 'One order of the store, with its status history' })
  @ApiParam({ name: 'id', description: 'Order id' })
  @ApiOkResponse({ type: OwnerOrderEntity })
  async findOne(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<OwnerOrderEntity> {
    return toOwnerOrder(await this.queries.getForOwner(currentUser.sub, id));
  }

  @Post(':id/confirm')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'PENDING → CONFIRMED, optionally removing lines',
    description:
      'Removed lines stay on the order (`removedAt`), their stock is given back and the total is recomputed by the server. Removing every line is a 400 (cancel instead). If the order is already CONFIRMED the current order is returned with `changed: false` and the removal list is ignored, neither validated nor applied.',
  })
  @ApiParam({ name: 'id', description: 'Order id' })
  @ApiOkResponse({ type: OwnerOrderTransitionEntity })
  @ApiBadRequestResponse({
    description:
      'Malformed body, or a removal that cannot be applied: items not on this order, already removed, or every line',
  })
  @ApiConflictResponse({ type: OrderErrorEntity, description: STATE_CONFLICT })
  confirm(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: ConfirmOrderDto,
  ) {
    return this.respond(
      currentUser,
      id,
      this.transitions.confirm(id, currentUser.sub, {
        removeItemIds: dto.removeItemIds,
      }),
    );
  }

  @Post(':id/ready')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'CONFIRMED → READY_FOR_PICKUP' })
  @ApiParam({ name: 'id', description: 'Order id' })
  @ApiOkResponse({ type: OwnerOrderTransitionEntity })
  @ApiConflictResponse({ type: OrderErrorEntity, description: STATE_CONFLICT })
  ready(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.respond(
      currentUser,
      id,
      this.transitions.markReady(id, currentUser.sub),
    );
  }

  @Post(':id/complete')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'READY_FOR_PICKUP → COMPLETED (handed over and paid)',
    description: 'Never changes stock.',
  })
  @ApiParam({ name: 'id', description: 'Order id' })
  @ApiOkResponse({ type: OwnerOrderTransitionEntity })
  @ApiConflictResponse({ type: OrderErrorEntity, description: STATE_CONFLICT })
  complete(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.respond(
      currentUser,
      id,
      this.transitions.complete(id, currentUser.sub),
    );
  }

  @Post(':id/cancel')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Cancel a PENDING or CONFIRMED order',
    description:
      'Needs a non-empty `reason`, which the customer can read. Gives reserved stock back.',
  })
  @ApiParam({ name: 'id', description: 'Order id' })
  @ApiOkResponse({ type: OwnerOrderTransitionEntity })
  @ApiBadRequestResponse({ description: 'Missing or empty reason' })
  @ApiConflictResponse({ type: OrderErrorEntity, description: STATE_CONFLICT })
  cancel(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: OwnerCancelOrderDto,
  ) {
    return this.respond(
      currentUser,
      id,
      this.transitions.cancelByOwner(id, currentUser.sub, dto.reason),
    );
  }

  @Post(':id/no-show')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'READY_FOR_PICKUP → NO_SHOW (“Non retirée”)',
    description: 'Manual, never automatic. Gives reserved stock back.',
  })
  @ApiParam({ name: 'id', description: 'Order id' })
  @ApiOkResponse({ type: OwnerOrderTransitionEntity })
  @ApiConflictResponse({ type: OrderErrorEntity, description: STATE_CONFLICT })
  noShow(
    @CurrentUser() currentUser: JwtPayload,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.respond(
      currentUser,
      id,
      this.transitions.markNoShow(id, currentUser.sub),
    );
  }

  /** The transition's outcome with the order in its full, owner-facing shape. */
  private async respond(
    currentUser: JwtPayload,
    id: number,
    result: Promise<OrderTransitionResult>,
  ): Promise<OwnerOrderTransitionEntity> {
    const { changed } = await result;
    return {
      changed,
      order: toOwnerOrder(await this.queries.getForOwner(currentUser.sub, id)),
    };
  }
}
