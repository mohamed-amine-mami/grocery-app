import { UserRole } from '../users/user-role.enum.js';

/** Kept minimal on purpose — identifies the user and their role, nothing sensitive. */
export interface JwtPayload {
  sub: number;
  role: UserRole;
  iat?: number;
  exp?: number;
}
