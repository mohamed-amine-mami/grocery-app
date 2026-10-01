import 'dotenv/config';
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { UsersModule } from '../users/users.module.js';
import { AuthController } from './auth.controller.js';
import { AuthService } from './auth.service.js';
import { JwtAuthGuard } from './jwt-auth.guard.js';
import { RolesGuard } from './roles.guard.js';

if (!process.env['JWT_SECRET']) {
  throw new Error('JWT_SECRET environment variable is required');
}

@Module({
  imports: [
    UsersModule,
    JwtModule.register({
      secret: process.env['JWT_SECRET'],
      signOptions: { expiresIn: '7d' },
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtAuthGuard, RolesGuard],
  // JwtModule is re-exported because guards are instantiated in the module
  // that uses them and `JwtAuthGuard` needs `JwtService`.
  exports: [JwtAuthGuard, RolesGuard, JwtModule],
})
export class AuthModule {}
