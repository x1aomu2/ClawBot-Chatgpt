# 微信官方 ClawBot 一键接入第三方 API 路由

这是一个面向 Windows 的微信消息路由项目。它通过 `cc-connect` 接入微信，再把收到的消息交给本地 `router.mjs` 自动判断：普通问答 / 代码走代码接口，生图 / 修图走图片接口。

当前版本的重点：

- 新电脑不需要提前安装 Node.js、cc-connect、Codex 或 Claude Code
- 双击 `launch-router.cmd` 会自动准备运行环境
- `cc-connect` 只负责微信收发，真正业务路由在 `router.mjs`
- 代码和生图都走你自己配置的第三方 API
- 图片返回微信时使用微信 CDN 直连上传，不再走本地媒体代理

## 快速开始

直接双击：

```cmd
launch-router.cmd
```

第一次运行会自动完成：

1. 切换控制台到 UTF-8
2. 检查 Node.js 18+
3. 没有 Node.js 时自动下载到 `.router-data\nodejs\`
4. 检查 `cc-connect`
5. 没有或版本太旧时自动安装 `cc-connect@beta`
6. 把项目根目录加进本次进程的 PATH，让 `cc-connect` 找到本地 `codex.cmd`
7. 生成实际运行配置 `config.route.toml`
8. 扫微信二维码绑定
9. 填写图片 API 和代码 API 配置
10. 写入 `router.env.local.cmd`
11. 启动微信路由服务

## 新电脑能不能直接用

可以复制整个项目文件夹到一台刚装好的 Windows 电脑上，然后双击 `launch-router.cmd`。

需要满足：

- 电脑能联网
- PowerShell 能运行
- 可以访问 npm / Node 下载源
- 第一次运行时能扫码登录微信
- 你手里有第三方 API 的 endpoint、key、model

不需要提前手工安装：

- Node.js
- cc-connect
- OpenAI Codex
- Claude Code

如果你想少填一次 API，可以把旧电脑里的 `router.env.local.cmd` 一起复制过去。这个文件里有 API key 和微信 token，属于敏感配置，不要发给别人。微信登录状态跨电脑不一定完全可用，换电脑后通常建议重新扫码一次。

## 当前运行链路

实际链路是：

```text
微信消息
  -> cc-connect
  -> 本地 codex.cmd 兼容壳
  -> router.route.cmd
  -> router.mjs
  -> 按内容自动选择代码 API 或图片 API
  -> 结果回到 cc-connect
  -> 微信
```

注意：`config.route.toml` 里会看到：

```toml
[projects.agent]
type = "codex"
```

这里的 `codex` 只是为了兼容 `cc-connect` 的 agent 协议。项目根目录里的 `codex.cmd` 会接管这个入口，它不是在调用真实的 OpenAI Codex，也不会走 Claude Opus。

## 主要文件

- `launch-router.cmd`：推荐的一键启动入口
- `launch-router.ps1`：自动安装依赖、扫码、写配置、启动服务
- `launch-router.watchdog.ps1`：窗口关闭后清理本次启动的子进程
- `router.mjs`：核心路由逻辑，决定走代码链路还是图片链路
- `router.cmd`：通用路由入口
- `router.route.cmd`：给 `cc-connect` 使用的路由入口
- `router.control.cmd`：处理 `/route` 控制命令
- `codex.cmd`：Codex 兼容壳，给 `cc-connect` 探测和调用
- `router.env.cmd`：公共环境模板，会先加载 `router.env.local.cmd`
- `router.env.local.cmd`：启动器自动生成的真实配置，包含 token 和 API key
- `config.toml`：基础配置模板
- `config.route.toml`：启动器生成的实际运行配置
- `.router-data\`：Node、微信状态、会话状态等运行数据
- `.cc-router-cache\`：图片缓存、最近图片上下文等临时数据

## 第一次运行

双击 `launch-router.cmd` 后，按提示完成以下步骤：

1. 扫微信二维码。
2. 如果扫码后没拿到 token，先在微信里给机器人发一条消息，再重新运行一次。
3. 填写图片 API：
   - `Image API key`
   - `Image API endpoint`
   - `Image provider`
   - `Image model`
4. 填写代码 API：
   - `Code API key`
   - `Code API endpoint`
   - `Code provider`
   - `Code model`
5. 选择图片尺寸、图片质量、代码温度等选项。

保存后会生成：

```text
router.env.local.cmd
```

以后双击 `launch-router.cmd` 会默认复用这个配置。

## 修改配置

如果已经有 `router.env.local.cmd`，双击 `launch-router.cmd` 默认使用保存配置。

想手动选择配置动作，可以直接运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\launch-router.ps1
```

