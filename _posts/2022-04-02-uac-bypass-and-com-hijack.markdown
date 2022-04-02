---
layout: post
title: "UAC Bypass与COM劫持"
date: 2022-04-02 20:29:18 +0800
categories: reverse-engineering uac-bypass com-hijack windows
---

事情的起因源于朋友问我关于 com 劫持能否用于过 uac，在我的认知里，无论是注册 com、修改 com 相关注册表都需要管理员权限，因为那些项一般都是在 HKLM 中的，因此 com 劫持肯定无法用于过 UAC。然而第二天他就丢来了一个文章 [COM Hijacking « 倾旋的博客](http://payloads.online/archivers/2018-10-14/1/)，文章的最后写了利用 eventvwr.exe 进行 com 劫持的利用。 

![](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/Pasted%20image%2020220331205325.png)

首先这打破了我认知上的误区，注册 com 其实并不一定需要管理员，将 com 组件注册到 HKLM 下面确实是需要管理员权限的，但是我们还可以将 com 组件注册在 HKCU 下面，这样这个 com 组件只有当前用户可以使用。

这个过 uac 的原理似乎很简单，浏览相关文章后，大概了解了原因

> 在 windows 注册表中， HKCR 只是 HKLM\\Software\\Classes 与 HKCU\\Software\\Classes 的组合。在 HKCU 中写的键值会被合并到 HKCR 中。程序在读取 HKCR 中的内容时会先读取 HKCU 中的项，如果没有再读取 HKLM 中的项。

所以可以往 HKCU 中添加 eventvwr 用到的一个 com 组件的项，eventvwr 在加载 com 访问 HKCR 的过程中，会先查找 HKCU 中的项，然后才是 HKLM 中的项，进而进行劫持。

但事实似乎又不是这样，如果对于任意 com 组件，都可以通过 hkcu 中写相应的项进行劫持，那样引起的安全问题是巨大的，在浏览文章的过程中，我也看到了微软早已对这种劫持思路有所防范：

[Application Compatibility: UAC: COM Per-User Configuration \| Microsoft Docs](https://docs.microsoft.com/en-us/previous-versions/bb756926(v=msdn.10))

- Beginning with Windows Vista® and Windows Server® 2008, if the integrity level of a process is higher than Medium, the COM runtime ignores per-user COM configuration and accesses only per-machine COM configuration. This action reduces the surface area for elevation of privilege attacks, preventing a process with standard user privileges from configuring a COM object with arbitrary code and having this code called from an elevated process.

大意是 elevated 的进程只会根据 HKLM 中的 com 配置去调用 com 对象而不会根据 HCKU 中的 com 配置去调用对象。

这与上面的 com 劫持案例有明显的冲突，于是我决定写个 com 组件注册到 HKCU 下，然后以管理权限运行一个 loader 尝试加载自己的 com 组件试验一下。

结论：

![](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/Pasted%20image%2020220331213409.png)

那么为什么 eventvwr 又可以进行 uac bypass 呢？

eventvwr 实际上会去直接调用 mmc 打开事件查看器，mmc 加载 com 时会去读取相应的注册表项，其调用栈如下：

![](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/Pasted%20image%2020220402151116.png)

ida 分析其读取注册表加载 com 组件的代码，其流程大致如下

```cpp
_snwprintf_s(Buffer, 0x400ui64, 0xFFFFFFFFFFFFFFFFui64, L"CLSID\\%s\\InprocServer32", v18);
v6 = RegOpenKeyExW (HKEY_CLASSES_ROOT, Buffer, 0, 0x20019u, &hKey);
v7 = RegQueryValueExW(hKey, 0i64, 0i64, &Type, 0i64, cbData)
v10 = LoadLibraryExW(Data, 0i64, 8u);
v11 = GetProcAddress(v10, "DllGetClassObject")) 
v12 = ((__int64 (__fastcall *)(const __m128i *, GUID *, DWORD *))v11)(a1, &IID_IClassFactory, lpcbData);
```

正与我猜测的一致，clr 调用 com 模块并不是通过 CoCreateInstance 加载的，而是自己重新实现了 com 加载，导致了可以被 com 劫持。

那么在正常的 com 加载流程中为什么不能进行劫持呢？

用 procmon 观察普通的 com 加载流程，发现在 combase.dll 中，通过调用 CComRegCatalog :: GetClassInfoW 获取 com 信息，然后进行加载。使用 RegOpenKeyExW 打开相应注册表项时，并非直接使用 HKEY_CLASSES_ROOT 读取对应注册表项，而是从使用了对象中存储的一个注册表句柄。

伪代码

```cpp
hKey = this->m_hkeyClassesRoot;
RegOpenKeyExW(hKey, SubKey, 0, 0x20019, &hkey);
```

而这个句柄则是通过 OpenClassesRootKeyExW 获取的。

OpenClassesRootKeyExW 根据用户权限打开不同的注册表项作为 HKCR 供之后 com 加载使用

```cpp
if(bElevated)
{
    v6 = RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"Software\\Classes", 0, 0x2000000u, &hKey);
}
else
{
    v15 = RegOpenUserClassesRoot(TokenHandle, 0, 0x2000000u, &hKey);
}
```

至此所有疑问全部解决

ps:
尽管这种 uac 绕过的方式已经有四五年之久，但是网上真正深入去分析这个绕过成因的文章却少之又少，谈到为什么可以绕过，仅仅简单提到了 HKCU 与 HKLM 键值读取的先后顺序，其底层的真正逻辑又有多少人关注呢？单纯学会绕过技术本身是没有意义的。最近拜读了一下四哥早年那篇《你尽力了吗？》的文章，我觉得里面很多话都说的相当有价值，也说出了我的心声，我摘录一小段作为本文的结尾，希望大家都能有所收获。

> 我一直都希望大家从这里学到的不是技术本身，而是学习方法和一种不再狂热的淡然。很多技术，明天就会过时，如果你掌握的是学习方法，那你还有下一个机会，如果你掌握的仅仅是这个技术本身，你就没有机会了。
