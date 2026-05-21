# 微信入口智能路由（Mac Docker 版）

这是一个运行在 Mac 服务器上的微信入口智能路由项目。服务通过 Docker 启动 `cc-connect`，接入微信后把消息自动分流到图片接口或代码接口，并支持图片附件编辑、最近图片上下文和微信媒体直连上传。

当前版本只保留 Mac / Linux Shell + Docker 的部署方式。

## 一句话启动

```sh
cp .env.example .env
vi .env
sh deploy.sh up
sh deploy.sh logs
```

第一次运行前请先在 `.env` 里填好图片接口和代码接口配置。微信 token 可以先留空，容器会自动进入扫码绑定。

## 当前启动流程

执行：

```sh
sh deploy.sh up
```

主机上的 `deploy.sh` 会做这些事：

1. 检查是否存在 `docker`
2. 检查可用的 `docker compose` 或 `docker-compose`
3. 创建 `.router-data/`
4. 执行 `docker compose up -d --build`

容器启动后，`docker-entrypoint.sh` 会继续做这些事：

1. 加载 `router.env.sh`
2. 读取 `.env` 传入的环境变量
3. 读取 `.router-data/router.env.local.sh` 中保存过的本地值
4. 创建 `.router-data/` 和 `.router-data/.cc-router-cache/`
5. 校验图片接口和代码接口是否已配置
6. 自动补全 `WEIXIN_ALLOW_FROM`、`WEIXIN_CDN_BASE_URL`、`WEIXIN_ACCOUNT_ID`
7. 如果没有 `WEIXIN_TOKEN`，生成二维码并执行微信扫码绑定
8. 将扫码得到的 token 和当前 API 配置保存到 `.router-data/router.env.local.sh`
9. 生成 `.router-data/config.route.toml`
10. 启动 `cc-connect --config /app/.router-data/config.route.toml --force`

脚本会检查 Docker / Compose 是否存在，但不会自动安装 Docker。Node.js 和 `cc-connect@beta` 会在 Docker 镜像构建时安装到容器里。

## 常用命令

```sh
sh deploy.sh up       # 构建镜像并后台启动
sh deploy.sh logs     # 查看实时日志
sh deploy.sh restart  # 重新构建并强制重启容器
sh deploy.sh stop     # 停止并删除容器
sh deploy.sh status   # 查看容器状态
sh deploy.sh shell    # 进入容器 shell
```

## 首次部署

### 1. 准备配置

```sh
cp .env.example .env
vi .env
```

至少需要填写：

```env
OPENAI_API_KEY=
ROUTER_IMAGE_ENDPOINT=
ROUTER_CODE_ENDPOINT=
```

也可以不用统一的 `OPENAI_API_KEY`，改为分别填写：

```env
ROUTER_IMAGE_API_KEY=
ROUTER_CODE_API_KEY=
```

`WEIXIN_TOKEN` 第一次可以留空。

### 2. 启动服务

```sh
sh deploy.sh up
sh deploy.sh logs
```

如果微信还没绑定，日志会提示二维码路径：

```text
.router-data/weixin-qr.png
```

在 Mac 上打开这张图片，用微信扫码。扫码后如果没有立刻拿到 token，先给机器人发一条微信消息，再执行：

```sh
sh deploy.sh restart
```

### 3. 绑定成功后

绑定成功后，容器会把保存值写到：

```text
.router-data/router.env.local.sh
```

之后再启动会优先复用保存值。`.env` 中的非空配置会覆盖保存值。

## 环境变量

### 微信

```env
WEIXIN_TOKEN=
WEIXIN_ALLOW_FROM=*
WEIXIN_ADMIN_FROM=
WEIXIN_ACCOUNT_ID=
WEIXIN_SETUP_TIMEOUT=600
WEIXIN_FORCE_REBIND=
WEIXIN_CDN_BASE_URL=https://novac2c.cdn.weixin.qq.com/c2c
```

- `WEIXIN_TOKEN`：微信登录 token，首次运行可以留空。
- `WEIXIN_ALLOW_FROM`：允许访问的微信来源，默认 `*`。
- `WEIXIN_ADMIN_FROM`：管理员微信来源。
- `WEIXIN_ACCOUNT_ID`：账号 ID，留空时会从 token 前缀自动补全。
- `WEIXIN_FORCE_REBIND`：设为 `1` 时强制重新扫码绑定。
- `WEIXIN_CDN_BASE_URL`：微信媒体直连上传的 CDN 协议基址。

### 图片接口

```env
ROUTER_IMAGE_API_KEY=
ROUTER_IMAGE_ENDPOINT=https://your-api.example/v1
ROUTER_IMAGE_PROVIDER=OpenAI
ROUTER_IMAGE_MODEL=gpt-image-2
ROUTER_IMAGE_API=auto
ROUTER_IMAGE_SIZE=
ROUTER_IMAGE_QUALITY=high
ROUTER_IMAGE_CONTEXT_TTL_MINS=30
ROUTER_IMAGE_CONTEXT_MAX=4
```

