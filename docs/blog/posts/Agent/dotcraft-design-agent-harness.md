---
date: 2026-03-29T15:18:00
authors:
  - AkiKurisu
categories:
  - Agent
---

# DotCraft：从零设计一款 Agent Harness

<!-- more -->

无论是2025年 Coding Agent 的兴起，还是2026年个人助手类的 Claw Agent 的广泛普及，作为一名游戏程序员，很难不对此感到兴奋。

而当我深入探索、学习、开发后，发现做 Agent 和做游戏还真是颇为相似，编写程序是为了印证创意，迭代过程充满着正反馈，让我回到了大学时孜孜不倦学习游戏开发的日子。

本篇就是笔者在学习和实践过程中设计 DotCraft 这一个 Agent Harness 项目的经历分享，希望对感兴趣的小伙伴们有所帮助~

![banner](https://github.com/DotCraftDev/resources/raw/master/dotcraft/banner.png)

## 功能展示

DotCraft 的核心价值在于 **统一会话核心**（Unified Session Core）——所有入口共享同一个执行引擎。无论你使用什么工具，都能无缝切换并保持记忆连贯。

### 终端与桌面

从命令行到图形界面，DotCraft 提供了三种客户端满足不同场景需求：

**CLI** 是最直接的起点，适合在本地项目目录中直接与 DotCraft 协作：

![repl](https://github.com/DotCraftDev/resources/raw/master/dotcraft/repl.gif)

**TUI** 是基于 Ratatui 构建的富文本终端界面，提供更友好的交互体验：

![tui](https://github.com/DotCraftDev/resources/raw/master/dotcraft/tui.gif)

**Desktop** 是基于 Electron + React 的桌面应用，提供多会话管理、自动化任务、Cron 定时任务、Skill 管理等功能集成。

Desktop 更重要的功能是支持跨渠道的会话复原，不止是单纯的记忆共享，而是可以直接续上其他渠道的会话继续工作。

![desktop](https://github.com/DotCraftDev/resources/raw/master/dotcraft/desktop.gif)

### 社交渠道接入

DotCraft 支持将同一个工作区接入 QQ、企业微信等聊天平台，让 Agent 随时随地响应你的需求。

![qqbot](https://github.com/DotCraftDev/resources/raw/master/dotcraft/qqbot.gif)

除了内建渠道外，DotCraft 还提供 Python 和 TypeScript SDK，方便接入 Telegram、微信等外部平台：

![telegram](https://github.com/DotCraftDev/resources/raw/master/dotcraft/telegram.jpg)

![wechat](https://github.com/DotCraftDev/resources/raw/master/dotcraft/wechat.jpg)

### 编辑器集成

通过 ACP（Agent Client Protocol）协议，DotCraft 可以在 Unity、JetBrains IDE、Obsidian 等编辑器中直接使用。编辑器中的 Agent 与 CLI、Desktop 完全共享会话状态，无需手动同步：

![unity](https://github.com/DotCraftDev/resources/raw/master/dotcraft/unity.gif)

### 可观察与治理

Dashboard 提供用量统计、会话追踪、工具调用记录，让 Agent 的每一次执行都清晰可见：

![dashboard](https://github.com/DotCraftDev/resources/raw/master/dotcraft/dashboard.png)

完整的工具调用追踪，便于调试和优化：

![trace](https://github.com/DotCraftDev/resources/raw/master/dotcraft/trace.png)

### 自动化管线

DotCraft 的 Automations 受 OpenAI 的 [Symphony](https://github.com/openai/symphony) 启发， 支持本地任务与 GitHub Issue/PR 编排，由 AppServer 托管轮询、派发 Agent、维护审核状态：

![desktop-github](https://github.com/DotCraftDev/resources/raw/master/dotcraft/desktop_github.png)

PR 自动 Review，提升团队协作效率：

![github-tracker](https://github.com/DotCraftDev/resources/raw/master/dotcraft/github-tracker.png)

### API 与服务接入

如果你想把 DotCraft 作为服务接入其他应用，可以通过 OpenAI 兼容 API 或 AG-UI 协议：

![agui](https://github.com/DotCraftDev/resources/raw/master/dotcraft/agui.gif)

## 从 Agent 到 Agent Harness 的设计历程

### 小试牛刀

2025年 Coding Agent 改变了大部分程序员的工作方式，以 Claude 为首的高端模型让程序员减少了"给AI代码擦屁股"的次数，让 AI Native 的项目更容易落地和持续开发。

2026年 OpenClaw 带火了个人助手类的 Agent 应用，它为 AI 的 ToC 场景应用打开了更宽广的市场，类似项目和产品雨后春笋般涌现。例如极简主义的 Claw（Nanobot）、用 Rust 等高性能语言重写的 Claw（ZeroClaw）、深度集成自家社交渠道的 Claw（腾讯的 QClaw，小米的 Mimo MiClaw）。

在这一浪潮下，笔者受 nanobot 启发开始打造 DotBot（DotCraft的初版），其最初的定位是用 C# 重写一个极简版的 OpenClaw。

于是 DotBot 和目前的 Agent 应用一样完全拥抱大模型服务，基于微软最新的 Agent Framework 实现了 Claw 的核心功能，然后接入了 QQ、企业微信平台中跑通了生活和工作的社交场景。

但在实现后我才发现 "这个方向和我想的不太一样"，因此我在开源几天后删除了仓库（注意：如果已有 fork，删除仓库会将项目权限转移给第一个 fork 用户，不推荐这种做法）。

### Coding Agent 还是 Claw Agent

为什么觉得方向不一样呢？原因有三：

一是 OpenClaw 实际是一个启发性的产品（创意产品），而非有技术壁垒的产品，一旦有一个 Claw 后，其他的版本实际都没有"核心卖点"。以游戏打比方，就是有一个《杀戮尖塔》后，其他的类似游戏都只会被称为"类杀戮尖塔"的"爬塔"游戏，甚至有的只能叫做《杀戮尖塔》的 Mod。而国内涌现的大量产品，都是借 Claw 热点做出的"类杀戮尖塔"游戏。

二是 Coding Agent 也在这一个浪潮中悄悄改变，Claude Code、Codex、Manus 都顺势推出了桌面应用，让 Agent 不再停留在专业的 IDE、CLI 中，而是深入到用户的各类办公、生活场景中。甚至更简单来说，Claude Code 增加一个 "/loop" 命令就足以替代 OpenClaw 的 Heartbeat 核心功能。

三是 用什么语言编写在 Agent 时代下不再重要，任何语言完成后都可以使用别的语言快速复刻（当然要花钱就是了）。

因此我个人认为 Agent 应用已经完全从 "专注于垂直领域" 的小步探索转向了 "适用于通用场景" 的更高追求。新的 Agent 应用要有价值，需要找到更普遍的需求。

### 统一的会话后端

在使用 Agent 工具的时候，笔者经常希望能让它们的会话串联起来。

例如下面的场景：

1. 我在 QQ 上命令 Agent 实现了一个功能，Agent 完成了功能。
2. 我回到电脑前，到 Rider 中启动打开发现有问题，于是打开 Cursor 新开一个会话描述问题，Cursor 的 Agent 读取一遍文件查看修改并修复。
3. 我离开了电脑，想起刚刚一个功能的修复不对，在 QQ 上询问 Agent，但它不记得最近的修改。

这里的主要矛盾在于不同 Agent 应用之间的会话是独立的，它们有各自的 Agent 后端以及 Agent 基础设施。用户想要 "跨应用场景" 来共享 "记忆"，只能借助文档（Claude.md, Agent.md）用文件的方式将散落的信息汇总起来。

当然聪明的厂商们也并非对这个问题没有解决方案，Jetbrains 为了解决用户在 IDE 上无法使用现有 Coding Agent 工具的问题，推出了 ACP （Agent Client Protocol）协议，这样开发者依然可以在 IDE 中使用熟悉的 Claude Code、Gemini CLI 等工具。

但这个方案依然不够彻底，要打通所有场景，需要所有应用使用同一个 Agent 后端，以及同一套包含会话管理、记忆系统的 Agent 基础设施。

而如今我们将 Agent 和 Infra 的结合称之为 Agent Harness，因此更准确的说法是所有应用使用同一个 Agent Harness。

在这个构想下，下面的使用场景将成为可能：

1. Obsidian 中规划了任务，派遣 Agent 制定实现计划 A。
2. 微信命令 Agent 完成计划 A。
3. 用户打开 IDE 发现问题，IDE 中 Agent 能接着修复。
4. 离开电脑后使用其他的社交软件都能继续工作。
5. QQ 群机器人能定时汇报今天的修改内容到开发群中。

## DotCraft 的设计

这里非常感谢 OpenAI 的 Codex 为笔者提供了巨大的启发，感兴趣的小伙伴可以查看 OpenAI 的这篇博客了解 Codex 的具体设计： [解锁 Codex 运行框架：我们如何构建 App Server](https://openai.com/zh-Hans-CN/index/unlocking-the-codex-harness/)。

简单而言，Codex 一开始也是将 Agent 和应用绑定（例如 Codex 的 TUI、CLI）。但之后 OpenAI 发现日益增长的 Agent 需求意味着应用不再唯一，将 Codex 重构为了前后端分离的形式。

例如用户使用 Codex TUI 时，TUI 进程会拉起一个 AppServer 的子进程，以 stdio 的方式和前端进程通信。对于其他的 IDE、VSCode 插件都可以用 WebSocket 复用这个 AppServer，接入 JSON-RPC 协议后，前端不再需要关心 Agent 的底层实现，所有的会话都由 AppServer 负责管理。这让 OpenAI 能够快速开发、迭代 Codex Desktop 等应用。

![entry](https://github.com/DotCraftDev/resources/raw/master/dotcraft/entry.png)

于是笔者想到如果把 IM、IDE 也复用这个 AppServer 不就可以打通社交渠道、编辑器开发环境，统一全部的会话了吗！

因此在持续了一个月的高强度 Harness Engineering 后，笔者成功将 DotBot 改造为了 DotCraft，一个打通上述所有场景的 Agent Harness 应用。

![intro](https://github.com/DotCraftDev/resources/raw/master/dotcraft/intro.png)

当然除了统一会话外，要完整搭建一个 Agent 应用还有非常多的细节，这里就不赘述了，感兴趣的小伙伴们可以在仓库的中文文档中查阅。

## 总结

一个月的高强度 AI Coding 让我体验了从简单的 Vibe Coding 到 Harness Engineering 的转变。

当然这一切的发展太过迅速，笔者也难以直接给出多么深刻的实践经验，以下是个人的感慨。

在代码生成吞吐量指数级上升的当下，程序员的工作不再是 Coding 本身，而是更重要的结构性问题。
例如 “代码重构” 这件事情不再会因为 “改动量多大，工期长” 而成为瓶颈或限制时，如何让这个庞大的 “代码生产机器” 驶向正确的方向就是程序员最需要做的事情。

## 仓库链接

[DotCraftDev/DotCraft](https://github.com/DotCraftDev/DotCraft)

欢迎Star、Fork和贡献代码！
