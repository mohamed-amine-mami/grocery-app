import { NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import type { ValidatedImage } from '../images/image-file.pipe.js';
import { USER_AVATAR_PROFILE } from '../images/image-profiles.js';
import { InMemoryImageStorage } from '../images/in-memory-image-storage.js';
import { type PhotoState, UsersService } from './users.service.js';

const image: ValidatedImage = {
  buffer: Buffer.from('jpeg-bytes'),
  contentType: 'image/jpeg',
};
const none: PhotoState = { photo: null, photoPublicId: null };

/** The service with its one database step replaced, recording the order of events. */
class StubbedUsersService extends UsersService {
  calls: string[] = [];
  previous: PhotoState = none;
  failWith: Error | null = null;
  lastNext: PhotoState | null = null;

  protected override swapPhoto(userId: number, next: PhotoState) {
    this.calls.push('swap');
    this.lastNext = next;
    if (this.failWith) {
      return Promise.reject(this.failWith);
    }
    return Promise.resolve({
      user: { id: userId, photo: next.photo } as never,
      previous: this.previous,
    });
  }
}

function setup() {
  const storage = new InMemoryImageStorage();
  const service = new StubbedUsersService(storage);
  // Record storage calls in the same timeline as the database step.
  const upload = storage.upload.bind(storage);
  const remove = storage.delete.bind(storage);
  storage.upload = (file, options) => {
    service.calls.push('upload');
    return upload(file, options);
  };
  storage.delete = (publicId) => {
    service.calls.push(`delete ${publicId}`);
    return remove(publicId);
  };
  return { storage, service };
}

describe('UsersService.setPhoto', () => {
  it('uploads under users/{id}/profile with the avatar profile, then saves url and id', async () => {
    const { storage, service } = setup();
    const user = await service.setPhoto(12, image);

    const [stored] = storage.uploaded;
    expect(stored!.publicId).toMatch(/^users\/12\/profile-[0-9a-f]{16}$/);
    expect(stored!.options).toEqual({
      folder: 'users/12',
      name: 'profile',
      profile: USER_AVATAR_PROFILE,
    });
    expect(stored!.file).toBe(image.buffer);
    expect(service.lastNext).toEqual({
      photo: stored!.url,
      photoPublicId: stored!.publicId,
    });
    expect(user.photo).toBe(stored!.url);
  });

  it('deletes the previous managed image only after the database switched', async () => {
    const { service } = setup();
    service.previous = {
      photo: 'https://res.example/old.jpg',
      photoPublicId: 'users/12/profile-old',
    };
    await service.setPhoto(12, image);
    expect(service.calls).toEqual([
      'upload',
      'swap',
      'delete users/12/profile-old',
    ]);
  });

  it('never deletes a legacy URL (a photo without a storage reference)', async () => {
    const { storage, service } = setup();
    service.previous = {
      photo: 'https://legacy.example/me.jpg',
      photoPublicId: null,
    };
    await service.setPhoto(12, image);
    expect(storage.deleted).toEqual([]);
    expect(service.calls).toEqual(['upload', 'swap']);
  });

  it('deletes nothing when there was no photo', async () => {
    const { storage, service } = setup();
    await service.setPhoto(12, image);
    expect(storage.deleted).toEqual([]);
  });

  it('on a database failure deletes the NEW image, keeps the old one, and rethrows', async () => {
    const { storage, service } = setup();
    service.previous = {
      photo: 'https://res.example/old.jpg',
      photoPublicId: 'users/12/profile-old',
    };
    service.failWith = new Error('db down');
    await expect(service.setPhoto(12, image)).rejects.toThrow('db down');

    expect(storage.uploaded).toHaveLength(0); // the new asset is gone
    expect(storage.deleted).toHaveLength(1);
    expect(storage.deleted[0]).toMatch(/^users\/12\/profile-[0-9a-f]{16}$/);
    expect(storage.deleted).not.toContain('users/12/profile-old');
  });

  it('reports the database error even when removing the new image also fails', async () => {
    const { storage, service } = setup();
    service.failWith = new NotFoundException('User 12 not found');
    storage.failDeletes = true;
    await expect(service.setPhoto(12, image)).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('does not touch the database when the upload fails', async () => {
    const { storage, service } = setup();
    storage.failUploads = true;
    await expect(service.setPhoto(12, image)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(service.calls).toEqual(['upload']);
  });

  it('still succeeds when cleaning up the previous image fails', async () => {
    const { storage, service } = setup();
    service.previous = {
      photo: 'https://res.example/old.jpg',
      photoPublicId: 'users/12/profile-old',
    };
    storage.failDeletes = true;
    await expect(service.setPhoto(12, image)).resolves.toBeDefined();
  });
});

describe('UsersService.removePhoto', () => {
  it('clears the database first, then deletes the managed image', async () => {
    const { service } = setup();
    service.previous = {
      photo: 'https://res.example/old.jpg',
      photoPublicId: 'users/12/profile-old',
    };
    const user = await service.removePhoto(12);
    expect(service.lastNext).toEqual(none);
    expect(service.calls).toEqual(['swap', 'delete users/12/profile-old']);
    expect(user.photo).toBeNull();
  });

  it('does not touch storage for a legacy URL or for no photo', async () => {
    const { storage, service } = setup();
    service.previous = {
      photo: 'https://legacy.example/me.jpg',
      photoPublicId: null,
    };
    await service.removePhoto(12);
    service.previous = none;
    await service.removePhoto(12);
    expect(storage.deleted).toEqual([]);
  });

  it('keeps the database cleared and reports 503 when deleting the image fails', async () => {
    const { storage, service } = setup();
    service.previous = {
      photo: 'https://res.example/old.jpg',
      photoPublicId: 'users/12/profile-old',
    };
    storage.failDeletes = true;
    await expect(service.removePhoto(12)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    // The swap (which cleared the columns) ran, and nothing restored them.
    expect(service.calls).toEqual(['swap', 'delete users/12/profile-old']);
    expect(service.lastNext).toEqual(none);
  });
});
