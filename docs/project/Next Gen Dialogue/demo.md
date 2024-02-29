# Next Gen Dialogue Demo

!!! abstract

    介绍演示项目实现细节 [https://github.com/AkiKurisu/Next-Gen-Dialogue-Demo](https://github.com/AkiKurisu/Next-Gen-Dialogue-Demo)

## 丰富对话行为

你可以使用`NextPieceModule`可以将一段对话中需要有不同表现的部分分到不同的Piece中。

<img src="../../../assets/images/2024-02-29/NextPieceModule.png">

你可以使用`ConditionModule`可以根据条件增加对话选项

<img src="../../../assets/images/2024-02-29/ConditionModule.png">

!!! tips
    对话片段也可以使用`ConditionModule`哦

## 事件传递

Demo中使用`UnityEvent`来传递事件

<img src="../../../assets/images/2024-02-29/UnityEvent.png">

!!! warning
    `UnityEvent`会对场景或其他资产产生依赖关系，如果你想将对话与资产解耦，请不要使用`UnityEvent`


* 其他事件模组：
基于Unity`ScriptableObject`的事件模组`ScriptableEventModule`

## 本地化

Demo中没有使用本地化拓展，而是直接使用另一个对话树来播放英文字幕版本。

!!! tips
    复制中文对话树后，增加`EditorTranslateModule`并一键翻译

<img src="../../../assets/images/2024-02-29/Localization_Editor.png">