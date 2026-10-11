export interface CloudinaryConfig {
  readonly cloudName: string;
  readonly apiKey: string;
  readonly apiSecret: string;
  /** Optional root folder (e.g. `grocergo-dev`) keeping environments apart. */
  readonly folderPrefix?: string;
}

const PREFIX = /^[A-Za-z0-9_-]+(\/[A-Za-z0-9_-]+)*$/;

/**
 * Reads the Cloudinary settings. Returns `null` — never throws — when any
 * required one is missing or the prefix is malformed, so the application
 * still starts and uploads answer 503.
 */
export function readCloudinaryConfig(
  env: Record<string, string | undefined>,
): CloudinaryConfig | null {
  const cloudName = env['CLOUDINARY_CLOUD_NAME']?.trim();
  const apiKey = env['CLOUDINARY_API_KEY']?.trim();
  const apiSecret = env['CLOUDINARY_API_SECRET']?.trim();
  if (!cloudName || !apiKey || !apiSecret) {
    return null;
  }
  const rawPrefix = env['CLOUDINARY_FOLDER_PREFIX']
    ?.trim()
    .replace(/^\/+|\/+$/g, '');
  if (rawPrefix && !PREFIX.test(rawPrefix)) {
    return null;
  }
  return { cloudName, apiKey, apiSecret, folderPrefix: rawPrefix || undefined };
}
