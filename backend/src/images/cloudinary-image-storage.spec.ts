import { Logger, ServiceUnavailableException } from '@nestjs/common';
import { vi } from 'vitest';
import {
  CloudinaryImageStorage,
  type CloudinaryClient,
} from './cloudinary-image-storage.js';
import type { CloudinaryConfig } from './cloudinary-config.js';
import { STORE_PHOTO_PROFILE, USER_AVATAR_PROFILE } from './image-profiles.js';

const settings: CloudinaryConfig = {
  cloudName: 'demo-cloud',
  apiKey: 'key-123',
  apiSecret: 'secret-abc',
};

type UploadCallback = Parameters<
  CloudinaryClient['uploader']['upload_stream']
>[1];

function fakeSdk() {
  const end = vi.fn();
  const upload_stream = vi.fn(
    (options: Record<string, unknown>, callback: UploadCallback) => {
      end.mockImplementation(() =>
        callback(null, {
          secure_url: `https://res.cloudinary.com/demo-cloud/image/upload/v9/${String(options['public_id'])}.jpg`,
          public_id: String(options['public_id']),
        }),
      );
      return { end };
    },
  );
  const destroy = vi.fn().mockResolvedValue({ result: 'ok' });
  const config = vi.fn();
  const sdk: CloudinaryClient = {
    config,
    uploader: { upload_stream, destroy },
  };
  return { sdk, config, upload_stream, destroy, end };
}

const file = Buffer.from('image-bytes');

