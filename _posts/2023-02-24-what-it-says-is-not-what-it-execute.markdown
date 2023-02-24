---
layout: post
title: "What It Says Is Not What It eXecute"
date: 2023-02-24 16:08:51 +0800
categories: debugging
---

对于每个程序员来说，编程时最依赖也最为可靠的便是官方给的文档以及 sdk 中的种种信息。然而即便是官网文档，其内容也并非完全正确。本文将分享我最近调试的两个bug。

# EnumDesktops

这是一个枚举指定 window station 上所有 desktop 的函数

```cpp
BOOL EnumDesktopsA(
  [in, optional] HWINSTA          hwinsta,
  [in]           DESKTOPENUMPROCA lpEnumFunc,
  [in]           LPARAM           lParam
);
```

关于第一个参数，文档写的是如果是 NULL 则当前的 window station 会被使用

`[in, optional] hwinsta`

A handle to the window station whose desktops are to be enumerated. This handle is returned by the [CreateWindowStation](https://learn.microsoft.com/en-us/windows/desktop/api/winuser/nf-winuser-createwindowstationa), [GetProcessWindowStation](https://learn.microsoft.com/en-us/windows/desktop/api/winuser/nf-winuser-getprocesswindowstation), or [OpenWindowStation](https://learn.microsoft.com/en-us/windows/desktop/api/winuser/nf-winuser-openwindowstationa) function, and must have the WINSTA_ENUMDESKTOPS access right. For more information, see [Window Station Security and Access Rights](https://learn.microsoft.com/en-us/windows/desktop/winstation/window-station-security-and-access-rights).

If this parameter is NULL, the current window station is used.

实际上当 window station 为 NULL 时则会在回调中返回 winstation 的列表，也就是说此时该函数并不会返回desktop的列表，而是返回所有window station的列表。

调用链：
`user32!InternalEnumObjects` > `NtUserBuildNameList` > `_BuildNameList`

根据代码可以看到，当给 `_BuildNameList` 传入的 pwinsta 为 NULL 时，该函数返回的是 winstation 的列表

```cpp
    /*
     * If we're enumerating windowstations, pwinsta is NULL.  Otherwise,
     * we're enumerating desktops.
     */
    if (pwinsta == NULL) {
        pobj  = (PBYTE)grpWinStaList;
        amDesired = WINSTA_ENUMERATE;
        pGenericMapping = &WinStaMapping;
        iNext = FIELD_OFFSET(WINDOWSTATION, rpwinstaNext);
    } else {
        pobj = (PBYTE)pwinsta->rpdeskList;
        amDesired = DESKTOP_ENUMERATE;
        pGenericMapping = &DesktopMapping;
        iNext = FIELD_OFFSET(DESKTOP, rpdeskNext);
    }

```


# ZwMapViewOfSection

这倒不是 msdn 上文档出错，而是我不知道从哪搞过来的一份 ntdll 声明出错了。

MSDN 上函数的声明

```cpp
NTSYSAPI NTSTATUS ZwMapViewOfSection(
  [in]                HANDLE          SectionHandle,
  [in]                HANDLE          ProcessHandle,
  [in, out]           PVOID           *BaseAddress,
  [in]                ULONG_PTR       ZeroBits,
  [in]                SIZE_T          CommitSize,
  [in, out, optional] PLARGE_INTEGER  SectionOffset,
  [in, out]           PSIZE_T         ViewSize,
  [in]                SECTION_INHERIT InheritDisposition,
  [in]                ULONG           AllocationType,
  [in]                ULONG           Win32Protect
);
```

头文件中的声明

```cpp
NTSYSAPI
NTSTATUS
NTAPI
ZwMapViewOfSection (
    IN HANDLE SectionHandle,
    IN HANDLE ProcessHandle,
    IN OUT PVOID *BaseAddress,
    IN ULONG ZeroBits,
    IN ULONG CommitSize,
    IN OUT PLARGE_INTEGER SectionOffset OPTIONAL,
    IN OUT PULONG ViewSize,
    IN SECTION_INHERIT InheritDisposition,
    IN ULONG AllocationType,
    IN ULONG Protect
    );
```

可以看到 CommitSize 和 ZeroBits 的大小在 x64 的情况下是不对的，ULONG 是 4 字节而 ULONG_PTR 和 SIZE_T 都是 8 字节。这就导致了在传参的时候，原来栈上杂乱的数据会影响到这两个参数的高位，导致传参不正确。

---

之前读了一篇关于代码分析的论文，名字叫《What You See Is Not What You eXecute》，所以我就也模仿了一下起了这么一个标题。