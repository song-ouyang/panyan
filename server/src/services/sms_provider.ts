import { timingSafeEqual } from 'node:crypto';
import * as DypnsapiClientModule from '@alicloud/dypnsapi20170525/dist/client.js';
import {
  CheckSmsVerifyCodeRequest,
  SendSmsVerifyCodeRequest
} from '@alicloud/dypnsapi20170525/dist/models/model.js';
import * as OpenApiClient from '@alicloud/openapi-client';
import { config } from '../config.js';

export class SmsProviderError extends Error {
  constructor(message: string, readonly statusCode = 503) {
    super(message);
  }
}

type DypnsapiClientConstructor = new (config: OpenApiClient.Config) => {
  sendSmsVerifyCode: (request: SendSmsVerifyCodeRequest) => Promise<{
    body?: { code?: string; success?: boolean };
  }>;
  checkSmsVerifyCode: (request: CheckSmsVerifyCodeRequest) => Promise<{
    body?: {
      code?: string;
      success?: boolean;
      model?: { verifyResult?: string };
    };
  }>;
};

const DypnsapiClient = (
  (DypnsapiClientModule.default as { default?: DypnsapiClientConstructor })?.default ??
  DypnsapiClientModule.default
) as unknown as DypnsapiClientConstructor;

function isSameSecret(value: string, expected: string): boolean {
  const actualBytes = Buffer.from(value, 'utf8');
  const expectedBytes = Buffer.from(expected, 'utf8');
  return actualBytes.length === expectedBytes.length && timingSafeEqual(actualBytes, expectedBytes);
}

export function isReviewLoginPhone(phone: string): boolean {
  return Boolean(
    config.APP_REVIEW_LOGIN_PHONE &&
      config.APP_REVIEW_LOGIN_CODE &&
      isSameSecret(phone, config.APP_REVIEW_LOGIN_PHONE)
  );
}

export function isSmsSendAccepted(body: {
  code?: string;
  success?: boolean;
} | undefined): boolean {
  return body?.code === 'OK' && body.success === true;
}

export function isSmsVerificationPassed(body: {
  code?: string;
  success?: boolean;
  model?: { verifyResult?: string };
} | undefined): boolean {
  return isSmsSendAccepted(body) && body?.model?.verifyResult === 'PASS';
}

function hasAliyunConfiguration(): boolean {
  return Boolean(
    config.ALIYUN_ACCESS_KEY_ID &&
      config.ALIYUN_ACCESS_KEY_SECRET &&
      config.ALIYUN_SMS_SIGN_NAME &&
      config.ALIYUN_SMS_TEMPLATE_CODE
  );
}

function createClient() {
  const clientConfig = new OpenApiClient.Config({
    accessKeyId: config.ALIYUN_ACCESS_KEY_ID,
    accessKeySecret: config.ALIYUN_ACCESS_KEY_SECRET,
    connectTimeout: 5_000,
    readTimeout: 10_000
  });
  clientConfig.endpoint = 'dypnsapi.aliyuncs.com';
  return new DypnsapiClient(clientConfig);
}

export async function sendSmsCode(phone: string): Promise<void> {
  // App Review must be able to enter the app even if the SMS provider has an outage.
  if (isReviewLoginPhone(phone)) return;
  if (!hasAliyunConfiguration()) {
    throw new SmsProviderError('短信服务暂不可用，请稍后重试。');
  }

  try {
    const request = new SendSmsVerifyCodeRequest({
      phoneNumber: phone,
      countryCode: '86',
      signName: config.ALIYUN_SMS_SIGN_NAME,
      templateCode: config.ALIYUN_SMS_TEMPLATE_CODE,
      templateParam: JSON.stringify({
        code: '##code##',
        min: String(config.ALIYUN_SMS_TEMPLATE_MIN)
      }),
      codeLength: 6,
      codeType: 1,
      validTime: config.ALIYUN_SMS_TEMPLATE_MIN * 60,
      interval: 60,
      duplicatePolicy: 1,
      returnVerifyCode: false
    });
    const response = await createClient().sendSmsVerifyCode(request);
    if (!isSmsSendAccepted(response.body)) {
      throw new SmsProviderError('验证码发送失败，请稍后重试。');
    }
  } catch (error) {
    if (error instanceof SmsProviderError) throw error;
    throw new SmsProviderError('验证码发送失败，请稍后重试。');
  }
}

export async function verifySmsCode(phone: string, code: string): Promise<{ isReview: boolean }> {
  if (isReviewLoginPhone(phone)) {
    if (!isSameSecret(code, config.APP_REVIEW_LOGIN_CODE)) {
      throw new SmsProviderError('验证码错误或已过期。', 401);
    }
    return { isReview: true };
  }
  if (!hasAliyunConfiguration()) {
    throw new SmsProviderError('短信服务暂不可用，请稍后重试。');
  }

  try {
    const response = await createClient().checkSmsVerifyCode(
      new CheckSmsVerifyCodeRequest({
        phoneNumber: phone,
        countryCode: '86',
        verifyCode: code
      })
    );
    if (response.body?.code !== 'OK' || response.body?.success !== true) {
      throw new SmsProviderError('验证码校验失败，请稍后重试。');
    }
    if (!isSmsVerificationPassed(response.body)) {
      throw new SmsProviderError('验证码错误或已过期。', 401);
    }
    return { isReview: false };
  } catch (error) {
    if (error instanceof SmsProviderError) throw error;
    throw new SmsProviderError('验证码校验失败，请稍后重试。');
  }
}
