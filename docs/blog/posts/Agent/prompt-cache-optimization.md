---
date: 2026-05-30T18:25:00
authors:
  - AkiKurisu
categories:
  - Agent
---

# 为什么你的 Agent 这么贵：Prompt Cache 命中率为 0 的排查记录

前段时间我把 DotCraft 接到工作流里跑任务，遇到了一个非常直观的问题：一个任务明明只跑了几分钟，账单却接近 50 美刀。

更离谱的是，我去后台看了一眼：cache hit rate = 0。

这意味着 Agent 每一轮工具调用，都在把同一份 System Prompt、工具 Schema、历史消息重新付费。对于普通 ChatBot 来说，这可能只是贵一点；但对于一个会连续调用几十次工具的 Agent 来说，这就是一台非常稳定的烧钱机器。

后来我在 DotCraft 里补了一套 Trace，把 System Prompt、Tools Schema、History Prefix 都打上 Hash，一轮一轮地查，才发现真正破坏 Prompt Cache 的往往不是模型，而是 Agent Harness 里几个很常见、也很容易被忽视的设计习惯。

<!-- more -->

![banner](../../../assets/images/2026-05-30/banner.png)

这篇文章主要记录一下这次排查过程，也顺便聊聊一个我最近越来越强烈的判断：

> Agent 的核心不是会不会 Function Call，而是 Harness 如何控制上下文、成本、权限、状态和可观测性。

如果你正在做 Coding Agent、MCP 客户端、企业内部 Agent，或者只是觉得“为什么我的 AI 应用这么贵”，这篇应该会比较有参考价值。

## 先说结论

Prompt Cache 优化不是玄学，也不是单纯换个便宜模型就能解决的问题。对于 Agent 来说，真正要控制的是输入前缀的稳定性。

我这次主要踩到了几个坑：

1. Plan 模式切换时改了 System Prompt 和工具列表，导致前缀直接变化。
2. 时间戳、当前模式、用户实时状态被塞进 System Prompt，导致每一轮都像新请求。
3. AGENTS.md、MEMORY.md、Skill 索引实时刷新，导致系统提示词持续抖动。
4. MCP 工具启用后动态刷新，导致 Tools Schema 变化。
5. 上下文压缩、记忆整理、分支会话如果设计不好，也会把原本可以复用的前缀缓存打碎。

对应的解决思路也很简单粗暴：

1. 能固定在 System Prompt 里的东西就固定，不要每轮变。
2. 动态信息尽量追加到 User Message 后面，而不是塞进系统提示词。
3. 工具列表不要随便变，模式限制交给 Policy 层兜底。
4. 低频变更内容做快照，不要每轮实时刷新。
5. 对 System Prompt、Tools Schema、History Prefix 做 Hash 和 Trace，没有观测就没有优化。

下面是 DotCraft 里应用侧统计的 Usage 视图。Prompt Cache 这类问题如果只靠体感，很容易变成“感觉好像便宜了”；但对 Agent Harness 来说，最后一定要落到可观测数据上。

![usage](../../../assets/images/2026-05-30/dotcraft-usage.png)

## 起因：一个几分钟烧掉 50 美刀的任务

