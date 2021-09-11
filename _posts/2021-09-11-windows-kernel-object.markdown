---
layout: post
title: "Windows内核对象"
date: 2021-09-11 15:38:57 +0800
categories: kernel windows
---

## Windows Kernel Object的结构

从_OBJECT_HEADER看起

```
kd> dt nt!_OBJECT_HEADER
   +0x000 PointerCount     : Int8B
   +0x008 HandleCount      : Int8B
   +0x008 NextToFree       : Ptr64 Void
   +0x010 Lock             : _EX_PUSH_LOCK
   +0x018 TypeIndex        : UChar
   +0x019 TraceFlags       : UChar
   +0x01a InfoMask         : UChar
   +0x01b Flags            : UChar
   +0x020 ObjectCreateInfo : Ptr64 _OBJECT_CREATE_INFORMATION
   +0x020 QuotaBlockCharged : Ptr64 Void
   +0x028 SecurityDescriptor : Ptr64 Void
   +0x030 Body             : _QUAD
```

当我们查看一个windows object时，我们查看的是object的body字段。	

```
kd> !process 0 0 explorer.exe
PROCESS fffffa801a8e1b30
    SessionId: 1  Cid: 087c    Peb: 7fffffd7000  ParentCid: 0840
    DirBase: 0aa8e000  ObjectTable: fffff8a001e39d30  HandleCount: 642.
    Image: explorer.exe
```

如上，可以看到EPROCESS的位置在fffffa801a8e1b30，根据_OBJECT_HEADER的结构我们可以计算出其_OBJECT_HEADER的位置在fffffa801a8e1b30-30，即fffffa801a8e1b00上。可以使用!object来确认计算的结果是否正确

```
kd> dt _OBJECT_HEADER fffffa801a8e1b00
nt!_OBJECT_HEADER
   +0x000 PointerCount     : 0n366
   +0x008 HandleCount      : 0n7
   +0x008 NextToFree       : 0x00000000`00000007 Void
   +0x010 Lock             : _EX_PUSH_LOCK
   +0x018 TypeIndex        : 0x7 ''
   +0x019 TraceFlags       : 0 ''
   +0x01a InfoMask         : 0x8 ''
   +0x01b Flags            : 0 ''
   +0x020 ObjectCreateInfo : 0xfffffa80`1a400100 _OBJECT_CREATE_INFORMATION
   +0x020 QuotaBlockCharged : 0xfffffa80`1a400100 Void
   +0x028 SecurityDescriptor : 0xfffff8a0`01dfd8db Void
   +0x030 Body             : _QUAD
kd> !object fffffa801a8e1b30
Object: fffffa801a8e1b30  Type: (fffffa8018d42a80) Process
    ObjectHeader: fffffa801a8e1b00 (new version)
    HandleCount: 7  PointerCount: 366
```

然而_OBJECT_HEADER与Body并不是整个object的全部，实际上在object header前面还有optional headers与pool header，一个完全的windows object应该是这样的：

- _POOL_HEADER
- _OBJECT_QUOTA_CHARGES (optional)
- _OBJECT_HANDLE_DB (optional)
- _OBJECT_NAME (optional)
- _OBJECT_CREATOR_INFO (optional)
- _OBJECT_HEADER
- body 

\_OBJECT_HEADER在_OBJECT_HEADER->InfoMask中使用掩码的方式来表示哪些可选头存在

| Bit  | Type             |
| ---- | ------------------------------ |
| 0x01 | nt!_OBJECT_HEADER_CREATOR_INFO|
| 0x02 | nt!_OBJECT_HEADER_NAME_INFO|
| 0x04 | nt!_OBJECT_HEADER_HANDLE_INFO|
| 0x08 | nt!_OBJECT_HEADER_QUOTA_INFO |
| 0x10 | nt!_OBJECT_HEADER_PROCESS_INFO |

内核中存在一个数组ObpInfoMaskToOffset，我们可以根据InfoMask我们可以计算出一个数值作为数组的索引，从而获取我们想要的optional header距离object header的偏移

Offset = ObpInfoMaskToOffset[OBJECT_HEADER->InfoMask & (DesiredHeaderBit | (DesiredHeaderBit-1))]

在explorer.exe的例子中，其InfoMask值为8，因此他只有一个_OBJECT_HEADER_QUOTA_INFO的可选头，要计算出他的偏移则计算0x8 & (0x8|0x8-1) = 0x8，根据计算出的索引值找到偏移

```
kd> ?nt!ObpInfoMaskToOffset
Evaluate expression: -8796025365056 = fffff800`04085dc0
kd> db fffff800`04085dc0+0x8 L1
fffff800`04085dc8  20     
```

得到偏移为0x20，用object header的地址减去偏移即为我们想找的可选头的地址

```
kd> dt nt!_OBJECT_HEADER_QUOTA_INFO fffffa8018d42a80-20
   +0x000 PagedPoolCharge  : 0
   +0x004 NonPagedPoolCharge : 0
   +0x008 SecurityDescriptorCharge : 0x13030002
   +0x010 SecurityDescriptorQuotaBlock : (null) 
   +0x018 Reserved         : 0
