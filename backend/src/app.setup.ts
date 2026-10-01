import { ValidationPipe, type INestApplication } from '@nestjs/common';

/** App-wide configuration shared by `main.ts` and the e2e tests, so tests run against the real pipeline. */
export function setupApp(app: INestApplication): void {
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
}
