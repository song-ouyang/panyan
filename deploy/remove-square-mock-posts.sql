-- Remove only unchanged posts from the legacy square experience seed.
-- Existing foreign keys cascade their fixture likes/comments; users stay intact.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '15s';

SELECT pg_advisory_xact_lock(
  hashtextextended('wanpan:square-experience-seed:v1', 0)
);

-- Keep identities and interactions stable between the safety check and deletion.
LOCK TABLE users IN SHARE MODE;
LOCK TABLE sends, post_likes, comments IN SHARE ROW EXCLUSIVE MODE;

CREATE TEMP TABLE square_cleanup_fixture_authors ON COMMIT DROP AS
SELECT * FROM (VALUES
  ('00000000-0000-4000-8000-00000000e101'::uuid, 'fixture:wanpan:square:ayan'),
  ('00000000-0000-4000-8000-00000000e102'::uuid, 'fixture:wanpan:square:xiaolin'),
  ('00000000-0000-4000-8000-00000000e103'::uuid, 'fixture:wanpan:square:maomao'),
  ('00000000-0000-4000-8000-00000000e104'::uuid, 'fixture:wanpan:square:chengzi'),
  ('00000000-0000-4000-8000-00000000e105'::uuid, 'fixture:wanpan:square:xiaoyu')
) AS fixture(id, openid);

CREATE TEMP TABLE square_cleanup_posts ON COMMIT DROP AS
SELECT s.id
FROM sends AS s
JOIN (VALUES
  ('00000000-0000-4000-8000-00000000e201'::uuid,
   '00000000-0000-4000-8000-00000000e101'::uuid,
   '【完攀体验】第一次把害怕的落脚稳稳踩住，小小进步也值得记下来。'),
  ('00000000-0000-4000-8000-00000000e202'::uuid,
   '00000000-0000-4000-8000-00000000e102'::uuid,
   '【完攀体验】今天只专心练脚法，放慢一点以后反而爬得更顺了。'),
  ('00000000-0000-4000-8000-00000000e203'::uuid,
   '00000000-0000-4000-8000-00000000e103'::uuid,
   '【完攀体验】下班后来爬半小时，手臂酸酸的，心情却满格了。'),
  ('00000000-0000-4000-8000-00000000e204'::uuid,
   '00000000-0000-4000-8000-00000000e104'::uuid,
   '【完攀体验】练了好几次重心切换，终于找到不用硬拉的感觉。'),
  ('00000000-0000-4000-8000-00000000e205'::uuid,
   '00000000-0000-4000-8000-00000000e105'::uuid,
   '【完攀体验】被旁边的岩友提醒了一个小细节，原来换个方向就豁然开朗。'),
  ('00000000-0000-4000-8000-00000000e206'::uuid,
   '00000000-0000-4000-8000-00000000e101'::uuid,
   '【完攀体验】最后一把才完攀，差点就放弃了，幸好再试了一次。'),
  ('00000000-0000-4000-8000-00000000e207'::uuid,
   '00000000-0000-4000-8000-00000000e102'::uuid,
   '【完攀体验】热身线也有新发现，身体贴墙一点，每一步都更轻松。'),
  ('00000000-0000-4000-8000-00000000e208'::uuid,
   '00000000-0000-4000-8000-00000000e103'::uuid,
   '【完攀体验】给自己定了个小目标：先爬得稳，再慢慢追求更高难度。'),
  ('00000000-0000-4000-8000-00000000e209'::uuid,
   '00000000-0000-4000-8000-00000000e104'::uuid,
   '【完攀体验】今天学会了用腿发力，手上终于没有那么快没电。'),
  ('00000000-0000-4000-8000-00000000e210'::uuid,
   '00000000-0000-4000-8000-00000000e105'::uuid,
   '【完攀体验】和新认识的岩友互相保护、互相加油，爬墙真的会让人变勇敢。'),
  ('00000000-0000-4000-8000-00000000e211'::uuid,
   '00000000-0000-4000-8000-00000000e101'::uuid,
   '【完攀体验】同一条线换了三种思路，没爬完也一样收获满满。'),
  ('00000000-0000-4000-8000-00000000e212'::uuid,
   '00000000-0000-4000-8000-00000000e103'::uuid,
   '【完攀体验】这周第二次来爬，记得热身、放松，也记得为每次进步鼓掌。')
) AS legacy(id, user_id, caption)
  ON s.id = legacy.id
 AND s.user_id = legacy.user_id
 AND s.caption = legacy.caption
JOIN users AS author ON author.id = s.user_id
JOIN square_cleanup_fixture_authors AS fixture
  ON fixture.id = author.id AND fixture.openid = author.openid
WHERE s.route_id IS NULL
  AND s.video_url IS NULL
  AND s.image_urls = '{}'::text[];

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM (
      SELECT l.user_id FROM post_likes AS l
      JOIN square_cleanup_posts AS target ON target.id = l.send_id
      UNION ALL
      SELECT c.user_id FROM comments AS c
      JOIN square_cleanup_posts AS target ON target.id = c.send_id
    ) AS interaction
    WHERE NOT EXISTS (
      SELECT 1
      FROM users AS author
      JOIN square_cleanup_fixture_authors AS fixture
        ON fixture.id = author.id AND fixture.openid = author.openid
      WHERE author.id = interaction.user_id
    )
  ) THEN
    RAISE EXCEPTION
      'Square mock post cleanup refused: non-fixture comments or likes exist on a target post; review those interactions before retrying.';
  END IF;
END
$$;

WITH interaction_counts AS (
  SELECT
    (SELECT count(*) FROM post_likes AS l
     JOIN square_cleanup_posts AS target ON target.id = l.send_id) AS likes,
    (SELECT count(*) FROM comments AS c
     JOIN square_cleanup_posts AS target ON target.id = c.send_id) AS comments
), deleted AS (
  DELETE FROM sends AS s
  USING square_cleanup_posts AS target
  WHERE s.id = target.id
  RETURNING s.id
)
SELECT (SELECT count(*) FROM deleted) AS deleted_mock_posts,
       likes AS deleted_mock_likes,
       comments AS deleted_mock_comments
FROM interaction_counts;

COMMIT;
