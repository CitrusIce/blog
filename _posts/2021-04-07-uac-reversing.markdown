---
layout: post
title: "UAC逆向"
date: 2021-04-07 14:17:43 +0800
categories: reverse-engineering
---

网上的文章关于uac的具体细节太少，大部分都是如何绕过uac，但是如果不了解uac的机制又怎么能理解那些绕过的手法呢，于是便决定去逆向uac。

## 谁拉起的elevated进程

尽管在任务管理器中使用管理员身份启动的进程的父进程是explorer，但是在explorer中KERNELBASE!CreateProcessW位置下断，使用管理员权限运行程序，并不会断下，而正常启动程序则可以正常断下来，这说明elevated的程序很有可能并非是由explorer拉起的。从权限的角度想这也很合理：explorer本身并不是一个system进程或elevated的进程，如果是由explorer拉起，那自然也不可能达到提权的目的。

如果以管理员身份启动程序并不会调用CreateProcessW，那肯定是在某一个函数中走了另一个分支。因此正常启动一个程序，断下，查看调用栈进行分析，尝试确定关键函数

```
1: kd> bp /p ffffbb86ae9da340 kernelbase!createprocessw
0: kd> g
Breakpoint 3 hit
KERNELBASE!CreateProcessW:
0033:00007ffc`4f576a50 4c8bdc          mov     r11,rsp
0: kd> k
 # Child-SP          RetAddr               Call Site
