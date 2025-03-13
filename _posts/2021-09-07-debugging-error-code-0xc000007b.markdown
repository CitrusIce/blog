---
layout: post
title: "调试PE装载过程——0xC000007B"
date: 2021-09-07 15:02:28 +0800
categories: reverse-engineering debugging PEPacker
---

自己写了个壳，对win10上一些程序加壳后发现程序无法运行，错误提示为0xC000007B，改来改去也找不到原因，于是准备调式一下，本文记录部分调试的过程以及思路。



0xC000007B很明显是一个NTSTATUS值，其对应的宏为STATUS_INVALID_IMAGE_FORMAT，这表明加壳后的PE文件对于操作系统来说是一个非法的PE文件，那么首先想到的就是在创建进程的过程中由于PE格式错误而导致进程创建失败。由于之前存在知识的误区，以为ntdll以及pe文件的装载是在内核中进行的，导致我调了半天NtCreateUserProcess。后来当我发现NtCreateUserProcess最终成功创建了进程之后我才醒悟，镜像的装载应该是在三环中由ntdll进行的。

尽管镜像的装载是在三环进行，但这并不代表可以使用三环调试器去调试镜像的装载过程，三环调试的入口在镜像装载之后，这使得无法在三环调试镜像装载的过程，还是需要靠内核调试。



首先用脚本断在进程创建成功之后，并切换到目标进程空间。由于此时peb的ldr项没有被初始化所以无法自动加载符号，需要手动指定ntdll的机制来装载符号。用内存搜索的方式搜索MZ头或者切换到其他进程空间查看ntdll的基址。在找到基址之后使用

```
1: kd> .reload ntdll.dll=00007ffe`27f10000,001F5000
```

手动装载符号。

开始定位问题，当程序装在失败后，由于进程已经创建，肯定需要调用ntdll!NtTerminateProcess终止进程，因此在这里下断，然后继续执行，当出现错误窗口后点击确定，程序会断在ntdll!NtTerminateProcess，此时查看调用堆栈

```
0: kd> bp /1 ntdll!NtTerminateProcess
0: kd> g
Breakpoint 2 hit
ntdll!NtTerminateProcess:
0033:00007ffe`27fac310 4c8bd1          mov     r10,rcx
1: kd> k
 # Child-SP          RetAddr               Call Site
00 00000012`f84ef568 00007ffe`27fd2375     ntdll!NtTerminateProcess
01 00000012`f84ef570 00007ffe`27f847c3     ntdll!_LdrpInitialize+0x4db99
02 00000012`f84ef610 00007ffe`27f8476e     ntdll!LdrpInitialize+0x3b
03 00000012`f84ef640 00000000`00000000     ntdll!LdrInitializeThunk+0xe
```

看到程序在_LdrpInitialize调用了退出函数。

通过ida看到有许多分支都可以导致\_LdrpInitialize失败，为了确定失败的具体地方，在\_LdrpInitialize下断，用pa命令trace程序的执行流程。

