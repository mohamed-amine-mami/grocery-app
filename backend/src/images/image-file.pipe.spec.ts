import { BadRequestException, PayloadTooLargeException } from '@nestjs/common';
import { IMAGE_MAX_BYTES, ImageFilePipe } from './image-file.pipe.js';

const pipe = new ImageFilePipe();

const jpeg = (size = 64) =>
  Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(size)]);
const png = () =>
  Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    Buffer.alloc(64),
  ]);
const webp = () =>
  Buffer.concat([
    Buffer.from('RIFF'),
    Buffer.from([0x24, 0, 0, 0]),
    Buffer.from('WEBPVP8 '),
    Buffer.alloc(64),
  ]);

describe('ImageFilePipe', () => {
  it.each([
    ['JPEG', jpeg(), 'image/jpeg'],
    ['PNG', png(), 'image/png'],
    ['WebP', webp(), 'image/webp'],
  ])('accepts a %s', (_name, buffer, contentType) => {
    expect(pipe.transform({ buffer })).toEqual({ buffer, contentType });
  });

  it.each([
    ['GIF', Buffer.from('GIF89a' + 'x'.repeat(64))],
    ['SVG', Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"></svg>')],
    ['PDF', Buffer.from('%PDF-1.7 ' + 'x'.repeat(64))],
    ['plain text', Buffer.from('hello, not an image at all')],
    ['an executable', Buffer.from([0x4d, 0x5a, 0x90, 0x00, 0x03, 0, 0, 0])],
    ['a RIFF file that is not WebP', Buffer.from('RIFF\0\0\0\0WAVEfmt ')],
    ['a truncated PNG header', Buffer.from([0x89, 0x50, 0x4e])],
  ])('rejects %s with 400', (_name, buffer) => {
    expect(() => pipe.transform({ buffer })).toThrow(BadRequestException);
  });

  it('judges the bytes, not what the client claimed', () => {
    // A text file sent as image/jpeg named photo.jpg is refused …
    const lie = {
      buffer: Buffer.from('not an image'),
      mimetype: 'image/jpeg',
      originalname: 'photo.jpg',
    };
    expect(() => pipe.transform(lie)).toThrow(BadRequestException);
    // … and a real PNG sent as text/plain named notes.txt is accepted as PNG.
    const truth = {
      buffer: png(),
      mimetype: 'text/plain',
      originalname: 'notes.txt',
    };
    expect(pipe.transform(truth).contentType).toBe('image/png');
  });

  it('requires a file, and a non-empty one', () => {
    expect(() => pipe.transform(undefined)).toThrow(BadRequestException);
    expect(() => pipe.transform({ buffer: Buffer.alloc(0) })).toThrow(
      BadRequestException,
    );
  });

  it('accepts exactly 5 MB and refuses one byte more with 413', () => {
    const atLimit = Buffer.concat([
      Buffer.from([0xff, 0xd8, 0xff]),
      Buffer.alloc(IMAGE_MAX_BYTES - 3),
    ]);
    expect(pipe.transform({ buffer: atLimit }).contentType).toBe('image/jpeg');
    const over = Buffer.concat([atLimit, Buffer.alloc(1)]);
    expect(() => pipe.transform({ buffer: over })).toThrow(
      PayloadTooLargeException,
    );
  });

  it('measures the real buffer, not a size the client declared', () => {
    const over = Buffer.alloc(IMAGE_MAX_BYTES + 1, 0xff);
    expect(() => pipe.transform({ buffer: over, size: 10 } as never)).toThrow(
      PayloadTooLargeException,
    );
  });

  it('keeps the limit at 5 MB', () => {
    expect(IMAGE_MAX_BYTES).toBe(5 * 1024 * 1024);
  });
});