它会让你选择：

- `U`：使用保存配置
- `C`：重新填写图片和代码 API
- `R`：重新绑定微信，会清理本地微信缓存并重新扫码

常见选择：

- 只换 API key 或模型：选 `C`
- 微信 token 失效或换微信：选 `R`
- 没改配置：选 `U`

## 微信里怎么用

支持这些命令：

```text
/route status
/route auto
/route image
/route code
```

也支持中文别名：

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
自动模式
智能模式
智能路由
```

推荐保持 `auto`：

- 文字问答、代码问题默认走代码 API
- 生图、画图、海报、插画等请求走图片 API
- 带图片附件并要求修图时走图片编辑链路

## 图片附件和修图

用户在微信里发图片时，`router.mjs` 会把图片保存为最近图片上下文。

默认上下文：

- 保留最近 30 分钟
- 最多保留 4 张

这些请求会优先走图片编辑：

- 改背景
- 去水印
- 裁剪
- 调色
- 修图
- 美化
- 抠图
- 替换元素
- 根据刚才那张图修改

如果用户只发图片、不带有效提示词，默认不回复，只保存图片上下文。

## 第三方 API 配置

真实配置保存在 `router.env.local.cmd`。

### 图片 API

常用变量：

```cmd
set "ROUTER_IMAGE_API_KEY=your_image_key"
set "ROUTER_IMAGE_ENDPOINT=https://your-api.example/v1"
set "ROUTER_IMAGE_PROVIDER=openai-responses"
set "ROUTER_IMAGE_MODEL=gpt-image-2"
set "ROUTER_IMAGE_API=auto"
set "ROUTER_IMAGE_SIZE="
set "ROUTER_IMAGE_QUALITY=high"
```

`ROUTER_IMAGE_API` 支持：

- `auto`：自动判断协议
- `responses` / `openai-responses`：走 `/v1/responses`
- `images` / `openai-images`：走 `/v1/images/generations` 和 `/v1/images/edits`

自动匹配规则：

- 模型名以 `gpt-image-` 或 `dall-e-` 开头时，优先走 Images 协议
- endpoint 填到域名、`/v1`、`/v1/responses`、`/v1/images` 都可以，程序会自动补齐常见路径
- 有原图上下文时，Images 协议会自动切到 `/images/edits`

### 代码 / 问答 API

常用变量：

```cmd
set "ROUTER_CODE_API_KEY=your_code_key"
set "ROUTER_CODE_ENDPOINT=https://your-api.example/v1"
set "ROUTER_CODE_PROVIDER=openai-responses"
set "ROUTER_CODE_MODEL=gpt-5"
set "ROUTER_CODE_TEMPERATURE=0.2"
set "ROUTER_CODE_MAX_OUTPUT_TOKENS="
set "ROUTER_CODE_REASONING_EFFORT="
```

`ROUTER_CODE_PROVIDER` 菜单支持：

- `openai-responses`
- `anthropic`
- `gemini`
- `deepseek`
- `openrouter`
- 自定义

如果 provider 是 `openai` / `openai-responses` / `responses`，会按 OpenAI Responses 兼容格式调用。其他 provider 会走通用 HTTP JSON 格式。

## 微信 CDN 和代理说明

当前版本不启动本地媒体代理，也不走代理传图。

图片返回微信的链路是：

```text
router.mjs 生成图片
  -> cc-connect send image
  -> cc-connect 按微信协议上传到 WEIXIN_CDN_BASE_URL
  -> 微信收到图片
```

默认 CDN 基址：

```cmd
set "WEIXIN_CDN_BASE_URL=https://novac2c.cdn.weixin.qq.com/c2c"
```

`config.route.toml` 里保留：

```toml
proxy = ""
```

这是为了兼容 `cc-connect` 的配置字段，空字符串表示不使用代理。

注意：

- 直接在浏览器打开 `https://novac2c.cdn.weixin.qq.com/c2c` 出现 404 不代表上传失败
- 这个地址不是普通网页目录，而是微信 CDN 协议基址
- 实际图片上传由 `cc-connect` 结合微信 token、接口和文件路径完成
- 不建议再加本地媒体代理，当前项目里已经删除了相关代理代码

