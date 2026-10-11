import { ServiceUnavailableException } from '@nestjs/common';
import {
  ImageStorageService,
  type StoredImage,
  type UploadImageOptions,
} from './image-storage.service.js';
import { createPublicId, toDeliveryUrl } from './public-id.js';

export interface InMemoryImage extends StoredImage {
  readonly file: Buffer;
  readonly options: UploadImageOptions;
}

/**
 * The storage tests use: no network, no provider. Keeps what was uploaded and
 * deleted so a test can assert on it, and can be told to fail.
 */
export class InMemoryImageStorage extends ImageStorageService {
  private readonly images = new Map<string, InMemoryImage>();

  /** Public ids passed to `delete`, in order (including ones that did not exist). */
  readonly deleted: string[] = [];

  /** While true, `upload` / `delete` answer 503 like a provider outage. */
  failUploads = false;
  failDeletes = false;

  get uploaded(): InMemoryImage[] {
    return [...this.images.values()];
  }

  has(publicId: string): boolean {
    return this.images.has(publicId);
  }

  upload(file: Buffer, options: UploadImageOptions): Promise<StoredImage> {
    if (this.failUploads) {
      return Promise.reject(this.unavailable());
    }
    const publicId = createPublicId(options.folder, options.name);
    const url = toDeliveryUrl(
      `https://images.test/image/upload/v1/${publicId}.jpg`,
    );
    this.images.set(publicId, { url, publicId, file, options });
    return Promise.resolve({ url, publicId });
  }

  delete(publicId: string): Promise<void> {
    this.deleted.push(publicId);
    if (this.failDeletes) {
      return Promise.reject(this.unavailable());
    }
    this.images.delete(publicId);
    return Promise.resolve();
  }

  private unavailable(): ServiceUnavailableException {
    return new ServiceUnavailableException(
      'Image storage is temporarily unavailable',
    );
  }
}
