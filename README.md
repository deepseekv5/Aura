# Aura · AI 角色工坊 for Mac

macOS 原生 SwiftUI 应用：自由创建 AI 角色、随时对话；角色在对话中**自己写入 / 创建 / 检索长期记忆**（OpenAI 兼容 API，可完全自定义）。UI 遵循 macOS 26 液态玻璃设计，极简黑白灰。

## 功能

- **角色系统**：自由创建任意角色——名称、主题色头像（名字首字）、人设、场景、开场白、标签；内置 5 个快速模板（自由创作 / 深度对话 / 面试教练 / 语言陪练 / 小说角色）；编辑、复制、删除、导入导出（见下）。
- **真实世界工具（10 个）**：查天气（Open-Meteo 主源 + wttr.in 兜底）、查新闻（Bing News RSS，国内可达，Google News 兜底）、网页搜索（Bing）、精确计算器、随机数/骰子/硬币、播放/停止本机音乐、查当前时间、定时提醒（本地通知）、**生成图片**（Pollinations 免费，无 Key）、长期记忆读写。查询结果由角色口语化转述；演示模式下这些工具同样使用真实数据。
- **意图兜底**：即使所用模型不支持 function calling，只要用户消息明确命中意图（天气/时间/新闻/音乐/计算/搜索/提醒/生图），应用会自动获取真实数据注入上下文，模型基于真实数据回答，不会再用"我无法查询"搪塞。
- **读图与生图**：输入框左侧可附加图片（发给支持视觉的模型，如混元 Vision / GLM-4V / GPT-4o），图片随消息保存与展示，点击可放大；"画一张……"会触发免费生图并直接在气泡中显示。
- **MiMo 语音朗读**：接入小米 MiMo TTS（OpenAI 兼容，默认免费的 mimo-v2.5-tts），支持自动朗读（可开关）与逐条手动播放，9 种预置音色可选、mp3/wav 可选、试听按钮；演示模式下用 macOS 系统语音朗读。设置 → 语音朗读 中配置 API Key。
- **长期记忆**：
  - AI 通过工具调用 `save_memory` 主动写入记忆（气泡下方显示「已记忆」提示条）；
  - 通过 `search_memory` 主动检索记忆；
  - 每轮对话自动注入「置顶记忆 + 按关键词/重要性/时间打分的相关记忆」；
  - 右侧记忆面板：搜索、分类筛选、手动增删改、置顶核心记忆、查看来源与使用次数；
  - 「从对话提炼记忆」一键整理近期对话为结构化记忆。
- **API 自配置**：多套 API 配置档案，任意 OpenAI 兼容服务（OpenAI / DeepSeek / 智谱 / Kimi / OpenRouter / 中转站）；Base URL 智能归一化（有无 `/v1` 均可）；一键拉取模型列表、测试连接；温度 / max tokens / 历史条数可调；角色可绑定专属配置、覆盖模型与温度；API Key 存储在本地 `config.json`（权限 0600）。
- **多人对话**：选择多个角色创建群聊，用户发言后各角色按顺序依次回应（互相可见）。
- **会话**：流式输出、多会话管理、历史对话切换、消息编辑并重发 / 重新生成 / 删除 / 复制、导出 Markdown。
- **全局搜索**：`⌘K` 跨角色搜索对话与记忆。
- **演示模式**：默认开启，无需 API Key 即可体验完整链路（本地模拟流式回复 + 记忆写入）。
- **快捷键**：⌘N 新建角色 · ⌘⇧N 新对话 · ⌘⇧G 新多人对话 · ⌘⇧M 记忆面板 · ⌘K 全局搜索 · ⌘↩ 发送 · ⌘, 设置。
- **语音输入**：输入条麦克风按钮，Mac 原生 Speech 框架听写（中文优先），说话转文字填入输入框
- **打电话**：对角色说「打电话给张三」或「拨打 10086」，按通讯录姓名查找号码后经系统 iPhone 接续拨出（需同 iCloud 的 iPhone）；打开网址、读剪贴板、查电脑状态一应俱全
- **屏幕读取密码保护**：设置 → 通用 → 屏幕读取，开启需设置密码；重启后需重新解锁
- 无 emoji 设计：头像用名字首字 + 主题色；AI 回复默认过滤 emoji（可全局/按角色关闭）。

## 构建与运行

```bash
./make-app.sh
```

生成 `dist/Aura.app` 并自动启动。要求 macOS 26+ 与 Command Line Tools（无需完整 Xcode）。

> 构建说明：本机 CLT 未携带 SwiftUI 宏插件（libSwiftUIMacros.dylib），`make-app.sh` 会自动生成一份「影子 SDK」（APFS 克隆系统 SDK 并剥离 SwiftUICore 接口中的外部宏声明，使 `@State` 等回退到传统 propertyWrapper 实现），再用 `swiftc` 直接编译全部源文件——全程零第三方依赖、无需 SwiftPM。若安装了完整 Xcode，`Package.swift` 亦可正常使用。

## API 配置示例

设置 → API 配置 → 添加配置：

| 服务 | Base URL | 模型示例 |
|---|---|---|
| DeepSeek | `https://api.deepseek.com` | `deepseek-chat` |
| 智谱 GLM | `https://open.bigmodel.cn/api/paas` | `glm-4.7` |
| Kimi | `https://api.moonshot.cn` | `kimi-k2` |
| OpenAI | `https://api.openai.com` | `gpt-5.2` |
| OpenRouter | `https://openrouter.ai/api` | 见服务端列表 |
| 本地 Ollama | `http://127.0.0.1:11434` | `qwen3:14b` |

步骤：填 Base URL → 填 API Key → 点「拉取模型列表」下拉选择 → 「测试连接」→ 设为默认 → 关闭演示模式。

> GLM 等推理模型若在回复里混入思考过程：开启该配置的「关闭思考模式」（附加 thinking=disabled）；历史消息不设上限，全部上下文都会送出。部分模型以文本内嵌 `<tool_call>` 形式发起工具调用（GLM 原生风格），应用会自动解析执行。

## 数据

所有数据存于 `~/Library/Application Support/AIRoleSim/`：`characters.json`、`conversations.json`、`memories.json`、`config.json`（含 API Key，权限 0600）。设置页可一键在访达中打开。

## 已知限制

- 供应商需支持 OpenAI `tools` 参数才能自动记忆；不支持时可在角色编辑器中关闭「自动管理记忆」（手动记忆功能不受影响）。
- 记忆检索为关键词 + 重要性 + 时间打分（零配置），未用向量语义检索。
- 未签名/未公证（本地 ad-hoc 签名），首次打开若被 Gatekeeper 拦截：右键 → 打开。