describe('CloudinaryImageStorage', () => {
  // Failure paths log the provider's message: keep it out of the test output.
  let logSpy: ReturnType<typeof vi.spyOn>;
  beforeEach(() => {
    logSpy = vi
      .spyOn(Logger.prototype, 'error')
      .mockImplementation(() => undefined);
  });
  afterEach(() => vi.restoreAllMocks());

  describe('upload', () => {
    it('configures the SDK once with the credentials', () => {
      const { sdk, config } = fakeSdk();
      new CloudinaryImageStorage(settings, sdk);
      expect(config).toHaveBeenCalledWith({
        cloud_name: 'demo-cloud',
        api_key: 'key-123',
        api_secret: 'secret-abc',
        secure: true,
      });
    });

    it('sends the file with a unique public id and the profile transformation', async () => {
      const { sdk, upload_stream, end } = fakeSdk();
      const storage = new CloudinaryImageStorage(settings, sdk);

      const stored = await storage.upload(file, {
        folder: 'users/12',
        name: 'profile',
        profile: USER_AVATAR_PROFILE,
      });

      expect(end).toHaveBeenCalledWith(file);
      const options = upload_stream.mock.calls[0]![0];
      // The SDK would read a plain `transformation` string as a named one.
      expect(options).not.toHaveProperty('transformation');
      expect(options).toMatchObject({
        resource_type: 'image',
        asset_folder: 'users/12',
        overwrite: false,
        allowed_formats: ['jpg', 'png', 'webp'],
        raw_transformation: 'c_fill,g_auto,w_512,h_512',
      });
      expect(options['public_id']).toMatch(/^users\/12\/profile-[0-9a-f]{16}$/);
      expect(stored.publicId).toBe(options['public_id']);
    });

    it('uses the store profile for a store photo', async () => {
      const { sdk, upload_stream } = fakeSdk();
      await new CloudinaryImageStorage(settings, sdk).upload(file, {
        folder: 'stores/3',
        name: 'photo',
        profile: STORE_PHOTO_PROFILE,
      });
      expect(upload_stream.mock.calls[0]![0]).toMatchObject({
        raw_transformation: 'c_limit,w_1200',
      });
      expect(upload_stream.mock.calls[0]![0]['public_id']).toMatch(
        /^stores\/3\/photo-/,
      );
    });

    it('returns an HTTPS delivery URL with f_auto,q_auto', async () => {
      const { sdk } = fakeSdk();
      const stored = await new CloudinaryImageStorage(settings, sdk).upload(
        file,
        {
          folder: 'users/1',
          name: 'profile',
          profile: USER_AVATAR_PROFILE,
        },
      );
      expect(stored.url).toMatch(
        /^https:\/\/res\.cloudinary\.com\/demo-cloud\/image\/upload\/f_auto,q_auto\/v9\/users\/1\/profile-[0-9a-f]{16}\.jpg$/,
      );
    });

    it('gives every upload a new public id', async () => {
      const { sdk } = fakeSdk();
      const storage = new CloudinaryImageStorage(settings, sdk);
      const options = {
        folder: 'users/1',
        name: 'profile',
        profile: USER_AVATAR_PROFILE,
      };
      const first = await storage.upload(file, options);
      const second = await storage.upload(file, options);
      expect(first.publicId).not.toBe(second.publicId);
      expect(first.url).not.toBe(second.url);
    });

    it('puts the folder prefix in the id and the folder', async () => {
      const { sdk, upload_stream } = fakeSdk();
      const storage = new CloudinaryImageStorage(
        { ...settings, folderPrefix: 'grocergo-dev' },
        sdk,
      );
      const stored = await storage.upload(file, {
        folder: 'users/1',
        name: 'profile',
        profile: USER_AVATAR_PROFILE,
      });
      expect(stored.publicId).toMatch(/^grocergo-dev\/users\/1\/profile-/);
      expect(upload_stream.mock.calls[0]![0]['asset_folder']).toBe(
        'grocergo-dev/users/1',
      );
    });

    it('answers 503 when the SDK fails, without leaking the secret', async () => {
      const { sdk, end } = fakeSdk();
      end.mockImplementation(() => undefined);
      sdk.uploader.upload_stream = vi.fn((_o, callback: UploadCallback) => ({
        end: () => callback(new Error('network down: secret-abc'), undefined),
      }));
      const storage = new CloudinaryImageStorage(settings, sdk);
      const failure = await storage
        .upload(file, {
          folder: 'users/1',
          name: 'profile',
          profile: USER_AVATAR_PROFILE,
        })
        .catch((error: unknown) => error);
      expect(failure).toBeInstanceOf(ServiceUnavailableException);
      expect(
        JSON.stringify((failure as ServiceUnavailableException).getResponse()),
      ).not.toContain('secret-abc');
      const logged = JSON.stringify(logSpy.mock.calls);
      expect(logged).toContain('network down');
      expect(logged).not.toContain('secret-abc');
    });

    it('answers 503 when the SDK returns no URL', async () => {
      const { sdk } = fakeSdk();
      sdk.uploader.upload_stream = vi.fn((_o, callback: UploadCallback) => ({
        end: () => callback(null, {}),
      }));
      await expect(
        new CloudinaryImageStorage(settings, sdk).upload(file, {
          folder: 'users/1',
          name: 'profile',
          profile: USER_AVATAR_PROFILE,
        }),
      ).rejects.toBeInstanceOf(ServiceUnavailableException);
    });
  });

  describe('delete', () => {
    it('destroys the asset and invalidates the CDN copy', async () => {
      const { sdk, destroy } = fakeSdk();
      await new CloudinaryImageStorage(settings, sdk).delete(
        'users/1/profile-ab',
      );
      expect(destroy).toHaveBeenCalledWith('users/1/profile-ab', {
        resource_type: 'image',
        invalidate: true,
      });
    });

    it('treats an asset that is already gone as deleted', async () => {
      const { sdk, destroy } = fakeSdk();
      destroy.mockResolvedValue({ result: 'not found' });
      await expect(
        new CloudinaryImageStorage(settings, sdk).delete('users/1/gone'),
      ).resolves.toBeUndefined();
    });

    it.each([
      ['an unexpected result', () => Promise.resolve({ result: 'error' })],
      ['a thrown error', () => Promise.reject(new Error('timeout'))],
    ])('answers 503 on %s', async (_name, behaviour) => {
      const { sdk, destroy } = fakeSdk();
      destroy.mockImplementation(behaviour);
      await expect(
        new CloudinaryImageStorage(settings, sdk).delete('users/1/x'),
      ).rejects.toBeInstanceOf(ServiceUnavailableException);
    });
  });

  describe('without configuration', () => {
    it('constructs, touches nothing, and answers 503 on every call', async () => {
      const { sdk, config, upload_stream, destroy } = fakeSdk();
      const storage = new CloudinaryImageStorage(null, sdk);
      expect(config).not.toHaveBeenCalled();
      await expect(
        storage.upload(file, {
          folder: 'users/1',
          name: 'profile',
          profile: USER_AVATAR_PROFILE,
        }),
      ).rejects.toBeInstanceOf(ServiceUnavailableException);
      await expect(storage.delete('users/1/x')).rejects.toBeInstanceOf(
        ServiceUnavailableException,
      );
      expect(upload_stream).not.toHaveBeenCalled();
      expect(destroy).not.toHaveBeenCalled();
    });
  });
});
