import { NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import type { ValidatedImage } from '../images/image-file.pipe.js';
import { STORE_PHOTO_PROFILE } from '../images/image-profiles.js';
import { InMemoryImageStorage } from '../images/in-memory-image-storage.js';
import { type StorePhotoState, StoresService } from './stores.service.js';

const image: ValidatedImage = {
  buffer: Buffer.from('jpeg-bytes'),
  contentType: 'image/jpeg',
};
const none: StorePhotoState = { photo: null, photoPublicId: null };

/** The service with its database steps replaced, recording the order of events. */
class StubbedStoresService extends StoresService {
  calls: string[] = [];
  previous: StorePhotoState = none;
  failWith: Error | null = null;
  hasStore = true;
  lastNext: StorePhotoState | null = null;

  override findByOwner(ownerId: number) {
    if (!this.hasStore) {
      return Promise.reject(
        new NotFoundException('This owner has no store yet'),
      );
    }
    return Promise.resolve({ id: 30 + ownerId } as never);
  }

  protected override swapPhoto(ownerId: number, next: StorePhotoState) {
    this.calls.push('swap');
    this.lastNext = next;
    if (this.failWith) {
      return Promise.reject(this.failWith);
    }
    return Promise.resolve({
      store: { id: 30 + ownerId, photo: next.photo } as never,
      previous: this.previous,
    });
  }
}

function setup() {
  const storage = new InMemoryImageStorage();
  const service = new StubbedStoresService(storage);
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

const oldManaged: StorePhotoState = {
  photo: 'https://res.example/old.jpg',
  photoPublicId: 'stores/31/photo-old',
};

describe('StoresService.setPhoto', () => {
  it('uploads under stores/{storeId}/photo with the store profile, then saves url and id', async () => {
    const { storage, service } = setup();
    const store = await service.setPhoto(1, image);

    const [stored] = storage.uploaded;
    expect(stored!.publicId).toMatch(/^stores\/31\/photo-[0-9a-f]{16}$/);
    expect(stored!.options).toEqual({
      folder: 'stores/31',
      name: 'photo',
      profile: STORE_PHOTO_PROFILE,
    });
    expect(service.lastNext).toEqual({
      photo: stored!.url,
      photoPublicId: stored!.publicId,
    });
    expect(store.photo).toBe(stored!.url);
  });

  it('deletes the previous managed image only after the database switched', async () => {
    const { service } = setup();
    service.previous = oldManaged;
    await service.setPhoto(1, image);
    expect(service.calls).toEqual([
      'upload',
      'swap',
      'delete stores/31/photo-old',
    ]);
  });

  it('never deletes a legacy URL, nor anything when there was no photo', async () => {
    const { storage, service } = setup();
    service.previous = {
      photo: 'https://legacy.example/s.jpg',
      photoPublicId: null,
    };
    await service.setPhoto(1, image);
    service.previous = none;
    await service.setPhoto(1, image);
    expect(storage.deleted).toEqual([]);
  });

  it('on a database failure deletes the NEW image, keeps the old one, and rethrows', async () => {
    const { storage, service } = setup();
    service.previous = oldManaged;
    service.failWith = new Error('db down');
    await expect(service.setPhoto(1, image)).rejects.toThrow('db down');
    expect(storage.uploaded).toHaveLength(0);
    expect(storage.deleted).toHaveLength(1);
    expect(storage.deleted[0]).toMatch(/^stores\/31\/photo-[0-9a-f]{16}$/);
    expect(storage.deleted).not.toContain('stores/31/photo-old');
  });

  it('reports the database error even when removing the new image also fails', async () => {
    const { storage, service } = setup();
    service.failWith = new Error('db down');
    storage.failDeletes = true;
    await expect(service.setPhoto(1, image)).rejects.toThrow('db down');
  });

  it('uploads nothing when the owner has no store', async () => {
    const { storage, service } = setup();
    service.hasStore = false;
    await expect(service.setPhoto(1, image)).rejects.toBeInstanceOf(
      NotFoundException,
    );
    expect(service.calls).toEqual([]);
    expect(storage.uploaded).toHaveLength(0);
  });

  it('does not touch the database when the upload fails', async () => {
    const { storage, service } = setup();
    storage.failUploads = true;
    await expect(service.setPhoto(1, image)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(service.calls).toEqual(['upload']);
  });

  it('still succeeds when cleaning up the previous image fails', async () => {
    const { storage, service } = setup();
    service.previous = oldManaged;
    storage.failDeletes = true;
    await expect(service.setPhoto(1, image)).resolves.toBeDefined();
  });
});

describe('StoresService.removePhoto', () => {
  it('clears the database first, then deletes the managed image', async () => {
    const { service } = setup();
    service.previous = oldManaged;
    const store = await service.removePhoto(1);
    expect(service.lastNext).toEqual(none);
    expect(service.calls).toEqual(['swap', 'delete stores/31/photo-old']);
    expect(store.photo).toBeNull();
  });

  it('does not touch storage for a legacy URL or for no photo', async () => {
    const { storage, service } = setup();
    service.previous = {
      photo: 'https://legacy.example/s.jpg',
      photoPublicId: null,
    };
    await service.removePhoto(1);
    service.previous = none;
    await service.removePhoto(1);
    expect(storage.deleted).toEqual([]);
  });

  it('keeps the database cleared and reports 503 when deleting the image fails', async () => {
    const { storage, service } = setup();
    service.previous = oldManaged;
    storage.failDeletes = true;
    await expect(service.removePhoto(1)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(service.calls).toEqual(['swap', 'delete stores/31/photo-old']);
    expect(service.lastNext).toEqual(none);
  });
});
