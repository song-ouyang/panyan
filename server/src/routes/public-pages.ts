import type { FastifyPluginAsync, FastifyReply } from 'fastify';

const contactEmail = 'ouyangsong8@gmail.com';
const developerName = 'guoba';
const effectiveDate = '2026年9月1日';

type PublicPage = {
  title: string;
  eyebrow: string;
  intro: string;
  content: string;
};

function renderPage(page: PublicPage): string {
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="color-scheme" content="light">
  <meta name="theme-color" content="#fffaf3">
  <title>${page.title}｜完攀日记</title>
  <style>
    :root { color-scheme: light; --ink: #20252b; --muted: #697177; --line: #eadfce; --paper: #fffdf9; --cream: #fff7e8; --coral: #f2674f; --coral-soft: #fff0eb; }
    * { box-sizing: border-box; }
    body { margin: 0; color: var(--ink); background: linear-gradient(180deg, var(--cream), #fff 42%); font: 16px/1.75 -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif; }
    a { color: #c74735; text-underline-offset: 3px; }
    .shell { width: min(860px, calc(100% - 32px)); margin: 0 auto; padding: max(36px, env(safe-area-inset-top)) 0 max(64px, env(safe-area-inset-bottom)); }
    .hero { padding: clamp(28px, 6vw, 52px); border: 1px solid var(--line); border-radius: 30px; background: rgba(255,253,249,.96); box-shadow: 0 18px 50px rgba(80,54,32,.08); }
    .eyebrow { margin: 0 0 10px; color: var(--coral); font-size: 13px; font-weight: 800; letter-spacing: .12em; }
    h1 { margin: 0; font-size: clamp(32px, 7vw, 52px); line-height: 1.16; letter-spacing: -.04em; }
    .intro { max-width: 680px; margin: 18px 0 0; color: var(--muted); font-size: 17px; }
    .meta { display: inline-flex; margin-top: 20px; padding: 7px 12px; border-radius: 999px; color: #a33a2b; background: var(--coral-soft); font-size: 13px; font-weight: 700; }
    .content { margin-top: 18px; padding: clamp(24px, 5vw, 42px); border: 1px solid var(--line); border-radius: 26px; background: var(--paper); }
    section + section { margin-top: 34px; padding-top: 30px; border-top: 1px solid var(--line); }
    h2 { margin: 0 0 12px; font-size: 21px; line-height: 1.35; }
    h3 { margin: 18px 0 6px; font-size: 17px; }
    p { margin: 10px 0; }
    ul { margin: 10px 0; padding-left: 1.35em; }
    li + li { margin-top: 7px; }
    .callout { margin-top: 16px; padding: 16px 18px; border-left: 4px solid var(--coral); border-radius: 4px 16px 16px 4px; background: var(--coral-soft); }
    nav { display: flex; flex-wrap: wrap; gap: 10px 18px; margin-top: 22px; }
    nav a { font-size: 14px; font-weight: 700; }
    footer { padding: 24px 8px 0; color: var(--muted); text-align: center; font-size: 13px; }
    @media (max-width: 520px) { .shell { width: min(100% - 20px, 860px); } .hero, .content { border-radius: 22px; } }
  </style>
</head>
<body>
  <main class="shell">
    <header class="hero">
      <p class="eyebrow">${page.eyebrow}</p>
      <h1>${page.title}</h1>
      <p class="intro">${page.intro}</p>
      <span class="meta">生效与更新日期：${effectiveDate}</span>
      <nav aria-label="相关页面">
        <a href="/privacy">隐私政策</a>
        <a href="/privacy-choices">隐私选择与账号删除</a>
        <a href="/terms">用户协议</a>
        <a href="/support">支持与联系</a>
      </nav>
    </header>
    <article class="content">${page.content}</article>
    <footer>完攀日记 · 开发者：${developerName} · <a href="mailto:${contactEmail}">${contactEmail}</a></footer>
  </main>
</body>
</html>`;
}

function html(reply: FastifyReply, page: PublicPage) {
  return reply
    .type('text/html; charset=utf-8')
    .header('cache-control', 'public, max-age=300')
    .header('content-security-policy', "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
    .header('referrer-policy', 'no-referrer')
    .header('x-frame-options', 'DENY')
    .header('x-content-type-options', 'nosniff')
    .send(renderPage(page));
}

const privacyPage: PublicPage = {
  eyebrow: 'APP PRIVACY',
  title: '完攀日记隐私政策',
  intro: '我们重视你的个人信息与选择权。本政策说明完攀日记在提供攀岩记录、线路、社区和岩友互动服务时如何处理个人信息。',
  content: `
    <section>
      <h2>1. 适用范围与服务提供者</h2>
      <p>本政策适用于“完攀日记”移动应用及相关服务。服务提供者及个人信息处理者为个人开发者 ${developerName}。如有问题，可通过 <a href="mailto:${contactEmail}">${contactEmail}</a> 联系。</p>
    </section>
    <section>
      <h2>2. 我们处理的信息</h2>
      <h3>账号与登录信息</h3>
      <ul>
        <li>使用手机号登录时，我们处理手机号和验证码校验结果；验证码由短信服务商发送。</li>
        <li>当应用提供且你主动选择微信登录时，我们接收微信返回的账号标识，以及你授权提供的昵称和头像。选择 Apple 登录时，我们接收 Apple 返回的账号标识，以及首次授权时可能提供的姓名。我们不会获得你的微信或 Apple 密码。</li>
      </ul>
      <h3>你主动提供的资料与内容</h3>
      <ul>
        <li>昵称、头像、个人简介。</li>
        <li>攀岩记录、线路信息、配文，以及你主动选择上传的图片或视频。</li>
        <li>评论、点赞、岩友关系、约爬信息、举报与反馈。</li>
      </ul>
      <h3>服务运行信息</h3>
      <p>为保障登录、接口安全和故障排查，服务器可能记录请求时间、IP 地址、接口状态和必要的安全日志。当前版本不会持续获取精确定位；照片、相机和麦克风等系统权限仅在你主动选择图片或视频相关功能时请求。</p>
    </section>
    <section>
      <h2>3. 信息的使用目的</h2>
      <ul>
        <li>创建与维护账号，完成身份校验并保障账号安全。</li>
        <li>展示岩馆、线路和攀岩记录，生成成长统计与排行榜。</li>
        <li>发布广场或岩友可见内容，支持互动、约爬、通知与举报处理。</li>
        <li>提供文件上传、客户支持、服务稳定性与安全防护。</li>
      </ul>
      <p>我们不会出售你的个人信息，也不会将个人信息用于与上述目的无关的个性化广告。</p>
    </section>
    <section>
      <h2>4. 对外提供与第三方服务</h2>
      <p>为实现必要功能，我们会使用阿里云提供的云服务器、对象存储和短信验证能力，以及你主动选择的微信或 Apple 登录服务。这些服务商仅在提供相应能力所需范围内处理信息。除取得你的单独同意、履行法定义务或保护人身与财产安全等依法允许的情形外，我们不会向其他第三方提供你的个人信息。</p>
      <p>你选择公开发布的昵称、头像、配文、攀岩记录、图片或视频可能被其他用户看到；选择仅岩友可见或私密时，我们会按照你选择的范围展示。</p>
    </section>
    <section>
      <h2>5. 存储、保护与保留期限</h2>
      <p>生产服务使用部署在中国境内的云服务器和对象存储。我们采取访问控制、HTTPS 传输、权限隔离和必要备份等措施保护数据。我们仅在实现服务目的、履行法定义务和处理争议所需的期限内保留信息；账号删除后，将依法删除或匿名化主服务中的相关个人信息，轮换备份最长保留 14 天，法律法规要求另行保留的记录除外。</p>
    </section>
    <section>
      <h2>6. 你的权利与选择</h2>
      <p>你可以在应用内查看或修改个人资料，管理自己发布的内容和可见范围，解除岩友关系，并申请注销账号和删除数据。详细步骤见<a href="/privacy-choices">“隐私选择与账号删除”</a>。无法通过应用完成时，可使用注册手机号相关信息发送邮件至 <a href="mailto:${contactEmail}">${contactEmail}</a>，我们会在核验账号归属后处理。账号注销前，你可以先删除不希望继续保留的公开内容；如需协助清理已上传的媒体文件，可同时在邮件中说明。</p>
    </section>
    <section>
      <h2>7. 未成年人保护</h2>
      <p>攀岩具有一定风险。未满 18 周岁的用户应在监护人同意和指导下使用本服务及参与线下攀岩活动；未满 14 周岁的儿童应由监护人代为阅读并同意本政策。如监护人发现儿童信息被不当处理，请联系我们。</p>
    </section>
    <section>
      <h2>8. 政策更新与联系我们</h2>
      <p>功能、权限或处理方式发生重要变化时，我们会更新本政策，并通过应用内提示或其他合理方式告知。对本政策或个人信息处理有任何疑问、意见或请求，请联系：</p>
      <div class="callout"><strong>个人开发者：${developerName}</strong><br>联系邮箱：<a href="mailto:${contactEmail}">${contactEmail}</a></div>
    </section>`
};

const privacyChoicesPage: PublicPage = {
  eyebrow: 'PRIVACY CHOICES',
  title: '隐私选择与账号删除',
  intro: '你可以控制个人资料、发布内容、可见范围和账号数据。本页说明可用的操作与联系途径。',
  content: `
    <section>
      <h2>查看与更正</h2>
      <p>登录后进入“我的”，可查看个人资料和攀岩记录；通过“编辑个人资料”修改头像、昵称和简介。</p>
    </section>
    <section>
      <h2>内容与社交关系</h2>
      <p>你可以管理自己发布的动态、图片、视频和线路内容，并按产品提供的选项调整公开、仅岩友可见或私密范围。遇到不当内容时，可在动态、评论或用户主页的“更多”菜单中提交举报；拉黑用户后，双方的动态、评论和互动会被隔离。你也可以在“我的岩友”中解除岩友关系。</p>
    </section>
    <section>
      <h2>注销账号并删除数据</h2>
      <p>登录后进入“我的”中的“账号与隐私”，选择“注销并删除账号”，阅读影响并再次确认。请求完成后，账号将退出登录，主服务中的个人资料及与账号关联的数据将依照法律要求删除或匿名化，且通常无法恢复。轮换备份最长保留 14 天；如需协助清理已上传的媒体文件，可通过下方备用方式联系我们。</p>
      <div class="callout"><strong>备用申请方式</strong><br>如果无法登录或无法在应用内提交，请使用注册手机号相关信息发送邮件至 <a href="mailto:${contactEmail}">${contactEmail}</a>，主题写明“完攀日记账号删除”。请勿在邮件中发送验证码或密码。</div>
    </section>
    <section>
      <h2>撤回权限</h2>
      <p>你可以在 iOS“设置”中关闭相机、照片、麦克风等权限。关闭后对应功能可能无法使用，但不会影响不依赖该权限的浏览功能。</p>
    </section>
    <section>
      <h2>响应请求</h2>
      <p>为防止他人冒用，我们可能要求验证账号归属。收到完整请求并完成核验后，我们会在法律规定的期限内响应。</p>
    </section>`
};

const termsPage: PublicPage = {
  eyebrow: 'TERMS OF USE',
  title: '完攀日记用户协议',
  intro: '使用完攀日记前，请阅读本协议。继续注册、登录或使用服务，表示你理解并同意本协议。',
  content: `
    <section><h2>1. 服务说明</h2><p>完攀日记提供岩馆与线路浏览、攀岩记录、图片或视频发布、成长统计、排行榜、广场、岩友和约爬等信息服务。部分功能可能随版本和运营情况调整。</p></section>
    <section><h2>2. 账号责任</h2><p>你应提供真实、合法的信息并妥善保护账号。不得冒用他人身份、转让账号或利用服务实施违法行为。发现异常使用时，请及时联系我们。</p></section>
    <section><h2>3. 攀岩与线下活动安全</h2><p>攀岩具有受伤风险。线路难度、用户经验和约爬信息仅供参考，不能替代岩馆规则、专业指导、充分热身、保护措施或现场判断。线下活动由参与者自主决定并自行确认身份、场地与安全安排。</p></section>
    <section><h2>4. 用户内容</h2><p>你应确保发布的文字、图片、视频和线路信息合法且拥有必要权利。不得发布违法、侵权、虚假、骚扰、广告、侵犯隐私或危害他人安全的内容。线路投稿发布后可直接展示；平台仍可根据举报、安全或合规需要限制、纠正或删除违规内容。</p></section>
    <section><h2>5. 服务管理</h2><p>为维护社区安全和服务稳定，我们提供举报和拉黑功能，并可对违规内容或账号采取提醒、限制功能、删除内容或终止服务等措施。排行榜用于社区激励，不构成官方竞技成绩。</p></section>
    <section><h2>6. 知识产权</h2><p>完攀日记的产品设计、程序和原创内容受法律保护。你保留自己发布内容的合法权利，并授权我们在提供、展示和改进服务所必要的范围内使用该内容；删除内容或账号后，该授权在合理技术处理周期后终止，依法需保留的除外。</p></section>
    <section><h2>7. 变更、终止与联系</h2><p>我们可能因功能、安全、法律或运营需要更新服务与协议，并以合理方式提示重要变化。你可停止使用并注销账号。争议适用中华人民共和国法律，双方应先友好协商。联系邮箱：<a href="mailto:${contactEmail}">${contactEmail}</a>。</p></section>`
};

const supportPage: PublicPage = {
  eyebrow: 'APP SUPPORT',
  title: '完攀日记支持与联系',
  intro: '遇到登录、验证码、内容发布、账号或数据问题，可通过以下方式联系我们。',
  content: `
    <section>
      <h2>联系我们</h2>
      <div class="callout"><strong>支持邮箱</strong><br><a href="mailto:${contactEmail}">${contactEmail}</a></div>
      <p>邮件中请说明问题发生的时间、使用的设备和复现步骤。请勿发送短信验证码、密码、完整身份凭证或其他不必要的敏感信息。</p>
    </section>
    <section><h2>账号与隐私</h2><p>如需访问、更正或删除个人信息，请先查看<a href="/privacy-choices">隐私选择与账号删除</a>。无法登录时，可通过支持邮箱申请协助。</p></section>
    <section><h2>安全提醒</h2><p>完攀日记不会通过邮件索要验证码或密码。攀岩及约爬活动请遵守岩馆规定，并根据自身能力做好安全保护。</p></section>`
};

export const publicPageRoutes: FastifyPluginAsync = async (app) => {
  app.get('/privacy', async (_request, reply) => html(reply, privacyPage));
  app.get('/privacy-choices', async (_request, reply) => html(reply, privacyChoicesPage));
  app.get('/terms', async (_request, reply) => html(reply, termsPage));
  app.get('/support', async (_request, reply) => html(reply, supportPage));
};
