import { readCloudinaryConfig } from './cloudinary-config.js';

const full = {
  CLOUDINARY_CLOUD_NAME: 'demo-cloud',
  CLOUDINARY_API_KEY: 'key-123',
  CLOUDINARY_API_SECRET: 'secret-abc',
};

describe('readCloudinaryConfig', () => {
  it('reads the three credentials', () => {
    expect(readCloudinaryConfig(full)).toEqual({
      cloudName: 'demo-cloud',
      apiKey: 'key-123',
      apiSecret: 'secret-abc',
      folderPrefix: undefined,
    });
  });

  it('is null — not an error — when nothing is set', () => {
    expect(readCloudinaryConfig({})).toBeNull();
  });

  it.each([
    'CLOUDINARY_CLOUD_NAME',
    'CLOUDINARY_API_KEY',
    'CLOUDINARY_API_SECRET',
  ])('is null when %s is missing or blank', (name) => {
    expect(readCloudinaryConfig({ ...full, [name]: undefined })).toBeNull();
    expect(readCloudinaryConfig({ ...full, [name]: '   ' })).toBeNull();
  });

  it('treats an empty prefix as none and trims slashes', () => {
    expect(
      readCloudinaryConfig({ ...full, CLOUDINARY_FOLDER_PREFIX: '' })
        ?.folderPrefix,
    ).toBeUndefined();
    expect(
      readCloudinaryConfig({
        ...full,
        CLOUDINARY_FOLDER_PREFIX: '/grocergo-dev/',
      })?.folderPrefix,
    ).toBe('grocergo-dev');
  });

  it('is null for a malformed prefix', () => {
    expect(
      readCloudinaryConfig({ ...full, CLOUDINARY_FOLDER_PREFIX: 'a b/../c' }),
    ).toBeNull();
  });
});
