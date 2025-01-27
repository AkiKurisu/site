---
date: 2025-01-26T23:13:42
draft: true
authors:
  - AkiKurisu
categories:
  - Unity
---

# 如何设计一个Unity可视化脚本框架（一）

<!-- more -->

## 简介

Ceres是我基于自身两年半的Unity独立游戏制作经验和半年的Unreal工作经验，开发出的可视化脚本框架。
其中，`Ceres.Flow`的功能类似于Unreal蓝图（Blueprint/Kismet）中EventGraph，方便开发者基于事件和节点连线来实现游戏逻辑。
由于UE的蓝图已经成为了游戏业内的可视化脚本方案标杆，为了易于理解，下文简称可视化脚本为蓝图。

![Example](../../../assets/images/2025-01-27/ceres_flow.png)

本期文章系列旨在分享我开发中的一些设计点和解决问题的过程。

## 现有框架
先看看现有轮子的问题。

### [XNode](https://github.com/Siccity/xNode)

XNode是比较早期的Unity可视化脚本方案，对于C#新手也能轻松上手。

以下是官方文档中的示例，作为后文分析的参考。

```C#
// public classes deriving from Node are registered as nodes for use within a graph
public class MathNode : Node {
    // Adding [Input] or [Output] is all you need to do to register a field as a valid port on your node 
    [Input] public float a;
    [Input] public float b;
    // The value of an output node field is not used for anything, but could be used for caching output results
    [Output] public float result;
    [Output] public float sum;

    // The value of 'mathType' will be displayed on the node in an editable format, similar to the inspector
    public MathType mathType = MathType.Add;
    public enum MathType { Add, Subtract, Multiply, Divide}
    
    // GetValue should be overridden to return a value for any specified output port
    public override object GetValue(NodePort port) {

        // Get new a and b values from input connections. Fallback to field values if input is not connected
        float a = GetInputValue<float>("a", this.a);
        float b = GetInputValue<float>("b", this.b);

        // After you've gotten your input values, you can perform your calculations and return a value
        if (port.fieldName == "result")
            switch(mathType) {
                case MathType.Add: default: return a + b;
                case MathType.Subtract: return a - b;
                case MathType.Multiply: return a * b;
                case MathType.Divide: return a / b;
            }
        else if (port.fieldName == "sum") return a + b;
        else return 0f;
    }
}
```
以下是笔者总结的问题：

- 每个Node都是一个`ScriptableObject`，也就是以资产的方式持久化。这种方式使得开发者难以进行内存管理，例如控制反序列化的时机，一个简单的例子是，Graph也是一个资产，Graph里面存储了Node的引用，而Node也是资产，一旦加载Graph，Unity就会将引用的所有Node进入内存中。
  相应带来的好处是方便了编辑器的开发，Unity的Custom Inspector只适用于UnityEngine.Object（以下简称UObject），这个限制与引擎对Asset的解析方式有关，不易修改。

- 运行时框架有性能问题，例如上文示例中GetInputValue会进行拆装箱，造成明显的性能问题，实现源码见[NodePort](https://github.com/Siccity/xNode/blob/master/Scripts/NodePort.cs#L139)。

- 基础框架较为简单，例如GetInputValue的设计很不方便拓展

### [NodeGraphProcessor](https://github.com/alelievr/NodeGraphProcessor)

NodeGraphProcessor使用了GraphView、SerializeReference等Unity2020版本后的新功能和新特性。

以下是笔者总结的优点：

- 基于`SerializeReference`进行序列化，这样一个Graph只需要一个Outer资产即可，不需要每个Node都创建一个资产。
  
- 编辑器拥有`GraphView`所有的特性，例如`Mipmap`，`RelayNode`，`StickNode`等，方便开发者拓展。

- 每个Node的输入输出（Input Output Port）不需要像XNode一样手动获取值，并且对绑定Port的反射使用Delegate进行了优化。
  具体参考自[MAKING REFLECTION FLY AND EXPLORING DELEGATES](https://codeblog.jonskeet.uk/2008/08/09/making-reflection-fly-and-exploring-delegates/)

以下是问题：

- 运行时大量的反射导致性能问题，例如TypeAdapter、Graph初始化、Port初始化
  
- 缺少对于非UObject的对象序列化支持，可参考其内置的[SerializableObject](https://github.com/alelievr/NodeGraphProcessor/blob/master/Assets/com.alelievr.NodeGraphProcessor/Runtime/Utils/SerrializableObject.cs)

- 运行时Port传递数据基于反射，并且有拆装箱，详见[NodePort.PullData](https://github.com/alelievr/NodeGraphProcessor/blob/master/Assets/com.alelievr.NodeGraphProcessor/Runtime/Elements/NodePort.cs#L298)

## 问题总结

和UE的蓝图比较起来，NodeGraphProcessor和XNode无论在运行时性能还是工作流设计上都存在一些遗憾。总结如下：

- 运行时开销不容忽视
  
- 功能拓展依靠用户增加节点

- 和C#脚本之间的衔接差

- 序列化功能不完整

## 设计目标

基于上述问题，我认为设计一个新的轮子需要满足以下目标：

- 能够轻松在C#和蓝图之间调用
  
- 更友好的编辑器

- 运行时拥有更好的性能

- 轻松拓展功能

那么本篇笔者先分析了一下现有轮子的问题与新轮子的设计目标，
下一期我将会分享一些具体问题的设计思路与解决方案。
当然项目一直在持续开发中，欢迎提issues。

## 引用
https://github.com/AkiKurisu/Ceres