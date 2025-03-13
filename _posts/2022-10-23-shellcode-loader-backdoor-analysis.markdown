---
layout: post
title: "ByPassAVTeam ShellcodeLoader后门分析"
date: 2022-10-23 13:29:16 +0800
categories: 逆向
---

看到有人转发[这个项目](https://github.com/ByPassAVTeam/ShellcodeLoader)说带后门，因为很眼熟这个项目，所以下载下来分析一下。

项目主要部分是个带mfc框架的shellcode loader加上使用冷门函数(PfxInitialize)反沙箱，这种东西只能说躲得过初一躲不过十五。还配了一个自动化配置shellcode的程序，根据别人的消息，后门就在这个自动化配置shellcode的工具里，LoaderMaker.exe。

另外项目开源的代码是干净的，并没有后门，存在后门的是github项目里发布的预编译程序。

先看一眼导入表

![](/assets/images/image-20221022230914572.png)

OpenProcess，CreateToolhelp32Snapshot，一股进程注入的味道扑面而来。

ida粗略看一眼大致流程，其实会发现还是挺正常的，正常的打banner，正常的读文件，正常的写入shellcode，要说有一点点可疑，那也就是那个sedebug提权和anti_sandbox，但是也没见到什么恶意行为。

![](/assets/images/image-20221022231746749.png)

那么作者是将后门藏在哪里了呢，我第一反应是tls，第二反应是cruntime初始化阶段。但是既然咱们上面已经看到了可以的OpenProcess和CreateToolhelp32Snapshot，就不需要那么麻烦一个一个找了，找到CreateToolhelp32Snapshot，然后看一眼交叉引用，对着代码一顿分析。

![](/assets/images/image-20221022232245207.png)

通过函数名获取pid，不用多说了吧。

继续看引用了get_pid的函数

![](/assets/images/image-20221022232341446.png)

栈字符串解密->get_pid->sub401290，接着看这个sub_401290

![](/assets/images/image-20221023120322393.png)

栈字符串解密->动态获取VirutalAllocEx->动态获取WriteProcessMemory->alloc+write将shellcode1写入内存->创建一块可执行内存并写入sub_41a8b0处的shellcode2->执行shellcode2。shellcode1大小经典929，cs stager基本没跑了

其实看到这里基本已经差不多了，按一般套路来说shellcode2的功能就是createthread、apc、setthreadcontext三选一，但是既然分析还是要分析完，继续看这个shellcode什么功能吧

![](/assets/images/image-20221023130424471.png)

push 0x33+far ret，哟这不天堂之门么，作者还是有点意思的，将shellcode dump出来，又是一顿分析

![](/assets/images/image-20221022233049093.png)

先调sub_A3然后返回值作为函数指针调用，那么sub_A3就是动态获取函数了，那么把sub_A3单独提取出来，跑了一下，发现获取到的是NtCreatethreadEx，那么到此就结束了。

但是最开始的问题还没有回答，后门到底是在什么地方执行的呢？

一通交叉引用，发现后门居然是在最开始标注的printf里

![](/assets/images/image-20221022233636692.png)

不得不说作者还是非常懂逆向人员的心态的，看到输出字符串的函数就会忽略过去，因此就把后门代码藏在这种不显眼的位置。



对脚本小子们的一记重拳，利好红队开发

