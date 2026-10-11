import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import type { ValidatedImage } from '../images/image-file.pipe.js';
import { STORE_PHOTO_PROFILE } from '../images/image-profiles.js';
import { ImageStorageService } from '../images/image-storage.service.js';
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

/** The storage reference of the photo is internal: it is never part of a response. */
function toPublicStore<T extends { photoPublicId: string | null }>(store: T) {
  const { photoPublicId: _photoPublicId, ...publicStore } = store;
  return publicStore;
}

type StorePublic = Awaited<ReturnType<StoresService['findByOwner']>>;

/** What a store's photo columns held (or should hold). Both null: no photo. */
export interface StorePhotoState {
  photo: string | null;
  photoPublicId: string | null;
}

/**
 * Every method is scoped by `ownerId`, which the controller takes from the
 * verified JWT — there is deliberately no way to address a store by id.
 */
@Injectable()
export class StoresService {
  private readonly logger = new Logger(StoresService.name);

  constructor(private readonly images: ImageStorageService) {}

  async findByOwner(ownerId: number) {
    const store = await db.orm.public.Store.first({ ownerId });
    if (!store) {
      throw new NotFoundException('This owner has no store yet');
    }
    return toPublicStore(store);
  }

  async createForOwner(ownerId: number, dto: CreateStoreDto) {
    try {
      // `isOpen` is left to its column default (false): new stores start closed.
      return toPublicStore(
        await db.orm.public.Store.create(Object.assign({}, dto, { ownerId })),
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
      return toPublicStore(store);
    } catch (error) {
      if (error instanceof NotFoundException) {
        throw error;
      }
      handleWriteError(error);
    }
  }

  /**
   * Replaces the owner's own store photo: upload the new image, then switch
   * the database to it, and only then delete the previous managed one. If the
   * database step fails the new image is deleted again and the database is
   * untouched. A legacy URL (no `photoPublicId`) is replaced but never deleted.
   */
  async setPhoto(ownerId: number, image: ValidatedImage) {
    const { id: storeId } = await this.findByOwner(ownerId);
    const stored = await this.images.upload(image.buffer, {
      folder: `stores/${storeId}`,
      name: 'photo',
      profile: STORE_PHOTO_PROFILE,
    });
    let swapped: { store: StorePublic; previous: StorePhotoState };
    try {
      swapped = await this.swapPhoto(ownerId, {
        photo: stored.url,
        photoPublicId: stored.publicId,
      });
    } catch (error) {
      await this.discard(stored.publicId, 'new');
      throw error;
    }
    if (swapped.previous.photoPublicId) {
      // The new photo is already in place: a failed cleanup only leaves an orphan.
      await this.discard(swapped.previous.photoPublicId, 'previous');
    }
    return swapped.store;
  }

  /**
   * Removes the owner's own store photo. The database is cleared first and
   * stays cleared even if deleting the stored image then fails (that failure
   * is still reported). No photo, or a legacy URL, never touches storage.
   */
  async removePhoto(ownerId: number) {
    const { store, previous } = await this.swapPhoto(ownerId, {
      photo: null,
      photoPublicId: null,
    });
    if (previous.photoPublicId) {
      await this.images.delete(previous.photoPublicId);
    }
    return store;
  }

  /**
   * Writes the photo columns and returns the store together with the values
   * they replaced, read in the same transaction. All or nothing.
   */
  protected async swapPhoto(
    ownerId: number,
    next: StorePhotoState,
  ): Promise<{ store: StorePublic; previous: StorePhotoState }> {
    return await db.transaction(async (tx) => {
      const previous = await tx.orm.public.Store.select(
        'photo',
        'photoPublicId',
      ).first({ ownerId });
      if (!previous) {
        throw new NotFoundException('This owner has no store yet');
      }
      const store = await tx.orm.public.Store.where({ ownerId }).update(next);
      if (!store) {
        throw new NotFoundException('This owner has no store yet');
      }
      return { store: toPublicStore(store), previous };
    });
  }

  private async discard(publicId: string, which: 'new' | 'previous') {
    try {
      await this.images.delete(publicId);
    } catch {
      this.logger.warn(
        `Could not delete the ${which} stored image ${publicId}`,
      );
    }
  }
}
