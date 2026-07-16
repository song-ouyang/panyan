# 完攀日记部署命令（Ubuntu 22.04/24.04）

## 需要提前准备

- 一台有公网 IP 的 Ubuntu 22.04 或 24.04 服务器
- 一个已备案域名，例如 `api.wanpan.example.com`
- 域名的 A 记录已指向服务器公网 IP
- 安全组放行 TCP `22`、`80`、`443`，以及 UDP `443`
- 微信公众平台重置后的新 AppSecret

不要开放 PostgreSQL 的 `5432` 端口，生产 Compose 只允许 API 在内部网络访问数据库。

## 1. 首次安装 Docker

SSH 登录服务器后执行：

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run --rm hello-world
```

如果使用非 root 用户，可执行：

```bash
sudo usermod -aG docker "$USER"
```

退出 SSH 后重新登录，让用户组权限生效。

## 2. 在 Mac 上生成生产配置

```bash
cd "/Users/guoba/Documents/爬墙高手"
cp .env.production.example .env.production
openssl rand -hex 32
openssl rand -hex 32
```

将两次生成的不同随机值分别用于 `POSTGRES_PASSWORD` 和 `JWT_SECRET`，然后编辑 `.env.production`：

```env
DOMAIN=api.你的域名.com
ACME_EMAIL=你的邮箱
POSTGRES_DB=wanpan
POSTGRES_USER=wanpan
POSTGRES_PASSWORD=第一段随机值
JWT_SECRET=第二段随机值
WECHAT_APP_ID=wx87ff92b724ffea73
WECHAT_APP_SECRET=重置后的新AppSecret
MODERATION_MODE=manual
UPLOAD_MODE=oss
OSS_REGION=oss-cn-shenzhen
OSS_BUCKET=你的Bucket名称
OSS_ACCESS_KEY_ID=RAM用户AccessKeyId
OSS_ACCESS_KEY_SECRET=RAM用户AccessKeySecret
OSS_PUBLIC_BASE_URL=https://你的Bucket访问域名
```

`DOMAIN` 不要包含 `https://` 或路径。

## 3. 从 Mac 上传并启动

把命令中的服务器 IP 和 SSH 用户替换掉：

```bash
cd "/Users/guoba/Documents/爬墙高手"
bash deploy/deploy-from-mac.sh root@服务器公网IP /opt/wanpan-diary
```

脚本会上传代码、构建镜像、启动 PostgreSQL/API/Caddy、执行数据库迁移，并自动申请 HTTPS 证书。

## 4. 验证

```bash
curl https://api.你的域名.com/health
ssh root@服务器公网IP 'cd /opt/wanpan-diary && docker compose --env-file .env.production -f docker-compose.prod.yml ps'
ssh root@服务器公网IP 'cd /opt/wanpan-diary && docker compose --env-file .env.production -f docker-compose.prod.yml logs --tail=100 api caddy'
```

健康检查应返回 `{"ok":true,...}`。

## 5. 修改小程序接口

修改 `miniprogram/utils/config.js`：

```js
module.exports = {
  API_BASE_URL: 'https://api.你的域名.com/api',
  UPLOAD_MODE: 'oss',
  DEV_LOGIN: false
};
```

在微信公众平台将 `https://api.你的域名.com` 分别加入：

- request 合法域名
- uploadFile 合法域名
- downloadFile 合法域名

还需将 OSS Bucket 的 HTTPS 访问域名加入小程序的 `request` 和 `downloadFile` 合法域名。

## 6. 配置 OSS MP4 分片上传

创建仅允许访问指定 Bucket `videos/*` 路径的 RAM 用户，不要使用阿里云主账号 AccessKey。Bucket 跨域规则至少配置：

- 来源：小程序调试阶段可用 `*`，正式环境按实际来源收紧
- 允许 Methods：`PUT`、`GET`、`HEAD`
- 允许 Headers：`*`
- 暴露 Headers：`ETag`、`x-oss-request-id`

小程序上传流程为：后端初始化 Multipart Upload → 小程序读取 5MB 分片 → 使用15分钟有效的签名 URL 直传 OSS → 后端完成合并。AccessKey Secret 始终只保存在服务器环境变量中。

## 日常更新

代码修改后重新执行同一条命令：

```bash
bash deploy/deploy-from-mac.sh root@服务器公网IP /opt/wanpan-diary
```

## 查看日志和回滚前备份

```bash
ssh root@服务器公网IP
cd /opt/wanpan-diary
docker compose --env-file .env.production -f docker-compose.prod.yml logs -f --tail=200 api
bash deploy/backup.sh
```

建议通过服务器 `crontab` 每天执行备份，并把备份同步到另一台机器或对象存储。
