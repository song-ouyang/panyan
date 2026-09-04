import { describe, expect, it, vi } from 'vitest';

const fakeReviewPhone = '19000000009';
const fakeReviewCode = '246810';

const mocks = vi.hoisted(() => ({
  config: {
    APP_REVIEW_LOGIN_PHONE: '19000000009',
    APP_REVIEW_LOGIN_CODE: '246810',
    ALIYUN_ACCESS_KEY_ID: '',
    ALIYUN_ACCESS_KEY_SECRET: '',
    ALIYUN_SMS_SIGN_NAME: '',
    ALIYUN_SMS_TEMPLATE_CODE: '',
    ALIYUN_SMS_TEMPLATE_MIN: 5
  }
}));

vi.mock('../src/config.js', () => ({ config: mocks.config }));

import {
  SmsProviderError,
  isReviewLoginPhone,
  sendSmsCode,
  verifySmsCode
} from '../src/services/sms_provider.js';

describe('App Review SMS login adapter', () => {
  it('accepts the configured review account without depending on Aliyun', async () => {
    expect(isReviewLoginPhone(fakeReviewPhone)).toBe(true);
    await expect(sendSmsCode(fakeReviewPhone)).resolves.toBeUndefined();
    await expect(verifySmsCode(fakeReviewPhone, fakeReviewCode)).resolves.toEqual({
      isReview: true
    });
  });

  it('maps a wrong review code to an authentication error', async () => {
    const error = await verifySmsCode(fakeReviewPhone, '000000').catch(
      (caught: unknown) => caught
    );

    expect(error).toBeInstanceOf(SmsProviderError);
    expect(error).toMatchObject({ statusCode: 401 });
  });

  it('maps an unconfigured ordinary SMS path to service unavailable', async () => {
    const sendError = await sendSmsCode('13800138000').catch(
      (caught: unknown) => caught
    );
    const loginError = await verifySmsCode('13800138000', '123456').catch(
      (caught: unknown) => caught
    );

    expect(sendError).toBeInstanceOf(SmsProviderError);
    expect(sendError).toMatchObject({ statusCode: 503 });
    expect(loginError).toBeInstanceOf(SmsProviderError);
    expect(loginError).toMatchObject({ statusCode: 503 });
  });
});
