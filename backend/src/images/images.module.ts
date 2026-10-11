import { Logger, Module } from '@nestjs/common';
import { readCloudinaryConfig } from './cloudinary-config.js';
import { CloudinaryImageStorage } from './cloudinary-image-storage.js';
import { ImageFilePipe } from './image-file.pipe.js';
import { ImageStorageService } from './image-storage.service.js';

/**
 * Image storage for any feature: import this module and depend on
 * `ImageStorageService`. Tests replace that provider with `InMemoryImageStorage`.
 */
@Module({
  providers: [
    {
      provide: ImageStorageService,
      useFactory: () => {
        const settings = readCloudinaryConfig(process.env);
        if (!settings) {
          new Logger('ImagesModule').warn(
            'Cloudinary is not configured: image uploads answer 503',
          );
        }
        return new CloudinaryImageStorage(settings);
      },
    },
    ImageFilePipe,
  ],
  exports: [ImageStorageService, ImageFilePipe],
})
export class ImagesModule {}
