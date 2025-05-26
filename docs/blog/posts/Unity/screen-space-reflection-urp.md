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

本篇文章是一个工程实践的分享，并不着重于基础概念和算法的解释，如果没了解过 SSR，推荐看一下下面的文章和博客。

概念和算法了解：[图形学基础|屏幕空间反射(SSR)](https://blog.csdn.net/qjh5606/article/details/120102582)

Linear优化的算法详解：[Sugu Lee - Screen Space Reflections : Implementation and optimization – Part 1 : Linear Tracing Method](https://sugulee.wordpress.com/2021/01/16/performance-optimizations-for-screen-space-reflections-technique-part-1-linear-tracing-method/)

Hiz优化的算法详解：[Sugu Lee - Screen Space Reflections : Implementation and optimization – Part 2 : HI-Z Tracing Method](https://sugulee.wordpress.com/2021/01/19/screen-space-reflections-implementation-and-optimization-part-2-hi-z-tracing-method/)

因为 URP 上没有 SSR，得自己实现或者第三方插件，这里选取了开源的[JoshuaLim007/Unity-ScreenSpaceReflections-URP](https://github.com/JoshuaLim007/Unity-ScreenSpaceReflections-URP)和[EricHu33/URP_SSR](https://github.com/EricHu33/URP_SSR)。前者提供了三种 SSR 的实现算法，并包括了上述两种优化方案，后者额外拓展了部分算法，并支持 Forward 管线以及 RenderGraph API。

## ForwardGBuffer适配

SSR 至少需要采样 Depth、Normal、Smoothness/Roughness，在新的 URP Forward 管线中， Normal 可以直接从 `DepthNormalPass` 生成的 `_CameraNormalTexture` 中采样。而 Smoothness 则无法获得，Eric 的实现中是增加了一个ThinGBufferPass（我倾向于叫ForwardGBuffer）来专门收集 BRDFData 的 Reflectivity。

笔者是在2022开发的，这里补一下Eric中缺失的传统 ScriptableRenderPass 实现：

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

这里比较hack的地方是使用 `overrideShader` 来 fetch 当前材质中和 `overrideShader` 属性名称相同的值。

但工程上实践后，笔者认为这不是一个好的方式，它对于标准化的 `Lit.shader` 而言是有效的，但对于更多自定义的材质就不见得那么有效了。
因此在每个需要使用 SSR 的 shader 中手动增加一个 `ForwardGBufferPass` 才是更合理的方式。例如下面直接在 `Lit.shader` 中添加一个 `ForwardGBufferPass`。

```hlsl
Pass
{
    Name "ForwardGBuffer"
    Tags
    {
        "LightMode" = "ForwardGBuffer"
    }
    
    ZWrite Off
    Cull Off
    ZTest Equal
    
    // To be able to tag stencil with disableSSR information for forward
    Stencil
    {
        WriteMask [_StencilWriteMaskGBuffer]
        Ref [_StencilRefGBuffer]
        Comp Always
        Pass Replace
    }
    
    HLSLPROGRAM
    #pragma target 4.5
    #pragma shader_feature_local_fragment _SPECULAR_SETUP
    
    //--------------------------------------
    // GPU Instancing
    #pragma multi_compile_instancing
    #pragma instancing_options renderinglayer
    #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"
                
    #include "LitForwardGBufferPass.hlsl"

    #pragma vertex LitPassVertex
    #pragma fragment LitForwardGBufferPassFragment

    half4 LitForwardGBufferPassFragment(Varyings input) : SV_Target
    {
        UNITY_SETUP_INSTANCE_ID(input);
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

        SurfaceData surfaceData = (SurfaceData)0;
        InitializeStandardLitSurfaceData(input.uv, surfaceData);
        BRDFData brdfData = (BRDFData)0;

        // NOTE: can modify "surfaceData"...
        InitializeBRDFData(surfaceData, brdfData);
        return surfaceData.smoothness;
    }
    ENDHLSL
}
```

类似HDRP的实现，为了控制哪些区域需要 SSR，我们可以在 `ForwardGBufferPass` 或 `DepthNormalPass` 中写入 Stencil，然后在 SSR 中跳过非 Mask 区域。

```hlsl
bool doesntReceiveSSR = false;
uint stencilValue = GetStencilValue(LOAD_TEXTURE2D_X(_StencilTexture, positionSS.xy));
doesntReceiveSSR = (stencilValue & STENCIL_USAGE_IS_SSR) == 0;
if (doesntReceiveSSR)
{
    return half4(0, 0, 0, 0);
}
```

`_StencilTexture` 需要从Pass中传入， 需要注意在 Forward 渲染路径下如果不开启 `DepthPriming` 的情况下，`DepthNormalPass` 将深度写入 `_CameraDepthTexture` 而非 `_CameraDepthAttachment`。

```c#
var depthTexture = GetCameraDepthTexture(); // _CameraDepthAttachment 或 _CameraDepthTexture 根据你的Stencil写入在哪
cmd.SetGlobalTexture("_StencilTexture", depthTexture, RenderTextureSubElement.Stencil);
```

## Hiz优化

Eirc 使用了和 JoshuaLim 一样的基于 `Texture2DArray` 的 Hiz 生成方案。

这个方案的主要问题在显存开销过高，例如模拟11级 Mipmap 需要2048 * 2048 * 11的 RTArray。这明显是不合理的，因为 Hiz 的分辨率是远小于纹理分辨率的。

一种优化方案是手动创建每个 Level 的 RT，然后给不同的分辨率，但这个会有切换 RenderTarget 的开销，并且采样极其麻烦。

而理论上我们应该使用 Texture2D 自带的 Mipmap，然后手动写入 Mipmap，于是我看了一下 HDRP 的实现。

HDRP的 Hiz 即 Depth Pyramid 使用了一个 Packed Atlas 打包图集的方式，将所有 Mipmap 放在一张RT中。

采样时通过预计算各个 Level 下 UV 偏移量+屏幕空间位置进行计算就可以直接采样到对应 Level 的深度，非常优雅，使用示例如下：

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

因此我们可以完全抄一下 HDRP 的 Depth Pyramid 实现。

而在进一步检索后，笔者发现 Unity6 额外对 Depth Pyramid 的 Compute Shader 又进行了一波优化，见[知乎清盐-浅析Unity6 GPU Resident Drawer(下)(HiZ GPU Occlusion Culling)](https://zhuanlan.zhihu.com/p/842429737)。简而言之是通过 Group Shared Memeory 减少了 Dispatch 次数，1920× 1080 DepthAttachment 只需要3个 Dispatch。

Ok，这也抄走。然后笔者看到 HDRP 对于第一个 Mipmap 即完整的 DepthBuffer 的拷贝是使用 Compute Shader 进行加速的，也抄了。

## TAA适配

HDRP 的 SSR 还有一个 TAA 流程，但这块要抄 HDRP 的实现在没有 RenderGraph 的情况下会比较复杂，所以笔者这里就不阐释了。URP 14 里要实现的话和抄一遍内置的 TAA 差不多，只是把累加的目标换一下。

另一种是不使用 SSR 的 TAA 但开启相机全屏 TAA 的情况，需要修改下算法中的参数。如将 `UNITY_MATRIX_VP` 替换为 `_NonJitteredViewProjMatrix`， 否则相机拉远反射面会有明显抖动。

## 重要性采样

在 Eric 和 Joshua 的 SSR 实现中，反射方向是直接使用视线和法线`reflect`获得，没有 Glossy 效果，只是根据金属度进行过渡，在粗糙度较高时效果略差。

而 HDRP 的反射方向使用了基于[Eric Heitz.2018. Sampling the GGX Distribution of Visible Normals](https://jcgt.org/published/0007/04/01/paper.pdf)提出的 VNDF 重要性采样方法，更物理精确，Glossy 效果更准确。

![VNDF](../../../assets/images/2025-05-13/vndf.png)

这部分知识推荐看蛋白胨大佬的文章[Importance Sampling PDFs (VNDF, Spherical Caps)](https://zhuanlan.zhihu.com/p/682281086)和三月雨大佬的实践[Visible NDF重要性采样实践](https://zhuanlan.zhihu.com/p/690342321)。

因此这块我们也可以直接抄到 URP 下，保留原来的近似方法，移动端性能较差的话仍使用它。


## 效果

最终在 Unity2022 Forward 渲染路径下的效果：
![SSR](../../../assets/images/2025-05-13/ssr.png)

## 引用

[Sugu Lee - Screen Space Reflections : Implementation and optimization – Part 1 : Linear Tracing Method](https://sugulee.wordpress.com/2021/01/16/performance-optimizations-for-screen-space-reflections-technique-part-1-linear-tracing-method/)

[Sugu Lee - Screen Space Reflections : Implementation and optimization – Part 2 : HI-Z Tracing Method](https://sugulee.wordpress.com/2021/01/19/screen-space-reflections-implementation-and-optimization-part-2-hi-z-tracing-method/)

[图形学基础|屏幕空间反射(SSR)](https://blog.csdn.net/qjh5606/article/details/120102582)

[知乎清盐-浅析Unity6 GPU Resident Drawer(下)(HiZ GPU Occlusion Culling)](https://zhuanlan.zhihu.com/p/842429737)

[JoshuaLim007/Unity-ScreenSpaceReflections-URP](https://github.com/JoshuaLim007/Unity-ScreenSpaceReflections-URP)

[EricHu33/URP_SSR](https://github.com/EricHu33/URP_SSR)