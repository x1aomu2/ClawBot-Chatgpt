# 微信入口智能路由

这是一个面向 Windows 的微信消息路由方案。它把微信官方插件`ClawBot`接入 `cc-connect`，再按内容自动分流到图片接口或代码接口。按照`Chatgpt API`来写的第三方API和生图

# 模型说明

图片接口模型填`gpt-image-2`
代码接口模型填`gpt-5.5`

## 这个仓库做什么

- `launch-router.cmd` 是唯一推荐的一键入口
- 首次运行会自动准备 Node.js 18+ 和 `cc-connect@beta`
- 启动时会自动生成/重写 `config.route.toml`
- 首次运行会通过微信二维码完成绑定，并保存本地 token
- 图片和代码接口配置会保存到 `router.env.local.cmd`
- 微信里可以随时查看或切换路由模式
- 关闭启动窗口后，会自动清理本次启动产生的子进程

## 主要文件

- `launch-router.cmd`：一键启动入口
- `launch-router.ps1`：初始化、扫码、写入本地配置、启动路由
- `launch-router.watchdog.ps1`：窗口关闭后，负责清理相关子进程
- `router.mjs`：核心路由逻辑
- `router.cmd`：核心入口，读取 `router.env.cmd` 后进入 `router.mjs`
- `router.route.cmd`：路由专用入口，使用 `config.route.toml`
- `router.control.cmd`：控制入口，处理 `/route` 这类命令
- `router.env.cmd`：公共模板，优先加载 `router.env.local.cmd`
- `router.env.local.cmd`：本地自动生成的真实配置，不要提交到 Git
- `config.toml`：基础配置模板
- `config.route.toml`：启动器生成的实际路由配置
- `cc-connect.route.cmd`：直接启动路由的兼容入口
- `codex.cmd` / `codex-router*.cmd`：历史兼容壳

## 快速开始

直接双击：

```cmd
launch-router.cmd
```

启动器会按当前机器状态自动处理这些事：

