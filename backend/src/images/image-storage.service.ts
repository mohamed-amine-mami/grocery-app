import type { ImageProfile } from './image-profiles.js';

export interface UploadImageOptions {
  /** Where the image lives, e.g. `users/12` or `stores/3`. Letters, digits, `_`, `-`, `/` only. */
  readonly folder: string;
  /** Start of the file name, e.g. `profile`; a random suffix makes every upload unique. */
  readonly name: string;
  readonly profile: ImageProfile;
}

export interface StoredImage {
  /** The URL clients display: HTTPS, with the delivery transformation applied. */
  readonly url: string;
  /** The storage reference needed to replace or delete the image later. Never sent to clients. */
  readonly publicId: string;
}

/**
 * Image storage as the application sees it. Nothing outside this module knows
 * which provider is behind it; `CloudinaryImageStorage` is the real one and
 * `InMemoryImageStorage` the one tests use.
 *
 * Failures (provider unreachable, storage not configured) are a 503
 * `ServiceUnavailableException`.
 */
export abstract class ImageStorageService {
  /** Stores [file] under a new unique public id. Never overwrites. */
  abstract upload(
    file: Buffer,
    options: UploadImageOptions,
  ): Promise<StoredImage>;

  /** Removes an image. Deleting one that is already gone succeeds. */
  abstract delete(publicId: string): Promise<void>;
}