笔者从二月份 Claw 类 Agent 助手兴起后，开始设计开发 [DotCraft](https://github.com/DotHarness/dotcraft)——一个以 .NET 技术栈、C# 为主要语言的 AI Agent。

它最初只是我自己的 Claw 助手和群机器人，后来随着不断迭代，逐渐吸收了很多主流 Coding Agent 的功能，也开始成为我游戏开发工作里的主力工具。因为拓展性比较强，工作中的一些 Agentic 业务也逐步基于这套 Agent Harness 来做。

![dotcraft-desktop](../../../assets/images/2026-05-30/dotcraft-desktop.png)

最初把 DotCraft 接到工作开发场景时，用的是公司的 Claude Opus 4.7 API。模型本身很强，效果也确实不错，但跑了几次之后账单就有点不对劲了。

一个任务只跑了几分钟，接近 50 美刀。

虽然没有之前流传的“某游戏公司一夜烧掉价值几百万的 Token”那么夸张，但也足够让我停下来重新审视整个 Harness 的设计。于是我去后台看缓存命中情况，结果发现 cache hit rate 竟然是 0。

这就很难绷了。

大部分大模型厂商都会把输入 Token 按“缓存命中”和“未命中”分开计费。按我当时接触到的计费规则，缓存命中的部分通常会便宜一大截；具体比例每家厂商、每个模型、每种协议都不一样，最终还是要以实时文档为准。

但核心结论很清楚：对于 Agent 来说，缓存打不中就是贵。

因为 Agent 早就不是 ChatGPT 3.5 时代那种一问一答的聊天机器人了。现在的 Agent 往往会连续调用几十次工具，甚至上百次工具。每一次工具调用之后，客户端都要把历史消息、工具结果、系统提示词、工具 Schema 重新发给模型。

如果这些重复前缀能被缓存命中，成本会下降很多；如果每轮都打不中，那就是每一轮都在重新付费。

所以这次排查的目标也很明确：不是先去换便宜模型，而是先搞清楚 DotCraft 为什么完全吃不到 Prompt Cache。

## 为什么 Agent 对 Prompt Cache 特别敏感

首先要说明一下 Agent 的基本循环。

Agent 本质上就是 LLM + Function Call 组成的循环：用户发消息，LLM 输出消息；如果 LLM 调用了工具，客户端就执行工具，再把历史消息和最新工具结果发回 LLM，如此往复。

![function call](../../../assets/images/2026-05-30/function-calling-diagram-steps.png)

这里容易被忽略的一点是：我们平时说的“一轮对话”，和 Agent 内部真正发给模型的“一轮请求”，不是一回事。

用户可能只是问了一句话，但 Agent 内部可能经历了：

1. 模型思考并调用搜索工具。
2. 客户端返回搜索结果。
3. 模型读取文件。
4. 客户端返回文件内容。
5. 模型修改文件。
6. 客户端返回修改结果。
7. 模型继续验证。
8. 客户端返回验证结果。

用户看起来只说了一句话，底层可能已经跑了很多轮。

![reasoning](../../../assets/images/2026-05-30/reasoning-turns.png)

而每一轮请求里，除了上一轮的输出和历史消息之外，通常还会带上两块非常大的东西：

1. System Prompt：包括应用内硬编码的规则，也包括用户可编辑的项目上下文，例如 CLAUDE.md、AGENTS.md 等。
2. Tools Schema：包括所有内置工具和 MCP 工具的 JSON Schema。

于是问题就来了：如果 System Prompt 或 Tools Schema 每一轮都在变，那么输入前缀就稳定不下来。

Prompt Cache 的核心并不复杂，至少从应用开发者视角看，可以先粗暴理解成一句话：

> 前缀越稳定，越容易命中；前缀越抖，越容易烧钱。

## 缓存到底是怎么碎掉的

那是不是只要保证每轮输入前缀一致，就一定能命中缓存？

当然不是。真正的缓存命中逻辑在大模型后端实现，不同厂商作用到推理端 KV Cache 的方式也不完全一样。应用开发者不需要关心所有底层细节，但至少要理解协议层面的几个约束。

以 OpenAI Chat Completions 这种比较典型的隐式缓存为例，开发者不需要手动指定缓存断点，后端会对输入消息数组做前缀匹配。只要后续请求不修改数组前面的内容，前缀在大多数情况下就有机会复用。

![prompt-cache-breakpoint](../../../assets/images/2026-05-30/prompt-cache-breakpoint.jpg)

但这只是理想情况。实际落地时还有两个很常见的干扰因素。

第一个是路由问题。第 N 轮请求的缓存可能写到了 A 集群，但第 N+1 轮被路由到了 B 集群，自然就读不到前面的缓存。

第二个是时效问题。缓存本质上占用推理资源，尤其是 GPU 显存，各家厂商都会设置 TTL。超过时间之后，缓存自然会失效。

所以厂商会提供一些自己的协议能力来解决这些问题。比如 Codex 使用 OpenAI Responses 协议时，除了隐式缓存之外，还会通过一些请求参数和关联信息维持路由黏性；Anthropic 则支持更显式的 cache control 和更长 TTL，但对应会带来额外的缓存写入成本。

![prompt-cache-mixed-ttl](../../../assets/images/2026-05-30/prompt-cache-mixed-ttl.png)

这些是厂商层面的能力。下游应用开发者真正需要控制的，是自己的请求前缀到底稳不稳定。

## 我先给 DotCraft 补了一套 Trace

一开始看到 cache hit rate = 0 的时候，我其实也不确定问题出在哪里。

可能是厂商路由问题，可能是 TTL 问题，也可能是 DotCraft 自己把前缀弄碎了。只看账单和命中率是没法定位的，所以第一步不是优化，而是补观测。

DotCraft 里我主要做了两件事。

第一，对每次发给 LLM 的 Request，把 System Prompt 和 Tools Schema 分别计算 Hash。只要某一轮 Hash 变了，就能立刻知道是系统提示词变了，还是工具列表变了。

第二，根据不同协议的返回包统计缓存写入和读取情况。Anthropic 这类协议会给相关字段，OpenAI 某些协议则没有那么直接，所以需要应用侧做更多归因。

这里还有一个很多人容易误解的点：缓存命中不代表命中率一定是 100%。

命中率和当轮输入里“可复用前缀”的占比有关。比如上一轮只写入了 100 Token 的缓存，而上一轮输出了 900 Token，那么当前轮理论最大命中率也只有 10%。再比如用户每次都开新会话，只问一个问题就走，那么永远处于冷启动，理论命中率就是 0%。

所以如果一个项目只说“缓存命中率稳定 98%、99%”，但不说会话长度、冷启动比例、上下文压缩策略、输入输出占比，那这个数字其实没有太多参考价值。

相比之下，DotCraft 这边主打一个不躲、不藏、不绕、不逃，稳稳地把应用侧数据都摆出来。哈哈。

下面是 DotCraft 的 Dashboard Trace。可以看到用户发送 User Message 后，模式信息和时间戳被追加在它后面，而不是塞进最前面的 System Prompt。

![dashboard](../../../assets/images/2026-05-30/dotcraft-dashboard.png)

## 真正破坏缓存的几个设计

有了 Trace 之后，问题就很好查了。DotCraft 老版本里确实有不少会破坏缓存的设计，其中有些在 OpenClaw 的早期版本里也能看到，这也是当时很多使用者对它的核心“评价”——贵。

### 1. Plan 模式切换时改 System Prompt 和工具列表

这是最典型的问题。

很多 Agent 都会有 Plan / Act 之类的模式。Plan 模式下只允许规划，不允许改文件；Act 模式下才允许执行修改。

最直接的实现方式是：进入 Plan 模式时，改 System Prompt，移除文件写入工具；进入 Act 模式时，再把 System Prompt 和工具列表换回来。

这听起来很合理，但从 Prompt Cache 角度看就是灾难。因为 System Prompt 一变，前缀变了；Tools Schema 一变，前缀也变了。

更好的做法是：在 System Prompt 里固定写好各种模式的行为准则，然后在当前 User Message 后面追加一段当前模式信息，告诉 Agent 现在处于 Plan 还是 Act。工具层面不要频繁改 Schema，而是由 Policy 层兜底。如果 Plan 模式下 Agent 误用了文件写入工具，客户端直接返回错误和引导信息。

这样行为上仍然能限制 Agent，但前缀不会每轮乱跳。

### 2. 把时间戳塞进 System Prompt

第二个坑更隐蔽：把用户实时信息放进 System Prompt，比如当前时间、当前工作目录状态、当前模式、临时环境信息等。

这些信息看上去像“系统上下文”，但它们的问题是变化太频繁。一旦放在 System Prompt 里，就会导致系统提示词每轮变化，缓存自然很难命中。

我的策略是：实时信息追加到 User Message 后面。

这类信息本来就是“本轮请求的动态上下文”，不应该污染稳定前缀。

### 3. AGENTS.md、MEMORY.md、Skill 索引实时刷新

很多 Coding Agent 会读取项目里的 AGENTS.md、CLAUDE.md、MEMORY.md，或者维护一套 Skill 索引。这些内容确实很重要，但不能因此每一轮都重新刷新进 System Prompt。

尤其是 MEMORY.md 这种低频变更内容，如果每轮实时读取并拼进系统提示词，等于每轮都在赌它不变。一旦有后台任务更新了记忆，或者索引顺序变化，缓存就会被打碎。

DotCraft 后来对这类内容做了分页和快照管理。低频变更内容保留快照，只在上下文压缩之后、TTL 失效之后，或者明确需要刷新时才更新。

换句话说，Agent 需要记忆，但记忆不能成为每轮请求里的随机扰动源。

### 4. MCP 工具实时刷新

MCP 很好用，但 MCP 工具多了之后，Tools Schema 会变得非常大。

如果 MCP 工具启用后还会动态刷新，或者每轮都重新枚举工具，那么 Tools Schema 的顺序、描述、参数都可能发生变化。哪怕只是顺序变了，对前缀缓存来说也可能是一次破坏。

DotCraft 里为 MCP 工具增加了 Deferred Loading，目前主要支持 OpenAI Responses 协议。核心思路是：基础工具稳定放在前缀里，增量工具通过延迟加载进入上下文，尽量不要破坏已有前缀缓存。

这也是我现在对 MCP 的一个看法：MCP 不是越多越好。对于 Agent Harness 来说，工具数量、工具加载时机、工具权限、工具 Schema 稳定性，都应该被当成工程问题来设计。

## 更高级的缓存命中策略

前面这些只能算 Agent Harness 的基础优化。如果继续往 Claude Code、Codex 这类更成熟的 Harness 看，会发现 Prompt Cache 还有一些更高级的玩法。

### 显式缓存控制

Anthropic 协议支持显式 cache control，可以提供多个 Cache Point 断点，让应用侧更灵活地做分段缓存。

它最直接的好处是“缓存回退”。

假设历史会话发生了变化，比如上下文压缩之后，完整历史已经不一样了；但如果前面的“系统提示词 + 工具 Schema”有一个稳定断点，那么后续请求仍然可以复用这个断点之前的缓存。

对于长上下文 Agent 来说，这个能力非常关键。因为 Agent 不只是要缓存“完整历史”，更重要的是缓存那些昂贵、稳定、重复出现的基础前缀。

### 上下文压缩如何复用前缀

上下文压缩也是 Agent Harness 里非常重要的一环。

Codex 的上下文压缩走的是一个特殊的 Compact API，具体实现比较黑盒。笔者推测它应该也用了类似显式缓存断点的设计，尽量复用“系统提示词 + 工具 Schema”这部分稳定前缀。

另一种思路是 Claude Code 那种 Fork 分支会话：从主会话复制系统提示词、工具 Schema 和历史消息，再追加一条 User Message，让 LLM 生成 Summary。这样分支会话也能复用主会话前缀缓存。

DotCraft 采用的是类似 Claude Code 的方案，并且把这套策略用在了记忆整理功能上：主会话继续工作，后台 Fork 一个分支会话完成 MEMORY.md 和 HISTORY.md 的总结与写入。

对于无法复用前缀的冷启动场景，例如应用重启之后，DotCraft 会退回 Legacy 方案：直接修改系统提示词、移除工具 Schema、过滤工具输出，用更低成本的方式生成上下文 Summary。

这里没有银弹，只有取舍。

### 缓存预热

还有一种策略是缓存预热。

前面提到，用户发 Request 时会有一个冷启动窗口。这段时间里缓存还没有写好，无法立刻读取。预热的思路就是：应用先行发送“系统提示词 + 工具 Schema”来写入这部分前缀缓存，等用户真正发请求时就能直接命中。

![prompt-cache-prewarm](../../../assets/images/2026-05-30/prompt-cache-prewarm.jpg)

这在大规模并行 Agent 场景里会更有价值。比如多个会话共享同一套 System Prompt 和工具 Schema，就可以复用同一份预热后的前缀缓存。

当然，预热本身也有成本。它适合高频、稳定、可复用的场景，不适合用户随便开一个一次性会话就无脑预热。

### 中途插入系统提示词

写这篇文章时恰逢 Claude Opus 4.8 发布。抛开那些颇为唬人的 Benchmark 不谈，这次更让我感兴趣的是：它支持把系统提示词随时追加到历史会话之后。

![mid-conversation-system-messages](../../../assets/images/2026-05-30/mid-conversation-system-messages.jpg)

这个能力对 Agent Harness 很有价值。

还是拿 Plan 模式切换来说，过去如果想强约束 Agent 行为，很多实现会选择修改最初的 System Prompt。但这样会破坏稳定前缀。现在如果协议支持中途追加系统提示词，就可以在切换模式之后直接追加一段新的系统级约束，而不是把所有模式规则都 hardcode 在最初的系统提示词里。

这会让 Harness 的行为控制更灵活，也更省 Token。

不过这类能力往往和厂商后训练、协议设计、模型行为有关，不是简单照搬 API 字段就能完全复刻的。所以我更倾向于把它看成厂商专属优化，而不是通用方案。

## 回到 Agent Harness：省钱只是表象

这次 Prompt Cache 排查之后，我对 Agent 开发的一个感受更强烈了：

> Agent 的价值不在“会不会调用工具”，而在 Harness 能不能把工具调用变成可控、可观测、可迭代的工程系统。

Function Call 本身并不复杂。真正麻烦的是这些问题：

1. 上下文怎么组织，才能既有信息量，又不无限膨胀？
2. System Prompt 哪些内容应该稳定，哪些内容应该动态？
3. 工具 Schema 怎么加载，才能既好用，又不污染前缀？
4. 模式切换、权限控制、错误恢复，应该由 Prompt 管，还是由 Policy 管？
5. 记忆系统什么时候读，什么时候写，什么时候压缩？
6. 出了问题之后，能不能通过 Trace 快速定位，而不是靠猜？

Prompt Cache 只是其中一个切面。它看起来是成本优化，但背后其实是 Agent Harness 的架构问题。

游戏开发里我们很熟悉这种事。性能优化从来不是最后加一个开关就能解决的，它会反过来影响渲染管线、资源组织、场景结构、工具链和工作流。Agent 也是一样：成本、上下文和工具系统如果一开始不设计好，后面就会变成到处漏水。

## 最后给一份检查清单

如果你也在做 Agent，可以按这个清单过一遍：

1. System Prompt 是否每一轮都完全一致？
2. 当前时间、当前模式、用户状态是否被错误地塞进 System Prompt？
3. Tools Schema 是否会因为模式切换、MCP 刷新、工具顺序变化而抖动？
4. AGENTS.md、MEMORY.md、Skill 索引是否每轮实时刷新？
5. 是否对 System Prompt 和 Tools Schema 分别打 Hash？
6. 是否区分了缓存写入、缓存读取、冷启动窗口和 TTL 失效？
7. 上下文压缩后，是否还能复用“系统提示词 + 工具 Schema”的稳定前缀？
8. Plan / Act 这类模式限制，是通过修改工具列表实现，还是通过 Policy 层兜底？
9. MCP 工具是否支持按需加载，而不是一次性把所有工具塞进上下文？
10. 是否有 Dashboard 或 Trace 能解释每一轮为什么贵？

如果这些问题都答不上来，那 Prompt Cache 命中率低大概率不是厂商的问题，而是 Harness 还没有长出自己的控制面。

## 结语

Agent Harness 里的很多东西，本质上都是工程上的优化手段。当然，中间也少不了一些有趣的奇技淫巧，哈哈。

我越来越觉得，现代 Agent 的通用形态会逐渐沉淀下来：上下文管理、工具加载、权限控制、记忆系统、Trace、缓存策略、压缩策略，最后都会变成 Harness 的基础设施。

所以现在造一个 Agent，理论上确实可以“照葫芦画瓢”；但真正有价值的不是把 Function Call Loop 跑起来，而是让它在具体业务里稳定、便宜、可控地创造价值。

笔者在设计 DotCraft 时，也更看重拓展性和架构设计。与其跟风堆功能，不如在真实业务里持续打磨这些基础能力。

最后欢迎小伙伴们 Star、Fork 和 Contribute ~

仓库链接：[DotHarness - DotCraft](https://github.com/DotHarness/DotCraft)

## 参考资料

- [OpenAI — Prompt caching guide](https://developers.openai.com/api/docs/guides/prompt-caching)
- [Anthropic — Prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
- [Anthropic — Pricing](https://platform.claude.com/docs/en/about-claude/pricing)
- [Anthropic — Mid-conversation system messages](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages)
- [Anthropic — What's new in Claude Opus 4.8](https://platform.claude.com/docs/en/about-claude/models/whats-new-claude-4-8)
- [OpenAI Codex — CLI features](https://developers.openai.com/codex/cli/features)
