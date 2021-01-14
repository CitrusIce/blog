---
layout: post
title: "逆向的一些总结"
date: 2020-07-09 18:35:43 +0800
categories: reverse-engineering
---

最近做了一些windows逆向的工作，尽管大部分都是苦力活，但还是有一些收获，所以总结一下

- 观察程序行为

  - 文件操作
  - 注册表读写
  - dll调用
  - ……

  procmon

- 定位关键代码

  - 搜索字符串特征
  - 相关windows api
    - CreateFile
    - ReadFile
    - WriteFile
    - ……
  - 内存断点
  - 函数特征，ida signature，findcrypt

- 代码分析

  - 动态分析 => 分析具体行为
  - 静态分析 => 分析调用关系，程序逻辑
  - 关注数据流向
  - 类的识别

- 逆不动？

  - 注入进程寻找解密后的数据
  - 找到解密函数直接调用

- 未解决的问题以及可能的解决方案

  - 结构体及类的逆向

    下次可以尝试使用reclass

  - 在发现一个已经初始化完毕的对象、结构体后，难以定位之前对其进行初始化、写入数据等操作的代码

    - ce搜索指针链，一层一层定位初始化代码

    - 下断new，malloc、VirtualAlloc等函数，定位构造函数

    - 根据构造函数特征定位构造函数

      - 使用ecx传参（类函数特征）

      - 函数开始push ebx, esi, edi, ecx寄存器，对exc操作之后再pop ecx

        <https://bbs.pediy.com/thread-195449.htm>

        <https://www.cnblogs.com/predator-wang/p/8031071.html>

ps：

web手做逆向，有点惨
