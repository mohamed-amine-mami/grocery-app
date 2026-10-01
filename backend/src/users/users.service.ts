import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { hashPassword } from '../common/password.util.js';
import { db } from '../prisma/db.js';
import { CreateUserDto } from './dto/create-user.dto.js';

const USER_FIELDS = [
  'id',
  'name',
  'email',
  'phoneNumber',
  'whatsappNumber',
  'photo',
  'role',
  'createdAt',
  'updatedAt',
] as const;

function conflictMessageForUniqueViolation(error: unknown): string | undefined {
  if (typeof error !== 'object' || error === null) {
    return undefined;
  }
  const { sqlState, constraint } = error as {
    sqlState?: string;
    constraint?: string;
  };
  if (sqlState !== '23505') {
    return undefined;
  }
  if (constraint === 'User_email_key') {
    return 'A user with this email already exists';
  }
  if (constraint === 'User_phoneNumber_key') {
    return 'A user with this phone number already exists';
  }
  return 'A user with these details already exists';
}

@Injectable()
export class UsersService {
  async create(dto: CreateUserDto) {
    try {
      return await db.orm.public.User.select(...USER_FIELDS).create(
        Object.assign({}, dto, { password: await hashPassword(dto.password) }),
      );
    } catch (error) {
      const message = conflictMessageForUniqueViolation(error);
      if (message) {
        throw new ConflictException(message);
      }
      throw error;
    }
  }

  async findOne(id: number) {
    const user = await db.orm.public.User.select(...USER_FIELDS).first({ id });
    if (!user) {
      throw new NotFoundException(`User ${id} not found`);
    }
    return user;
  }

  /** Full row, including the password hash — for the auth module's own use only. */
  async findByPhoneNumberForAuth(phoneNumber: string) {
    return await db.orm.public.User.where({ phoneNumber }).first();
  }
}
