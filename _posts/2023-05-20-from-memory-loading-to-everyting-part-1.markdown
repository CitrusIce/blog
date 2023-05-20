---
layout: post
title: "From Memory Loading to Everything - Part 1"
date: 2023-05-20 11:02:16 +0800
categories: windows
---

我接触 Windows 最开始看的两本书是《PE 权威指南》和《Windows 核心编程》，学这两本书的目的也很简单：实现内存加载。我们知道，要实现内存加载，最重要的是处理 PE 中的三个表：导入表，iat 和重定位表。然而跟 pe 装载有关系的表却不仅仅只有这三个，那么剩下的表都有着怎样的内容？在 PE 的装在过程中发挥了什么样的作用？

毫无疑问，仅仅处理导入表和重定位表的内存加载是不完美的，只能实现部分 pe 的加载。

这个系列目的在于提供 pe 装载部分细节的**索引**，希望读者能通过这些索引去更深入的学习，以实现完美的内存加载技术。当然，不会有现成的代码，甚至不会有太多细节。

对 pe 这些表的了解过程一定程度上也代表了我的二进制学习历程。

# PEB_LDR_DATA

尽管 PEB_LDR_DATA 并非是 pe 中的一个表，但是它记录了当前进程中到底有哪些模块被装载，如果要实现完美的内存加载，它是少不了的，因为 GetModuleHandle 是依赖于 LdrpCheckForLoadedDll ，而 LdrpCheckForLoadedDll 最终就是检查 PEB_LDR_DATA。

另外，如果要将内存加载的模块设置为主模块，需要修改 ` (HMODULE)(PVOID)NtCurrentPeb()->ImageBaseAddress`

```cpp
//0x58 bytes (sizeof)
struct _PEB_LDR_DATA
{
    ULONG Length;                                                           //0x0
    UCHAR Initialized;                                                      //0x4
    VOID* SsHandle;                                                         //0x8
    struct _LIST_ENTRY InLoadOrderModuleList;                               //0x10
    struct _LIST_ENTRY InMemoryOrderModuleList;                             //0x20
    struct _LIST_ENTRY InInitializationOrderModuleList;                     //0x30
    VOID* EntryInProgress;                                                  //0x40
    UCHAR ShutdownInProgress;                                               //0x48
    VOID* ShutdownThreadId;                                                 //0x50
}; 

//0x120 bytes (sizeof)
struct _LDR_DATA_TABLE_ENTRY
{
    struct _LIST_ENTRY InLoadOrderLinks;                                    //0x0
    struct _LIST_ENTRY InMemoryOrderLinks;                                  //0x10
    struct _LIST_ENTRY InInitializationOrderLinks;                          //0x20
    VOID* DllBase;                                                          //0x30
    VOID* EntryPoint;                                                       //0x38
    ULONG SizeOfImage;                                                      //0x40
    struct _UNICODE_STRING FullDllName;                                     //0x48
    struct _UNICODE_STRING BaseDllName;                                     //0x58
    union
    {
        UCHAR FlagGroup[4];                                                 //0x68
        ULONG Flags;                                                        //0x68
        struct
        {
            ULONG PackagedBinary:1;                                         //0x68
            ULONG MarkedForRemoval:1;                                       //0x68
            ULONG ImageDll:1;                                               //0x68
            ULONG LoadNotificationsSent:1;                                  //0x68
            ULONG TelemetryEntryProcessed:1;                                //0x68
            ULONG ProcessStaticImport:1;                                    //0x68
            ULONG InLegacyLists:1;                                          //0x68
            ULONG InIndexes:1;                                              //0x68
            ULONG ShimDll:1;                                                //0x68
            ULONG InExceptionTable:1;                                       //0x68
            ULONG ReservedFlags1:2;                                         //0x68
            ULONG LoadInProgress:1;                                         //0x68
            ULONG LoadConfigProcessed:1;                                    //0x68
            ULONG EntryProcessed:1;                                         //0x68
            ULONG ProtectDelayLoad:1;                                       //0x68
            ULONG ReservedFlags3:2;                                         //0x68
            ULONG DontCallForThreads:1;                                     //0x68
            ULONG ProcessAttachCalled:1;                                    //0x68
            ULONG ProcessAttachFailed:1;                                    //0x68
            ULONG CorDeferredValidate:1;                                    //0x68
            ULONG CorImage:1;                                               //0x68
            ULONG DontRelocate:1;                                           //0x68
            ULONG CorILOnly:1;                                              //0x68
            ULONG ChpeImage:1;                                              //0x68
            ULONG ReservedFlags5:2;                                         //0x68
            ULONG Redirected:1;                                             //0x68
            ULONG ReservedFlags6:2;                                         //0x68
            ULONG CompatDatabaseProcessed:1;                                //0x68
        };
    };
    USHORT ObsoleteLoadCount;                                               //0x6c
    USHORT TlsIndex;                                                        //0x6e
    struct _LIST_ENTRY HashLinks;                                           //0x70
    ULONG TimeDateStamp;                                                    //0x80
    struct _ACTIVATION_CONTEXT* EntryPointActivationContext;                //0x88
    VOID* Lock;                                                             //0x90
    struct _LDR_DDAG_NODE* DdagNode;                                        //0x98
    struct _LIST_ENTRY NodeModuleLink;                                      //0xa0
    struct _LDRP_LOAD_CONTEXT* LoadContext;                                 //0xb0
    VOID* ParentDllBase;                                                    //0xb8
    VOID* SwitchBackContext;                                                //0xc0
    struct _RTL_BALANCED_NODE BaseAddressIndexNode;                         //0xc8
    struct _RTL_BALANCED_NODE MappingInfoIndexNode;                         //0xe0
    ULONGLONG OriginalBase;                                                 //0xf8
    union _LARGE_INTEGER LoadTime;                                          //0x100
    ULONG BaseNameHashValue;                                                //0x108
    enum _LDR_DLL_LOAD_REASON LoadReason;                                   //0x10c
    ULONG ImplicitPathOptions;                                              //0x110
    ULONG ReferenceCount;                                                   //0x114
    ULONG DependentLoadFlags;                                               //0x118
    UCHAR SigningLevel;                                                     //0x11c
}; 
```

