import { describe, expect, it } from 'vitest';
import {
  isSmsSendAccepted,
  isSmsVerificationPassed
} from '../src/services/sms_provider.js';

describe('Aliyun SMS result validation', () => {
  it('accepts a send only when the provider reports OK and success', () => {
    expect(isSmsSendAccepted({ code: 'OK', success: true })).toBe(true);
    expect(isSmsSendAccepted({ code: 'OK', success: false })).toBe(false);
    expect(isSmsSendAccepted({ code: 'LIMIT_CONTROL', success: true })).toBe(false);
    expect(isSmsSendAccepted(undefined)).toBe(false);
  });

  it('accepts a verification only when VerifyResult is PASS', () => {
    expect(isSmsVerificationPassed({
      code: 'OK',
      success: true,
      model: { verifyResult: 'PASS' }
    })).toBe(true);
    expect(isSmsVerificationPassed({
      code: 'OK',
      success: true,
      model: { verifyResult: 'UNKNOWN' }
    })).toBe(false);
    expect(isSmsVerificationPassed({ code: 'OK', success: true })).toBe(false);
    expect(isSmsVerificationPassed({
      code: 'SERVER_ERROR',
      success: false,
      model: { verifyResult: 'PASS' }
    })).toBe(false);
  });
});
