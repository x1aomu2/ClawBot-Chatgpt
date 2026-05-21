#!/usr/bin/env node

import { spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const STATE_FILE = path.join(ROOT, ".cc-router-state.json");
const DECISION_LOG_FILE = path.join(ROOT, ".cc-router-decisions.log");
const CACHE_DIR = path.join(ROOT, ".cc-router-cache");
const IMAGE_CONTEXT_FILE = path.join(CACHE_DIR, "recent-images.json");
const IMAGE_CONTEXT_TTL_MS =
  (Number.parseInt(process.env.ROUTER_IMAGE_CONTEXT_TTL_MINS || "30", 10) || 30) *
  60 *
  1000;
const MAX_IMAGE_CONTEXT_ITEMS =
  Number.parseInt(process.env.ROUTER_IMAGE_CONTEXT_MAX || "4", 10) || 4;
const CC_CONNECT_CMD = process.env.ROUTER_CC_CONNECT_CMD || "cc-connect.cmd";
const CONFIG_FILE = process.env.ROUTER_CONFIG_FILE || path.join(ROOT, "config.toml");
const DATA_DIR = process.env.ROUTER_DATA_DIR || path.join(ROOT, ".router-data");
const PROJECT_NAME = process.env.ROUTER_PROJECT_NAME || "test";

function envOrDefault(name, fallback) {
  return Object.prototype.hasOwnProperty.call(process.env, name)
    ? process.env[name]
    : fallback;
}

const DEFAULT_STATE = {
  route_mode: "auto",
  thread_id: null,
  image_provider: process.env.ROUTER_IMAGE_PROVIDER || "openai-responses",
  image_model: process.env.ROUTER_IMAGE_MODEL || "gpt-5",
  image_endpoint: process.env.ROUTER_IMAGE_ENDPOINT || "",
  image_api_key:
    process.env.ROUTER_IMAGE_API_KEY || process.env.OPENAI_API_KEY || "",
  image_api: process.env.ROUTER_IMAGE_API || "auto",
  image_size: envOrDefault("ROUTER_IMAGE_SIZE", ""),
  image_quality: process.env.ROUTER_IMAGE_QUALITY || "high",
  code_provider: process.env.ROUTER_CODE_PROVIDER || "openai-responses",
  code_model: process.env.ROUTER_CODE_MODEL || "gpt-5",
  code_endpoint: process.env.ROUTER_CODE_ENDPOINT || "",
  code_api_key:
    process.env.ROUTER_CODE_API_KEY || process.env.OPENAI_API_KEY || "",
  code_temperature: process.env.ROUTER_CODE_TEMPERATURE || "0.2",
  code_max_output_tokens: envOrDefault("ROUTER_CODE_MAX_OUTPUT_TOKENS", ""),
  code_reasoning_effort: process.env.ROUTER_CODE_REASONING_EFFORT || "",
  code_system_prompt:
    process.env.ROUTER_CODE_SYSTEM_PROMPT ||
    "你是一个微信入口的中文助手。回答要自然、简洁、直接。普通问候直接用一句自然回应，不要自称 OpenAI 训练的模型，不要提模型身份或训练背景，除非用户明确询问。编程问题要可运行、可落地，必要时先给结论再给步骤。",
};

const IMAGE_WORDS = [
  "\u56fe\u7247",
  "\u56fe\u50cf",
  "\u6d77\u62a5",
  "\u63d2\u753b",
  "\u7acb\u7ed8",
  "\u539f\u753b",
  "\u4eba\u8bbe",
  "\u89d2\u8272\u8bbe\u8ba1",
  "\u89d2\u8272\u56fe",
  "\u8bbe\u5b9a\u56fe",
  "\u58c1\u7eb8",
  "\u5934\u50cf",
  "\u5c01\u9762",
  "banner",
  "poster",
  "illustration",
  "image",
  "img",
  "\u751f\u6210\u56fe",
  "\u751f\u6210\u56fe\u7247",
  "\u753b\u56fe",
  "\u753b\u4e00\u5f20",
  "\u753b\u5f20",
  "\u7ed8\u56fe",
  "\u7ed8\u5236",
  "\u51fa\u56fe",
  "\u751f\u56fe",
];

const IMAGE_PATTERNS = [
  /^(\/img|\/image|\/draw|\/art)\b/i,
  /(?:\u753b|\u7ed8\u5236|\u4f5c\u753b|\u753b\u51fa|\u753b\u4e2a|\u753b\u5f20|\u753b\u4e00\u5f20|\u7ed8\u56fe|\u51fa\u56fe|\u751f\u56fe)/i,
  /(?:\u751f\u6210|\u505a|make|create)\s*(?:\u4e00|1)?(?:\u5f20|\u5e45|\u5957|\u4e2a).*(?:\u56fe|\u56fe\u7247|\u56fe\u50cf|\u6d77\u62a5|\u63d2\u753b|\u58c1\u7eb8|\u5934\u50cf|\u5c01\u9762|\u7acb\u7ed8|\u539f\u753b|\u4eba\u8bbe|\u89d2\u8272|\u4eba\u7269|\u573a\u666f|logo|banner|poster|illustration|image)/i,
  /(?:\u4eba\u7269|\u89d2\u8272).*(?:\u7acb\u7ed8|\u539f\u753b|\u8bbe\u5b9a\u56fe|\u63d2\u753b|\u4eba\u8bbe)/i,
];

const IMAGE_EDIT_PATTERNS = [
  /(?:这张|这幅|这两张|这几张|原图|图片|照片|图像|图中|图里|素材|截图).*(?:修图|精修|优化|美化|增强|提亮|调色|处理|修复|去除|删除|替换|保留|换成|改成|改为|变成|变为|换背景|改背景|去背景|去水印|抠图|裁剪|裁切|旋转|缩放|放大|缩小|降噪|锐化|模糊|清晰|上色|风格化|卡通化|动漫化|证件照|加字|加logo|打码|擦除|复原|修补)/i,
  /(?:修图|精修|优化|美化|增强|提亮|调色|处理|修复|去除|删除|替换|保留|换成|改成|改为|变成|变为|换背景|改背景|去背景|去水印|抠图|裁剪|裁切|旋转|缩放|放大|缩小|降噪|锐化|模糊|清晰|上色|风格化|卡通化|动漫化|证件照|加字|加logo|打码|擦除|复原|修补).*(?:图|图片|照片|图像|原图|素材|截图)/i,
  /(?:edit|modify|retouch|enhance|upscale|crop|resize|remove|replace|background|watermark|mosaic|blur|sharpen|colorize|restore).*(?:image|photo|picture|img|pic)/i,
  /(?:image|photo|picture|img|pic).*(?:edit|modify|retouch|enhance|upscale|crop|resize|remove|replace|background|watermark|mosaic|blur|sharpen|colorize|restore)/i,
];

const IMAGE_EDIT_WORDS = [
  "修图",
  "精修",
  "美化",
  "提亮",
  "调色",
  "换背景",
  "改背景",
  "去背景",
  "去水印",
  "抠图",
  "裁剪",
  "裁切",
  "旋转",
  "缩放",
  "放大",
  "缩小",
  "降噪",
  "锐化",
  "模糊",
  "清晰",
  "上色",
  "风格化",
  "卡通化",
  "动漫化",
  "证件照",
  "加字",
  "加logo",
  "打码",
  "擦除",
  "复原",
  "修补",
  "retouch",
  "upscale",
  "crop",
  "resize",
  "background",
  "watermark",
  "mosaic",
  "blur",
  "sharpen",
  "colorize",
  "restore",
];

main().catch((err) => {
  console.error(err?.stack || err?.message || String(err));
  process.exit(1);
});

async function main() {
  const [role = "agent", ...argv] = process.argv.slice(2);
  if (role === "control") {
    await handleControl(argv);
    return;
  }
  await handleAgent(argv);
}

async function handleControl(argv) {
  const action = normalizeRouteAction(argv.join(" ") || "status");
  const state = await loadState();

  if (action === "status" || action === "show") {
    console.log(formatStatusText(state));
    return;
  }

  if (["auto", "image", "code"].includes(action)) {
    state.route_mode = action;
    await saveState(state);
    console.log(formatStatusText(state, `\u5df2\u5207\u6362\u5230 ${action} \u8def\u7531\u6a21\u5f0f`));
    return;
  }

  console.log("Usage: /route status|auto|image|code");
  process.exitCode = 1;
}

async function handleAgent(argv) {
  const input = await extractAgentInput(argv);
  const prompt = input.prompt;
  let state = await loadState();

  if (input.threadId && input.threadId !== state.thread_id) {
    state.thread_id = input.threadId;
    await saveState(state);
  }

  const inputImagePaths = await normalizeInputImagePaths(input.imagePaths);
  if (inputImagePaths.length > 0) {
    await setRecentImages(inputImagePaths, state);
  }

  const routeAction = normalizeRouteAction(prompt);
  if (routeAction === "status" || looksLikeStatusQuery(prompt)) {
    emitText(formatStatusText(state), state);
    return;
  }
  if (["auto", "image", "code"].includes(routeAction)) {
    state.route_mode = routeAction;
    await saveState(state);
    emitText(formatStatusText(state, `\u5df2\u5207\u6362\u5230 ${routeAction} \u8def\u7531\u6a21\u5f0f`), state);
    return;
  }

  if (inputImagePaths.length > 0 && isImageAttachmentOnlyPrompt(prompt)) {
    emitNoReply(state);
    return;
  }

  state = await loadState();
  let decision = determineRoute(prompt, state);
  const hasImageContext = inputImagePaths.length > 0 || (await hasRecentImages(state));
  if (
    decision.route === "code" &&
    hasImageContext &&
    looksLikeImageEditRequest(prompt)
  ) {
    decision = { route: "image", reason: "image_edit_context_match" };
  }
  await logRouteDecision(prompt, state, decision);
  const route = decision.route;
  if (route === "image") {
    try {
      const editImagePaths = await resolveImagesForImageRequest(
        inputImagePaths,
        prompt,
        state,
      );
      const imagePath = await generateImage(prompt, state, editImagePaths);
      await sendImageBack(imagePath, state);
      await setRecentImages([imagePath], state);
      emitNoReply(state);
      return;
    } catch (err) {
      emitText(
        `\u56fe\u7247\u94fe\u8def\u5931\u8d25\uff1a${err?.message || String(err)}`,
        state,
      );
      return;
    }
  }

  try {
    const answer = await generateCodeResponse(prompt, state, argv);
    emitText(sanitizeAssistantText(answer), state);
  } catch (err) {
    emitText(
      `\u4ee3\u7801\u94fe\u8def\u5931\u8d25\uff1a${err?.message || String(err)}`,
      state,
    );
  }
}

async function extractAgentInput(argv) {
  const valueFlags = new Set([
    "-c",
    "--config",
    "-m",
    "--model",
    "--local-provider",
    "-p",
    "--profile",
    "--profile-v2",
    "-s",
    "--sandbox",
    "-C",
    "--cd",
    "--add-dir",
    "-a",
    "--ask-for-approval",
    "--enable",
    "--disable",
    "--output-schema",
    "--color",
    "-o",
    "--output-last-message",
  ]);

  const skipFlags = new Set([
    "exec",
    "e",
    "--json",
    "--full-auto",
    "--ephemeral",
    "--skip-git-repo-check",
    "--ignore-user-config",
    "--ignore-rules",
    "--dangerously-bypass-approvals-and-sandbox",
    "--dangerously-bypass-hook-trust",
    "--strict-config",
    "--oss",
    "--search",
    "--no-alt-screen",
  ]);

  const promptParts = [];
  const imagePaths = [];
  let threadId = "";
  let waitingForResumeThread = false;
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "resume" || arg === "--resume") {
      waitingForResumeThread = true;
      continue;
    }
    if (waitingForResumeThread && looksLikeThreadId(arg)) {
      threadId = arg;
      waitingForResumeThread = false;
      continue;
    }
    if (arg === "-i" || arg === "--image") {
      if (i + 1 < argv.length) {
        imagePaths.push(argv[i + 1]);
        i += 1;
      }
      continue;
    }
    if (arg.startsWith("--image=")) {
      imagePaths.push(arg.slice("--image=".length));
      continue;
    }
    if (skipFlags.has(arg)) {
      continue;
    }
    if (valueFlags.has(arg)) {
      i += 1;
      continue;
    }
    if (arg === "-" || arg.startsWith("-")) {
      continue;
    }
    promptParts.push(arg);
  }

  if (promptParts.length > 0) {
    return { prompt: promptParts.join(" ").trim(), threadId, imagePaths };
  }

  if (!process.stdin.isTTY) {
    const stdin = await readStdin();
    if (stdin.trim()) {
      return { prompt: stdin.trim(), threadId, imagePaths };
    }
  }

  return { prompt: "", threadId, imagePaths };
}

