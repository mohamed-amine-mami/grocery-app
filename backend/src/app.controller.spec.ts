import { AppController } from './app.controller.js';

describe('AppController', () => {
  it('reports health', () => {
    const result = new AppController().health();
    expect(result.status).toBe('ok');
    expect(Number.isNaN(Date.parse(result.timestamp))).toBe(false);
  });
});
