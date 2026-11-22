# AI 角色模拟（macOS 原生 + 液态玻璃）开发计划

## Context（背景）

在空目录 `/Users/zeroneil/Desktop/ai角色formac` 从零开发一款 Mac 原生 AI 角色模拟应用。环境已确认：macOS 27.3 / arm64、Swift 6.2.3、SDK 26.2，**Liquid Glass API（`glassEffect`、`GlassEffectContainer`、`.glass` 按钮样式）全部可用**；机器未装 Xcode（仅有 Command Line Tools），因此采用 **SwiftPM 构建 + 脚本组装 .app bundle**，不用 xcodeproj。用户已确认：API 仅支持 OpenAI 兼容协议；记忆检索用关键词+重要性+时间打分（零配置）。

## 技术方案

- **纯 SwiftUI + Foundation，零第三方依赖**（避免拉包失败；SSE 流式解析手写）
- 部署目标 macOS 26.0，直接使用真实 Liquid Glass API（侧栏玻璃质感、悬浮玻璃输入条、记忆卡片玻璃卡片、`.glass`/`.glassProminent` 按钮、`glassEffectID` 形变动画）
- 数据存 `~/Library/Application Support/AIRoleSim/`（角色/记忆/会话各为 JSON；config.json 含 API Key，`chmod 600`）

## 核心功能实现

**1. 角色系统（随便创建）**：名称、emoji 头像（内置表情网格）+ 渐变色、人设描述、开场白、标签；每角色独立对话与记忆库；可随时编辑/删除/复制。

**2. API 配置（自己配置）**：设置页填 Base URL + API Key + 模型名；`GET /v1/models` 一键拉取模型列表下拉选择；温度/max tokens 滑块；Base URL 智能归一化（有无 `/v1`、有无 `/chat/completions` 都能识别，适配 DeepSeek/GLM/Kimi/OpenRouter/中转站）；Key 存本地 0600 文件。**内置演示模式开关**（无 Key 也能完整体验流式对话与记忆写入，也用于自动化验证）。

**3. 长期记忆（AI 自己写入/创建/查看）**：
- **工具调用**：模型可调用 `save_memory(content, category, importance, pinned)` 主动写入记忆、`search_memory(query)` 主动查询记忆；聊天中实时执行工具循环，气泡下方显示"🧠 记住了…"玻璃小条
- **自动注入**：每轮对话把「置顶记忆 + 按打分选取的 Top-N 相关记忆」注入系统提示（打分 = 关键词命中(中文子串/英文词元) + 重要性权重 + 时间新近衰减）；供应商不支持 tools 时自动降级重试（去掉 tools）
- **记忆面板**：右侧 Inspector 展示全部记忆，支持搜索、分类筛选、手动增删改、置顶为"核心记忆"、查看来源（AI 写入/手动）与使用次数
- **记忆整理**：一键让 AI 把当前对话归纳成结构化记忆

**4. 会话**：流式输出（逐字显示）、每角色多会话（历史会话可查看）、错误气泡带重试、复制消息。

## 文件清单

```
Package.swift                      — macOS 26.0 平台，executableTarget AIRoleSim
make-app.sh                        — swift build -c release → 组装 dist/AI角色模拟.app（Info.plist + ad-hoc 签名）→ open
README.md                          — 使用说明 + 各家 API 配置示例
Sources/AIRoleSim/
  AIRoleSimApp.swift               — @main 入口
  Models.swift                     — Character/Memory/Conversation/Message/APIConfig
  AppStore.swift                   — @MainActor 全局状态 + JSON 持久化
  APIClient.swift                  — OpenAI 兼容客户端：SSE 流式、tools、URL 归一化、模型列表
  ChatEngine.swift                 — 上下文组装（人设+记忆+历史）→ 流式回复 → 工具循环
  MemoryEngine.swift               — 记忆 CRUD + 打分检索 + 归纳整理
  DemoService.swift                — 演示模式模拟服务
  Views/RootView.swift             — NavigationSplitView 三栏骨架
  Views/SidebarView.swift          — 玻璃侧栏：角色列表、新建、设置
  Views/ChatView.swift             — 对话流 + 悬浮玻璃输入条（GlassEffectContainer）
  Views/MessageBubble.swift        — 气泡 + 记忆写入提示条
  Views/MemoryInspector.swift      — 记忆面板
  Views/CharacterEditor.swift      — 角色/编辑表单
  Views/SettingsView.swift         — API 配置页
  Views/GlassKit.swift             — 液态玻璃组件封装
```

## 验证步骤

1. `swift build` 编译通过
2. `./make-app.sh` 生成 .app 并启动，确认窗口正常显示、玻璃效果生效（截图验证）
3. UI 走查：创建角色 → 发消息（演示模式）→ 观察流式回复与"AI 记住了"提示 → 打开记忆面板确认 AI 写入的记忆 → 手动增删记忆 → 修改角色 → 新建会话
4. 检查数据落盘 JSON 与重启后状态恢复

## 说明

- 演示模式保证在没有 API Key 的情况下完整验证全部链路；你之后在设置里填入任意 OpenAI 兼容服务即可真实对话
- 不申请钥匙串权限（Key 存 0600 本地文件），避免频繁签名变更触发弹窗