```

### _OBJECT_TYPE

windows内核中有许多不同类型的对象，每个对象在object header包含了一个字段标注了其类型。在win7之前的windows版本中存在一个Type字段其包含了一个指针指向一个_OBJECT_TYPE结构体，在新版本中，这个字段变为了TypeIndex，其包含了一个全局数组nt!ObTypeIndexTable的索引，而这个数组中存着不同类型的结构体的指针。

在上述例子中，EPROCESS对象的TypeIndex为7，因此我们可以通过nt!ObTypeIndexTable[0x7]来获取指向其_OBJECT_TYPE的指针

```
kd> dt nt!_OBJECT_TYPE poi(nt!ObTypeIndexTable + ( 7 * @$ptrsize ))
   +0x000 TypeList         : _LIST_ENTRY [ 0xfffffa80`18d42a80 - 0xfffffa80`18d42a80 ]
   +0x010 Name             : _UNICODE_STRING "Process"
   +0x020 DefaultObject    : (null) 
   +0x028 Index            : 0x7 ''
   +0x02c TotalNumberOfObjects : 0x27
   +0x030 TotalNumberOfHandles : 0xf0
   +0x034 HighWaterNumberOfObjects : 0x27
   +0x038 HighWaterNumberOfHandles : 0xf2
   +0x040 TypeInfo         : _OBJECT_TYPE_INITIALIZER
   +0x0b0 TypeLock         : _EX_PUSH_LOCK
   +0x0b8 Key              : 0x636f7250
   +0x0c0 CallbackList     : _LIST_ENTRY [ 0xfffffa80`18d42b40 - 0xfffffa80`18d42b40 ]
```

可以看到，该对象是一个Process类型对象。

在windbg中可以使用"!object \ObjectTypes"来获取所有对象类型。

在windows10中，处于安全考虑，TypeIndex字段被使用异或加密

http://www.powerofcommunity.net/poc2018/nikita.pdf

### 一切皆对象——_OBJECT_TYPE对象

如果我们使用!object命令来查看一个_OBJECT_TYPE结构体，我们会发现每一个类型竟然也是作为对象存在的

```
kd> !object poi(nt!ObTypeIndexTable + ( 7 * @$ptrsize ))
Object: fffffa8018d42a80  Type: (fffffa8018d41c00) Type
    ObjectHeader: fffffa8018d42a50 (new version)
    HandleCount: 0  PointerCount: 2
    Directory Object: fffff8a0000068f0  Name: Process
```

可以看到，process类型对象的类型为Type。继续查看其object header

```
kd> dt _OBJECT_HEADER fffffa8018d42a50
nt!_OBJECT_HEADER
   +0x000 PointerCount     : 0n2
   +0x008 HandleCount      : 0n0
   +0x008 NextToFree       : (null) 
   +0x010 Lock             : _EX_PUSH_LOCK
   +0x018 TypeIndex        : 0x2 ''
   +0x019 TraceFlags       : 0 ''
   +0x01a InfoMask         : 0x3 ''
   +0x01b Flags            : 0x13 ''
   +0x020 ObjectCreateInfo : (null) 
   +0x020 QuotaBlockCharged : (null) 
   +0x028 SecurityDescriptor : (null) 
   +0x030 Body             : _QUAD
```

可以看到其TypeIndex为2，说明Type类型同样也存在nt!ObTypeIndexTable中

```
kd> dt nt!_OBJECT_TYPE poi(nt!ObTypeIndexTable + ( 2 * @$ptrsize ))
   +0x000 TypeList         : _LIST_ENTRY [ 0xfffffa80`18d41bb0 - 0xfffffa80`1b524d60 ]
   +0x010 Name             : _UNICODE_STRING "Type"
   +0x020 DefaultObject    : 0xfffff800`040839e0 Void
   +0x028 Index            : 0x2 ''
   +0x02c TotalNumberOfObjects : 0x2a
   +0x030 TotalNumberOfHandles : 0
   +0x034 HighWaterNumberOfObjects : 0x2a
   +0x038 HighWaterNumberOfHandles : 0
   +0x040 TypeInfo         : _OBJECT_TYPE_INITIALIZER
   +0x0b0 TypeLock         : _EX_PUSH_LOCK
   +0x0b8 Key              : 0x546a624f
   +0x0c0 CallbackList     : _LIST_ENTRY [ 0xfffffa80`18d41cc0 - 0xfffffa80`18d41cc0 ]
```

回到ProcessType的object header上，其InfoMask值为3，说明它具有\_OBJECT_HEADER_CREATOR_INFO与_OBJECT_HEADER_NAME_INFO两个可选头，其中\_OBJECT_HEADER_CREATOR_INFO具有一个双向链表，通过这个链表我们可以遍历所有的Type

