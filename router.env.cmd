@ECHO off
if exist "%~dp0router.env.local.cmd" call "%~dp0router.env.local.cmd"
REM This file loads the local auto-generated values first.
REM The launcher will create or refresh router.env.local.cmd for you.
REM Uncomment and edit these only if you want to manage values manually.
REM set "WEIXIN_TOKEN=your_weixin_token"
REM set "WEIXIN_ALLOW_FROM=your_allow_from_id"
REM set "WEIXIN_ADMIN_FROM=your_admin_weixin_id"
REM set "WEIXIN_ACCOUNT_ID=your_account_id"
REM set "ROUTER_IMAGE_API_KEY=your_image_key"
REM set "ROUTER_IMAGE_ENDPOINT=https://your-image-api.example/v1/images"
REM set "ROUTER_IMAGE_PROVIDER=openai-responses"
REM set "ROUTER_IMAGE_MODEL=gpt-5"
REM set "ROUTER_IMAGE_API=auto"
REM set "ROUTER_CODE_API_KEY=your_code_key"
REM set "ROUTER_CODE_ENDPOINT=https://your-code-api.example/v1/responses"
REM set "ROUTER_CODE_PROVIDER=openai-responses"
REM set "ROUTER_CODE_MODEL=gpt-5"
