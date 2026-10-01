import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { comparePassword } from '../common/password.util.js';
import { UserRole } from '../users/user-role.enum.js';
import { UsersService } from '../users/users.service.js';
import { LoginDto } from './dto/login.dto.js';
import { RegisterDto } from './dto/register.dto.js';
import type { JwtPayload } from './jwt-payload.interface.js';

type PublicUser = Awaited<ReturnType<UsersService['findOne']>>;

@Injectable()
export class AuthService {
  constructor(
    private readonly usersService: UsersService,
    private readonly jwtService: JwtService,
  ) {}

  async register(dto: RegisterDto) {
    const user = await this.usersService.create(dto);
    return this.buildAuthResponse(user);
  }

  async login(dto: LoginDto) {
    const user = await this.usersService.findByPhoneNumberForAuth(
      dto.phoneNumber,
    );
    if (!user || !(await comparePassword(dto.password, user.password))) {
      throw new UnauthorizedException('Invalid phone number or password');
    }
    const { password: _password, ...publicUser } = user;
    return this.buildAuthResponse(publicUser);
  }

  async getCurrentUser(userId: number) {
    return await this.usersService.findOne(userId);
  }

  private buildAuthResponse(user: PublicUser) {
    const payload: JwtPayload = { sub: user.id, role: user.role as UserRole };
    return {
      accessToken: this.jwtService.sign(payload),
      user,
    };
  }
}