## Windows Kernel Object存在哪

所有的对象都由windows对象管理器（Object Manager）统一管理并以namespace进行分类，每个named kernel object有一个类似路径一样的名字，例如表示C盘驱动器的对象名为**\DosDevices\C:**，其中\DosDevice就是该对象的namespace。

## 打印所有内核对象

使用Nt函数NtOpenDirectoryObject/NtQueryDirectoryObject来遍历所有的Directory，进而遍历所有对象

```cpp
//https://github.com/adobe/chromium/blob/master/sandbox/tools/finder/finder_kernel.cc

#include <iostream>
#include <Windows.h>
#include <winternl.h>

#include <ntstatus.h>
#define DIRECTORY_QUERY 1
#define BUFFER_SIZE 0x800

typedef struct _OBJDIR_INFORMATION
{
	UNICODE_STRING          ObjectName;
	UNICODE_STRING          ObjectTypeName;
	BYTE                    Data[1];
} OBJDIR_INFORMATION, * POBJDIR_INFORMATION;
typedef NTSTATUS(*PFN_NtOpenDirectoryObject)(
	_Out_ PHANDLE            DirectoryHandle,
	_In_  ACCESS_MASK        DesiredAccess,
	_In_  POBJECT_ATTRIBUTES ObjectAttributes
	);
typedef NTSTATUS(*PFN_NtQueryDirectoryObject)(
	_In_      HANDLE  DirectoryHandle,
	_Out_opt_ PVOID   Buffer,
	_In_      ULONG   Length,
	_In_      BOOLEAN ReturnSingleEntry,
	_In_      BOOLEAN RestartScan,
	_Inout_   PULONG  Context,
	_Out_opt_ PULONG  ReturnLength
	);
typedef ULONG(*PFN_RtlNtStatusToDosError)(
	NTSTATUS Status
	);
void PrintNtStatus(NTSTATUS code)
{
	LPSTR errmsg = NULL;
	if (FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM |
		FORMAT_MESSAGE_FROM_HMODULE |
		FORMAT_MESSAGE_ALLOCATE_BUFFER,
		GetModuleHandle(L"ntdll.dll"), code,
		MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
		(LPSTR)&errmsg, 0, NULL))
	{
		printf("%s\n", errmsg);
	}

}
int wmain(int argc, wchar_t** argv)
{
	std::wstring path = L"\\";
	if (argc == 2)
	{
		path = argv[1];

	}
	HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
	PFN_NtQueryDirectoryObject pfnNtQueryDirectoryObject = (PFN_NtQueryDirectoryObject)GetProcAddress(hNtdll, "NtQueryDirectoryObject");
	PFN_NtOpenDirectoryObject pfnNtOpenDirectoryObject = (PFN_NtOpenDirectoryObject)GetProcAddress(hNtdll, "NtOpenDirectoryObject");
	PFN_RtlNtStatusToDosError pfnRtlNtStatusToDosError = (PFN_RtlNtStatusToDosError)GetProcAddress(hNtdll, "RtlNtStatusToDosError");
	UNICODE_STRING unicode_str;
	unicode_str.Length = (USHORT)path.length() * 2;
	unicode_str.MaximumLength = (USHORT)path.length() * 2 + 2;
	unicode_str.Buffer = (PWSTR)path.c_str();
	OBJECT_ATTRIBUTES path_attributes;
	InitializeObjectAttributes(&path_attributes,
		&unicode_str,
		0,      // No Attributes
		NULL,   // No Root Directory
		NULL);  // No Security Descriptor
	HANDLE file_handle;
	NTSTATUS ret = 0;
	ret = pfnNtOpenDirectoryObject(&file_handle,
		DIRECTORY_QUERY,
		&path_attributes);
	if (ret != STATUS_SUCCESS)
	{
		PrintNtStatus(ret);
		return 0;
	}
	ULONG index = 0;
	ULONG returnLength;
	POBJDIR_INFORMATION buffer = (POBJDIR_INFORMATION)malloc(BUFFER_SIZE);
	while (!(ret = pfnNtQueryDirectoryObject(file_handle, buffer, BUFFER_SIZE, TRUE, FALSE, &index, &returnLength)))
	{
		wprintf(L"%d	%s	%s\n", index, buffer->ObjectName.Buffer, buffer->ObjectTypeName.Buffer);
	}
	if (ret != STATUS_NO_MORE_ENTRIES)
	{
		PrintNtStatus(ret);
		return 0;
	}
	return 0;

}

```

一些参考资料：

https://codemachine.com/articles/object_headers.html

https://stackoverflow.com/questions/2643084/sysinternals-winobj-device-listing-mechanism

https://github.com/adobe/chromium/blob/master/sandbox/tools/finder/finder_kernel.cc

https://rayanfam.com/topics/reversing-windows-internals-part1/

----

内核路漫漫。。。