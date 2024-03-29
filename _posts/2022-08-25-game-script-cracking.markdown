---
layout: post
title: "记一次游戏挂机脚本的破解"
date: 2022-08-25 16:48:43 +0800
categories: reverse-engineering
---

昨天晚上睡觉的时候想到能不能把最近一直在用的游戏挂机脚本破解一下，于是今天就开始干了。看了一下，程序是.net写的，顿时感觉轻松不少。拖进反编译器看了一下代码，发现有部分代码做了去符号+控制流平坦化，不过强度不是很高，破解是有戏了。

程序是通过卡号/卡密网络验证的，搜了一下字符串，定位到登录失败的部分。此时查看调用堆栈，往上翻，便可以定位到判断网络验证结果的部分。在附近搜寻了一下，发现这验证部分居然不是托管代码，而是native的，作者写了一个wrapper去调用native代码进行网络验证。找到这个dll，研究了一下，发现它既是一个.net assembly，又是一个native dll，不知道是什么东西生成的。

.net+native的组合调试起来有点恶心，所以不想摸索网络验证的部分了，决定找一下验证成功后都修改了哪些变量表示验证成功。又是一番摸索，在托管代码中找到了一个成员表示当前用户是否登录，patch该成员的get/set方法。测试一下，虽然显示登陆了，但是功能似乎无法正常使用，继续深入研究，发现在wrapper dll里有一个函数检查当前登录状态，在程序的一些功能位置会调这个函数检测登录情况，patch这个函数测试一下，发现确实可以绕过登录校验了。

然而并没有这么简单，使用一会功能之后，电脑上所有的进程都突然结束掉了，立马意识到这是程序有暗桩（这里感谢作者的不杀之恩，没有做格盘之类的操作，我没啥破解经验，是实体机上调的）。既然是所有程序都被结束了，那必然是有调了NtTerminateProcess（总不会inline syscall吧，哈哈，要是inline syscall那就只能trace指令了）。挂上调试器，在NtTerminateProcess函数下断点，等到断下来后，查看调用堆栈，发现上面有一个frame正是在之前看到的wrapper里。拖进ida再次分析，发现了暗桩的代码。代码非常明显，也没有做动态调用。长这样：

```asm
.text:1001A1CD                 push    0               ; th32ProcessID
.text:1001A1CF                 push    2               ; dwFlags
.text:1001A1D1                 call    ds:CreateToolhelp32Snapshot
.text:1001A1D7                 mov     esi, eax
.text:1001A1D9                 mov     [esp+140h+pe.dwSize], 128h
.text:1001A1E1                 lea     eax, [esp+140h+pe]
.text:1001A1E5                 push    eax             ; lppe
.text:1001A1E6                 push    esi             ; hSnapshot
.text:1001A1E7                 call    ds:Process32First
.text:1001A1ED                 test    eax, eax
.text:1001A1EF                 jz      short loc_1001A225
.text:1001A1F1                 mov     ebx, ds:OpenProcess
.text:1001A1F7                 mov     edi, ds:Process32Next
.text:1001A1FD                 nop     dword ptr [eax]
.text:1001A200
.text:1001A200 loc_1001A200:                           ; CODE XREF: sub_1001A130+F3↓j
.text:1001A200                 push    [esp+140h+pe.th32ProcessID] ; dwProcessId
.text:1001A204                 push    1               ; bInheritHandle
.text:1001A206                 push    1FFFFFh         ; dwDesiredAccess
.text:1001A20B                 call    ebx ; OpenProcess
.text:1001A20D                 push    0               ; uExitCode
.text:1001A20F                 push    eax             ; hProcess
.text:1001A210                 call    ds:TerminateProcess
.text:1001A216                 cmp     eax, 1
.text:1001A219                 lea     eax, [esp+140h+pe]
.text:1001A21D                 push    eax             ; lppe
.text:1001A21E                 push    esi             ; hSnapshot
.text:1001A21F                 call    edi ; Process32Next
.text:1001A221                 test    eax, eax
.text:1001A223                 jnz     short loc_1001A200
```

继续查找TerminateProcess的所有引用，一共发现了5个暗桩，一一patch后，程序就可以正常使用了。

我接触破解的时间其实比我接触安全还早一年，但那时缺乏操作系统相关的知识，而网上的很多破解教程也只是让你依葫芦画瓢的去单步跟或者找数据位置。当时虽然说看了一寒假破解教程，但是实际上一点都没有学明白，只是学会了怎么用od的快捷键。现在看来，没有操作系统相关的知识去看那些破解教程无异于天马行空，而在有了这些知识后，知道其背后的原理，破解自然是水到渠成的事了。