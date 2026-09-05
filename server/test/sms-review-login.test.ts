import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  CheckSmsVerifyCodeRequest,
  SendSmsVerifyCodeRequest
} from '@alicloud/dypnsapi20170525/dist/models/model.js';

const fakeReviewPhone = '19000000009';
const fakeReviewCode = '246810';
const fakeOrdinaryPhone = '19000000008';
const fakeSmsCode = '135790';

const mocks = vi.hoisted(() => {
  const sendSmsVerifyCode = vi.fn();
  const checkSmsVerifyCode = vi.fn();
  return {
    config: {
      APP_REVIEW_LOGIN_PHONE: '19000000009',
      APP_REVIEW_LOGIN_CODE: '246810',
      ALIYUN_ACCESS_KEY_ID: 'test-access-key-id',
      ALIYUN_ACCESS_KEY_SECRET: 'test-access-key-secret',
      ALIYUN_SMS_SIGN_NAME: 'test-sign-name',
      ALIYUN_SMS_TEMPLATE_CODE: 'test-template-code',
      ALIYUN_SMS_TEMPLATE_MIN: 5
    },
    sendSmsVerifyCode,
    checkSmsVerifyCode,
    clientConstructor: vi.fn(function () {
      return { sendSmsVerifyCode, checkSmsVerifyCode };
    })
  };
});

vi.mock('../src/config.js', () => ({ config: mocks.config }));
vi.mock('@alicloud/dypnsapi20170525/dist/client.js', () => ({
  default: mocks.clientConstructor
}));

import {
  SmsProviderError,
  isReviewLoginPhone,
  sendSmsCode,
  verifySmsCode
} from '../src/services/sms_provider.js';

const aliyunConfigKeys = [
  'ALIYUN_ACCESS_KEY_ID',
  'ALIYUN_ACCESS_KEY_SECRET',
  'ALIYUN_SMS_SIGN_NAME',
  'ALIYUN_SMS_TEMPLATE_CODE'
] as const;

async function expectSmsError(promise: Promise<unknown>, statusCode: number) {
  await expect(promise).rejects.toMatchObject({
    constructor: SmsProviderError,
    statusCode
  });
}

