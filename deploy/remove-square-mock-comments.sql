-- Remove only the eight unchanged comments written by the legacy square seed.
-- Fixed IDs, original content, and the author's fixture identity must all match.
-- Posts, likes, real comments, and edited fixture comments are left untouched.
BEGIN;

SELECT pg_advisory_xact_lock(
  hashtextextended('wanpan:square-experience-seed:v1', 0)
);

WITH legacy_comments(id, send_id, user_id, content, author_openid) AS (
  VALUES
    ('00000000-0000-4000-8000-00000000e401'::uuid,
     '00000000-0000-4000-8000-00000000e201'::uuid,
     '00000000-0000-4000-8000-00000000e102'::uuid,
     '【完攀体验】这种稳稳落脚的快乐太懂了！',
     'fixture:wanpan:square:xiaolin'),
    ('00000000-0000-4000-8000-00000000e402'::uuid,
     '00000000-0000-4000-8000-00000000e202'::uuid,
     '00000000-0000-4000-8000-00000000e104'::uuid,
     '【完攀体验】慢一点真的会更顺，下次一起练。',
     'fixture:wanpan:square:chengzi'),
    ('00000000-0000-4000-8000-00000000e403'::uuid,
     '00000000-0000-4000-8000-00000000e203'::uuid,
     '00000000-0000-4000-8000-00000000e105'::uuid,
     '【完攀体验】快乐完攀，收工回家！',
     'fixture:wanpan:square:xiaoyu'),
    ('00000000-0000-4000-8000-00000000e404'::uuid,
     '00000000-0000-4000-8000-00000000e204'::uuid,
     '00000000-0000-4000-8000-00000000e101'::uuid,
     '【完攀体验】找到重心的那一刻特别爽。',
     'fixture:wanpan:square:ayan'),
    ('00000000-0000-4000-8000-00000000e405'::uuid,
     '00000000-0000-4000-8000-00000000e205'::uuid,
     '00000000-0000-4000-8000-00000000e103'::uuid,
     '【完攀体验】岩友的一句提醒经常就是通关密码。',
     'fixture:wanpan:square:maomao'),
    ('00000000-0000-4000-8000-00000000e406'::uuid,
     '00000000-0000-4000-8000-00000000e206'::uuid,
     '00000000-0000-4000-8000-00000000e105'::uuid,
     '【完攀体验】再试一把的你太棒啦！',
     'fixture:wanpan:square:xiaoyu'),
    ('00000000-0000-4000-8000-00000000e407'::uuid,
     '00000000-0000-4000-8000-00000000e208'::uuid,
     '00000000-0000-4000-8000-00000000e102'::uuid,
     '【完攀体验】稳稳升级，一起加油。',
     'fixture:wanpan:square:xiaolin'),
    ('00000000-0000-4000-8000-00000000e408'::uuid,
     '00000000-0000-4000-8000-00000000e210'::uuid,
     '00000000-0000-4000-8000-00000000e104'::uuid,
     '【完攀体验】遇到会鼓励人的岩友真好。',
     'fixture:wanpan:square:chengzi')
), deleted AS (
  DELETE FROM comments AS c
  USING legacy_comments AS legacy, users AS author
  WHERE c.id = legacy.id
    AND c.send_id = legacy.send_id
    AND c.user_id = legacy.user_id
    AND c.content = legacy.content
    AND author.id = c.user_id
    AND author.openid = legacy.author_openid
  RETURNING c.id
)
SELECT count(*) AS deleted_mock_comments FROM deleted;

COMMIT;
