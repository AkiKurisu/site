---
date: 2024-07-27T12:39:40
draft: true
authors:
  - AkiKurisu
categories:
  - Unity
---

# Unity射击游戏AI实现: 中级篇

<!-- more -->

本篇将继续完善上一章制作的射击游戏AI，并增加一些高级的AI Feature。

## AI视野

AI怎么发现它的敌人呢？玩家通过相机提供的视野来发现对手，那么AI也可以拥有一个虚拟的视野，以下简称`FOV`。