describe('App Review SMS login adapter', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    Object.assign(mocks.config, {
      APP_REVIEW_LOGIN_PHONE: fakeReviewPhone,
      APP_REVIEW_LOGIN_CODE: fakeReviewCode,
      ALIYUN_ACCESS_KEY_ID: 'test-access-key-id',
      ALIYUN_ACCESS_KEY_SECRET: 'test-access-key-secret',
      ALIYUN_SMS_SIGN_NAME: 'test-sign-name',
      ALIYUN_SMS_TEMPLATE_CODE: 'test-template-code',
      ALIYUN_SMS_TEMPLATE_MIN: 5
    });
    mocks.sendSmsVerifyCode.mockReset().mockResolvedValue({
      body: { code: 'OK', success: true }
    });
    mocks.checkSmsVerifyCode.mockReset().mockResolvedValue({
      body: { code: 'OK', success: true, model: { verifyResult: 'PASS' } }
    });
  });

  it('accepts the configured fixed code repeatedly without sending or using Aliyun', async () => {
    for (const key of aliyunConfigKeys) mocks.config[key] = '';

    expect(isReviewLoginPhone(fakeReviewPhone)).toBe(true);
    await expect(verifySmsCode(fakeReviewPhone, fakeReviewCode)).resolves.toEqual({
      isReview: true
    });
    await expect(verifySmsCode(fakeReviewPhone, fakeReviewCode)).resolves.toEqual({
      isReview: true
    });
    expect(mocks.clientConstructor).not.toHaveBeenCalled();
    expect(mocks.sendSmsVerifyCode).not.toHaveBeenCalled();
    expect(mocks.checkSmsVerifyCode).not.toHaveBeenCalled();
  });

  it.each([fakeReviewPhone, fakeOrdinaryPhone])(
    'sends a real provider request for phone %s',
    async (phone) => {
      await expect(sendSmsCode(phone)).resolves.toBeUndefined();

      expect(mocks.clientConstructor).toHaveBeenCalledExactlyOnceWith(
        expect.objectContaining({
          accessKeyId: mocks.config.ALIYUN_ACCESS_KEY_ID,
          accessKeySecret: mocks.config.ALIYUN_ACCESS_KEY_SECRET,
          endpoint: 'dypnsapi.aliyuncs.com',
          connectTimeout: 5_000,
          readTimeout: 10_000
        })
      );
      expect(mocks.sendSmsVerifyCode).toHaveBeenCalledExactlyOnceWith(
        expect.any(SendSmsVerifyCodeRequest)
      );
      expect(mocks.sendSmsVerifyCode.mock.calls[0][0]).toMatchObject({
        phoneNumber: phone,
        countryCode: '86',
        signName: mocks.config.ALIYUN_SMS_SIGN_NAME,
        templateCode: mocks.config.ALIYUN_SMS_TEMPLATE_CODE,
        templateParam: JSON.stringify({ code: '##code##', min: '5' }),
        codeLength: 6,
        codeType: 1,
        validTime: 300,
        interval: 60,
        duplicatePolicy: 1,
        returnVerifyCode: false
      });
    }
  );

  it.each([fakeReviewPhone, fakeOrdinaryPhone])(
    'accepts a provider-verified SMS code for phone %s',
    async (phone) => {
      await expect(verifySmsCode(phone, fakeSmsCode)).resolves.toEqual({
        isReview: false
      });

      expect(mocks.checkSmsVerifyCode).toHaveBeenCalledExactlyOnceWith(
        expect.any(CheckSmsVerifyCodeRequest)
      );
      expect(mocks.checkSmsVerifyCode.mock.calls[0][0]).toMatchObject({
        phoneNumber: phone,
        countryCode: '86',
        verifyCode: fakeSmsCode
      });
    }
  );

  it('does not let an ordinary phone bypass verification with the review code', async () => {
    mocks.checkSmsVerifyCode.mockResolvedValue({
      body: { code: 'OK', success: true, model: { verifyResult: 'FAIL' } }
    });

    expect(isReviewLoginPhone(fakeOrdinaryPhone)).toBe(false);
    await expectSmsError(verifySmsCode(fakeOrdinaryPhone, fakeReviewCode), 401);
    expect(mocks.checkSmsVerifyCode).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({
        phoneNumber: fakeOrdinaryPhone,
        verifyCode: fakeReviewCode
      })
    );
  });

  it.each(['APP_REVIEW_LOGIN_PHONE', 'APP_REVIEW_LOGIN_CODE'] as const)(
    'disables fixed-code login when %s is missing',
    async (key) => {
      mocks.config[key] = '';
      mocks.checkSmsVerifyCode.mockResolvedValue({
        body: { code: 'OK', success: true, model: { verifyResult: 'FAIL' } }
      });

      expect(isReviewLoginPhone(fakeReviewPhone)).toBe(false);
      await expectSmsError(verifySmsCode(fakeReviewPhone, fakeReviewCode), 401);
      expect(mocks.checkSmsVerifyCode).toHaveBeenCalledExactlyOnceWith(
        expect.objectContaining({
          phoneNumber: fakeReviewPhone,
          verifyCode: fakeReviewCode
        })
      );
    }
  );

  it.each(aliyunConfigKeys)(
    'requires %s to send or verify a regular SMS code, including for the review phone',
    async (key) => {
      mocks.config[key] = '';

      for (const phone of [fakeReviewPhone, fakeOrdinaryPhone]) {
        await expectSmsError(sendSmsCode(phone), 503);
        await expectSmsError(verifySmsCode(phone, fakeSmsCode), 503);
      }
      expect(mocks.clientConstructor).not.toHaveBeenCalled();
    }
  );

  it.each([
    undefined,
    { code: 'LIMIT_CONTROL', success: false },
    { code: 'OK', success: false }
  ])('reports a rejected review-phone send as unavailable: %j', async (body) => {
    mocks.sendSmsVerifyCode.mockResolvedValue({ body });

    await expectSmsError(sendSmsCode(fakeReviewPhone), 503);
    expect(mocks.sendSmsVerifyCode).toHaveBeenCalledOnce();
  });

  it('reports a provider send exception instead of pretending the review SMS was sent', async () => {
    mocks.sendSmsVerifyCode.mockRejectedValue(new Error('provider timeout'));

    await expectSmsError(sendSmsCode(fakeReviewPhone), 503);
    expect(mocks.sendSmsVerifyCode).toHaveBeenCalledOnce();
  });

  it.each(['FAIL', 'UNKNOWN', undefined])(
    'rejects a review-phone SMS code when the provider verification result is %s',
    async (verifyResult) => {
      mocks.checkSmsVerifyCode.mockResolvedValue({
        body: { code: 'OK', success: true, model: { verifyResult } }
      });

      await expectSmsError(verifySmsCode(fakeReviewPhone, fakeSmsCode), 401);
      expect(mocks.checkSmsVerifyCode).toHaveBeenCalledOnce();
    }
  );

  it.each([
    undefined,
    { code: 'SERVER_ERROR', success: false },
    { code: 'OK', success: false }
  ])('reports a provider verification failure as unavailable: %j', async (body) => {
    mocks.checkSmsVerifyCode.mockResolvedValue({ body });

    await expectSmsError(verifySmsCode(fakeReviewPhone, fakeSmsCode), 503);
    expect(mocks.checkSmsVerifyCode).toHaveBeenCalledOnce();
  });

  it('reports a provider verification exception as unavailable', async () => {
    mocks.checkSmsVerifyCode.mockRejectedValue(new Error('provider timeout'));

    await expectSmsError(verifySmsCode(fakeReviewPhone, fakeSmsCode), 503);
    expect(mocks.checkSmsVerifyCode).toHaveBeenCalledOnce();
  });
});
