import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { setupApp } from '../src/app.setup.js';

describe('AppController (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleFixture = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleFixture.createNestApplication();
    setupApp(app);
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /health is public', async () => {
    const response = await request(app.getHttpServer())
      .get('/health')
      .expect(200);
    expect(response.body).toMatchObject({ status: 'ok' });
  });

  it.each([
    ['GET', '/users'],
    ['GET', '/users/1'],
    ['PATCH', '/users/1'],
    ['DELETE', '/users/1'],
    ['GET', '/stores'],
    ['GET', '/stores/1'],
    ['POST', '/stores'],
    ['PATCH', '/stores/1'],
    ['DELETE', '/stores/1'],
  ] as const)(
    'the old generic CRUD route %s %s no longer exists',
    async (method, path) => {
      const http = app.getHttpServer();
      const call = {
        GET: request(http).get(path),
        POST: request(http).post(path),
        PATCH: request(http).patch(path),
        DELETE: request(http).delete(path),
      }[method];
      await call.expect(404);
    },
  );
});
