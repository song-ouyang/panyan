import { z } from 'zod';

export const idParams = z.object({ id: z.string().uuid() });
export const pagination = z.object({ cursor: z.string().datetime().optional(), limit: z.coerce.number().int().min(1).max(50).default(20) });
export const profileBody = z.object({ nickname: z.string().trim().min(1).max(32), avatarUrl: z.string().url().nullable().optional(), bio: z.string().max(120).nullable().optional() });
export const sendBody = z.object({ routeId: z.string().uuid(), attempts: z.number().int().positive().max(999).default(1), videoUrl: z.string().url().nullable().optional(), caption: z.string().max(300).nullable().optional(), visibility: z.enum(['public', 'friends', 'private']).default('public') });
export const meetupBody = z.object({ gymId: z.string().uuid(), title: z.string().min(2).max(80), startsAt: z.string().datetime(), maxPeople: z.number().int().min(2).max(50).default(4), note: z.string().max(300).nullable().optional() });
export const commentBody = z.object({ content: z.string().trim().min(1).max(300) });

