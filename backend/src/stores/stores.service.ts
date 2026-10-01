import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { db } from '../prisma/db.js';
import { CreateStoreDto } from './dto/create-store.dto.js';
import { UpdateStoreDto } from './dto/update-store.dto.js';

function sqlState(error: unknown): string | undefined {
  return typeof error === 'object' && error !== null
    ? (error as { sqlState?: string }).sqlState
    : undefined;
}

function handleWriteError(error: unknown): never {
  switch (sqlState(error)) {
    case '23505': // unique_violation — Store.ownerId
      throw new ConflictException('This owner already has a store');
    case '23502': // not_null_violation — e.g. PATCH { "name": null }
      throw new BadRequestException('Required fields cannot be null');
    case '23514': // check_violation — store_coordinates_together
      throw new BadRequestException(
        'latitude and longitude must be provided together',
      );
    case '23503': // foreign_key_violation — the token's user no longer exists
      throw new UnauthorizedException('Owner account no longer exists');
    default:
      throw error;
  }
}

/**
 * Every method is scoped by `ownerId`, which the controller takes from the
 * verified JWT — there is deliberately no way to address a store by id.
 */
@Injectable()
export class StoresService {
  async findByOwner(ownerId: number) {
    const store = await db.orm.public.Store.first({ ownerId });
    if (!store) {
      throw new NotFoundException('This owner has no store yet');
    }
    return store;
  }

  async createForOwner(ownerId: number, dto: CreateStoreDto) {
    try {
      // `isOpen` is left to its column default (false): new stores start closed.
      return await db.orm.public.Store.create(
        Object.assign({}, dto, { ownerId }),
      );
    } catch (error) {
      handleWriteError(error);
    }
  }

  async updateForOwner(ownerId: number, dto: UpdateStoreDto) {
    // Transformed DTOs carry `undefined`-valued keys, so check values, not keys.
    if (Object.values(dto).every((value) => value === undefined)) {
      return await this.findByOwner(ownerId);
    }
    // `PartialType` makes every DTO field optional, which also switches off the
    // DTO's pairing rule — so it is enforced here. Sending `null` for both
    // clears the location. The DB CHECK is the last line of defence.
    if ((dto.latitude === undefined) !== (dto.longitude === undefined)) {
      throw new BadRequestException(
        'latitude and longitude must be provided together',
      );
    }
    try {
      const store = await db.orm.public.Store.where({ ownerId }).update(dto);
      if (!store) {
        throw new NotFoundException('This owner has no store yet');
      }
      return store;
    } catch (error) {
      if (error instanceof NotFoundException) {
        throw error;
      }
      handleWriteError(error);
    }
  }
}
