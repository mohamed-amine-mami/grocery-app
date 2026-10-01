import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { UserRole } from '../users/user-role.enum.js';
import type { RequestWithUser } from './jwt-auth.guard.js';
import { ROLES_KEY } from './roles.decorator.js';

/**
 * Checks the role carried by the JWT against `@Roles(...)`. Must run after
 * `JwtAuthGuard`, which is what attaches `request.user`. A route without
 * `@Roles` is denied rather than silently left open.
 */
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const allowedRoles = this.reflector.getAllAndOverride<
      UserRole[] | undefined
    >(ROLES_KEY, [context.getHandler(), context.getClass()]);
    const user = context.switchToHttp().getRequest<RequestWithUser>().user;
    if (!allowedRoles?.length || !user || !allowedRoles.includes(user.role)) {
      throw new ForbiddenException('Insufficient permissions');
    }
    return true;
  }
}