# TLS 表

Windows TLS (Thread Local Storage) 机制意在为每个线程提供的独立的存储空间，分为动态 TLS 和静态 TLS，动态 TLS 自然不必多说，通过 Windows Api 实现，而静态 TLS 则关乎 PE 的 TLS 表。

```cpp
typedef struct _IMAGE_TLS_DIRECTORY64 {
    ULONGLONG StartAddressOfRawData;
    ULONGLONG EndAddressOfRawData;
    ULONGLONG AddressOfIndex;         // PDWORD
    ULONGLONG AddressOfCallBacks;     // PIMAGE_TLS_CALLBACK *;
    DWORD SizeOfZeroFill;
    union {
        DWORD Characteristics;
        struct {
            DWORD Reserved0 : 20;
            DWORD Alignment : 4;
            DWORD Reserved1 : 8;
        } DUMMYSTRUCTNAME;
    } DUMMYUNIONNAME;

} IMAGE_TLS_DIRECTORY64;
```

在装载 pe 的时候，ntdll 使用 LdrpAllocateTlsEntry 为每个 image 分配 tls 表项，具体来说就是找到 image 的 tls 表，然后在内存中分配一个 buffer 将表中的数据拷贝到 buffer 中，并调用 `LdrpAcquireTlsIndex` 为这个 tls entry 分配一个 index（也就是 tls index），最后将这块 buffer 加入一个双向链表 `LdrpTlsList`。

在分配完 index 后，对于 LdrpTlsList 中的每个 tls entry，ntdll 将其包含的静态 tls data 写入 teb 中的 ThreadLocalStoragePointer 指向的数组中。

如果反汇编一段读取静态 tls 数据的代码，我们就可以看到，程序通过 tlsindex 在 ThreadLocalStoragePointer 中读取了数据。

```asm
 mov eax,108                            
 mov eax,eax                            
 mov ecx,dword ptr ds:[<_tls_index>]    
 mov rdx,qword ptr gs:[58]           
 add rax,qword ptr ds:[rdx+rcx*8]       
 mov r9d,1                              
 xor r8d,r8d                            
 mov rdx,rax               
 xor ecx,ecx                            
 call qword ptr ds:[<&MessageBoxA>]     

```

---

最近几个月一直没有写博客，这篇文章写得也很简略，一方面因为脑子里确实没什么东西，另一方面也因为工作换了，精力少了很多，我也不确定这个系列是否能写完。虽然本文技术上的内容没有写多少，但是还有其他话想说正。如我去年所写的，“事情的发展总是凡人难以预料的，通过渗透入门安全的时候我无论如何也不会想到三年后已经早已不再接触渗透”，如今这似乎像预言一样的东西确实兑现了。尽管现在做的东西已经不属于安全行业了，但是我仍然认为它跟安全有着联系，我也仍然认为我是一个搞安全的。

最后仿写一段本人刚刚接触二进制时看到的一篇大佬的文章末尾写的话，我觉得此时此刻恰如彼时彼刻：

写这篇文章时笔者不禁想起了几年前刚成为黑客只是想绕过 360 做免杀的自己，如今几年过去了以笔者的能力自认为做到完美的免杀变成易如反掌的事情了，但是笔者却成为了一个送外卖的外卖小哥. 安全路漫漫, 要学的东西还有很多。