`ROUTER_IMAGE_API=auto` 会根据是否带输入图片自动选择生成或编辑。最近图片上下文默认保留 30 分钟，最多 4 张。

### 代码接口

```env
ROUTER_CODE_API_KEY=
ROUTER_CODE_ENDPOINT=https://your-api.example/v1/responses
ROUTER_CODE_PROVIDER=OpenAI
ROUTER_CODE_MODEL=gpt-5.5
ROUTER_CODE_TEMPERATURE=0.2
ROUTER_CODE_MAX_OUTPUT_TOKENS=
ROUTER_CODE_REASONING_EFFORT=
```

## 微信媒体直连

当前版本不启动本地媒体代理，也不再使用微信代理变量。

容器生成的路由配置中固定为：

```toml
cdn_base_url = "${WEIXIN_CDN_BASE_URL}"
proxy = ""
```

默认值是：

```text
https://novac2c.cdn.weixin.qq.com/c2c
```

这个地址不是网页入口，浏览器直接打开出现 404 是正常的。真正的上传和下载地址会由微信协议动态生成。

## 图片附件编辑

发送图片附件时，路由器会先把图片保存为最近图片上下文。如果后续消息包含编辑语义，会自动走图片编辑链路。

示例：

```text
把这张图改成证件照
去掉水印
换成白色背景
裁剪一下
调亮一点
修一修这张照片
```

当前支持的编辑输入方式：

- 当前微信消息里的图片附件
- 最近图片上下文
- OpenAI Responses `input_image`
- OpenAI Images `/v1/images/edits`
- 自定义 HTTP 接口 `image_paths`

如果只发送图片但没有明确编辑要求，路由器只记录上下文，不主动回复。

## 微信里可用命令

```text
/route status
/route auto
/route image
/route code
```

中文别名：

```text
当前模式
图片模式
图像模式
生图模式
生成图片模式
绘图模式
画图模式
代码模式
问答模式
通用问答模式
文本模式
自动模式
智能模式
智能路由
```

默认是 `auto` 模式：

- 图片生成、图片编辑、海报、头像、插画等请求走图片链路
- 普通问答和代码请求走代码链路

## 查看当前保存的 API

保存文件在 Mac 主机目录：

```text
.router-data/router.env.local.sh
```

也可以进入容器查看：

```sh
sh deploy.sh shell
cat /app/.router-data/router.env.local.sh
```

这个文件可能包含微信 token 和 API Key，不要提交到 Git。

## 重新绑定微信

修改 `.env`：

```env
WEIXIN_FORCE_REBIND=1
```

然后执行：

```sh
sh deploy.sh restart
sh deploy.sh logs
```

绑定完成后，把 `WEIXIN_FORCE_REBIND` 清空，再重启一次。

## 运行时文件

所有运行时数据都放在 `.router-data/`：

```text
.router-data/config.route.toml
.router-data/.weixin-setup.toml
.router-data/weixin-qr.png
.router-data/router.env.local.sh
.router-data/.cc-router-state.json
.router-data/.cc-router-decisions.log
.router-data/.cc-router-cache/recent-images.json
.router-data/weixin/
.router-data/sessions/
```

## 文件说明

- `deploy.sh`：Mac 服务器一键部署和运行入口
- `Dockerfile`：构建 Node.js + `cc-connect` 运行镜像
- `docker-compose.yml`：容器配置和环境变量映射
- `docker-entrypoint.sh`：容器内启动、扫码、配置生成和服务启动逻辑
- `.env.example`：环境变量模板
- `router.mjs`：核心智能路由逻辑
- `router.sh`：agent 入口
- `router.route.sh`：路由入口
- `router.control.sh`：`/route` 控制入口
- `router.env.sh`：公共环境加载脚本
- `cc-connect.route.sh`：直接启动 `cc-connect` 的兼容入口

## 常见问题

### 启动提示 Docker 不存在

先在 Mac 服务器安装 Docker Desktop 或 Docker Engine，然后重新执行：

```sh
sh deploy.sh up
```

### 日志提示缺少 API 配置

说明 `.env` 里还没填完整。补齐 API Key 和 endpoint 后执行：

```sh
sh deploy.sh restart
```

### 没看到二维码

先看日志：

```sh
sh deploy.sh logs
```

二维码默认在：

```text
.router-data/weixin-qr.png
```

### 扫码后没有 token

先给机器人发一条微信消息，再执行：

```sh
sh deploy.sh restart
```

### 图片返回失败

先确认图片接口支持当前模型和协议。路由器会自动适配：

- 无输入图：图片生成
- 有输入图并带编辑语义：图片编辑
- OpenAI Images：自动使用 `/v1/images/edits`
- OpenAI Responses：发送 `input_image`
- 自定义 HTTP：发送 `image_paths`