async function extractPrompt(argv) {
  const input = await extractAgentInput(argv);
  return input.prompt;
}

function looksLikeThreadId(value) {
  return /^[0-9a-f][0-9a-f-]{15,}$/i.test(String(value || ""));
}

async function generateCodeResponse(prompt, state, argv) {
  const provider = normalizeRemoteProvider(state.code_provider);
  if (state.code_endpoint && ["openai", "openai-responses", "responses"].includes(provider)) {
    return await generateCodeTextViaOpenAI(prompt, state, state.code_endpoint);
  }
  if (state.code_endpoint) {
    return await generateCodeTextViaHttp(prompt, state);
  }
  return await generateCodeTextViaOpenAI(prompt, state);
}

async function generateCodeTextViaOpenAI(prompt, state, endpoint = "") {
  if (!state.code_api_key) {
    throw new Error("\u7f3a\u5c11 OPENAI_API_KEY \u6216 ROUTER_CODE_API_KEY");
  }
  if (!endpoint) {
    throw new Error("\u7f3a\u5c11 ROUTER_CODE_ENDPOINT");
  }

  const body = {
    model: state.code_model,
    instructions: state.code_system_prompt,
    input: prompt,
  };
  const maxOutputTokens = parsePositiveInteger(state.code_max_output_tokens);
  if (maxOutputTokens) {
    body.max_output_tokens = maxOutputTokens;
  }
  if (state.code_reasoning_effort) {
    body.reasoning = { effort: state.code_reasoning_effort };
  }

  const resolvedEndpoint = resolveResponsesEndpoint(endpoint, "ROUTER_CODE_ENDPOINT");
  const response = await fetch(resolvedEndpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${state.code_api_key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(
      `OpenAI \u4ee3\u7801\u63a5\u53e3\u5931\u8d25: ${response.status} ${response.statusText}`,
    );
  }

  const json = await response.json();
  const text = extractTextContent(json);
  if (!text) {
    throw new Error("\u6ca1\u6709\u5728 OpenAI \u54cd\u5e94\u91cc\u627e\u5230\u6587\u672c\u5185\u5bb9");
  }
  return sanitizeAssistantText(text);
}

function normalizeRemoteProvider(provider) {
  const normalized = String(provider || "openai-responses").toLowerCase();
  if (normalized === "codex") {
    return "openai-responses";
  }
  return normalized;
}

async function generateCodeTextViaHttp(prompt, state) {
  if (!state.code_endpoint) {
    throw new Error("\u7f3a\u5c11 ROUTER_CODE_ENDPOINT");
  }
  const headers = {
    "Content-Type": "application/json",
  };
  if (state.code_api_key) {
    headers.Authorization = `Bearer ${state.code_api_key}`;
  }

  const payload = {
    prompt,
    model: state.code_model,
    system_prompt: state.code_system_prompt,
    temperature: parseNumber(state.code_temperature),
    max_output_tokens: parsePositiveInteger(state.code_max_output_tokens),
  };

  const response = await fetch(state.code_endpoint, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    throw new Error(`\u4ee3\u7801\u63a5\u53e3\u5931\u8d25: ${response.status} ${response.statusText}`);
  }

  const contentType = response.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    const json = await response.json();
    const text = extractTextContent(json);
  if (text) {
      return sanitizeAssistantText(text);
    }
    throw new Error("\u4ee3\u7801\u63a5\u53e3 JSON \u91cc\u6ca1\u6709\u627e\u5230\u6587\u672c\u5185\u5bb9");
  }

  const text = (await response.text()).trim();
  if (!text) {
    throw new Error("\u4ee3\u7801\u63a5\u53e3\u8fd4\u56de\u7a7a\u5185\u5bb9");
  }
  try {
    const parsed = JSON.parse(text);
    const extracted = extractTextContent(parsed);
    if (extracted) {
      return sanitizeAssistantText(extracted);
    }
  } catch {
    // Plain text response; fall through.
  }
  return sanitizeAssistantText(text);
}

