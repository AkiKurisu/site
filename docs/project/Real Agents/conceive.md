# 在实验前——构思

基于[Generative Agents: Interactive Simulacra of Human Behavior](https://arxiv.org/abs/2304.03442)（以下简称GA）等论文, 着重于人工智能代理的行为规划框架和实现。

## 总结GA

在决策层，GA一文核心部分为反射(`Reflect`)，从而将记忆（即历史记录）压缩提炼重点(`Summarize`)获取NPC角色的“思想”。


在执行层，GA使用GPT结构化输出文本到游戏中的解释器来执行，如果解释器的指令足够原子化，就可以让NPC自己执行变化丰富的行为序列从而表现出其“真实”。

## 反思
最终的行为总会依赖解释器，不可能完全让AI生成一切行为，最终都需要原子指令，而AI生成行为的丰富程度取决于原子指令的丰富程度和AI对其的理解力。

>因此除了让AI通过解释语言来转为行为（例如GA中的行为设计的原子操作是将行为拆解到三元组），还可以让设计者提供有限行为，让AI学习如何使用，在Agent Sims论文中近似的概念被称为Tool-Use System。

综上，我们完全可以使用传统的AI决策模型，让AI能借助程序化的工具实现更可信的行为模拟。


## 设想一
根据Goap提供的`Goal`、`Action`之间的关系由语言模型进行总结概括，运行时完全由AI生成Plan。

Goap的决策使用A*算法获取`Plan`，在GameAIPro中，这被称为`Backward推理`的方式，如让大语言模型操控，则应使用`Forward推理`的方式。

例如使用Multi-Agents时，我们将一个任务的提示词交给一个Agent，让其完成一个推理任务，再将结果交给下一级的Agent，从而形成一个近似层级任务网络HTN的决策模型，因此后续我们将该方式称为`代理决策的方式`。

## 设想二
仅在Goap的`Planner`基础上加一层Reflect让决策更具生命力,后续我们将该方法称为`辅助决策的方式`。

具体而言，是保留Goap对于Plan的`Backword推理`，但对于Goal的权重系数由生成式代生成或Goal直接由生成式代理选择，这种方式对于已有游戏框架的侵入或改动是最小的，可以简单快速的让虚拟世界的NPC更鲜活。


## 实验

对于上述设想的实验，详见[实验篇](./experiment.md)

## 参考文献
<i>Behavior Selection Algorithms An Overview</i>. Michael Dawe, Steve Gargolinski, Luke Dicken, Troy Humphreys, and Dave Mark. Game AI Pro.