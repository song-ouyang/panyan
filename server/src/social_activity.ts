import { z } from 'zod';
import { pagination } from './schemas.js';

export type PersonalActivity = 'comments' | 'favorites' | 'likes';
const cursorPayload = z.object({
  version: z.literal(1),
  kind: z.enum(['comments', 'favorites', 'likes']),
  at: z.string().datetime(),
  id: z.string().uuid()
});

export function parseActivityQuery(kind: PersonalActivity, input: unknown) {
  return pagination.extend({
    cursor: pagination.shape.cursor.transform((cursor, context) => {
      if (cursor === undefined) return undefined;
      try {
        const parsed = cursorPayload.safeParse(JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')));
        if (parsed.success && parsed.data.kind === kind) return parsed.data;
      } catch {
        // Return a validation error without leaking decoder details.
      }
      context.addIssue({ code: z.ZodIssueCode.custom, message: '分页位置已失效，请刷新后重试' });
      return z.NEVER;
    })
  }).parse(input);
}

export function encodeActivityCursor(kind: PersonalActivity, row: { _activity_id: string; _cursor_at: string }) {
  return Buffer.from(JSON.stringify({ version: 1, kind, at: row._cursor_at, id: row._activity_id }), 'utf8').toString('base64url');
}

// These aliases and parameter positions are internal constants. Match the post
// detail ACL before pagination: an old interaction never grants access itself.
export const activityPostVisibility = `
  NOT EXISTS (
    SELECT 1 FROM friendships blocked
    WHERE blocked.status='blocked' AND (
      (blocked.requester_id=$1 AND blocked.addressee_id=s.user_id) OR
      (blocked.addressee_id=$1 AND blocked.requester_id=s.user_id)
    )
  ) AND (
    s.user_id=$1 OR (
      s.moderation_status='approved' AND (
        s.visibility='public' OR (
          s.visibility='friends' AND EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status='accepted' AND (
              (f.requester_id=$1 AND f.addressee_id=s.user_id) OR
              (f.addressee_id=$1 AND f.requester_id=s.user_id)
            )
          )
        )
      )
    )
  )`;

export const activityPostFields = `
  s.id,s.attempts,s.video_url,s.image_urls,s.caption,s.visibility,s.moderation_status,s.sent_at,
  u.id user_id,u.nickname,u.avatar_url,r.id route_id,r.name route_name,r.grade,r.color,
  g.id gym_id,g.name gym_name,
  (SELECT count(*)::int FROM post_likes l WHERE l.send_id=s.id) like_count,
  (SELECT count(*)::int FROM comments c WHERE c.send_id=s.id
    AND (c.moderation_status='approved' OR (c.moderation_status='pending' AND c.user_id=$1))
    AND NOT EXISTS (
      SELECT 1 FROM friendships blocked_commenter WHERE blocked_commenter.status='blocked' AND (
        (blocked_commenter.requester_id=$1 AND blocked_commenter.addressee_id=c.user_id) OR
        (blocked_commenter.addressee_id=$1 AND blocked_commenter.requester_id=c.user_id)
      )
    )) comment_count,
  EXISTS(SELECT 1 FROM post_likes own_like WHERE own_like.send_id=s.id AND own_like.user_id=$1) liked,
  EXISTS(SELECT 1 FROM post_favorites own_favorite WHERE own_favorite.send_id=s.id AND own_favorite.user_id=$1) favorited`;
