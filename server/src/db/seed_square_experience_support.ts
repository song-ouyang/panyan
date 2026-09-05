import type { QueryResultRow } from "pg";

export type SquareExperienceSeedQuery = <
  T extends QueryResultRow = QueryResultRow,
>(
  text: string,
  values?: unknown[],
) => Promise<{ rows: T[]; rowCount: number | null }>;

export type SquareExperienceSeedResult = {
  users: number;
  posts: number;
  likes: number;
  comments: number;
};

const fixtureOpenidPrefix = "fixture:wanpan:square:";
const fixtureCopyPrefix = "【完攀体验】";

const experienceProfiles = [
  {
    id: "00000000-0000-4000-8000-00000000e101",
    openid: `${fixtureOpenidPrefix}ayan`,
    nickname: "完攀体验·阿岩",
    bio: "完攀体验账号，用于展示真实的攀爬交流氛围。",
  },
  {
    id: "00000000-0000-4000-8000-00000000e102",
    openid: `${fixtureOpenidPrefix}xiaolin`,
    nickname: "完攀体验·小林",
    bio: "完攀体验账号，喜欢记录脚法和重心。",
  },
  {
    id: "00000000-0000-4000-8000-00000000e103",
    openid: `${fixtureOpenidPrefix}maomao`,
    nickname: "完攀体验·猫猫",
    bio: "完攀体验账号，下班后也要开心爬两把。",
  },
  {
    id: "00000000-0000-4000-8000-00000000e104",
    openid: `${fixtureOpenidPrefix}chengzi`,
    nickname: "完攀体验·橙子",
    bio: "完攀体验账号，正在练习动态和协调。",
  },
  {
    id: "00000000-0000-4000-8000-00000000e105",
    openid: `${fixtureOpenidPrefix}xiaoyu`,
    nickname: "完攀体验·小屿",
    bio: "完攀体验账号，期待认识更多岩友。",
  },
] as const;

const experiencePosts = [
  {
    id: "00000000-0000-4000-8000-00000000e201",
    profileIndex: 0,
    hoursAgo: 1,
    caption: `${fixtureCopyPrefix}第一次把害怕的落脚稳稳踩住，小小进步也值得记下来。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e202",
    profileIndex: 1,
    hoursAgo: 3,
    caption: `${fixtureCopyPrefix}今天只专心练脚法，放慢一点以后反而爬得更顺了。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e203",
    profileIndex: 2,
    hoursAgo: 5,
    caption: `${fixtureCopyPrefix}下班后来爬半小时，手臂酸酸的，心情却满格了。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e204",
    profileIndex: 3,
    hoursAgo: 8,
    caption: `${fixtureCopyPrefix}练了好几次重心切换，终于找到不用硬拉的感觉。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e205",
    profileIndex: 4,
    hoursAgo: 12,
    caption: `${fixtureCopyPrefix}被旁边的岩友提醒了一个小细节，原来换个方向就豁然开朗。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e206",
    profileIndex: 0,
    hoursAgo: 18,
    caption: `${fixtureCopyPrefix}最后一把才完攀，差点就放弃了，幸好再试了一次。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e207",
    profileIndex: 1,
    hoursAgo: 24,
    caption: `${fixtureCopyPrefix}热身线也有新发现，身体贴墙一点，每一步都更轻松。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e208",
    profileIndex: 2,
    hoursAgo: 30,
    caption: `${fixtureCopyPrefix}给自己定了个小目标：先爬得稳，再慢慢追求更高难度。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e209",
    profileIndex: 3,
    hoursAgo: 38,
    caption: `${fixtureCopyPrefix}今天学会了用腿发力，手上终于没有那么快没电。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e210",
    profileIndex: 4,
    hoursAgo: 48,
    caption: `${fixtureCopyPrefix}和新认识的岩友互相保护、互相加油，爬墙真的会让人变勇敢。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e211",
    profileIndex: 0,
    hoursAgo: 60,
    caption: `${fixtureCopyPrefix}同一条线换了三种思路，没爬完也一样收获满满。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e212",
    profileIndex: 2,
    hoursAgo: 72,
    caption: `${fixtureCopyPrefix}这周第二次来爬，记得热身、放松，也记得为每次进步鼓掌。`,
  },
] as const;

const experienceLikes = [
  [0, 1], [0, 2], [0, 3], [0, 4],
  [1, 0], [1, 2], [1, 4],
  [2, 0], [2, 1], [2, 3],
  [3, 1], [3, 2], [3, 4],
  [4, 0], [4, 3],
  [5, 1], [5, 2], [6, 3], [7, 4], [9, 0],
] as const;

const experienceComments = [
  {
    id: "00000000-0000-4000-8000-00000000e401",
    postIndex: 0,
    profileIndex: 1,
    content: `${fixtureCopyPrefix}这种稳稳落脚的快乐太懂了！`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e402",
    postIndex: 1,
    profileIndex: 3,
    content: `${fixtureCopyPrefix}慢一点真的会更顺，下次一起练。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e403",
    postIndex: 2,
    profileIndex: 4,
    content: `${fixtureCopyPrefix}快乐完攀，收工回家！`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e404",
    postIndex: 3,
    profileIndex: 0,
    content: `${fixtureCopyPrefix}找到重心的那一刻特别爽。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e405",
    postIndex: 4,
    profileIndex: 2,
    content: `${fixtureCopyPrefix}岩友的一句提醒经常就是通关密码。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e406",
    postIndex: 5,
    profileIndex: 4,
    content: `${fixtureCopyPrefix}再试一把的你太棒啦！`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e407",
    postIndex: 7,
    profileIndex: 1,
    content: `${fixtureCopyPrefix}稳稳升级，一起加油。`,
  },
  {
    id: "00000000-0000-4000-8000-00000000e408",
    postIndex: 9,
    profileIndex: 3,
    content: `${fixtureCopyPrefix}遇到会鼓励人的岩友真好。`,
  },
] as const;

