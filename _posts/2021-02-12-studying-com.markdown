---
layout: post
title: "COM学习"
date: 2021-02-12 18:21:48 +0800
categories: develop
---

com不是什么新的东西，主要是写一下学习路径

## 类

回答以下几个问题

类在内存中的样子？

类对象在内存中的样子？

多态底层怎么实现？为什么基类指针指向派生类对象就能实现多态？底层是怎么做的？

构造函数可以为虚函数吗？如果构造函数为虚函数，能够实现多态吗？为什么？

析构函数可以为虚函数吗？为什么？

如果派生类不重写虚函数， 基类指针指向派生类对象，调用的是谁的虚函数？

## 认识COM组件

com有in-proc与out-proc两种形态

使用c/c++编写inproc com组件

编写outproc组件

- 了解idl、alt
- 使用alt实现out-proc com
- 不使用alt实现out-proc com

## localserver com如何通信

基于rpc

编写RPC helloworld

## vbs如何获取到类函数地址

对于脚本语言来说，他无法获取到目标类函数在虚表中的位置，那么com组件通过什么样的方式来实现"语言无关"呢？

了解IDispatch

了解typelib

## Marshaling

## DCOM

https://saravanesh.files.wordpress.com/2007/09/understanding-com.pdf

## dll surrogate

https://docs.microsoft.com/en-us/windows/win32/com/registering-the-dll-server-for-surrogate-activation

---

ole、activex、winrt、.net，com是这些东西的基础，在了解了com之后再去学习这些微软的技术、框架会变得更加轻松