function extractTextContent(json) {
  if (!json) return "";
  if (typeof json === "string") {
    return json;
  }
  if (typeof json.output_text === "string") {
    return json.output_text;
  }
  if (typeof json.text === "string") {
    return json.text;
  }
  if (typeof json.result === "string") {
    return json.result;
  }
  if (typeof json.content === "string") {
    return json.content;
  }
  if (Array.isArray(json.choices)) {
    for (const choice of json.choices) {
      const text = extractTextFromChoice(choice);
      if (text) {
        return text;
      }
    }
  }
  if (Array.isArray(json.output)) {
    const text = collectTextFromItems(json.output);
    if (text) {
      return text;
    }
  }
  if (Array.isArray(json.data)) {
    for (const item of json.data) {
      const text = extractTextContent(item);
      if (text) {
        return text;
      }
    }
  }
  if (json.message) {
    const text = extractTextContent(json.message);
    if (text) {
      return text;
    }
  }
  if (Array.isArray(json.content)) {
    const text = collectTextFromItems(json.content);
    if (text) {
      return text;
    }
  }
  return "";
}

function extractTextFromChoice(choice) {
  if (!choice) return "";
  if (typeof choice.text === "string") {
    return choice.text;
  }
  if (typeof choice.content === "string") {
    return choice.content;
  }
  if (Array.isArray(choice.content)) {
    return collectTextFromItems(choice.content);
  }
  if (typeof choice.message?.content === "string") {
    return choice.message.content;
  }
  if (Array.isArray(choice.message?.content)) {
    return collectTextFromItems(choice.message.content);
  }
  if (typeof choice.delta?.content === "string") {
    return choice.delta.content;
  }
  if (Array.isArray(choice.delta?.content)) {
    return collectTextFromItems(choice.delta.content);
  }
  return "";
}

function collectTextFromItems(items) {
  const parts = [];
  for (const item of items) {
    if (!item) {
      continue;
    }
    if (typeof item === "string") {
      parts.push(item);
      continue;
    }
    if (typeof item.text === "string") {
      parts.push(item.text);
      continue;
    }
    if (typeof item.content === "string") {
      parts.push(item.content);
      continue;
    }
    if (typeof item.output_text === "string") {
      parts.push(item.output_text);
      continue;
    }
    if (Array.isArray(item.content)) {
      const nested = collectTextFromItems(item.content);
      if (nested) {
        parts.push(nested);
      }
    }
  }
  return parts.join("").trim();
}

function parseNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function parsePositiveInteger(value) {
  const parsed = Number.parseInt(String(value), 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
}

function decideRoute(prompt, state) {
  return determineRoute(prompt, state).route;
}

function determineRoute(prompt, state) {
  if (!prompt) {
    const route = state.route_mode === "image" ? "image" : "code";
    return { route, reason: "empty_prompt" };
  }
  if (looksLikeStatusQuery(prompt)) {
    return { route: "status", reason: "status_query" };
  }
  if (state.route_mode === "image") {
    return { route: "image", reason: "forced_image_mode" };
  }
  if (state.route_mode === "code") {
    return { route: "code", reason: "forced_code_mode" };
  }
  if (looksLikeImageRequest(prompt)) {
    return { route: "image", reason: "auto_image_match" };
  }
  return { route: "code", reason: "auto_code_fallback" };
}

function looksLikeImageRequest(text) {
  const lower = text.toLowerCase();
  if (IMAGE_PATTERNS.some((pattern) => pattern.test(lower))) {
    return true;
  }
  return IMAGE_WORDS.some((word) => lower.includes(word.toLowerCase()));
}

function looksLikeImageEditRequest(text) {
  const value = String(text || "").trim().toLowerCase();
  if (!value) {
    return false;
  }
  if (IMAGE_EDIT_PATTERNS.some((pattern) => pattern.test(value))) {
    return true;
  }
  return IMAGE_EDIT_WORDS.some((word) => value.includes(word.toLowerCase()));
}

function isImageAttachmentOnlyPrompt(prompt) {
  const compact = String(prompt || "")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
  return (
    !compact ||
    compact === "please analyze the attached image(s)." ||
    compact === "please analyze the attached image." ||
    compact === "analyze the attached image(s)." ||
    compact === "analyze the attached image."
  );
}

function normalizeRouteAction(text) {
  const raw = String(text || "").trim();
  if (!raw) {
    return "status";
  }

  const lower = raw.toLowerCase().replace(/^\/?route\b/i, "").trim();
  const compact = lower.replace(/[\s，。,.!！?？:："'“”‘’`]+/g, "");

  if (["status", "show", "mode", "mode?", "\u5f53\u524d\u6a21\u5f0f", "\u73b0\u5728\u4ec0\u4e48\u6a21\u5f0f", "\u5f53\u524d\u8def\u7531", "\u8def\u7531\u72b6\u6001"].includes(compact)) {
    return "status";
  }
  if (["image", "img", "draw", "art", "\u56fe\u7247\u6a21\u5f0f", "\u56fe\u50cf\u6a21\u5f0f", "\u751f\u56fe\u6a21\u5f0f", "\u751f\u6210\u56fe\u6a21\u5f0f", "\u751f\u6210\u56fe\u7247\u6a21\u5f0f", "\u7ed8\u56fe\u6a21\u5f0f", "\u753b\u56fe\u6a21\u5f0f"].includes(compact)) {
    return "image";
  }
  if (["code", "coding", "text", "chat", "\u4ee3\u7801\u6a21\u5f0f", "\u95ee\u7b54\u6a21\u5f0f", "\u901a\u7528\u95ee\u7b54\u6a21\u5f0f", "\u6587\u672c\u6a21\u5f0f"].includes(compact)) {
    return "code";
  }
  if (["auto", "smart", "\u81ea\u52a8\u6a21\u5f0f", "\u667a\u80fd\u6a21\u5f0f", "\u81ea\u52a8\u8def\u7531", "\u667a\u80fd\u8def\u7531", "\u667a\u80fd\u5207\u6362"].includes(compact)) {
    return "auto";
  }

  if (/(?:\u5207\u6362|\u8fdb\u5165|\u4f7f\u7528|\u6539\u6210|\u6362\u6210|\u8bbe\u4e3a|\u6253\u5f00|\u5f00\u542f).*(?:\u56fe\u7247|\u56fe\u50cf|\u751f\u56fe|\u751f\u6210\u56fe|\u7ed8\u56fe|\u753b\u56fe).*(?:\u6a21\u5f0f|\u94fe\u8def)/i.test(compact)) {
    return "image";
  }
  if (/(?:\u5207\u6362|\u8fdb\u5165|\u4f7f\u7528|\u6539\u6210|\u6362\u6210|\u8bbe\u4e3a|\u6253\u5f00|\u5f00\u542f).*(?:\u4ee3\u7801|\u95ee\u7b54|\u6587\u672c).*(?:\u6a21\u5f0f|\u94fe\u8def)/i.test(compact)) {
    return "code";
  }
  if (/(?:\u5207\u6362|\u8fdb\u5165|\u4f7f\u7528|\u6539\u6210|\u6362\u6210|\u8bbe\u4e3a|\u6253\u5f00|\u5f00\u542f).*(?:\u81ea\u52a8|\u667a\u80fd).*(?:\u6a21\u5f0f|\u94fe\u8def|\u8def\u7531)/i.test(compact)) {
    return "auto";
  }

  return "";
}

function looksLikeStatusQuery(text) {
  const lower = text.toLowerCase().trim();
  if (
    lower === "\u5f53\u524d\u6a21\u5f0f" ||
    lower === "\u73b0\u5728\u4ec0\u4e48\u6a21\u5f0f" ||
    lower === "\u5f53\u524d\u8def\u7531" ||
    lower === "\u8def\u7531\u72b6\u6001" ||
    lower === "mode?" ||
    lower === "status?"
  ) {
    return true;
  }
  return /(?:current|now|status|mode|route|当前|现在|路由|模式).*(?:what|which|state|status|是什么|哪种|多少)/i.test(
    lower,
  );
}

function sanitizeAssistantText(text) {
  const lines = String(text || "")
    .replace(/\r\n/g, "\n")
    .split("\n")
    .filter((line) => {
      const trimmed = line.trim();
      if (!trimmed) {
        return true;
      }
      const normalized = trimmed
        .replace(/^[*`_~>\-\s]+/, "")
        .replace(/[*`_~>\-\s]+$/, "")
        .trim();
      if (isStatusFooterLine(trimmed) || isStatusFooterLine(normalized)) {
        return false;
      }
      if (isPathFooterLine(trimmed) || isPathFooterLine(normalized)) {
        return false;
      }
      return true;
    });

  return lines.join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

function isStatusFooterLine(text) {
  const compact = String(text || "")
    .replace(/\s+/g, " ")
    .trim();
  return /^(?:\u5269\u4f59|remaining)\s*\d+%/i.test(compact) && /(?:projects\/test|\/projects\/test)/i.test(compact);
}

function isPathFooterLine(text) {
  const compact = String(text || "")
    .replace(/\s+/g, " ")
    .trim();
  if (!compact) {
    return false;
  }

  const stripped = compact
    .replace(/^[*`_~>\-\s]+/, "")
    .replace(/[*`_~>\-\s]+$/, "")
    .trim();

  return /^(?:\.{3}|\u2026|\u22ef)?\/?projects\/test\/?$/i.test(stripped);
}
function formatStatusText(state, prefix = "") {
  const parts = [];
  if (prefix) {
    parts.push(prefix);
  }
  parts.push(`\u5f53\u524d\u8def\u7531\u6a21\u5f0f\uff1a${state.route_mode}`);
  if (state.route_mode === "auto") {
    parts.push(
      "\u81ea\u52a8\u5224\u522b\uff1a\u56fe\u7247\u7c7b\u8bf7\u6c42\u8d70\u56fe\u7247\u94fe\u8def\uff0c\u5176\u4f59\u76f4\u63a5\u8d70\u4ee3\u7801 API",
    );
  }
  parts.push("");
  parts.push(`\u56fe\u50cf\u540e\u7aef\uff1a${describeBackend(state, "image")}`);
  parts.push(`\u4ee3\u7801\u540e\u7aef\uff1a${describeBackend(state, "code")}`);
  parts.push("");
  parts.push(`\u67e5\u8be2\u6307\u4ee4\uff1a/route status \u6216 \u201c\u5f53\u524d\u6a21\u5f0f\u201d`);
  parts.push(`\u5207\u6362\u6307\u4ee4\uff1a/route auto\u3001/route image\u3001/route code\uff0c\u6216 \u81ea\u52a8\u6a21\u5f0f\u3001\u751f\u56fe\u6a21\u5f0f\u3001\u4ee3\u7801\u6a21\u5f0f`);
  return parts.join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

function describeBackend(state, kind) {
  const model = state[`${kind}_model`] || "";
  if (model) {
    return model;
  }
  return state[`${kind}_provider`] || "\u672a\u914d\u7f6e";
}

async function logRouteDecision(prompt, state, decision) {
  const entry = {
    time: new Date().toISOString(),
    mode: state.route_mode || DEFAULT_STATE.route_mode,
    route: decision.route,
    reason: decision.reason,
    prompt: shorten(prompt || "", 120),
  };

  try {
    await fs.appendFile(DECISION_LOG_FILE, `${JSON.stringify(entry)}\n`, "utf8");
  } catch {
  }
}

function emitText(text, state) {
  const threadId = ensureThreadId(state);
  writeJson({ type: "thread.started", thread_id: threadId });
  writeJson({ type: "turn.started" });
  writeJson({
    type: "item.completed",
    item: { id: "item_0", type: "agent_message", text },
  });
  writeJson({
    type: "turn.completed",
    usage: {
      input_tokens: 0,
      cached_input_tokens: 0,
      output_tokens: 0,
      reasoning_output_tokens: 0,
    },
  });
}

function emitNoReply(state) {
  emitText("NO_REPLY", state);
}

async function normalizeInputImagePaths(imagePaths = []) {
  const normalized = [];
  const seen = new Set();
  for (const rawPath of imagePaths) {
    const resolved = await resolveInputImagePath(rawPath);
    if (!resolved || seen.has(resolved)) {
      continue;
    }
    seen.add(resolved);
    normalized.push(resolved);
  }
  return normalized;
}

async function resolveInputImagePath(rawPath) {
  const raw = String(rawPath || "").trim();
  if (!raw) {
    return "";
  }

  let candidate = raw;
  if (/^file:\/\//i.test(candidate)) {
    try {
      candidate = fileURLToPath(candidate);
    } catch {
      return "";
    }
  }

  const candidates = path.isAbsolute(candidate)
    ? [candidate]
    : [path.resolve(process.cwd(), candidate), path.resolve(ROOT, candidate)];
  for (const item of candidates) {
    try {
      if (existsSync(item)) {
        return item;
      }
    } catch {
    }
  }
  return "";
}

async function setRecentImages(imagePaths, state) {
  const normalized = await normalizeInputImagePaths(imagePaths);
  if (normalized.length === 0) {
    return [];
  }

  const now = Date.now();
  const items = normalized.slice(0, MAX_IMAGE_CONTEXT_ITEMS).map((imagePath) => ({
    path: imagePath,
    time: now,
  }));
  const context = await readImageContext();
  const key = getImageContextKey(state);
  context.threads = context.threads || {};
  context.threads[key] = items;
  context.global = items;
  await writeImageContext(context);
  return normalized;
}

async function hasRecentImages(state) {
  const images = await getRecentImages(state);
  return images.length > 0;
}

async function getRecentImages(state) {
  const context = await readImageContext();
  const key = getImageContextKey(state);
  const threadItems = Array.isArray(context.threads?.[key]) ? context.threads[key] : [];
  const globalItems = Array.isArray(context.global) ? context.global : [];
  const now = Date.now();
  const seen = new Set();
  const result = [];
  for (const item of [...threadItems, ...globalItems]) {
    const imagePath = String(item?.path || "");
    const time = Number(item?.time || 0);
    if (!imagePath || seen.has(imagePath)) {
      continue;
    }
    if (time && now - time > IMAGE_CONTEXT_TTL_MS) {
      continue;
    }
    if (!existsSync(imagePath)) {
      continue;
    }
    seen.add(imagePath);
    result.push(imagePath);
    if (result.length >= MAX_IMAGE_CONTEXT_ITEMS) {
      break;
    }
  }
  return result;
}

async function resolveImagesForImageRequest(inputImagePaths, prompt, state) {
  if (inputImagePaths.length > 0) {
    return inputImagePaths;
  }
  if (!looksLikeImageEditRequest(prompt)) {
    return [];
  }
  return await getRecentImages(state);
}

function getImageContextKey(state) {
  return String(state?.thread_id || "global");
}

async function readImageContext() {
  try {
    const raw = await fs.readFile(IMAGE_CONTEXT_FILE, "utf8");
    const parsed = raw.trim() ? JSON.parse(raw) : {};
    return {
      global: Array.isArray(parsed.global) ? parsed.global : [],
      threads: parsed.threads && typeof parsed.threads === "object" ? parsed.threads : {},
    };
  } catch {
    return { global: [], threads: {} };
  }
}

async function writeImageContext(context) {
  await fs.mkdir(CACHE_DIR, { recursive: true });
  const pruned = pruneImageContext(context);
  const tmpFile = `${IMAGE_CONTEXT_FILE}.${process.pid}.${Date.now()}.tmp`;
  await fs.writeFile(tmpFile, `${JSON.stringify(pruned, null, 2)}\n`, "utf8");
  await fs.rename(tmpFile, IMAGE_CONTEXT_FILE);
}

function pruneImageContext(context) {
  const now = Date.now();
  const pruneItems = (items) =>
    (Array.isArray(items) ? items : [])
      .filter((item) => {
        const imagePath = String(item?.path || "");
        const time = Number(item?.time || 0);
        return imagePath && existsSync(imagePath) && (!time || now - time <= IMAGE_CONTEXT_TTL_MS);
      })
      .slice(0, MAX_IMAGE_CONTEXT_ITEMS);

  const threads = {};
  for (const [key, value] of Object.entries(context.threads || {})) {
    const items = pruneItems(value);
    if (items.length > 0) {
      threads[key] = items;
    }
  }

  return {
    global: pruneItems(context.global),
    threads,
  };
}

async function generateImage(prompt, state, inputImagePaths = []) {
  await fs.mkdir(CACHE_DIR, { recursive: true });
  const imagePath = path.join(
    CACHE_DIR,
    `${new Date().toISOString().replace(/[:.]/g, "-")}-${crypto.randomUUID()}.png`,
  );
  const imageBytes = await generateImageBytes(prompt, state, inputImagePaths);
  await fs.writeFile(imagePath, imageBytes);
  return imagePath;
}

async function generateImageBytes(prompt, state, inputImagePaths = []) {
  const provider = normalizeRemoteProvider(state.image_provider);
  if (state.image_endpoint && ["openai", "openai-responses", "responses"].includes(provider)) {
    return await generateImageBytesViaOpenAI(prompt, state, state.image_endpoint, inputImagePaths);
  }
  if (state.image_endpoint) {
    return await generateImageBytesViaHttp(prompt, state, inputImagePaths);
  }
  return await generateImageBytesViaOpenAI(prompt, state, "", inputImagePaths);
}

function resolveResponsesEndpoint(endpoint, missingLabel = "ROUTER_CODE_ENDPOINT") {
  if (!endpoint) {
    throw new Error(`\u7f3a\u5c11 ${missingLabel}`);
  }

  const trimmed = String(endpoint).trim();
  try {
    const url = new URL(trimmed);
    const pathname = url.pathname.replace(/\/+$/, "");
    if (pathname.endsWith("/responses")) {
      return url.toString();
    }
    if (pathname.endsWith("/v1")) {
      url.pathname = `${pathname}/responses`;
    } else {
      url.pathname = `${pathname}/v1/responses`;
    }
    return url.toString();
  } catch {
    return trimmed;
  }
}

async function generateImageBytesViaOpenAI(prompt, state, endpoint = "", inputImagePaths = []) {
  if (chooseOpenAIImageApi(state) === "images") {
    return await generateImageBytesViaOpenAIImages(prompt, state, endpoint, inputImagePaths);
  }
  return await generateImageBytesViaOpenAIResponses(prompt, state, endpoint, inputImagePaths);
}

function chooseOpenAIImageApi(state) {
  const mode = String(state.image_api || "auto").toLowerCase();
  const provider = String(state.image_provider || "").toLowerCase();
  const model = String(state.image_model || "").toLowerCase();

  if (["responses", "openai-responses"].includes(mode)) {
    return "responses";
  }
  if (["images", "image", "openai-images"].includes(mode)) {
    return "images";
  }
  if (["images", "image", "openai-images"].includes(provider)) {
    return "images";
  }
  if (model.startsWith("gpt-image-") || model.startsWith("dall-e-")) {
    return "images";
  }
  return "responses";
}

function resolveImagesEndpoint(endpoint) {
  if (!endpoint) {
    throw new Error("\u7f3a\u5c11 ROUTER_IMAGE_ENDPOINT");
  }

  const trimmed = String(endpoint).trim();
  try {
    const url = new URL(trimmed);
    const pathname = url.pathname.replace(/\/+$/, "");
    if (pathname.endsWith("/images/generations")) {
      return url.toString();
    }
    if (pathname.endsWith("/images")) {
      url.pathname = `${pathname}/generations`;
    } else if (pathname.endsWith("/v1")) {
      url.pathname = `${pathname}/images/generations`;
    } else if (pathname.endsWith("/v1/responses")) {
      url.pathname = pathname.replace(/\/responses$/, "/images/generations");
    } else if (pathname.endsWith("/responses")) {
      url.pathname = pathname.replace(/\/responses$/, "/images/generations");
    } else {
      url.pathname = `${pathname}/v1/images/generations`;
    }
    return url.toString();
  } catch {
    return trimmed;
  }
}

function resolveImageEditsEndpoint(endpoint) {
  if (!endpoint) {
    throw new Error("\u7f3a\u5c11 ROUTER_IMAGE_ENDPOINT");
  }

  const trimmed = String(endpoint).trim();
  try {
    const url = new URL(trimmed);
    const pathname = url.pathname.replace(/\/+$/, "");
    if (pathname.endsWith("/images/edits")) {
      return url.toString();
    }
    if (pathname.endsWith("/images/generations")) {
      url.pathname = pathname.replace(/\/generations$/, "/edits");
    } else if (pathname.endsWith("/images")) {
      url.pathname = `${pathname}/edits`;
    } else if (pathname.endsWith("/v1")) {
      url.pathname = `${pathname}/images/edits`;
    } else if (pathname.endsWith("/v1/responses")) {
      url.pathname = pathname.replace(/\/responses$/, "/images/edits");
    } else if (pathname.endsWith("/responses")) {
      url.pathname = pathname.replace(/\/responses$/, "/images/edits");
    } else {
      url.pathname = `${pathname}/v1/images/edits`;
    }
    return url.toString();
  } catch {
    return trimmed;
  }
}

async function generateImageBytesViaOpenAIResponses(
  prompt,
  state,
  endpoint = "",
  inputImagePaths = [],
) {
  if (!state.image_api_key) {
    throw new Error("\u7f3a\u5c11 OPENAI_API_KEY \u6216 ROUTER_IMAGE_API_KEY");
  }

  const imageTool = { type: "image_generation" };
  if (state.image_size) {
    imageTool.size = state.image_size;
  }
  if (state.image_quality) {
    imageTool.quality = state.image_quality;
  }
  if (inputImagePaths.length > 0) {
    imageTool.action = "edit";
  }

  let input = prompt;
  if (inputImagePaths.length > 0) {
    const content = [{ type: "input_text", text: prompt }];
    for (const imagePath of inputImagePaths) {
      content.push({
        type: "input_image",
        image_url: await readImageAsDataUrl(imagePath),
      });
    }
    input = [{ role: "user", content }];
  }

  const resolvedEndpoint = resolveResponsesEndpoint(endpoint, "ROUTER_IMAGE_ENDPOINT");
  const response = await fetch(resolvedEndpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${state.image_api_key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: state.image_model,
      input,
      tools: [imageTool],
    }),
  });

  if (!response.ok) {
    throw new Error(
      `OpenAI \u56fe\u7247\u63a5\u53e3\u5931\u8d25: ${response.status} ${response.statusText} api=responses endpoint=${resolvedEndpoint} model=${state.image_model}`,
    );
  }

  const json = await response.json();
  const imageBase64 = extractImageBase64(json);
  if (!imageBase64) {
    throw new Error("\u6ca1\u6709\u5728 OpenAI \u54cd\u5e94\u91cc\u627e\u5230\u56fe\u7247\u5185\u5bb9");
  }
  return decodeBase64Image(imageBase64);
}

async function generateImageBytesViaOpenAIImages(
  prompt,
  state,
  endpoint = "",
  inputImagePaths = [],
) {
  if (inputImagePaths.length > 0) {
    return await generateImageBytesViaOpenAIImageEdits(
      prompt,
      state,
      endpoint,
      inputImagePaths,
    );
  }

  if (!state.image_api_key) {
    throw new Error("\u7f3a\u5c11 OPENAI_API_KEY \u6216 ROUTER_IMAGE_API_KEY");
  }

  const payload = {
    model: state.image_model,
    prompt,
  };
  if (state.image_size) {
    payload.size = state.image_size;
  }
  if (state.image_quality) {
    payload.quality = state.image_quality;
  }

  const resolvedEndpoint = resolveImagesEndpoint(endpoint);
  const response = await fetch(resolvedEndpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${state.image_api_key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    throw new Error(
      `OpenAI \u56fe\u7247\u63a5\u53e3\u5931\u8d25: ${response.status} ${response.statusText} api=images endpoint=${resolvedEndpoint} model=${state.image_model}`,
    );
  }

  const json = await response.json();
  const imageBase64 = extractImageBase64(json);
  const imageUrl = extractImageUrl(json);
  if (imageBase64) {
    return decodeBase64Image(imageBase64);
  }
  if (imageUrl) {
    return await downloadImage(imageUrl);
  }
  throw new Error("\u6ca1\u6709\u5728 OpenAI Images \u54cd\u5e94\u91cc\u627e\u5230\u56fe\u7247\u5185\u5bb9");
}

async function generateImageBytesViaOpenAIImageEdits(
  prompt,
  state,
  endpoint = "",
  inputImagePaths = [],
) {
  if (!state.image_api_key) {
    throw new Error("\u7f3a\u5c11 OPENAI_API_KEY \u6216 ROUTER_IMAGE_API_KEY");
  }
  if (inputImagePaths.length === 0) {
    throw new Error("\u6ca1\u6709\u53ef\u7528\u7684\u539f\u56fe\uff0c\u65e0\u6cd5\u8fdb\u884c\u56fe\u7247\u4fee\u6539");
  }

  const form = new FormData();
  form.append("model", state.image_model);
  form.append("prompt", prompt);
  if (state.image_size) {
    form.append("size", state.image_size);
  }
  if (state.image_quality) {
    form.append("quality", state.image_quality);
  }

  const fieldName = inputImagePaths.length === 1 ? "image" : "image[]";
  for (const imagePath of inputImagePaths.slice(0, 16)) {
    const imageBytes = await fs.readFile(imagePath);
    const mimeType = detectImageMimeType(imagePath, imageBytes);
    const blob = new Blob([imageBytes], { type: mimeType });
    form.append(fieldName, blob, path.basename(imagePath));
  }

  const resolvedEndpoint = resolveImageEditsEndpoint(endpoint);
  const response = await fetch(resolvedEndpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${state.image_api_key}`,
    },
    body: form,
  });

  if (!response.ok) {
    throw new Error(
      `OpenAI \u56fe\u7247\u7f16\u8f91\u63a5\u53e3\u5931\u8d25: ${response.status} ${response.statusText} api=images.edits endpoint=${resolvedEndpoint} model=${state.image_model}`,
    );
  }

  const json = await response.json();
  const imageBase64 = extractImageBase64(json);
  const imageUrl = extractImageUrl(json);
  if (imageBase64) {
    return decodeBase64Image(imageBase64);
  }
  if (imageUrl) {
    return await downloadImage(imageUrl);
  }
  throw new Error("\u6ca1\u6709\u5728 OpenAI Images Edits \u54cd\u5e94\u91cc\u627e\u5230\u56fe\u7247\u5185\u5bb9");
}

async function generateImageBytesViaHttp(prompt, state, inputImagePaths = []) {
  const headers = {
    "Content-Type": "application/json",
  };
  if (state.image_api_key) {
    headers.Authorization = `Bearer ${state.image_api_key}`;
  }

  const payload = {
    prompt,
    model: state.image_model,
  };
  if (inputImagePaths.length > 0) {
    payload.images = await Promise.all(
      inputImagePaths.map(async (imagePath) => await readImageAsDataUrl(imagePath)),
    );
    payload.image_paths = inputImagePaths;
  }
  if (state.image_size) {
    payload.size = state.image_size;
  }
  if (state.image_quality) {
    payload.quality = state.image_quality;
  }

  const response = await fetch(state.image_endpoint, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    throw new Error(`\u56fe\u7247\u63a5\u53e3\u5931\u8d25: ${response.status} ${response.statusText}`);
  }

  const contentType = response.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    const json = await response.json();
    const imageBase64 = extractImageBase64(json);
    const imageUrl = extractImageUrl(json);
    if (imageBase64) {
      return decodeBase64Image(imageBase64);
    }
    if (imageUrl) {
      return await downloadImage(imageUrl);
    }
    throw new Error("\u56fe\u7247\u63a5\u53e3 JSON \u91cc\u6ca1\u6709\u627e\u5230\u56fe\u7247\u5185\u5bb9");
  }

  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.length === 0) {
    throw new Error("\u56fe\u7247\u63a5\u53e3\u8fd4\u56de\u7a7a\u5185\u5bb9");
  }
  return buffer;
}

function extractImageBase64(json) {
  if (!json) return "";
  if (typeof json === "string") {
    return json.replace(/^data:image\/[a-z]+;base64,/, "");
  }
  if (typeof json.result === "string") {
    return json.result.replace(/^data:image\/[a-z]+;base64,/, "");
  }
  if (typeof json.image_base64 === "string") {
    return json.image_base64;
  }
  if (typeof json.b64_json === "string") {
    return json.b64_json;
  }
  if (Array.isArray(json.data) && json.data.length > 0) {
    const first = json.data[0];
    if (typeof first?.b64_json === "string") {
      return first.b64_json;
    }
    if (typeof first?.base64 === "string") {
      return first.base64;
    }
  }
  if (Array.isArray(json.output)) {
    for (const item of json.output) {
      if (item?.type === "image_generation_call" && typeof item.result === "string") {
        return item.result;
      }
      if (item?.type === "image_generation_call" && typeof item.image_base64 === "string") {
        return item.image_base64;
      }
    }
  }
  return "";
}

function extractImageUrl(json) {
  if (!json) return "";
  if (typeof json === "string" && /^https?:\/\//i.test(json)) {
    return json;
  }
  if (typeof json.url === "string") return json.url;
  if (typeof json.image_url === "string") return json.image_url;
  if (Array.isArray(json.data) && json.data.length > 0) {
    const first = json.data[0];
    if (typeof first?.url === "string") return first.url;
    if (typeof first?.image_url === "string") return first.image_url;
  }
  return "";
}

async function downloadImage(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`\u4e0b\u8f7d\u56fe\u7247\u5931\u8d25: ${response.status} ${response.statusText}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

async function readImageAsDataUrl(imagePath) {
  const imageBytes = await fs.readFile(imagePath);
  const mimeType = detectImageMimeType(imagePath, imageBytes);
  return `data:${mimeType};base64,${imageBytes.toString("base64")}`;
}

function detectImageMimeType(imagePath, imageBytes = Buffer.alloc(0)) {
  const ext = path.extname(imagePath).toLowerCase();
  if (ext === ".jpg" || ext === ".jpeg") return "image/jpeg";
  if (ext === ".webp") return "image/webp";
  if (ext === ".gif") return "image/gif";
  if (ext === ".png") return "image/png";
  if (imageBytes.length >= 12 && imageBytes.slice(0, 4).toString("hex") === "89504e47") {
    return "image/png";
  }
  if (imageBytes.length >= 3 && imageBytes.slice(0, 3).toString("hex") === "ffd8ff") {
    return "image/jpeg";
  }
  if (imageBytes.length >= 12 && imageBytes.slice(8, 12).toString("ascii") === "WEBP") {
    return "image/webp";
  }
  return "image/png";
}

function decodeBase64Image(value) {
  const clean = value.replace(/^data:image\/[a-z]+;base64,/, "");
  return Buffer.from(clean, "base64");
}

async function sendImageBack(imagePath, state) {
  const sessionKey = await findLatestCcConnectSessionKey(state?.thread_id || "");
  const args = [
    "send",
    "--data-dir",
    DATA_DIR,
    "-p",
    PROJECT_NAME,
    "--session",
    sessionKey,
    "--image",
    imagePath,
  ];

  await new Promise((resolve, reject) => {
    const child = spawn(CC_CONNECT_CMD, args, {
      shell: true,
      stdio: "ignore",
    });
    child.on("error", reject);
    child.on("exit", (code, signal) => {
      if (signal) {
        reject(new Error(`cc-connect send \u4e2d\u65ad\u4e8e ${signal}`));
        return;
      }
      if (code && code !== 0) {
        reject(new Error(`cc-connect send \u9000\u51fa\u7801 ${code}`));
        return;
      }
      resolve();
    });
  });
}

async function findLatestCcConnectSessionKey(threadId = "") {
  const configured = process.env.ROUTER_CC_CONNECT_SESSION_KEY || "";
  if (configured.trim()) {
    return configured.trim();
  }

  const sessionsDir = path.join(DATA_DIR, "sessions");
  let files = [];
  try {
    files = await fs.readdir(sessionsDir);
  } catch {
    throw new Error(`\u627e\u4e0d\u5230 cc-connect sessions \u76ee\u5f55: ${sessionsDir}`);
  }

  const candidates = [];
  for (const file of files) {
    if (!file.endsWith(".json")) {
      continue;
    }
    const fullPath = path.join(sessionsDir, file);
    try {
      const stat = await fs.stat(fullPath);
      candidates.push({ fullPath, mtimeMs: stat.mtimeMs });
    } catch {
    }
  }

  candidates.sort((a, b) => b.mtimeMs - a.mtimeMs);
  if (threadId) {
    for (const candidate of candidates) {
      try {
        const parsed = JSON.parse(await fs.readFile(candidate.fullPath, "utf8"));
        const sessions = parsed?.sessions || {};
        const active = parsed?.active_session || {};
        for (const [sessionKey, sessionId] of Object.entries(active)) {
          if (sessions?.[sessionId]?.agent_session_id === threadId) {
            return sessionKey;
          }
        }
      } catch {
      }
    }
  }

  for (const candidate of candidates) {
    try {
      const parsed = JSON.parse(await fs.readFile(candidate.fullPath, "utf8"));
      const active = parsed?.active_session || {};
      const keys = Object.keys(active);
      if (keys.length > 0) {
        return keys[0];
      }
    } catch {
    }
  }

  throw new Error("\u6ca1\u6709\u627e\u5230\u53ef\u7528\u7684 cc-connect \u6d3b\u52a8\u4f1a\u8bdd");
}

function shorten(text, maxLen) {
  const compact = text.replace(/\s+/g, " ").trim();
  if (compact.length <= maxLen) return compact;
  return `${compact.slice(0, maxLen - 1)}…`;
}

function ensureThreadId(state = null) {
  if (state && state.thread_id) {
    return state.thread_id;
  }
  return crypto.randomUUID().replace(/-/g, "");
}

async function loadState() {
  if (!existsSync(STATE_FILE)) {
    const fresh = {
      ...DEFAULT_STATE,
      thread_id: crypto.randomUUID().replace(/-/g, ""),
    };
    await saveState(fresh);
    return fresh;
  }

  let parsed = {};
  try {
    const raw = await fs.readFile(STATE_FILE, "utf8");
    parsed = raw.trim() ? JSON.parse(raw) : {};
  } catch {
    parsed = {};
  }

  return {
    ...DEFAULT_STATE,
    route_mode: parsed.route_mode || DEFAULT_STATE.route_mode,
    thread_id: parsed.thread_id || crypto.randomUUID().replace(/-/g, ""),
  };
}

async function saveState(state) {
  const persisted = {
    route_mode: state.route_mode || DEFAULT_STATE.route_mode,
    thread_id: state.thread_id || crypto.randomUUID().replace(/-/g, ""),
  };
  await fs.mkdir(ROOT, { recursive: true });
  const tmpFile = `${STATE_FILE}.${process.pid}.${Date.now()}.tmp`;
  await fs.writeFile(tmpFile, `${JSON.stringify(persisted, null, 2)}\n`, "utf8");
  await fs.rename(tmpFile, STATE_FILE);
}

function writeJson(value) {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}
