import {
  DELIVERY_TRANSFORMATION,
  STORE_PHOTO_PROFILE,
  USER_AVATAR_PROFILE,
} from './image-profiles.js';
import { createPublicId, toDeliveryUrl } from './public-id.js';

describe('createPublicId', () => {
  it('builds users/{id}/… and stores/{id}/… paths', () => {
    expect(createPublicId('users/12', 'profile')).toMatch(
      /^users\/12\/profile-[0-9a-f]{16}$/,
    );
    expect(createPublicId('stores/3', 'photo')).toMatch(
      /^stores\/3\/photo-[0-9a-f]{16}$/,
    );
  });

  it('puts the optional root prefix in front', () => {
    expect(createPublicId('users/1', 'profile', 'grocergo-dev')).toMatch(
      /^grocergo-dev\/users\/1\/profile-[0-9a-f]{16}$/,
    );
  });

  it('never repeats', () => {
    const ids = new Set(
      Array.from({ length: 2000 }, () => createPublicId('users/1', 'profile')),
    );
    expect(ids.size).toBe(2000);
  });

  it.each([
    ['../users/1', 'profile'],
    ['users//1', 'profile'],
    ['/users/1', 'profile'],
    ['users/1', 'pro file'],
    ['users/1', 'a/b'],
    ['', 'profile'],
    ['users/1', ''],
  ])('refuses the unsafe folder %j / name %j', (folder, name) => {
    expect(() => createPublicId(folder, name)).toThrow();
  });
});

describe('transformations', () => {
  it('defines the approved profiles', () => {
    expect(USER_AVATAR_PROFILE.uploadTransformation).toBe(
      'c_fill,g_auto,w_512,h_512',
    );
    expect(STORE_PHOTO_PROFILE.uploadTransformation).toBe('c_limit,w_1200');
    expect(DELIVERY_TRANSFORMATION).toBe('f_auto,q_auto');
  });

  it('puts the delivery transformation into the delivered URL', () => {
    expect(
      toDeliveryUrl(
        'https://res.cloudinary.com/demo/image/upload/v17/users/1/profile-ab.jpg',
      ),
    ).toBe(
      'https://res.cloudinary.com/demo/image/upload/f_auto,q_auto/v17/users/1/profile-ab.jpg',
    );
  });

  it('refuses a URL that is not an upload URL', () => {
    expect(() => toDeliveryUrl('https://example.com/a.jpg')).toThrow();
  });
});
