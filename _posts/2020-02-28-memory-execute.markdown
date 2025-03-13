---
layout: post
title: "使用内存加载躲避静态查杀"
date: 2020-02-28 15:34:38 +0800
categories: anti-av post-exploition
---
在进行后渗透阶段的过程中，首先要面临的问题就是免杀。如果服务器安装了反病毒软件，那不管是用马进行权限维持还是上传提权exp进行提权，甚至使用一些隧道工具（如ew）都将都到影响。如果是使用msf/cs等工具可以使用加载shellcode的方式进行免杀，但是涉及到一些常用工具的免杀就需要用修改源码、修改特征码的方式进行处理。这种处理不但烦琐而且不具有通用性，因此开发一种通用的工具来进行免杀是必要的。

本文将只探讨思路，不涉及具体实现。

# 特征码技术与免杀

> 特征码技术：运用程序中某一段或几段64字节以下的代码作为判别程序病毒的主要依据

谈到杀毒软件就不得不说特征码技术，尽管历史悠久，但到目前为止仍是各大杀毒软件判断可执行程序的主要手段。shellcode分离免杀之所以能获得很好的效果就是因为shellcode加载器本身并不包含恶意代码，自然也不会包含恶意软件的特征码，而只有当加载器运行时，它才会从程序之外加载shellcode执行。

借鉴shellcode分离免杀的思路，如果将pe文件以加密的形式存储，使用加载器读取pe文件并解密，最后放到内存中执行，那么程序的免杀性将大大地提高。实际上类似的技术早在至少08年就被提出过，叫做反射型dll注入（reflective dll injection），通过内存而不是从磁盘上加载dll。要实现从内存加载可执行程序并不困难，只要了解操作系统如何将exe加载到内存并编程重新实现就可以了。

# 实现原理

exe程序被执行的过程：

1. windows pe loader读取pe文件，检查pe文件的有效性。
2. 根据pe文件头中的IMAGE_OPTIONAL_HEADER.SizeOfImage申请一块空间
3. pe loader将pe文件按IMAGE_OPTIONAL_HEADER.SectionAlignment展开，将pe文件装载到内存空间。
4. 根据pe文件的导入表，pe loader将pe所需要的dll加载进地址空间并更新IAT
5. 如果没有加载在pe文件中设定的ImageBase，需要使用重定位表进行重定位
6. 跳到pe入口点

基本上只要实现了上述几个步骤就可以实现内存加载，但是具体实现的时候我还遇到了几个问题：

1. 如果PE文件不存在重定位表，应该如何加载
2. 如何修改传给被加载程序的参数
3. 如何加载.Net PE
4. 如何加载x64程序

# 加载无重定位表的PE

关于重定位表：

>  当加载器加载程序时，如果加载器为某PE（.exe、.dll）分配的基址与其自身默认记录的ImageBase不相同，那么该程序文件加载完毕后就需要修正重定位表中的所有需要修正的地址。如果加载器分配的基址和该程序文件中记录默认的ImageBase相同，则不需要修正，重定位表对于该dll也是没有效用的。

因此如果将PE加载在默认的位置则可以无需重定位表。我们将加载器的ImageBase设为其他地址，为没有重定位表的pe程序让出空间，随后用virtualloc在目标pe程序的默认基址处开辟一块内存用来放置目标pe程序，这样就可以避免考虑重定位的问题。

# 修改传递给被加载程序的命令行参数

我对加载器的设想是传递一个目标pe文件路径参数给加载器，然后加载器通过路径进行加载。如果只是加载一些木马就不需要考虑命令行参数的问题，但是如果要加载一些工具那传递给加载器的参数就会污染传递给被加载pe文件的参数，因此需要考虑参数传递的问题。

## 一个进程如何获得命令行参数

一般进程获取到命令行参数的方法是通过windows api的GetCommandLine获取

```c
LPSTR GetCommandLineA();
LPWSTR GetCommandLineW();
```

有一个误区是很多人认为这个函数是从进程peb中获取到的参数，但实际上系统在加载进程时保存了一份命令行参数的拷贝在某个私有变量中，GetCommandLine都是从那个拷贝中获取，因此只有修改了拷贝的地址中的内容才有效。

## 示例代码

```c
LPWSTR pCommandLine = GetCommandLineW();
LPSTR pCommandLineA = GetCommandLineA();
strcpy(pCommandLineA, arguments.c_str());
int maxCount = lstrlenW(pCommandLine);
size_t converted = 0;
mbstowcs_s(&converted, pCommandLine, arguments.length() + 1, arguments.c_str(), maxCount);
```

# 如何加载.Net程序

PE实际上只是一种存储数据的方式，尽管都是PE文件，但是.Net程序与Win32程序还是有着本质的区别。要了解.Net，还要从CLR说起。

