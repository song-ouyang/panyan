import { z } from 'zod';
import { config as loadEnv } from 'dotenv';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
loadEnv({ path: resolve(here, '../.env') });

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  HOST: z.string().default('0.0.0.0'),
  DATABASE_URL: z.string().default(''),
  PGHOST: z.string().default(''),
  PGPORT: z.coerce.number().int().positive().default(5432),
  PGDATABASE: z.string().default(''),
  PGUSER: z.string().default(''),
  PGPASSWORD: z.string().default(''),
  JWT_SECRET: z.string().min(16),
  WECHAT_APP_ID: z.string().default(''),
  WECHAT_APP_SECRET: z.string().default(''),
  WECHAT_MOBILE_APP_ID: z.string().default(''),
  WECHAT_MOBILE_APP_SECRET: z.string().default(''),
  APPLE_CLIENT_ID: z.string().default(''),
  APPLE_TEAM_ID: z.string().default(''),
  APP_REVIEW_LOGIN_PHONE: z.string().trim().refine(
    (value) => value === '' || /^1\d{10}$/.test(value),
    'APP_REVIEW_LOGIN_PHONE 必须是中国大陆 11 位手机号'
  ).default(''),
  APP_REVIEW_LOGIN_CODE: z.string().trim().refine(
    (value) => value === '' || /^\d{6}$/.test(value),
    'APP_REVIEW_LOGIN_CODE 必须是 6 位数字'
  ).default(''),
  ALIYUN_ACCESS_KEY_ID: z.string().default(''),
  ALIYUN_ACCESS_KEY_SECRET: z.string().default(''),
  ALIYUN_SMS_SIGN_NAME: z.string().default(''),
  ALIYUN_SMS_TEMPLATE_CODE: z.string().default(''),
  ALIYUN_SMS_TEMPLATE_MIN: z.coerce.number().int().min(1).max(30).default(5),
  UPLOAD_MODE: z.enum(['local', 'oss']).default('local'),
  OSS_REGION: z.string().default('oss-cn-shenzhen'),
  OSS_BUCKET: z.string().default(''),
  OSS_ACCESS_KEY_ID: z.string().default(''),
  OSS_ACCESS_KEY_SECRET: z.string().default(''),
  OSS_PUBLIC_BASE_URL: z.string().default(''),
  PUBLIC_BASE_URL: z.string().url().default('http://localhost:3000'),
  UPLOAD_DIR: z.string().default('./uploads'),
  MODERATION_MODE: z.enum(['off', 'manual']).default('off'),
  ALLOW_PRODUCTION_GYM_IMPORT: z.enum(['true', 'false'])
    .default('false')
    .transform((value) => value === 'true'),
  ALLOW_PRODUCTION_SQUARE_SEED: z.enum(['true', 'false'])
    .default('false')
    .transform((value) => value === 'true')
}).superRefine((value, context) => {
  const hasDatabaseUrl = value.DATABASE_URL.length > 0;
  const hasPostgresFields = Boolean(value.PGHOST && value.PGDATABASE && value.PGUSER && value.PGPASSWORD);
  if (!hasDatabaseUrl && !hasPostgresFields) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['DATABASE_URL'],
      message: '请设置 DATABASE_URL，或完整设置 PGHOST/PGDATABASE/PGUSER/PGPASSWORD'
    });
  }
  if (value.UPLOAD_MODE === 'oss') {
    const required = [
      ['OSS_BUCKET', value.OSS_BUCKET],
      ['OSS_ACCESS_KEY_ID', value.OSS_ACCESS_KEY_ID],
      ['OSS_ACCESS_KEY_SECRET', value.OSS_ACCESS_KEY_SECRET],
      ['OSS_PUBLIC_BASE_URL', value.OSS_PUBLIC_BASE_URL]
    ] as const;
    for (const [key, setting] of required) {
      if (!setting) {
        context.addIssue({ code: z.ZodIssueCode.custom, path: [key], message: `UPLOAD_MODE=oss 时必须设置 ${key}` });
      }
    }
    if (value.OSS_PUBLIC_BASE_URL && !value.OSS_PUBLIC_BASE_URL.startsWith('https://')) {
      context.addIssue({ code: z.ZodIssueCode.custom, path: ['OSS_PUBLIC_BASE_URL'], message: 'OSS_PUBLIC_BASE_URL 必须使用 HTTPS' });
    }
  }
  if (Boolean(value.WECHAT_MOBILE_APP_ID) !== Boolean(value.WECHAT_MOBILE_APP_SECRET)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['WECHAT_MOBILE_APP_ID'],
      message: 'WECHAT_MOBILE_APP_ID 与 WECHAT_MOBILE_APP_SECRET 必须同时设置或同时留空'
    });
  }
  const smsSettings = [
    value.ALIYUN_ACCESS_KEY_ID,
    value.ALIYUN_ACCESS_KEY_SECRET,
    value.ALIYUN_SMS_SIGN_NAME,
    value.ALIYUN_SMS_TEMPLATE_CODE
  ];
  if (smsSettings.some(Boolean) && !smsSettings.every(Boolean)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['ALIYUN_ACCESS_KEY_ID'],
      message: '阿里云短信配置必须完整设置或全部留空'
    });
  }
  if (Boolean(value.APP_REVIEW_LOGIN_PHONE) !== Boolean(value.APP_REVIEW_LOGIN_CODE)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['APP_REVIEW_LOGIN_PHONE'],
      message: 'APP_REVIEW_LOGIN_PHONE 与 APP_REVIEW_LOGIN_CODE 必须同时设置或同时留空'
    });
  }
});

export const config = schema.parse(process.env);
