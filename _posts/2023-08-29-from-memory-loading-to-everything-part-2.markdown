---
layout: post
title: "From Memory Loading to Everything - Part 2"
date: 2023-08-29 10:20:56 +0800
categories: windows
---

上一篇文章中我介绍了 tls 表以及 ldr，本文将介绍资源表、LdrpHashTable、异常表和 MFC 程序加载时出现的问题等相关内容。

# Resource Table

pe 的资源表用于存放资源文件，我们 `FindResourceA` 与 `LoadResource` 来从资源表中获取资源。

`FindResourceA` 是依赖 `BasepMapModuleHandle` 获取到 image 的句柄（基址）的，当我们传入 `NULL` 时，`BasepMapModuleHandle` 将取 `NtCurrentPeb()->ImageBaseAddress` 作为返回结果


# LdrpHashTable

编程中往往会用到 `GetModuleHandle` 找到模块的基址，这跟 LdrpHashTable 有关。

LdrpHashTable 是一个存放模块列表的 hash 表，而 GetModuleHandle 就是通过这个表进行模块的查询

```cpp
LIST_ENTRY LdrpHashTable[LDRP_HASH_TABLE_SIZE];
```

LdrDataTableEntry->HashLink 这个 hashlink 就与一个 listentry 相连接，因此可以通过找到一个模块的 ldrentry 间接找到这个整个 LdrpHashTable。

# Exception Table

x64 的异常与 x86 不同，不再依赖异常链表，而是将异常相关信息写在 pe 的 exception table 中，在 pe 装载后对 exception table 调用 `RtlAddFunctionTable` 注册异常。


# MFC 程序

尝试加载一下 mfc 程序，发现失败了。研究了一下发现是 `GetModuldeFileName` 的问题。

`GetModuldeFileName` 根据传入的 handle 在 InMemoryOrderLinks 链表中寻找对应的 ldr entry，然后返回 entry 中的 `FullDllName`。

对于内存加载的模块我没有添加对应的 ldr entry，因此导致 `GetModuldeFileName` 失败。而如果要添加 ldr entry，由于各个 windows 版本中的 ldr entry 结构并不一样，如何处理以保证兼容性也是一个问题。

报错的位置：

```cpp
v6 = GetModuleFileNameW(this->m_hInstance, Filename, 0x104u);
  if ( (!v6 || v6 == 260)
    && AfxAssertFailedLine("D:\\agent\\_work\\13\\s\\src\\vctools\\VC7Libs\\Ship\\ATLMFC\\Src\\MFC\\appinit.cpp", 75) )
  {
    __debugbreak();
  }
```

```
0:000> k
 # Child-SP          RetAddr               Call Site
00 000000ed`ba2f7958 00007ffd`37294d13     ntdll!RtlPcToFileHeader
01 000000ed`ba2f7960 00000001`40b14d8f     KERNELBASE!GetModuleHandleExW+0x83
02 000000ed`ba2f79a0 00000001`40b17233     encrytStringTool!common_message_window<char>+0x6f [minkernel\crts\ucrt\src\appcrt\misc\dbgrpt.cpp @ 333] 
03 000000ed`ba2f9c30 00000001`40b518dc     encrytStringTool!__acrt_MessageWindowA+0x43 [minkernel\crts\ucrt\src\appcrt\misc\dbgrpt.cpp @ 453] 
04 000000ed`ba2f9c70 00000001`40b170b0     encrytStringTool!_VCrtDbgReportA+0x99c [minkernel\crts\ucrt\src\appcrt\misc\dbgrptt.cpp @ 420] 
05 000000ed`ba2fed60 00000001`404352b4     encrytStringTool!_CrtDbgReport+0x60 [minkernel\crts\ucrt\src\appcrt\misc\dbgrpt.cpp @ 263] 
06 000000ed`ba2fedc0 00000001`40493f70     encrytStringTool!AfxAssertFailedLine+0x94 [C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Tools\MSVC\14.29.30037\atlmfc\include\afx.h @ 317] 
07 000000ed`ba2fef60 00000001`40493e03     encrytStringTool!CWinApp::SetCurrentHandles+0x110 [D:\agent\_work\13\s\src\vctools\VC7Libs\Ship\ATLMFC\Src\MFC\appinit.cpp @ 75] 
08 000000ed`ba2ff860 00000001`40baba30     encrytStringTool!AfxWinInit+0xc3 [D:\agent\_work\13\s\src\vctools\VC7Libs\Ship\ATLMFC\Src\MFC\appinit.cpp @ 46] 
09 000000ed`ba2ff8a0 00000001`40bab992     encrytStringTool!AfxWinMain+0x80 [D:\agent\_work\13\s\src\vctools\VC7Libs\Ship\ATLMFC\Src\MFC\winmain.cpp @ 29] 
0a 000000ed`ba2ff960 00000001`40aadd72     encrytStringTool!wWinMain+0x32 [D:\agent\_work\13\s\src\vctools\VC7Libs\Ship\ATLMFC\Src\MFC\appmodul.cpp @ 26] 
0b 000000ed`ba2ff990 00000001`40aadc1e     encrytStringTool!invoke_main+0x32 [D:\agent\_work\13\s\src\vctools\crt\vcstartup\src\startup\exe_common.inl @ 123] 
0c 000000ed`ba2ff9d0 00000001`40aadade     encrytStringTool!__scrt_common_main_seh+0x12e [D:\agent\_work\13\s\src\vctools\crt\vcstartup\src\startup\exe_common.inl @ 288] 
0d 000000ed`ba2ffa40 00000001`40aade0e     encrytStringTool!__scrt_common_main+0xe [D:\agent\_work\13\s\src\vctools\crt\vcstartup\src\startup\exe_common.inl @ 331] 
*** WARNING: Unable to verify checksum for test.exe
0e 000000ed`ba2ffa70 00007ff7`99381ed2     encrytStringTool!wWinMainCRTStartup+0xe [D:\agent\_work\13\s\src\vctools\crt\vcstartup\src\startup\exe_wwinmain.cpp @ 17] 
0f 000000ed`ba2ffaa0 00007ff7`9938256f     test!CallEntry+0xb2 
```