## Common Language Runtime

> The Common Language Runtime (CLR) is a complete, high level virtual machine designed to support a broad variety of programming languages and interoperation among them.

*公共语言运行时（CLR）是一套完整的、高级的虚拟机，它被设计为用来支持不同的编程语言，并支持它们之间的互操作。*

正如 JRE 是 JAVA 的运行环境一样，CLR是.Net的运行环境，不同的是它可以为多种语言提供支持。

![](/assets/images/20200227192210.png)

*著名的.Net体系*

.Net程序经过编译器编译后，会生成一种中间语言——MSIL，执行时CLR再将他们翻译为真正的机器语言执行。因此我们不能像处理Win32程序一样处理.Net程序，而需要与CLR进行交互，将.Net程序交给CLR去执行。

## 示例代码

加载.Net环境并执行.Net程序的代码很多，以下代码只是示范

```c
HRESULT hr;
ICLRMetaHost *pMetaHost = NULL;
ICLRRuntimeInfo *pRuntimeInfo = NULL;
ICLRRuntimeHost *pClrRuntimeHost = NULL;

// build runtime
hr = CLRCreateInstance(CLSID_CLRMetaHost, IID_PPV_ARGS(&pMetaHost));
hr = pMetaHost->GetRuntime(L"v4.0.30319", IID_PPV_ARGS(&pRuntimeInfo));
hr = pRuntimeInfo->GetInterface(CLSID_CLRRuntimeHost, 
    IID_PPV_ARGS(&pClrRuntimeHost));

// start runtime
hr = pClrRuntimeHost->Start();

// execute managed assembly
DWORD pReturnValue;
hr = pClrRuntimeHost->ExecuteInDefaultAppDomain(
    L"T:\\FrameworkInjection\\_build\\debug\\anycpu\\InjectExample.exe", 
    L"InjectExample.Program", 
    L"EntryPoint", 
    L"hello .net runtime", 
    &pReturnValue);

// free resources
pMetaHost->Release();
pRuntimeInfo->Release();
pClrRuntimeHost->Release();
```

# 加载x64程序

如果要图方便的话只要稍微修改一下代码重新编译一个x64的加载器就可以（事实上我就是这样做的），但如果我们追求极致，想让我们的加载器做到能同时加载32位和64位程序呢？理论上讲，如果我们的程序是32位的，那就没法执行64位的cpu指令，如果是64位的，同样也无法执行32位的cpu指令。想要实现在32位指令与64位指令的切换，就需要了解当我们在64位操作系统下执行了32位程序时，操作系统都做了哪些工作。

## Windows x64下的Win32程序

在64位系统，任何进程中首先执行的代码是64位的ntdll.dll，它会初始化一个64位的进程。而稍后32位的应用程序将运行在一个名为WoW64的子系统下（说到子系统有没有想到WSL），这个子系统加载32位的ntdll.dll，将cpu转换为32位模式以执行Win32程序中的代码。

![](/assets/images/20200227221306.png)

在x64系统下观察一个Win32程序，发现会同时加载了两个ntdll.dll，其中有一个处在64位的地址空间，这就是64位的ntdll.dll。32位的ntdll.dll并没有包含任何sysenter的指令，因此当Win32程序尝试通过32位的ntdll.dll与系统交互时，32位的ntdll.dll将参数转发给64位的ntdll.dll并再一次进行cpu的模式转换，回到64位完成这次系统调用。

可以看到，在启动程序与系统调用的过程中，cpu分别发生了64到32与32到64两种转换，如果我们手动实现这一过程，那么我们的程序也可以在32位与64位指令中进行切换。

## 天堂之门 从32位到64位

x64构架的cpu使用cs段寄存器来确定cpu的运行模式。在32位进程中，cs=0x23；在64位进程中，cs=0x33。当cs被更改后，cpu的运行模式便会发生转变。由此产生一种技术，天堂之门（Heaven's Gate），通过改变段寄存器来实现32位与64位代码的转换。

```asm
push 33h //将0x33压栈
push 64bit_code_address //将64bit的代码地址压栈
reft //模式转换
```

其中reft指令又叫far ret，是带有段寄存器的返回，它会从栈中弹出两个值，一个给cs，一个给ip，因此在reft执行后，cpu将按照64位模式继续执行64位代码。

# 小结

这算是我这段时期学习免杀的一个总结，尽管本文探讨的技术都十分古老，但放到现在仍旧值得我们去学习。

# 引用

<https://www.codeproject.com/Articles/607352/Injecting-Net-Assemblies-Into-Unmanaged-Processes>

<https://medium.com/@fsx30/hooking-heavens-gate-a-wow64-hooking-technique-5235e1aeed73>
