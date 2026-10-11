import { randomBytes } from 'node:crypto';
import { DELIVERY_TRANSFORMATION } from './image-profiles.js';

const SEGMENT = /^[A-Za-z0-9_-]+$/;

function assertSegments(path: string, what: string): void {
  if (path === '' || !path.split('/').every((part) => SEGMENT.test(part))) {
    throw new Error(`Invalid image ${what}: ${JSON.stringify(path)}`);
  }
}

/**
 * `users/12/profile-3f9c…`: the folder, the name, and 64 random bits so two
 * uploads never share an id (a new id is also a new URL, so caches refresh).
 */
export function createPublicId(
  folder: string,
  name: string,
  rootPrefix?: string,
): string {
  assertSegments(folder, 'folder');
  if (!SEGMENT.test(name)) {
    throw new Error(`Invalid image name: ${JSON.stringify(name)}`);
  }
  const path = `${folder}/${name}-${randomBytes(8).toString('hex')}`;
  return rootPrefix ? `${rootPrefix}/${path}` : path;
}

/** Inserts the delivery transformation into a Cloudinary-style upload URL. */
export function toDeliveryUrl(uploadUrl: string): string {
  const marker = '/upload/';
  const index = uploadUrl.indexOf(marker);
  if (index === -1) {
    throw new Error('Not an image upload URL');
  }
  const head = uploadUrl.slice(0, index + marker.length);
  return `${head}${DELIVERY_TRANSFORMATION}/${uploadUrl.slice(head.length)}`;
}
