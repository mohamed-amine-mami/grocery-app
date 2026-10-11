import {
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { hashPassword } from '../common/password.util.js';
import type { ValidatedImage } from '../images/image-file.pipe.js';
import { USER_AVATAR_PROFILE } from '../images/image-profiles.js';
import { ImageStorageService } from '../images/image-storage.service.js';
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

type PublicUser = Awaited<ReturnType<UsersService['findOne']>>;

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

/** What a user's photo columns held (or should hold). Both null: no photo. */
export interface PhotoState {
  photo: string | null;
  photoPublicId: string | null;
}

@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  constructor(private readonly images: ImageStorageService) {}

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

  /**
   * Replaces the user's own photo: upload the new image, then switch the
   * database to it, and only then delete the previous managed one. If the
   * database step fails the new image is deleted again and the database is
   * untouched. A legacy URL (no `photoPublicId`) is replaced but never deleted.
   */
  async setPhoto(userId: number, image: ValidatedImage) {
    const stored = await this.images.upload(image.buffer, {
      folder: `users/${userId}`,
      name: 'profile',
      profile: USER_AVATAR_PROFILE,
    });
    let swapped: { user: PublicUser; previous: PhotoState };
    try {
      swapped = await this.swapPhoto(userId, {
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
    return swapped.user;
  }

  /**
   * Removes the user's own photo. The database is cleared first and stays
   * cleared even if deleting the stored image then fails (that failure is
   * still reported). Having no photo, or a legacy URL, never touches storage.
   */
  async removePhoto(userId: number) {
    const { user, previous } = await this.swapPhoto(userId, {
      photo: null,
      photoPublicId: null,
    });
    if (previous.photoPublicId) {
      await this.images.delete(previous.photoPublicId);
    }
    return user;
  }

  /**
   * Writes the photo columns and returns the user together with the values
   * they replaced, read in the same transaction. All or nothing.
   */
  protected async swapPhoto(
    userId: number,
    next: PhotoState,
  ): Promise<{ user: PublicUser; previous: PhotoState }> {
    return await db.transaction(async (tx) => {
      const previous = await tx.orm.public.User.select(
        'photo',
        'photoPublicId',
      ).first({ id: userId });
      if (!previous) {
        throw new NotFoundException(`User ${userId} not found`);
      }
      const user = await tx.orm.public.User.select(...USER_FIELDS)
        .where({ id: userId })
        .update(next);
      if (!user) {
        throw new NotFoundException(`User ${userId} not found`);
      }
      return { user, previous };
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

  /** Full row, including the password hash — for the auth module's own use only. */
  async findByPhoneNumberForAuth(phoneNumber: string) {
    return await db.orm.public.User.where({ phoneNumber }).first();
  }
}
