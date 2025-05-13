---
date: 2025-05-13T16:47:53
draft: true
authors:
  - AkiKurisu
categories:
  - Unity
---

# UPR下的Screen Space Reflection实现

<!-- more -->

Screen Space Reflection (SSR 屏幕空间反射)是个很有效提高真实感的屏幕空间效果，并且非常常见。

本篇文章是一个偏工程实践的分享，并不着重于基础概念和算法的解释，如果没了解过SSR，推荐看一下下面的文章和博客。

概念和算法了解：[图形学基础|屏幕空间反射(SSR)](https://blog.csdn.net/qjh5606/article/details/120102582)

Linear优化的算法详解：[Sugu Lee - Screen Space Reflections : Implementation and optimization – Part 1 : Linear Tracing Method](https://sugulee.wordpress.com/2021/01/16/performance-optimizations-for-screen-space-reflections-technique-part-1-linear-tracing-method/)

Hiz优化的算法详解：[Sugu Lee - Screen Space Reflections : Implementation and optimization – Part 2 : HI-Z Tracing Method](https://sugulee.wordpress.com/2021/01/19/screen-space-reflections-implementation-and-optimization-part-2-hi-z-tracing-method/)

因为URP上没有SSR，得自己实现或者第三方插件，这里选取了开源的[JoshuaLim007/Unity-ScreenSpaceReflections-URP](https://github.com/JoshuaLim007/Unity-ScreenSpaceReflections-URP)和[EricHu33/URP_SSR](https://github.com/EricHu33/URP_SSR)。前者提供了三种SSR的实现算法，并包括了上述两种优化方案，后者额外拓展了部分算法，并支持Forward管线以及RenderGraph API。

## ForwardGBuffer

SSR至少需要采样Depth、Normal、Metallic/Specular，在新的URP Forward管线中，Normal可以直接从`DepthNormalPass`生成的`CameraNormalTexture`中采样。而Metallic则无法获得，Eric的实现中增加了一个ThinGBufferPass（我倾向于叫ForwardGBuffer）来专门收集BRDFData的Reflectivity。

但不知道为啥，2022的实现漏了，这里补一下。

## Hiz优化

Eirc使用了和JoshuaLim一样的基于Texture2DArray的Hiz生成方案。

这个方案的主要问题在显存开销过高，例如模拟11级Mipmap需要2048 * 2048 * 11的RTArray。这明显是不合理的，因为Hiz的分辨率是远小于纹理分辨率的。


## 引用

[Cross-Platform Mobile and PC Rendering in 'Earth: Revival'](https://gdcvault.com/play/1028751/Cross-Platform-Mobile-and-PC)