## 代理 IP 使用建议

当前运行方式默认不需要代理 IP。

如果你所在网络访问第三方 API 或 npm 很慢，可以从系统或网络层解决：

- 给 Windows 设置系统代理
- 给 npm 设置 registry，例如使用 npmmirror
- 使用能访问你第三方 API 的 endpoint

项目本身不会把图片上传切到代理。`proxy = ""` 请保持为空，除非你明确知道当前 `cc-connect` 版本支持某个代理字段并且你要让微信平台请求走代理。

## 手动测试

测试本地 Codex 兼容壳：

```cmd
codex.cmd --version
```

正常会输出类似：

```text
codex-cli 0.0.0-router
```

测试路由状态：

```cmd
codex.cmd exec --json 当前模式
```

正常会返回 JSON 事件，里面能看到当前路由模式、图片后端和代码后端。

测试控制命令：

```cmd
router.control.cmd status
router.control.cmd image
router.control.cmd code
router.control.cmd auto
```

## 常见问题

### 为什么日志里还是 agent=codex

这是正常的。

`cc-connect` 的 project 需要一个 agent 类型。这里使用 `type = "codex"` 是为了复用它的 Codex JSON 事件协议。真正被调用的是项目根目录的 `codex.cmd`，它会转到 `router.mjs`，不是外部 Codex。

### 为什么之前会走 Claude Opus

如果把 agent 改成 `claudecode`，普通问答会被 Claude Code 接管，容易走到 Claude 自己的 provider。当前版本已经改回本地 `codex.cmd` 兼容壳，业务请求由 `router.mjs` 统一分流。

### 启动时报 codex CLI not found

确认项目根目录里有：

```text
codex.cmd
```

启动器会自动把项目根目录加进本次进程 PATH。不要只运行全局 `cc-connect`，推荐用 `launch-router.cmd` 启动。

### 启动时报 cc-connect 版本太旧

重新运行：

```cmd
launch-router.cmd
```

启动器会尝试安装或更新：

```cmd
npm install -g cc-connect@beta
```

如果 npm 官方源失败，脚本会自动尝试 `registry.npmmirror.com`。

### 图片返回 503

这说明请求已经进入图片链路，但第三方图片接口没有成功返回。

重点检查：

- `ROUTER_IMAGE_ENDPOINT`
- `ROUTER_IMAGE_API_KEY`
- `ROUTER_IMAGE_MODEL`
- `ROUTER_IMAGE_API`
- 第三方接口是否支持生成或编辑
- 第三方接口是否支持当前尺寸和质量参数

### 微信 CDN 访问 404

直接打开 CDN 基址 404 是正常现象。它不是给浏览器直接访问的页面。只要微信里能收到返回图片，就说明 CDN 上传链路正常。

### 只发图片没有回复

这是预期行为。只发图片会保存为最近图片上下文，不主动回复。继续发“把背景改成白色”这类提示词，才会触发修图。

### 修改背景没有走图片链路

先确认最近 30 分钟内发过图片。如果没有可用原图，上下文为空，路由可能走普通问答。

也可以先切到图片模式：

```text
/route image
```

完成后再切回：

```text
/route auto
```

## 日志和状态文件

常用文件：

- `cc-connect-route.out.log`：`cc-connect` 标准输出
- `cc-connect-route.err.log`：`cc-connect` 错误输出
- `.cc-router-decisions.log`：每次路由判断记录
- `.cc-router-state.json`：当前路由模式和状态
- `.cc-router-cache\recent-images.json`：最近图片上下文
- `.router-data\`：微信状态、会话、Node 等运行数据

排查时优先看：

```text
cc-connect-route.out.log
cc-connect-route.err.log
.cc-router-decisions.log
```

## 安全提醒

不要把这些文件发给别人：

- `router.env.local.cmd`
- `.router-data\`
- `.cc-router-cache\`
- 各类日志里可能包含接口地址、微信 ID 或运行状态

`router.env.local.cmd` 里保存了 API key 和微信 token，属于敏感信息。

## 推荐日常用法

1. 平时双击 `launch-router.cmd`
2. 微信里保持 `/route auto`
3. 普通问题直接问
4. 生图直接说“生成一张……”
5. 修图先发图，再发修改要求
6. 换 API 时运行 `launch-router.ps1` 并选 `C`
7. 换微信或 token 失效时选 `R`