```
1: kd> bp /p @$proc /1 ntdll!_LdrpInitialize
1: kd> g
Breakpoint 1 hit
ntdll!_LdrpInitialize:
0033:00007ffe`27f847dc 4889542410      mov     qword ptr [rsp+10h],rdx
1: kd> pa ntdll!_LdrpInitialize+0x4db89
ntdll!_LdrpInitialize+0x5:
0033:00007ffe`27f847e1 53              push    rbx

......

ntdll!_LdrpInitialize+0x4d93a:
0033:00007ffe`27fd2116 e845fa0000      call    ntdll!LdrpInitializeProcess (00007ffe`27fe1b60)
ntdll!_LdrpInitialize+0x4d93f:
0033:00007ffe`27fd211b 8bf8            mov     edi,eax
ntdll!_LdrpInitialize+0x4d941:
0033:00007ffe`27fd211d 898424b0000000  mov     dword ptr [rsp+0B0h],eax
ntdll!_LdrpInitialize+0x4d948:
0033:00007ffe`27fd2124 85c0            test    eax,eax
ntdll!_LdrpInitialize+0x4d94a:
0033:00007ffe`27fd2126 794b            jns     ntdll!_LdrpInitialize+0x4d997 (00007ffe`27fd2173)
ntdll!_LdrpInitialize+0x4d94c:
0033:00007ffe`27fd2128 8b0582390a00    mov     eax,dword ptr [ntdll!LdrpDebugFlags (00007ffe`28075ab0)]
ntdll!_LdrpInitialize+0x4d952:
0033:00007ffe`27fd212e a803            test    al,3
ntdll!_LdrpInitialize+0x4d954:
0033:00007ffe`27fd2130 7431            je      ntdll!_LdrpInitialize+0x4d987 (00007ffe`27fd2163)
ntdll!_LdrpInitialize+0x4d987:
0033:00007ffe`27fd2163 a810            test    al,10h
ntdll!_LdrpInitialize+0x4d989:
0033:00007ffe`27fd2165 7401            je      ntdll!_LdrpInitialize+0x4d98c (00007ffe`27fd2168)
ntdll!_LdrpInitialize+0x4d98c:
0033:00007ffe`27fd2168 41be00200000    mov     r14d,2000h
ntdll!_LdrpInitialize+0x4d992:
0033:00007ffe`27fd216e e9f826fbff      jmp     ntdll!_LdrpInitialize+0x8f (00007ffe`27f8486b)
ntdll!_LdrpInitialize+0x8f:
0033:00007ffe`27f8486b 85ff            test    edi,edi
ntdll!_LdrpInitialize+0x91:
0033:00007ffe`27f8486d 0f88f0da0400    js      ntdll!_LdrpInitialize+0x4db87 (00007ffe`27fd2363)
ntdll!_LdrpInitialize+0x4db87:
0033:00007ffe`27fd2363 8bcf            mov     ecx,edi
ntdll!_LdrpInitialize+0x4db89:
0033:00007ffe`27fd2365 e86ee40000      call    ntdll!LdrpInitializationFailure (00007ffe`27fe07d8)
```

可以看到在程序调用LdrpInitializeProcess后执行流程走向了失败，在call    ntdll!LdrpInitializeProcess的下一条指令下断，断下后查看函数返回值发现正是所报出的错误代码

```
0: kd> bp /1 00007ffe`27fd211b
0: kd> g
Breakpoint 1 hit
ntdll!_LdrpInitialize+0x4d93f:
0033:00007ffe`27fd211b 8bf8            mov     edi,eax
0: kd> r rax
rax=00000000c000007b
```

层层深入LdrpInitializeProcess，最终定位到问题位于LdrpProcessMappedModule

![image-20210812171334927](/assets/images/image-20210812171334927.png)

问题来源于gs机制，由于LdrInitSecurityCookie调用失败返回0导致返回0xC000007B

继续深入：

LdrpFetchAddressOfSecurityCookie 失败 返回0

LdrImageDirectoryEntryToLoadConfig失败 返回0

![image-20210813102630235](/assets/images/image-20210813102630235.png)

分析代码发现LdrImageDirectoryEntryToLoadConfig会去寻找pe中的load config数据目录项，而程序经过加壳后把这块去掉了，因此无法找到



加上了原有的loadconfig数据目录项后又出现了另一个错误，报错同样是0xC000007B，问题出在LdrpFetchAddressOfSecurityCookie中

```
ntdll!LdrpFetchAddressOfSecurityCookie+0x4a:
0033:00007ffe`27f431fa 488b7858        mov     rdi,qword ptr [rax+58h] ds:002b:00007ff7`fe5e1498=0000000140032ce0
rax=00007ff7fe5e1440 rbx=00000030ab39eeb8 rcx=00007ff7fe580100
rdx=0000000000008664 rsi=00007ff7fe580000 rdi=0000000140032ce0
rip=00007ffe27f431fe rsp=00000030ab39ee40 rbp=0000000000084000
 r8=00007ff7fe5e1440  r9=00000030ab39ee00 r10=00007ff7fe580100
r11=00007ff7fe5e1440 r12=0000000000000000 r13=0000000000000003
r14=00000030ab39eeb0 r15=0000000000000000
iopl=0         nv up ei pl nz na pe nc
cs=0033  ss=002b  ds=002b  es=002b  fs=0053  gs=002b             efl=00000202
```

在获取了load config数据目录项的地址后，会将地址存在rax中，随后会去找rax+58h(88)中存的值放入rdi。这里rax指向的便是load config table，而0x58的偏移则为SecurityCookie

> 60/88 \| 4/8  \| SecurityCookie \| A pointer to a cookie that is used by Visual C++ or GS implementation. 

这个值是一个存放在表中的pointer，可以看到rdi中的地址是未经重定位的，因此导致了指针指向的位置不正确。

解决方案有两个，分析LdrpProcessMappedModule函数的逻辑可以发现即使LdrInitSecurityCookie调用失败也有另一种情况可以使代码走向成功的分支，即OSVersion<7，因此最简单的解决方案为修改PE头的字段则可以解决；另一种方案则是为PE加入load configuration directory，并为其在重定位表中加入指向SecurityCookie的重定位项。



参考资料：

https://github.com/upx/upx/issues/154

https://docs.microsoft.com/en-us/windows/win32/debug/pe-format#the-load-configuration-structure-image-only

------

在调试过程中修改了一个小脚本用于在IDA里直观的查看执行流程

```python
# https://unit42.paloaltonetworks.com/using-idapython-to-make-your-life-easier-part-4/
import idaapi
import re

info = idaapi.get_inf_structure()
if info.is_64bit():
    DEFAULT_REGEX = "([0-9A-Fa-f]{8})`([0-9A-Fa-f]{8})"
else:
    DEFAULT_REGEX = "([0-9A-Fa-f]{4})`([0-9A-Fa-f]{4})"

COLOR = [0xF2D475, 0xF2BD52, 0xBC7D2D, 0x6D4100]

addrList = []


def get_new_color(current_color):
    # colors = [0xFFE699, 0xFFCC33, 0xE6AC00, 0xB38600]
    if current_color == 0xFFFFFF:
        return COLOR[0]
    if current_color in COLOR:
        pos = COLOR.index(current_color)
        if pos == len(COLOR) - 1:
            return COLOR[pos]
        else:
            return COLOR[pos + 1]
    return 0xFFFFFF

def unhighlight():
    global addrList
    for addr in addrList:
        idaapi.set_item_color(addr, 0xffffff)
    addrList = []


def highlight(path,pattern=None):
    # read trace address file
    addrsFile = open(
        path, "r", 0
    )
    lines = addrsFile.readlines()
    if pattern is None:
        pattern = DEFAULT_REGEX

    for line in lines:
        # print(line)
        r = re.search(pattern, line)
        if r is not None:
            # print(r.groups())
            addr = int(r.groups()[0] + r.groups()[1], 16)
            # try:

            #     hexAddr = long(addr.replace("`", "")[0:16], 16)
            #     print(hexAddr)
            # except:
            #     continue

            addrColor = idaapi.get_item_color(addr)
            newColor = get_new_color(addrColor)
            idaapi.set_item_color(addr, newColor)
            addrList.append(addr)

    print("success!")

print("""Trace HighLighter Usage:
highlight(file_path,pattern=None)
unhight()
""")
```

首先在windbg中.logopen打开log，然后执行pa等trace命令，最后.logclose，在IDA控制台调用函数highlight(file_path,pattern=None)即可根据trace的log对执行的代码进行标记。

效果：

![image-20210907150755293](/assets/images/image-20210907150755293.png)





