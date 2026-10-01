import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { RequestWithUser } from './jwt-auth.guard.js';

/** Use only behind `JwtAuthGuard` — reads the payload it attaches to the request. */
export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext) => {
    return ctx.switchToHttp().getRequest<RequestWithUser>().user;
  },
);
