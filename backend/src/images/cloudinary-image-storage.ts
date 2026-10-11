import { Logger, ServiceUnavailableException } from '@nestjs/common';
import { v2 } from 'cloudinary';
import type { CloudinaryConfig } from './cloudinary-config.js';
import {
  ImageStorageService,
  type StoredImage,
  type UploadImageOptions,
} from './image-storage.service.js';
import { createPublicId, toDeliveryUrl } from './public-id.js';

/** The part of the Cloudinary SDK used here, so tests can stand in for it. */
export interface CloudinaryClient {
  config(options: Record<string, unknown>): unknown;
  uploader: {
    upload_stream(
      options: Record<string, unknown>,
      callback: (
        error: unknown,
        result: { secure_url?: string; public_id?: string } | undefined,
      ) => void,
    ): { end(buffer: Buffer): unknown };
    destroy(
      publicId: string,
      options: Record<string, unknown>,
    ): Promise<{ result?: string }>;
  };
}

const UNAVAILABLE = 'Image storage is temporarily unavailable';

/**
 * The only class that knows Cloudinary. Without configuration it is inert:
 * the application starts, and every call answers 503.
 */
export class CloudinaryImageStorage extends ImageStorageService {
  private readonly logger = new Logger(CloudinaryImageStorage.name);

  constructor(
    private readonly settings: CloudinaryConfig | null,
    private readonly sdk: CloudinaryClient = v2 as unknown as CloudinaryClient,
  ) {
    super();
    if (settings) {
      sdk.config({
        cloud_name: settings.cloudName,
        api_key: settings.apiKey,
        api_secret: settings.apiSecret,
        secure: true,
      });
    }
  }

  async upload(
    file: Buffer,
    options: UploadImageOptions,
  ): Promise<StoredImage> {
    const settings = this.requireSettings();
    const publicId = createPublicId(
      options.folder,
      options.name,
      settings.folderPrefix,
    );
    const folder = settings.folderPrefix
      ? `${settings.folderPrefix}/${options.folder}`
      : options.folder;
    try {
      const result = await new Promise<{ secure_url?: string }>(
        (resolve, reject) => {
          const stream = this.sdk.uploader.upload_stream(
            {
              resource_type: 'image',
              // The id carries the whole path, which also holds in accounts
              // whose folders are "dynamic" (`asset_folder` is then the view).
              public_id: publicId,
              asset_folder: folder,
              overwrite: false,
              unique_filename: false,
              use_filename: false,
              allowed_formats: ['jpg', 'png', 'webp'],
              // `raw_transformation`, not `transformation`: the SDK reads a plain
              // string given as `transformation` as a *named* transformation
              // (`t_c_fill,…`), which Cloudinary rejects as unknown.
              raw_transformation: options.profile.uploadTransformation,
            },
            (error, uploaded) =>
              error || !uploaded
                ? reject(error ?? new Error('No result'))
                : resolve(uploaded),
          );
          stream.end(file);
        },
      );
      if (!result.secure_url) {
        throw new Error('Upload returned no URL');
      }
      return { url: toDeliveryUrl(result.secure_url), publicId };
    } catch (error) {
      this.fail('upload', error);
    }
  }

  async delete(publicId: string): Promise<void> {
    this.requireSettings();
    try {
      const { result } = await this.sdk.uploader.destroy(publicId, {
        resource_type: 'image',
        invalidate: true,
      });
      if (result !== 'ok' && result !== 'not found') {
        throw new Error(`Unexpected delete result: ${String(result)}`);
      }
    } catch (error) {
      this.fail('delete', error);
    }
  }

  private requireSettings(): CloudinaryConfig {
    if (!this.settings) {
      throw new ServiceUnavailableException('Image storage is not configured');
    }
    return this.settings;
  }

  /** Logs the provider's message (never the credentials) and answers 503. */
  private fail(action: string, error: unknown): never {
    const reason =
      typeof error === 'object' && error !== null && 'message' in error
        ? String((error as { message: unknown }).message)
        : 'unknown error';
    const secret = this.settings?.apiSecret;
    const safe = secret ? reason.split(secret).join('[redacted]') : reason;
    this.logger.error(`Image ${action} failed: ${safe}`);
    throw new ServiceUnavailableException(UNAVAILABLE);
  }
}
