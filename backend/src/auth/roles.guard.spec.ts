import { ForbiddenException, type ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserRole } from '../users/user-role.enum.js';
import { Roles } from './roles.decorator.js';
import { RolesGuard } from './roles.guard.js';

class OwnerOnly {
  @Roles(UserRole.OWNER)
  handler() {}

  unprotected() {}
}

function contextFor(handlerName: 'handler' | 'unprotected', role?: UserRole) {
  return {
    getHandler: () => OwnerOnly.prototype[handlerName],
    getClass: () => OwnerOnly,
    switchToHttp: () => ({
      getRequest: () => ({ user: role ? { sub: 1, role } : undefined }),
    }),
  } as unknown as ExecutionContext;
}

describe('RolesGuard', () => {
  const guard = new RolesGuard(new Reflector());

  it('allows a user whose role is listed', () => {
    expect(guard.canActivate(contextFor('handler', UserRole.OWNER))).toBe(true);
  });

  it('rejects a user whose role is not listed', () => {
    expect(() =>
      guard.canActivate(contextFor('handler', UserRole.CLIENT)),
    ).toThrow(ForbiddenException);
  });

  it('rejects a request with no authenticated user', () => {
    expect(() => guard.canActivate(contextFor('handler'))).toThrow(
      ForbiddenException,
    );
  });

  it('denies routes that forgot @Roles instead of leaving them open', () => {
    expect(() =>
      guard.canActivate(contextFor('unprotected', UserRole.OWNER)),
    ).toThrow(ForbiddenException);
  });
});
