---
date: 2025-05-13T16:47:53
authors:
  - AkiKurisu
categories:
  - Unity
---

# UPR下的Screen Space Reflection工程实践

<!-- more -->

Screen Space Reflection (SSR 屏幕空间反射)是个很有效提高真实感的屏幕空间效果，并且非常常见。

本篇文章是一个工程实践的分享，并不着重于基础概念和算法的解释，如果没了解过SSR，推荐看一下下面的文章和博客。

概念和算法了解：[图形学基础|屏幕空间反射(SSR)](https://blog.csdn.net/qjh5606/article/details/120102582)

Linear优化的算法详解：[Sugu Lee - Screen Space Reflections : Implementation and optimization – Part 1 : Linear Tracing Method](https://sugulee.wordpress.com/2021/01/16/performance-optimizations-for-screen-space-reflections-technique-part-1-linear-tracing-method/)

Hiz优化的算法详解：[Sugu Lee - Screen Space Reflections : Implementation and optimization – Part 2 : HI-Z Tracing Method](https://sugulee.wordpress.com/2021/01/19/screen-space-reflections-implementation-and-optimization-part-2-hi-z-tracing-method/)

因为URP上没有SSR，得自己实现或者第三方插件，这里选取了开源的[JoshuaLim007/Unity-ScreenSpaceReflections-URP](https://github.com/JoshuaLim007/Unity-ScreenSpaceReflections-URP)和[EricHu33/URP_SSR](https://github.com/EricHu33/URP_SSR)。前者提供了三种SSR的实现算法，并包括了上述两种优化方案，后者额外拓展了部分算法，并支持Forward管线以及RenderGraph API。

## ForwardGBuffer

SSR至少需要采样Depth、Normal、Metallic/Specular，在新的URP Forward管线中，Normal可以直接从`DepthNormalPass`生成的`CameraNormalTexture`中采样。而Metallic则无法获得，Eric的实现中增加了一个ThinGBufferPass（我倾向于叫ForwardGBuffer）来专门收集BRDFData的Reflectivity。

但不知道为啥，2022的实现漏了，这里补一下。

```csharp
public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
{
    ref var cameraData = ref renderingData.cameraData;
    if (cameraData.renderer.cameraColorTargetHandle == null)
        return;
    var cmd = CommandBufferPool.Get();
    using (new ProfilingScope(cmd, profilingSampler))
    {
        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        cmd.SetRenderTarget(_forwardGBufferTarget, cameraData.renderer.cameraDepthTargetHandle);
        context.ExecuteCommandBuffer(cmd);
        var drawSettings = CreateDrawingSettings(_shaderTagIdList,
            ref renderingData, renderingData.cameraData.defaultOpaqueSortFlags);
        drawSettings.overrideShader = _gBufferShader;
        context.DrawRenderers(renderingData.cullResults, ref drawSettings,
            ref _filteringSettings);
    }
    context.ExecuteCommandBuffer(cmd);
    CommandBufferPool.Release(cmd);
}
```

这里比较hack的地方是使用`overrideShader`来fetch当前材质中和`overrideShader`属性名称相同的值。

## Hiz优化

Eirc使用了和JoshuaLim一样的基于`Texture2DArray`的Hiz生成方案。

这个方案的主要问题在显存开销过高，例如模拟11级Mipmap需要2048 * 2048 * 11的RTArray。这明显是不合理的，因为Hiz的分辨率是远小于纹理分辨率的。

一种优化方案是手动创建每个Level的RT，然后给不同的分辨率，但这个会有切换RenderTarget的开销，并且采样极其麻烦。

而理论上我们应该使用Texture2D自带的Mipmap，然后手动写入Mipmap，于是我看了一下HDRP的实现。

HDRP的Hiz即Depth Pyramid使用了一个Packed Atlas打包图集的方式，将所有Mipmap放在一张RT中。采样时通过预计算各个Level下UV偏移量+屏幕空间位置进行计算就可以直接采样到对应Level的深度，非常优雅，使用示例如下：

```c++
StructuredBuffer<int2>  _DepthPyramidMipLevelOffsets;
TEXTURE2D_X(_DepthPyramid);

float SampleDepthPyramid(float2 uv, int mipLevel)
{
    int2 mipCoord  = (int2)uv.xy >> mipLevel;
    int2 mipOffset = _DepthPyramidMipLevelOffsets[mipLevel];
    return  LOAD_TEXTURE2D_X(_DepthPyramid, mipOffset + mipCoord).r;
}
```

因此我们可以完全抄一下HDRP的Depth Pyramid实现。

而在进一步检索后，笔者发现Unity6额外对Depth Pyramid的Compute Shader又进行了一波优化，见[知乎清盐-浅析Unity6 GPU Resident Drawer(下)(HiZ GPU Occlusion Culling)](https://zhuanlan.zhihu.com/p/842429737)。简而言之是通过Group Shared Memeory减少了Dispatch次数，1920× 1080 DepthAttachment只需要3个Dispatch。

Ok，这也抄走。然后笔者看到HDRP对于第一个Mipmap即完整的DepthBuffer的拷贝是使用Compute Shader进行加速的，也抄了。

## TAA

HDRP的SSR还有一个TAA流程，但这块要抄HDRP的实现在没有RenderGraph的情况下会比较复杂，所以笔者这里就不阐释了。URP 14里要实现的话和抄一遍内置的TAA差不多，只是把累加的目标换一下。

另一种是不使用SSR的TAA但开启相机TAA的情况，需要修改下SSR算法中的参数。如将`UNITY_MATRIX_VP`替换为`_NonJitteredViewProjMatrix`， 否则相机拉远反射面会有明显抖动。

## 效果

最终在Unity2022 Forward渲染路径下的效果：
![SSR](../../../assets/images/2025-05-13/ssr.png)

## 引用

[Sugu Lee - Screen Space Reflections : Implementation and optimization – Part 1 : Linear Tracing Method](https://sugulee.wordpress.com/2021/01/16/performance-optimizations-for-screen-space-reflections-technique-part-1-linear-tracing-method/)

[Sugu Lee - Screen Space Reflections : Implementation and optimization – Part 2 : HI-Z Tracing Method](https://sugulee.wordpress.com/2021/01/19/screen-space-reflections-implementation-and-optimization-part-2-hi-z-tracing-method/)

[图形学基础|屏幕空间反射(SSR)](https://blog.csdn.net/qjh5606/article/details/120102582)

[知乎清盐-浅析Unity6 GPU Resident Drawer(下)(HiZ GPU Occlusion Culling)](https://zhuanlan.zhihu.com/p/842429737)

[JoshuaLim007/Unity-ScreenSpaceReflections-URP](https://github.com/JoshuaLim007/Unity-ScreenSpaceReflections-URP)

[EricHu33/URP_SSR](https://github.com/EricHu33/URP_SSR)