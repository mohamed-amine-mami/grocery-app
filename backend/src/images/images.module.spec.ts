import { ServiceUnavailableException } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { CloudinaryImageStorage } from './cloudinary-image-storage.js';
import { USER_AVATAR_PROFILE } from './image-profiles.js';
import { ImageFilePipe } from './image-file.pipe.js';
import { ImageStorageService } from './image-storage.service.js';
import { ImagesModule } from './images.module.js';
import { InMemoryImageStorage } from './in-memory-image-storage.js';

const variables = [
  'CLOUDINARY_CLOUD_NAME',
  'CLOUDINARY_API_KEY',
  'CLOUDINARY_API_SECRET',
  'CLOUDINARY_FOLDER_PREFIX',
] as const;

describe('ImagesModule', () => {
  const saved = Object.fromEntries(
    variables.map((name) => [name, process.env[name]]),
  );

  afterEach(() => {
    for (const name of variables) {
      if (saved[name] === undefined) delete process.env[name];
      else process.env[name] = saved[name];
    }
  });

  it('starts without Cloudinary configuration, and uploads answer 503', async () => {
    for (const name of variables) delete process.env[name];
    const module = await Test.createTestingModule({
      imports: [ImagesModule],
    }).compile();
    const storage = module.get(ImageStorageService);
    expect(storage).toBeInstanceOf(CloudinaryImageStorage);
    await expect(
      storage.upload(Buffer.from('x'), {
        folder: 'users/1',
        name: 'profile',
        profile: USER_AVATAR_PROFILE,
      }),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(module.get(ImageFilePipe)).toBeInstanceOf(ImageFilePipe);
  });

  it('starts with (placeholder) configuration without calling Cloudinary', async () => {
    process.env['CLOUDINARY_CLOUD_NAME'] = 'demo-cloud';
    process.env['CLOUDINARY_API_KEY'] = 'key-123';
    process.env['CLOUDINARY_API_SECRET'] = 'secret-abc';
    const module = await Test.createTestingModule({
      imports: [ImagesModule],
    }).compile();
    expect(module.get(ImageStorageService)).toBeInstanceOf(
      CloudinaryImageStorage,
    );
  });

  it('lets a test replace the storage with the in-memory one', async () => {
    const fake = new InMemoryImageStorage();
    const module = await Test.createTestingModule({ imports: [ImagesModule] })
      .overrideProvider(ImageStorageService)
      .useValue(fake)
      .compile();
    expect(module.get(ImageStorageService)).toBe(fake);
  });
});