export function assertSquareExperienceSeedAllowed(
  nodeEnv: string,
  allowProductionSquareSeed: boolean,
): void {
  if (nodeEnv === "production" && !allowProductionSquareSeed) {
    throw new Error(
      "Production square experience seed is disabled. Back up the database " +
        "and pass ALLOW_PRODUCTION_SQUARE_SEED=true only to the explicit " +
        "db:seed-square-experience command.",
    );
  }
}

async function seedSquareExperience(
  runQuery: SquareExperienceSeedQuery,
): Promise<SquareExperienceSeedResult> {
  const userIds: string[] = [];
  for (const profile of experienceProfiles) {
    const result = await runQuery<{ id: string }>(
      `INSERT INTO users(id,openid,nickname,bio,profile_completed)
       VALUES($1,$2,$3,$4,true)
       ON CONFLICT(openid) DO UPDATE SET
         nickname=EXCLUDED.nickname,
         bio=EXCLUDED.bio,
         profile_completed=true,
         updated_at=now()
       WHERE users.id=EXCLUDED.id
         AND users.openid LIKE 'fixture:wanpan:square:%'
       RETURNING id`,
      [profile.id, profile.openid, profile.nickname, profile.bio],
    );
    const userId = result.rows[0]?.id;
    if (userId !== profile.id) {
      throw new Error(
        `Square experience fixture namespace conflict for user ${profile.openid}`,
      );
    }
    userIds.push(userId);
  }

  const postIds: string[] = [];
  for (const post of experiencePosts) {
    const userId = userIds[post.profileIndex];
    if (!userId) throw new Error(`Missing fixture user for post ${post.id}`);
    const result = await runQuery<{ id: string }>(
      `INSERT INTO sends(
         id,user_id,route_id,attempts,video_url,caption,image_urls,visibility,
         moderation_status,sent_at
       ) VALUES($1,$2,NULL,1,NULL,$3,'{}'::text[],'public','approved',
         date_trunc('hour',now())-($4::int * interval '1 hour'))
       ON CONFLICT(id) DO UPDATE SET
         attempts=1,
         video_url=NULL,
         caption=EXCLUDED.caption,
         image_urls='{}'::text[]
       WHERE sends.user_id=EXCLUDED.user_id
         AND sends.route_id IS NULL
         AND sends.caption LIKE '【完攀体验】%'
       RETURNING id`,
      [post.id, userId, post.caption, post.hoursAgo],
    );
    const postId = result.rows[0]?.id;
    if (postId !== post.id) {
      throw new Error(
        `Square experience fixture namespace conflict for post ${post.id}`,
      );
    }
    postIds.push(postId);
  }

  for (const [postIndex, profileIndex] of experienceLikes) {
    const postId = postIds[postIndex];
    const userId = userIds[profileIndex];
    if (!postId || !userId) {
      throw new Error("Invalid square experience like fixture");
    }
    await runQuery(
      `INSERT INTO post_likes(send_id,user_id)
       VALUES($1,$2)
       ON CONFLICT(send_id,user_id) DO NOTHING`,
      [postId, userId],
    );
  }

  for (const comment of experienceComments) {
    const postId = postIds[comment.postIndex];
    const userId = userIds[comment.profileIndex];
    if (!postId || !userId) {
      throw new Error(`Invalid square experience comment ${comment.id}`);
    }
    const result = await runQuery<{ id: string }>(
      `INSERT INTO comments(id,send_id,user_id,content,moderation_status)
       VALUES($1,$2,$3,$4,'approved')
       ON CONFLICT(id) DO UPDATE SET
         content=EXCLUDED.content
       WHERE comments.send_id=EXCLUDED.send_id
         AND comments.user_id=EXCLUDED.user_id
         AND comments.content LIKE '【完攀体验】%'
       RETURNING id`,
      [comment.id, postId, userId, comment.content],
    );
    if (result.rows[0]?.id !== comment.id) {
      throw new Error(
        `Square experience fixture namespace conflict for comment ${comment.id}`,
      );
    }
  }

  return {
    users: experienceProfiles.length,
    posts: experiencePosts.length,
    likes: experienceLikes.length,
    comments: experienceComments.length,
  };
}

export async function runSquareExperienceSeed(
  runQuery: SquareExperienceSeedQuery,
  nodeEnv: string,
  allowProductionSquareSeed: boolean,
): Promise<SquareExperienceSeedResult> {
  assertSquareExperienceSeedAllowed(nodeEnv, allowProductionSquareSeed);
  return seedSquareExperience(runQuery);
}