深入这个函数，GetModuleFileNameW->LdrGetDllFullName->LdrpFindLoadedDllByHandle
最终通过 LdrpModuleBaseAddressIndex 这个东西找到 dllentry。

继续研究，通过 `LdrpModuleBaseAddressIndex` 的引用找到了函数 `LdrpInsertModuleToIndexLockHeld` ，这个函数处理了 LdrpMappingInfoIndex 和 LdrpModuleBaseAddressIndex，可见这两个东西都是我们需要处理的。

那么这两个东西到底是个什么结构？在一些逆向以及查找资料后，得知这个东西是个红黑树

```
RtlRbInsertNodeEx((unsigned __int64 *)&LdrpMappingInfoIndex, v7, v8, (unsigned __int64)&a1->MappingInfoIndexNode);
 result = RtlRbInsertNodeEx(
             (unsigned __int64 *)&LdrpModuleBaseAddressIndex,
             v10,
             v4,
             (unsigned __int64)&a1->BaseAddressIndexNode);
```

```cpp
typedef struct _RTL_BALANCED_NODE
{
    union
    {
        struct _RTL_BALANCED_NODE *Children[2];
        struct
        {
            struct _RTL_BALANCED_NODE *Left;
            struct _RTL_BALANCED_NODE *Right;
        };
    };
    union
    {
        UCHAR Red : 1;
        UCHAR Balance : 2;
        ULONG_PTR ParentValue;
    };
} RTL_BALANCED_NODE, *PRTL_BALANCED_NODE;

typedef struct _RTL_RB_TREE {
	PRTL_BALANCED_NODE Root;
	PRTL_BALANCED_NODE Min;
} RTL_RB_TREE, * PRTL_RB_TREE;

```

搞清楚了这两个东西是个红黑树，那么还需要知道这两个结构存的是什么内容的数据，继续逆向，得知 ldr data table entry 的 MappingInfoIndexNode 对应的 LdrpMappingInfoIndex，BaseAddressIndexNode 对应 LdrpModuleBaseAddressIndex。

红黑树的节点是可以通过 ParentValue 找到父节点的，因此定位到一棵树的 root 是可以做到，只要能找到任意一个节点就可以追寻到 root。定位到 root 以后直接调用 `RtlRbInsertNodeEx` 即可。

----

断断续续总算是把这篇文章弄完了。由于实在是没有精力，脑子里根本构建不出整个文章的思路，所以写得很散，只是潜意识觉得文章应该有什么就把该有的堆上去，还请见谅。

搞区块链以后常常会后悔，因为自己抛弃了一个安逸的环境。虽然这些后悔是我早已预料的，但是我还是高估了我对变化的环境的承受能力，我往往感到精疲力尽，并在想如果我当时没有做出这样的选择，我应该沉浸在 ida 和 windows 的世界里，享受轻松无压力的生活。尽管有一些言论是说“让自己走出舒适区”，但我却并不认同。只要这个舒适区是可持续的，那么一直待在里面没有什么不好。不过，虽然我嘴上是不认同这种观点，但是我实际的选择上却是倾向于认同的，也许是因为我还是想做一点事才这样选择。

博客我还是会尽力写，因为一方面我不想说让我二进制这块的学习就这样停滞，另外我也仍然想在安全这块有所成就，不过写的速度是不会像以前那样一个月一篇了。不过也无所谓，贵在坚持。