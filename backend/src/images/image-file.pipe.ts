import {
  BadRequestException,
  Injectable,
  PayloadTooLargeException,
  type PipeTransform,
} from '@nestjs/common';

export const IMAGE_MAX_BYTES = 5 * 1024 * 1024;

/** What an uploaded file looks like to the pipe (multer's memory-storage file fits). */
export interface UploadedImageFile {
  buffer: Buffer;
}

export type ImageContentType = 'image/jpeg' | 'image/png' | 'image/webp';

export interface ValidatedImage {
  buffer: Buffer;
  /** Found by reading the bytes, whatever the client claimed. */
  contentType: ImageContentType;
}

const PNG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const JPEG = [0xff, 0xd8, 0xff];

const startsWith = (buffer: Buffer, bytes: number[], at = 0) =>
  buffer.length >= at + bytes.length &&
  bytes.every((byte, i) => buffer[at + i] === byte);

function detect(buffer: Buffer): ImageContentType | null {
  if (startsWith(buffer, JPEG)) return 'image/jpeg';
  if (startsWith(buffer, PNG)) return 'image/png';
  // WebP: "RIFF" <size> "WEBP"
  if (
    startsWith(buffer, [0x52, 0x49, 0x46, 0x46]) &&
    startsWith(buffer, [0x57, 0x45, 0x42, 0x50], 8)
  ) {
    return 'image/webp';
  }
  return null;
}

/**
 * Accepts a JPEG, PNG or WebP of at most 5 MB. The type comes from the file's
 * own bytes; the `Content-Type` the client sent (and the file name) are never
 * consulted.
 */
@Injectable()
export class ImageFilePipe implements PipeTransform<
  UploadedImageFile | undefined,
  ValidatedImage
> {
  transform(file: UploadedImageFile | undefined): ValidatedImage {
    if (!file?.buffer?.length) {
      throw new BadRequestException('An image file is required');
    }
    if (file.buffer.length > IMAGE_MAX_BYTES) {
      throw new PayloadTooLargeException('The image must not exceed 5 MB');
    }
    const contentType = detect(file.buffer);
    if (!contentType) {
      throw new BadRequestException(
        'The image must be a JPEG, PNG or WebP file',
      );
    }
    return { buffer: file.buffer, contentType };
  }
}
