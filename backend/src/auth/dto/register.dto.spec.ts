import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { LoginDto } from './login.dto.js';
import { RegisterDto } from './register.dto.js';

const validRegistration = {
  name: 'Jane Doe',
  email: 'jane@example.com',
  password: 'changeme123',
  phoneNumber: '+21612345678',
  role: 'OWNER',
};

async function errorsFor(payload: Record<string, unknown>) {
  const dto = plainToInstance(RegisterDto, {
    ...validRegistration,
    ...payload,
  });
  const errors = await validate(dto, {
    whitelist: true,
    forbidNonWhitelisted: true,
  });
  return { dto, properties: errors.map((error) => error.property) };
}

describe('RegisterDto photo', () => {
  it('is not client-supplied: it is set by the photo upload only', async () => {
    expect(
      (await errorsFor({ photo: 'https://cdn.example.com/me.jpg' })).properties,
    ).toEqual(['photo']);
    expect(
      (await errorsFor({ photoPublicId: 'users/1/me' })).properties,
    ).toEqual(['photoPublicId']);
  });
});

describe('RegisterDto phoneNumber', () => {
  it.each(['+21612345678', '98999240', '+216 12 345 678', '98-999-240'])(
    'accepts %s',
    async (phoneNumber) => {
      expect((await errorsFor({ phoneNumber })).properties).toEqual([]);
    },
  );

  it('normalizes separators so the stored number is digits only', async () => {
    const { dto } = await errorsFor({ phoneNumber: '+216 12 345 678' });
    expect(dto.phoneNumber).toBe('+21612345678');
  });

  it('is required', async () => {
    const payload: Record<string, unknown> = { ...validRegistration };
    delete payload['phoneNumber'];
    const errors = await validate(plainToInstance(RegisterDto, payload));
    expect(errors.map((error) => error.property)).toContain('phoneNumber');
  });

  it.each(['', '   ', 'abc12345', '123', '+1234567890123456', '12345678x'])(
    'rejects %j',
    async (phoneNumber) => {
      expect((await errorsFor({ phoneNumber })).properties).toContain(
        'phoneNumber',
      );
    },
  );

  it('validates the optional whatsappNumber the same way', async () => {
    expect((await errorsFor({ whatsappNumber: 'nope' })).properties).toContain(
      'whatsappNumber',
    );
    expect(
      (await errorsFor({ whatsappNumber: '+21699999999' })).properties,
    ).toEqual([]);
  });
});

describe('LoginDto', () => {
  it('normalizes the phone number like registration does', () => {
    const dto = plainToInstance(LoginDto, {
      phoneNumber: '98 999 240',
      password: 'x',
    });
    expect(dto.phoneNumber).toBe('98999240');
  });
});
