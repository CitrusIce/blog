---
layout: post
title: "GDI Handle Manager"
date: 2022-11-23 20:40:29 +0800
categories: windows re pwn
---

Windows 10 rs1 1607 Anniversary Update 后，微软针对 gdi abuse 实施了缓解措施，让 gdicell 结构体无法在泄露 kernel address，同时 gdi handle manager 也有了一系列更新。

首先有了新的全局变量 `win32kbase!gpHandleManager`，由 `GdiHandleManager::Create` 创建

```
00000000 HandleManager   struc ; (sizeof=0x20, mappedto_28)
00000000 field_0         dd ?
00000004 field_4         dd ?
00000008 MaxHandleCount  dd ?
0000000C field_C         dd ?
00000010 HandleEntryDirectory dq ?
00000018 field_18        dq ?
00000020 HandleManager   ends
```

HandleEntryDirectory 是个 0x810 大小的表，其中包含了 256 个指向 EntryTable 的指针

```
00000000 HandleEntryDirectory struc ; (sizeof=0x810, mappedto_29)
00000000 header          dq ?
00000008 EntryTableArray dq 256 dup(?)
00000808 MaxHandle       dq ?
00000810 HandleEntryDirectory ends
```

HandleEntryTable 是个动态大小的结构，其 header 为 0x20 大小，整体大小为 `0x18*MaxHandleCount+0x20`。TableContentPtr 指向 Table 的 content 部分。

```
00000000 HandleEntryTable struc ; (sizeof=0x20, mappedto_30)
00000000 TableContentPtr dq ?
00000008 MaxHandleCount  dd ?
0000000C field_C         dd ?
00000010 field_10        dq ?
00000018 LookupTable     dq ?
00000020 HandleEntryTable ends
```

在 header 的 0x18 位置还有一个指向 lookup table 的指针，lookup table 为如下结构

```
00000000 HandleLookupTable struc ; (sizeof=0x10, mappedto_31)
00000000 TableContentPtr dq ?
00000008 MaxHandleCount  dq ?
00000010 HandleLookupTable ends
```

整个 lookup table 的大小为 ` size = 0x10 + (8 * ((unsigned __int64)(unsigned int)(handle_num + 0xFF) >> 8))`，0x10 为 header 大小。

lookuptable 的内容没逆出来，不知道从哪入手，参考了一下别人的最终搞明白了。每个 lookup table 中的 entry 是一个指针，指向一个数组，数组中存的是真正的 LOOKUP_ENTRY，第一个字段是个锁，第二个字段就是真正的 gdi object 地址

```cpp
 struct LookupEntryAddress {  
 LOOKUP_ENTRY *leaddress ;  
 } ; 

 struct LOOKUP_ENTRY {  
 DWORD64 lock;  
 PVOID64 GdiObjectAddress;  
 }; 
```

Reference：

[Center of Vulnerability Research: Windows 10 Anniversary Update: GDI handle management and vulnerabilities exploitation](http://cvr-data.blogspot.com/2016/11/windows-10-anniversary-update-gdi.html)