1. 检查 Node.js 是否为 18+；如果没有，会下载安装到 `.router-data\nodejs\`
2. 检查 `cc-connect` 是否已安装且版本足够；如果不够，会自动安装 `cc-connect@beta`
3. 每次启动都重写 `config.route.toml`，所以项目换目录后不用手改路径
4. 如果还没有本地配置，会提示你填写图片和代码 API
5. 如果还没有微信 token，会走二维码登录流程
6. 最后启动 `cc-connect` 路由服务

第一次扫码后：

- `weixin-qr.png` 会生成并自动打开
- 扫码成功后会自动提取 token
- 如果还是没拿到 token，先在微信里给机器人发一条消息，再重新运行一次

## 已有配置时

如果已经存在 `router.env.local.cmd`，启动器会先问你：

- `U`：直接使用保存的配置
- `C`：重新填写图片和代码 API
- `R`：重新绑定微信，会清理本地微信缓存并强制重新扫码

通常：

- 只改 API，选 `C`
- 微信 token 失效或换号，选 `R`
- 没有改动，选 `U` 或直接回车

## 微信里怎么用

支持这些命令：

- `/route status`
- `/route auto`
- `/route image`
- `/route code`

也支持中文别名：

- `当前模式`
- `图片模式`
- `图像模式`
- `生图模式`
- `生成图片模式`
- `绘图模式`
- `画图模式`
- `代码模式`
- `问答模式`
- `通用问答模式`
- `自动模式`
- `智能模式`
- `智能路由`

### 自动路由规则

在 `auto` 模式下，带有图片语义的请求会走图片链路，例如包含“图片”“生图”“画图”“image”“poster”“illustration”等内容；其余默认走代码链路。

### 查看当前状态

直接发：

```text
当前模式
```

或者：

```text
/route status
```

返回里会显示当前路由模式，以及图片和代码后端的简要信息。

## 配置说明

`router.env.cmd` 会先加载 `router.env.local.cmd`，所以本地真实配置都放在 `router.env.local.cmd`。

### 微信相关

- `WEIXIN_TOKEN`
- `WEIXIN_ALLOW_FROM`
- `WEIXIN_ADMIN_FROM`
- `WEIXIN_ACCOUNT_ID`

### 图片链路

- `ROUTER_IMAGE_API_KEY`
- `ROUTER_IMAGE_ENDPOINT`
- `ROUTER_IMAGE_PROVIDER`
- `ROUTER_IMAGE_MODEL`
- `ROUTER_IMAGE_API`
- `ROUTER_IMAGE_SIZE`
- `ROUTER_IMAGE_QUALITY`

### 代码链路

- `ROUTER_CODE_API_KEY`
- `ROUTER_CODE_ENDPOINT`
- `ROUTER_CODE_PROVIDER`
- `ROUTER_CODE_MODEL`
- `ROUTER_CODE_TEMPERATURE`
- `ROUTER_CODE_MAX_OUTPUT_TOKENS`
- `ROUTER_CODE_REASONING_EFFORT`

### 启动器会让你填什么

当前启动器会交互式询问这些项：

- 图片 API key
- 图片 API endpoint
- 图片 provider
- 图片 model
- 代码 API key
- 代码 API endpoint
- 代码 provider
- 代码 model
- 图片尺寸
- 图片质量
- 代码温度
- 最大输出长度

其中：

- `ROUTER_IMAGE_API` 默认是 `auto`
- `ROUTER_IMAGE_SIZE` 可以留空，表示使用接口默认值
- `ROUTER_IMAGE_QUALITY` 默认是 `high`
- `ROUTER_CODE_TEMPERATURE` 默认是 `0.2`
- `ROUTER_CODE_MAX_OUTPUT_TOKENS` 可以留空，表示不限制

### 图片接口怎么请求

当 `ROUTER_IMAGE_PROVIDER` 选择 OpenAI 兼容模式，且设置了 `ROUTER_IMAGE_ENDPOINT` 时：

- `ROUTER_IMAGE_API=auto`：自动判断走 `/v1/images/generations` 还是 `/v1/responses`
- `ROUTER_IMAGE_API=images`：强制走 `/v1/images/generations`
- `ROUTER_IMAGE_API=responses`：强制走 `/v1/responses` 的 `image_generation` 工具

如果不是 OpenAI 兼容模式，就会把 `prompt`、`model`、`size`、`quality` 直接发给你自己的图片接口。

接口返回可以是：

- 二进制图片
- JSON 里的 `image_base64`
- JSON 里的 `b64_json`
- JSON 里的 `url`
- JSON 里的 `image_url`

### 代码接口怎么请求

代码链路目前只走第三方 HTTP 或 OpenAI 兼容接口，不走本地 CLI。

OpenAI 兼容模式会发送：

- `model`
- `instructions`
- `input`
- `max_output_tokens`
- `reasoning.effort`（如果设置了 `ROUTER_CODE_REASONING_EFFORT`）

普通 HTTP 模式会发送：

- `prompt`
- `model`
- `system_prompt`
- `temperature`
- `max_output_tokens`

接口返回可以是：

- 纯文本
- `output_text`
- `text`
- `result`
- `content`
- `choices`
- `output`
- `data`
- `message`

## 运行时文件

这些文件是运行时产物，默认不应该提交到仓库：

- `.router-data/`
- `.cc-router-state.json`
- `.cc-router-decisions.log`
- `.cc-router-cache/`
- `weixin-qr.png`
- `.weixin-setup.toml`
- `.weixin-setup.runtime.log`
- `weixin-setup.out.log`
- `weixin-setup.err.log`
- `cc-connect-route.out.log`
- `cc-connect-route.err.log`
- `.router-data/launch-router.pids`

## 常见问题

### 没看到二维码

- 看看 `weixin-qr.png` 是否已经生成
- 启动器会自动尝试打开图片
- 如果自动打开失败，手动打开 `weixin-qr.png`

### 扫码后没有 token

- 先在微信里给机器人发一条消息
- 然后重新运行 `launch-router.cmd`

### 想重新绑定微信

- 重新运行 `launch-router.cmd`
- 选择 `R`

### 想改 API

- 重新运行 `launch-router.cmd`
- 选择 `C`
- 直接回车可以保留已经填过的值

### 图片返回 503

- 说明已经走到图片链路了
- 通常是图片接口限流、模型不支持、接口路径不兼容，或者服务端暂时不可用

### 关闭窗口后进程还在

- 正常情况下会自动清理
- 如果异常退出很多次，可以删掉 `.router-data/` 后重新启动

## 日常使用

平时你基本只需要记住一句话：

```cmd
launch-router.cmd
```

其他登录、保存、切换和清理，都已经交给脚本处理了。
