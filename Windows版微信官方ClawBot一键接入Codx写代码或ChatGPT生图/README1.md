# 微信入口智能路由

这是一个用于微信消息接入第三方 API 的智能路由项目。项目通过 `cc-connect` 接入微信，把收到的消息交给本地路由器判断：普通问答、代码类请求走代码接口，生图、修图、图片附件编辑走图片接口。

项目同时提供 Windows 一键版和 Mac Docker 版，方便在不同环境下部署运行。

## 核心功能

- 微信消息接入第三方 API
- 自动区分普通问答、代码请求、图片生成和图片编辑
- 支持微信图片附件作为编辑上下文
- 支持最近图片上下文，默认保留 30 分钟、最多 4 张
- 支持 OpenAI Responses `input_image`
- 支持 OpenAI Images `/v1/images/edits`
- 支持自定义 HTTP 图片接口的 `image_paths`
- 图片返回微信时使用微信 CDN 直连上传
- 不依赖本地媒体代理
- 支持 `/route` 命令在微信里切换路由模式

## 两个版本

### Windows 一键版

Windows 版适合在普通 Windows 电脑上直接运行。

推荐入口：

```cmd
launch-router.cmd
```

第一次运行会自动完成：

1. 切换控制台到 UTF-8
2. 检查 Node.js 18+
3. 没有 Node.js 时自动下载到 `.router-data\nodejs\`
4. 检查并安装 `cc-connect@beta`
5. 生成实际运行配置 `config.route.toml`
6. 扫微信二维码绑定
7. 填写图片 API 和代码 API
8. 保存配置到 `router.env.local.cmd`
9. 启动微信路由服务

Windows 版不需要提前手工安装 Node.js、`cc-connect`、Codex 或 Claude Code。适合本地电脑、测试机和需要双击启动的场景。

### Mac Docker 版

Mac 版适合部署在 Mac mini、Mac Studio、Mac 服务器或 Linux 服务器上，通过 Docker 后台运行。

推荐入口：

```sh
cp .env.example .env
vi .env
sh deploy.sh up
sh deploy.sh logs
```

Mac Docker 版启动流程：

1. 检查 Docker 和 Docker Compose
2. 构建 Docker 镜像
3. 容器内安装 Node.js 运行环境和 `cc-connect@beta`
4. 创建 `.router-data/` 运行目录
5. 读取 `.env` 和 `.router-data/router.env.local.sh`
6. 如果没有微信 token，生成二维码并扫码绑定
7. 生成 `.router-data/config.route.toml`
8. 启动 `cc-connect` 路由服务

Mac Docker 版只要求主机提前安装 Docker。Node.js 和 `cc-connect` 都在容器中处理，适合长期后台运行和服务器部署。

## 运行链路

```text
微信消息
  -> cc-connect
  -> router.mjs
  -> 自动判断图片链路或代码链路
  -> 第三方 API
  -> cc-connect
  -> 微信
```

图片发送链路使用微信媒体直连：

```text
cc-connect
  -> WEIXIN_CDN_BASE_URL
  -> 微信图片 CDN
```

默认 CDN 基址：

```text
https://novac2c.cdn.weixin.qq.com/c2c
```

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

- 图片生成、海报、头像、插画、修图、裁剪、去水印等请求走图片链路
- 普通问答、代码、文本分析等请求走代码链路

## 图片附件编辑

发送图片附件后，再发送类似下面的指令，会自动进入图片编辑链路：

```text
把这张图改成证件照
去掉水印
换成白色背景
裁剪一下
调亮一点
修一修这张照片
```

如果只发送图片但没有明确编辑要求，路由器会保存图片上下文，不主动回复。

## API 配置

可以使用统一 Key：

```env
OPENAI_API_KEY=
```

也可以分别配置图片和代码接口：

```env
ROUTER_IMAGE_API_KEY=
ROUTER_IMAGE_ENDPOINT=
ROUTER_IMAGE_MODEL=

ROUTER_CODE_API_KEY=
ROUTER_CODE_ENDPOINT=
ROUTER_CODE_MODEL=
```

保存后的本地配置属于敏感文件，不要提交到 GitHub。

Windows 版常见敏感文件：

```text
router.env.local.cmd
config.route.toml
.cc-router-state.json
.cc-router-decisions.log
.cc-router-cache/
.router-data/
```

Mac Docker 版常见敏感文件：

```text
.env
.router-data/router.env.local.sh
.router-data/config.route.toml
.router-data/.cc-router-state.json
.router-data/.cc-router-decisions.log
.router-data/.cc-router-cache/
.router-data/weixin/
.router-data/sessions/
```

## 适用场景

- 把微信作为个人 AI 助手入口
- 同时接入文本模型和图片模型
- 在微信里直接生成图片、修改图片、处理附件
- 在 Windows 电脑上快速双击启动
- 在 Mac 服务器上用 Docker 长期后台运行

## 版本选择

| 使用环境 | 推荐版本 | 启动方式 |
| --- | --- | --- |
| Windows 电脑 | Windows 一键版 | 双击 `launch-router.cmd` |
| 新 Windows 电脑 | Windows 一键版 | 自动补全 Node.js 和 `cc-connect` |
| Mac mini / Mac Studio | Mac Docker 版 | `sh deploy.sh up` |
| Linux 服务器 | Mac Docker 版 | `sh deploy.sh up` |
| 长期后台运行 | Mac Docker 版 | Docker Compose |

## 注意事项

- 第一次运行需要扫码登录微信。
- API Key、微信 token、本地运行数据不要提交到 GitHub。
- 微信 CDN 基址不是浏览器页面，直接打开出现 404 是正常的。
- 图片编辑是否成功取决于你配置的图片接口是否支持输入图片。
- Mac Docker 版会检测 Docker，但不会自动安装 Docker。
- Windows 一键版会自动准备 Node.js 和 `cc-connect`。

## 快速对照

Windows：

```cmd
launch-router.cmd
```

Mac / Linux：

```sh
cp .env.example .env
vi .env
sh deploy.sh up
sh deploy.sh logs
```
