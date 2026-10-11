import { ServiceUnavailableException } from '@nestjs/common';
import { InMemoryImageStorage } from './in-memory-image-storage.js';
import { STORE_PHOTO_PROFILE } from './image-profiles.js';
import { ImageStorageService } from './image-storage.service.js';

const options = {
  folder: 'stores/3',
  name: 'photo',
  profile: STORE_PHOTO_PROFILE,
};

describe('InMemoryImageStorage', () => {
  it('is an ImageStorageService', () => {
    expect(new InMemoryImageStorage()).toBeInstanceOf(ImageStorageService);
  });

  it('keeps what was uploaded under a unique id and a delivery URL', async () => {
    const storage = new InMemoryImageStorage();
    const first = await storage.upload(Buffer.from('a'), options);
    const second = await storage.upload(Buffer.from('b'), options);
    expect(first.publicId).toMatch(/^stores\/3\/photo-[0-9a-f]{16}$/);
    expect(first.publicId).not.toBe(second.publicId);
    expect(first.url).toContain('/f_auto,q_auto/');
    expect(storage.has(first.publicId)).toBe(true);
    expect(storage.uploaded).toHaveLength(2);
    expect(storage.uploaded[0]!.options).toEqual(options);
  });

  it('forgets a deleted image and records every delete', async () => {
    const storage = new InMemoryImageStorage();
    const { publicId } = await storage.upload(Buffer.from('a'), options);
    await storage.delete(publicId);
    await storage.delete('stores/3/never-existed');
    expect(storage.has(publicId)).toBe(false);
    expect(storage.deleted).toEqual([publicId, 'stores/3/never-existed']);
  });

  it('can be told to fail like a provider outage', async () => {
    const storage = new InMemoryImageStorage();
    storage.failUploads = true;
    await expect(
      storage.upload(Buffer.from('a'), options),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(storage.uploaded).toHaveLength(0);
    storage.failUploads = false;
    const { publicId } = await storage.upload(Buffer.from('a'), options);
    storage.failDeletes = true;
    await expect(storage.delete(publicId)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(storage.has(publicId)).toBe(true);
  });
});
