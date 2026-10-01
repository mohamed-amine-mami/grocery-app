import { SetMetadata } from '@nestjs/common';
import type { UserRole } from '../users/user-role.enum.js';

export const ROLES_KEY = 'roles';

/** Restricts a route to the given roles. Use together with `JwtAuthGuard` and `RolesGuard`. */
export const Roles = (...roles: UserRole[]) => SetMetadata(ROLES_KEY, roles);
