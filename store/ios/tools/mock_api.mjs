import { createReadStream, existsSync, readFileSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize } from 'node:path';

import { createGymCatalog } from './mock_gym_directory.mjs';

const host = process.env.HOST || '127.0.0.1';
const port = Number(process.env.PORT || 3001);
const projectRoot = normalize(join(import.meta.dirname, '../../..'));
const assetRoot = join(projectRoot, 'flutter_app', 'assets');
const publicBaseUrl = `http://${host}:${port}`;

const demoUser = {
  id: 'store-demo-user',
  nickname: '岩点点',
  avatar_url: `${publicBaseUrl}/media/profile-peek-cat-v2.png`,
  bio: '每周两次抱石，目标 V5',
  role: 'climber',
  profile_completed: true,
  created_at: '2026-01-18T10:00:00.000Z',
};

const profile = {
  ...demoUser,
  stats: {
    total_sends: 48,
    gym_count: 6,
    max_grade: 5,
    monthly_sends: 12,
    monthly_max_grade: 4,
  },
};

const publicGymDirectory = JSON.parse(
  readFileSync(join(projectRoot, 'data', 'gyms.public-verified.json'), 'utf8'),
);
const gymCatalog = createGymCatalog(publicGymDirectory, { publicBaseUrl });

function recentIso(minutesAgo) {
  return new Date(Date.now() - minutesAgo * 60_000).toISOString();
}

function feed(scope) {
  const squareItems = [
    {
      id: 'post-first-v3', user_id: 'climber-coconut', nickname: '椰椰不椰',
      avatar_url: `${publicBaseUrl}/media/profile-peek-cat-v2.png`, route_id: 'route-orange-moon', route_name: '白日梦', grade: 'V3', color: '#70C9E8', gym_id: 'gym-5plus-yunjian', gym_name: '5+Rock · 云间粮仓店', attempts: 4,
      image_urls: [`${publicBaseUrl}/media/launch-hero-v2.jpg`, `${publicBaseUrl}/media/mascot-celebrate.jpg`],
      caption: '第一次完攀 V3！试了好几次终于找到节奏，最后一手稳稳拿住！感谢同伴的鼓励和保护～', visibility: 'public', moderation_status: 'approved', sent_at: recentIso(12), like_count: 28, comment_count: 6, liked: true, comments: [],
    },
    {
      id: 'post-purple-12', user_id: 'climber-amao', nickname: '阿猫要努力',
      avatar_url: `${publicBaseUrl}/media/mascot-welcome.jpg`, route_id: 'route-purple-12', route_name: '紫色 12号', grade: 'V2', color: '#9A78E8', gym_id: 'gym-1778-hope', gym_name: '1778CLIMBING', attempts: 2, image_urls: [],
      caption: '热身墙新刷的这条线路好好玩，动作流畅不说，最后的收尾超解压～适合练节奏！', visibility: 'public', moderation_status: 'approved', sent_at: recentIso(76), like_count: 12, comment_count: 2, liked: false, comments: [],
    },
    {
      id: 'post-v4-green', user_id: 'climber-ayan', nickname: '阿岩同学',
      avatar_url: `${publicBaseUrl}/media/mascot-celebrate.jpg`, route_id: 'route-v4-green', route_name: '绿线转身', grade: 'V4', color: '#9DD5B0', gym_id: 'gym-tnt-fulifang', gym_name: 'TNT攀岩馆 · 富力坊店', attempts: 3, image_urls: [`${publicBaseUrl}/media/launch-hero-v2.jpg`],
      caption: '今天状态在线，V4 顺利拿下 ✅', visibility: 'public', moderation_status: 'approved', sent_at: recentIso(310), like_count: 36, comment_count: 8, liked: false, comments: [],
    },
    {
      id: 'post-warmup-moment', user_id: 'climber-momo', nickname: '默默热身中',
      avatar_url: `${publicBaseUrl}/media/friends-empty-cat-v2.png`, attempts: 1, image_urls: [`${publicBaseUrl}/media/route-map-cat-v2.png`],
      caption: '今天不卷难度，认真热身、练练脚法。每一次上墙都算数。', visibility: 'public', moderation_status: 'approved', sent_at: recentIso(520), like_count: 9, comment_count: 1, liked: false, comments: [],
    },
    {
      id: 'post-orange-moon',
      user_id: 'climber-stone',
      nickname: '小石头',
      avatar_url: `${publicBaseUrl}/media/mascot-celebrate.jpg`,
      route_id: 'route-orange-moon',
      route_name: '橙色月亮',
      grade: 'V4',
      color: '#FF6B52',
      gym_id: 'public-gym-6',
      gym_name: '丘山攀岩·CyPARK店',
      attempts: 3,
      image_urls: [`${publicBaseUrl}/media/launch-hero-v2.jpg`],
      caption: '下班后的第三把过！脚点终于踩稳了。',
      visibility: 'public',
      moderation_status: 'approved',
      sent_at: recentIso(18),
      like_count: 28,
      comment_count: 6,
      liked: true,
      comments: [],
    },
    {
      id: 'post-purple-slab',
      user_id: 'climber-lan',
      nickname: '阿岚',
      avatar_url: `${publicBaseUrl}/media/mascot-welcome.jpg`,
      route_id: 'route-purple-slab',
      route_name: '紫色薄荷',
      grade: 'V3',
      color: '#9A78E8',
      gym_id: 'public-gym-1',
      gym_name: '1778CLIMBING',
      attempts: 1,
      video_url: `${publicBaseUrl}/media/demo-send.mp4`,
      image_urls: [],
      caption: '今天的第一条 flash，开心到想再爬一遍。',
      visibility: 'public',
      moderation_status: 'approved',
      sent_at: recentIso(73),
      like_count: 16,
      comment_count: 3,
      liked: false,
      comments: [],
    },
  ];

  if (scope === 'friends') {
    return { items: squareItems.slice(0, 2), nextCursor: null };
  }
  return { items: squareItems, nextCursor: null };
}

