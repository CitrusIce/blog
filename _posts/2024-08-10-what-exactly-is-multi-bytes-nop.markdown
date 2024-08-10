---
layout: post
title: "nop word ptr ds:[rax+rax*1], ax 到底是什么东西"
date: 2024-08-10 13:35:55 +0800
categories: cpu
---

在逆向的时候我们经常会看到如下指令：

```asm
nop                                       
nop dword ptr [eax]                        
nop dword ptr [eax + 00h]                  
nop dword ptr [eax + eax*1 + 00h]            
nop dword ptr [eax + 00000000h]            
nop dword ptr [eax + eax*1 + 00000000h]  
```

虽然我们都知道他们没什么用，但是我们不知道的是为什么会出现这些指令。

理论上我们只需要一个nop就足以，但是为什么有这么多多字节组成的nop呢？

搜索一番我有了答案：

- 用于解决旧芯片的bug (https://devblogs.microsoft.com/oldnewthing/20110112-00/?p=11773)
- 用于指令对齐或者其他优化

多字节的nop在优化中用于将它之后的指令对齐到16字节，因为cpu抓取指令通常以16字节为一个单元，这样如果下一个指令是一个会被多次执行的指令（如循环最开始的一个指令）,那么将不用再次抓取下一个16字节而能够直接解码。这块我不太懂但我觉得似乎有点道理。另外intel在手册中也有提到：

> *3.4.1.5 - Assembly/Compiler Coding Rule 12. (M impact, H generality)*
> All branch targets should be 16-byte aligned.



另外我在bfd库中发现了相关代码，显示这些多字节指令用于填充buffer

https://android.googlesource.com/toolchain/binutils/+/f226517827d64cc8f9dccb0952731601ac13ef2a/binutils-2.23/bfd/cpu-i386.c#51

另外，多个单字节nop相比于一个多字节nop所画的的cpu时间更长，这也是一个原因

参考：

https://devblogs.microsoft.com/oldnewthing/20110112-00/?p=11773

https://stackoverflow.com/questions/43991155/what-does-nop-dword-ptr-raxrax-x64-assembly-instruction-do

https://softwareengineering.stackexchange.com/questions/158624/are-some-nop-codes-treated-differently-than-others

https://android.googlesource.com/toolchain/binutils/+/f226517827d64cc8f9dccb0952731601ac13ef2a/binutils-2.23/bfd/cpu-i386.c#51

https://stackoverflow.com/questions/27714524/x86-multi-byte-nop-and-instruction-prefix

https://news.ycombinator.com/item?id=12369414

https://stackoverflow.com/questions/18113995/performance-optimisations-of-x86-64-assembly-alignment-and-branch-prediction/18279617#18279617