00 00000000`0630d998 00007ffc`502dcbb4     KERNELBASE!CreateProcessW
01 00000000`0630d9a0 00007ffc`4d4c0ccd     KERNEL32!CreateProcessWStub+0x54
02 00000000`0630da00 00007ffc`4d47d68c     windows_storage!CInvokeCreateProcessVerb::CallCreateProcess+0x13d
03 00000000`0630dca0 00007ffc`4d478e54     windows_storage!CInvokeCreateProcessVerb::_PrepareAndCallCreateProcess+0x2b0
04 00000000`0630dd20 00007ffc`4d47778b     windows_storage!CInvokeCreateProcessVerb::_TryCreateProcess+0x3c
05 00000000`0630dd50 00007ffc`4d47740d     windows_storage!CInvokeCreateProcessVerb::Launch+0xef
06 00000000`0630ddf0 00007ffc`4d47c4b5     windows_storage!CInvokeCreateProcessVerb::Execute+0x5d
........
```

经过测试，CInvokeCreateProcessVerb::CallCreateProcess就是我们要找的关键函数。用ida对这个函数进行逆向，发现在以管理员身份运行程序时CInvokeCreateProcessVerb::CallCreateProcess会去调用AicLaunchAdminProcess，而AicLaunchAdminProcess本身并不拉起进程，而是做了rpc通信，看来真正拉起权限提升进程的程序并非是explorer

![image-20210320132941566](/assets/images/image-20210320132941566.png)

根据创建binding handle时使用的uuid在rpcview找到对应的接口，发现是一个svchost起的服务

![image-20210320132923499](/assets/images/image-20210320132923499.png)

从启动命令行中可以看到是appinfo

![image-20210320133100719](/assets/images/image-20210320133100719.png)

根据rpcview中显示的procedure地址，我们可以找到对应的dll，也就是appinfo.dll

![image-20210320133248408](/assets/images/image-20210320133248408.png)

根据接口地址找到对应函数RAiLaunchAdminProcess

在RAiLaunchAdminProcess中，我们可以看到最终调用了AiLaunchProcess，而AiLaunchProcess又是对CreateProcessAsUserW的封装，可以看出权限提升的进程最终是由appinfo服务进程拉起来的。

![image-20210406175451171](/assets/images/image-20210406175451171.png)

## 什么样的程序可以不弹出uac窗口

首先要找到使uac弹窗的函数

以管理员权限打开一个程序，弹出uac窗口后，windbg断下来，切换到appinfo服务所在的进程，打印所有线程的栈

```
1: kd> !process 48c 6
........
        THREAD ffffbb86af9b7080  Cid 048c.18b0  Teb: 000000eb9578f000 Win32Thread: ffffbb86b02046c0 WAIT: (UserRequest) UserMode Non-Alertable
            ffffbb86aa520080  ProcessObject
        Not impersonating
        DeviceMap                 ffffa90e43a35600
        Owning Process            ffffbb86add680c0       Image:         svchost.exe
        Attached Process          N/A            Image:         N/A
        Wait Start TickCount      21551          Ticks: 509 (0:00:00:07.953)
        Context Switch Count      3579           IdealProcessor: 1             
        UserTime                  00:00:00.265
        KernelTime                00:00:00.578
        Win32 Start Address ntdll!TppWorkerThread (0x00007ffc51aa20e0)
        Stack Init ffffb90acbaa7c90 Current ffffb90acbaa76a0
        Base ffffb90acbaa8000 Limit ffffb90acbaa2000 Call 0000000000000000
        Priority 9 BasePriority 8 PriorityDecrement 0 IoPriority 2 PagePriority 5
        Child-SP          RetAddr               : Args to Child                                                           : Call Site
        ffffb90a`cbaa76e0 fffff803`1b0e4e60     : ffffbb86`00000008 00000000`ffffffff ffffb90a`00000000 ffffbb86`ae3d2158 : nt!KiSwapContext+0x76
        ffffb90a`cbaa7820 fffff803`1b0e438f     : 00000000`00000009 00000000`00000000 ffffb90a`cbaa79e0 ffffffff`fffffffe : nt!KiSwapThread+0x500
        ffffb90a`cbaa78d0 fffff803`1b0e3c33     : ffff5817`00000000 fffff803`00000000 00000000`00000000 ffffbb86`af9b71c0 : nt!KiCommitThreadWait+0x14f
        ffffb90a`cbaa7970 fffff803`1b4f6531     : ffffbb86`aa520080 fffff803`00000006 ffffb90a`cbaa7b01 ffffb90a`cbaa7b00 : nt!KeWaitForSingleObject+0x233
        ffffb90a`cbaa7a60 fffff803`1b4f65da     : ffffbb86`af9b7080 00000000`00000000 00000000`00000000 00000000`00000000 : nt!ObWaitForSingleObject+0x91
        ffffb90a`cbaa7ac0 fffff803`1b20bbb5     : ffffbb86`af9b0000 00000000`00001000 00000000`00000000 00000000`00000000 : nt!NtWaitForSingleObject+0x6a
        ffffb90a`cbaa7b00 00007ffc`51b2be24     : 00007ffc`4f5926ee 00000000`00000022 00000023`00000004 00000004`00000000 : nt!KiSystemServiceCopyEnd+0x25 (TrapFrame @ ffffb90a`cbaa7b00)
        000000eb`99f7e1f8 00007ffc`4f5926ee     : 00000000`00000022 00000023`00000004 00000004`00000000 00000000`00000024 : ntdll!NtWaitForSingleObject+0x14
        000000eb`99f7e200 00007ffc`38537bf9     : 00000000`00000000 00000000`00000001 000000eb`00000000 00000000`00001c88 : KERNELBASE!WaitForSingleObjectEx+0x8e
        000000eb`99f7e2a0 00007ffc`38537503     : 00000000`00000000 00000220`790095e0 000000eb`00000002 00000000`00000004 : appinfo!AiLaunchConsentUI+0x559
        000000eb`99f7e4c0 00007ffc`38536ba2     : 00000000`00000021 00000000`00000021 00000000`00000000 00000220`7c39e7f8 : appinfo!AiCheckLUA+0x343
        000000eb`99f7e6a0 00007ffc`50772153     : 00000220`7b1f3e00 00000220`7b245df0 00000220`7c39e7f8 00000220`7c39e860 : appinfo!RAiLaunchAdminProcess+0xbe2
        000000eb`99f7ecb0 00007ffc`507da5ea     : 00000220`7b1f3e00 00000220`7b23fae0 00000220`772b1ae0 00007ffc`00000000 : RPCRT4!Invoke+0x73
        000000eb`99f7ed60 00007ffc`50756838     : 00000220`75a80000 00007ffc`51aa7000 00000220`0000000c 
        ...................
```

在茫茫线程中一番搜寻，很快便找到了我们想要的。可以看到UAC的弹窗流程是

RAiLaunchAdminProcess -> AiCheckLUA -> AiLaunchConsentUI

接下来开始逆AiLaunchConsentUI这个函数

![image-20210404131558600](/assets/images/image-20210404131558600.png)

构造命令行后会调用AiLaunchProcess来启动consent.exe，也就是真正绘制uac窗口的程序

为了快速定位关键代码，我们切换到consent.exe，打印consent.exe的线程栈，可惜这次并没有找到我们想要的，只好接着逆向consent.exe。

同时继续提出几个问题

- 在consent绘制的uac窗口上，我们可以看到要进行权限提升的程序的路径，命令行等等相关信息，consent是如何获取这些信息的？

  ![image-20210404133752729](/assets/images/image-20210404133752729.png)

  ![image-20210404134511322](/assets/images/image-20210404134511322.png)

  答案就在consent的命令行中。consent的命令行中传入了父进程的pid（appinfo服务的进程pid），一个结构体长度以及一个指向结构体的指针，随后consent调用NtReadVirtualMemory从父进程的内存中读取结构体的内容，这个结构体中就包含了需要特权提升的进程信息。

- 特权提升的进程最终是由appinfo服务进程拉起的，但是uac窗口则是consent绘制的，那consen如何将用户的操作反馈给appinfo服务进程？

  ![image-20210404134338774](/assets/images/image-20210404134338774.png)

  同样是通过读写appinfo进程的内存实现

通过逆向找到了决定是否弹窗的关键函数

![image-20210404135241498](/assets/images/image-20210404135241498.png)

关键代码

![image-20210404135516888](/assets/images/image-20210404135516888.png)

可以看到consent是否弹窗主要由父进程传入的结构体确定，因此再返回appinfo继续逆向

详细细节有些复杂，所以直接贴部分代码

![image-20210404135951243](/assets/images/image-20210404135951243.png)

![image-20210404140004231](/assets/images/image-20210404140004231.png)

![image-20210404140056297](/assets/images/image-20210404140056297.png)

![image-20210404140115678](/assets/images/image-20210404140115678.png)

可以看到对程序所处的路径有限制，同时包含一些白名单校验，当满足这些条件后，consent便不会绘制uac窗口。

## 令牌的权限提升过程

权限提升的过程位于consent中，consent从appinfo服务进程中获取未权限提升的令牌后，调用NtQueryInformationToken获取一个权限提升的令牌（undocument的用法），随后将这个token写回到appinfo服务进程中，appinfo再使用这个提升后的令牌创建进程。

![image-20210406164130159](/assets/images/image-20210406164130159.png)

通过NtQueryInformationToken获取权限提升的令牌

![image-20210406164314330](/assets/images/image-20210406164314330.png)

将令牌写回到appinfo的进程中去



文章写得有些简略，只是大致写了部分流程。断断续续逆了快两个月，终于看到了UAC的全貌，感觉十分舒畅。