function monthDashboard(month) {
  const safeMonth = /^\d{4}-\d{2}$/.test(month || '') ? month : '2026-08';
  return {
    month: safeMonth,
    days: [
      { day: `${safeMonth}-03T10:00:00.000Z`, gym_name: '丘山攀岩·CyPARK店', grade: 'V3', sends: 3 },
      { day: `${safeMonth}-08T10:00:00.000Z`, gym_name: '1778CLIMBING', grade: 'V4', sends: 2 },
      { day: `${safeMonth}-14T10:00:00.000Z`, gym_name: '大松果马达攀岩馆·金石店', grade: 'V4', sends: 3 },
      { day: `${safeMonth}-21T10:00:00.000Z`, gym_name: 'BLOC1 Climbing Gym攀岩馆', grade: 'V5', sends: 1 },
      { day: `${safeMonth}-27T10:00:00.000Z`, gym_name: '5+Rock 攀岩馆·云间粮仓店', grade: 'V3', sends: 3 },
    ],
    summary: {
      climbing_days: 5,
      sends: 12,
      gyms: 3,
      max_grade: 5,
      flashes: 4,
      videos: 6,
    },
    byGrade: [
      { grade: 'V3', sends: 6 },
      { grade: 'V4', sends: 5 },
      { grade: 'V5', sends: 1 },
    ],
    byGym: [
      { gym_id: 'public-gym-6', gym_name: '丘山攀岩·CyPARK店', sends: 6, max_grade: 4 },
      { gym_id: 'public-gym-1', gym_name: '1778CLIMBING', sends: 5, max_grade: 4 },
      { gym_id: 'public-gym-9', gym_name: 'BLOC1 Climbing Gym攀岩馆', sends: 1, max_grade: 5 },
    ],
  };
}

function sendJson(response, body, statusCode = 200) {
  const payload = Buffer.from(JSON.stringify(body));
  response.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': payload.length,
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*',
  });
  response.end(payload);
}

function serveMedia(response, pathname) {
  const filename = pathname.slice('/media/'.length);
  if (!filename || filename.includes('/') || filename.includes('..')) return false;
  const filePath = join(assetRoot, filename);
  if (!existsSync(filePath) || !statSync(filePath).isFile()) return false;
  const mime = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
  }[extname(filePath).toLowerCase()] || 'application/octet-stream';
  response.writeHead(200, {
    'Content-Type': mime,
    'Content-Length': statSync(filePath).size,
    'Cache-Control': 'public, max-age=3600',
  });
  createReadStream(filePath).pipe(response);
  return true;
}

const server = createServer((request, response) => {
  const url = new URL(request.url || '/', publicBaseUrl);
  const method = request.method || 'GET';

  if (method === 'OPTIONS') {
    response.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
    });
    response.end();
    return;
  }

  if (method === 'GET' && url.pathname.startsWith('/media/')) {
    if (!serveMedia(response, url.pathname)) {
      sendJson(response, { code: 'NOT_FOUND', message: '素材不存在' }, 404);
    }
    return;
  }

  if (method === 'GET' && url.pathname === '/api/health') {
    sendJson(response, { ok: true });
  } else if (method === 'GET' && url.pathname === '/api/users/me') {
    sendJson(response, profile);
  } else if (method === 'GET' && url.pathname === '/api/gyms/directory') {
    sendJson(response, gymCatalog.getDirectory({
      city: url.searchParams.get('city'),
      q: url.searchParams.get('q'),
    }));
  } else if (method === 'GET' && /^\/api\/gyms\/brands\/[^/]+\/stores$/.test(url.pathname)) {
    const brandId = decodeURIComponent(url.pathname.split('/')[4]);
    const detail = gymCatalog.getBrandDetail(brandId, {
      city: url.searchParams.get('city'),
    });
    if (detail) sendJson(response, detail);
    else sendJson(response, { code: 'NOT_FOUND', message: '岩馆品牌不存在' }, 404);
  } else if (method === 'GET' && url.pathname === '/api/gyms') {
    sendJson(response, gymCatalog.getGyms({
      city: url.searchParams.get('city'),
      q: url.searchParams.get('q'),
    }));
  } else if (method === 'GET' && /^\/api\/gyms\/[^/]+$/.test(url.pathname)) {
    const gymId = decodeURIComponent(url.pathname.split('/')[3]);
    const detail = gymCatalog.getGymDetail(gymId);
    if (detail) sendJson(response, detail);
    else sendJson(response, { code: 'NOT_FOUND', message: '岩馆不存在' }, 404);
  } else if (method === 'GET' && url.pathname === '/api/sends/feed') {
    sendJson(response, feed(url.searchParams.get('scope') || 'square'));
  } else if (method === 'GET' && url.pathname === '/api/users/me/month-dashboard') {
    sendJson(response, monthDashboard(url.searchParams.get('month')));
  } else if ((method === 'POST' || method === 'DELETE') && /^\/api\/sends\/[^/]+\/like$/.test(url.pathname)) {
    sendJson(response, { ok: true });
  } else {
    sendJson(response, { code: 'NOT_FOUND', message: `Route ${method}:${url.pathname} not found` }, 404);
  }
});

server.listen(port, host, () => {
  process.stdout.write(`Wanpan screenshot API: ${publicBaseUrl}/api\n`);
});
