---
layout: post
title: "Windows的各种路径"
date: 2021-12-29 17:30:17 +0800
categories: windows
---

翻译整理自以下页面：

[windows - Path prefixes \??\ and \\?\ - Stack Overflow](https://stackoverflow.com/questions/23041983/path-prefixes-and)
[command line - What does \??\ mean in \??\C:\Windows\System32\conhost.exe? - Super User](https://superuser.com/questions/810609/what-does-mean-in-c-windows-system32-conhost-exe)
[File path formats on Windows systems | Microsoft Docs](https://docs.microsoft.com/en-us/dotnet/standard/io/file-path-formats#dos-device-paths)
[Naming Files, Paths, and Namespaces - Win32 apps | Microsoft Docs](https://docs.microsoft.com/en-us/windows/win32/fileio/naming-a-file#win32-file-namespaces)

# DOS path

包含三部分：

- 盘符加冒号 (c:)
- 目录名
- 文件名

如果这三部分都有，则为绝对路径；如果没有盘符部分但是以 **\\** 开头，则从当前盘符的根目录开始；如果有盘符但后面没有 **\\** ，则为指定盘符的相对路径，相对于在那个盘符的当前目录（每个盘符下都存在一个当前目录），否则是当前目录的相对路径。
```
C:\Documents\Newsletters\Summer2018.pdf 
An absolute file path from the root of drive `C:`.

\Program Files\Custom Utilities\StringFinder.exe
An absolute path from the root of the current drive.

2018\January.xlsx
A relative path to a file in a subdirectory of the current directory.

..\Publications\TravelBrochure.pdf
A relative path to file in a directory that is a peer of the current directory.

C:\Projects\apilibrary\apilibrary.sln
An absolute path to a file from the root of drive `C:`.

C:Projects\apilibrary\apilibrary.sln
A relative path from the current directory of the `C:` drive.
```

[windows - Path prefixes \??\ and \\?\ - Stack Overflow](https://stackoverflow.com/questions/23041983/path-prefixes-and)
- The first is that the runtime library supports per-drive working directories using conventionally 'hidden' environment variables such as "=C:". For example, "C:System32" resolves to "C:\\Windows\\System32" if the "=C:" environment variable is set to "C:\\Windows".

windows 使用环境变量类似 "=C:" 这种名字用于记录当前驱动器的当前目录，因此设置这个环境变量可以修改其他驱动器的当前路径，从而影响 `C:Projects\apilibrary\apilibrary.sln` 这种路径形式的解析位置
```cpp
	SetEnvironmentVariableA("=C:", "C:\\Windows");
	HANDLE hFile = CreateFileA(R"(c:system32\notepad.exe)", GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
```

[windows - Path prefixes \??\ and \\?\ - Stack Overflow](https://stackoverflow.com/questions/23041983/path-prefixes-and)
- Also, if the last component of the path is a reserved DOS device name, including if the name has trailing colons, spaces, dots, and even a file extension, the path gets translated to a device path (e.g. "C:\\Windows\\nul: .txt" -> "\\??\\nul"). (DOS devices are also reserved in the final component of relative paths that have no drive.) Otherwise, the runtime library simply prepends "\\??\\" to the normalized path (e.g. "C:/Windows" -> "\\??\\C:\\Windows").

如果路径的最后一部分是一个保留的 DOS 设备名，包括如果设备名后尾随了冒号、空格和点甚至是文件扩展名，则直接转为该设备的路径 (e.g. "C:\\Windows\\nul: .txt" -> "\\??\\nul")。否则 windows 则直接在进行 normalized 后的 DOS path 前增加 `\??\`。
# UNC path

- 以 `\\`开始，后面接 host name，host name 可以是服务器名 (NetBIOS 机器名) 或 ip 地址
- share name，接在 host name 后面，host name 和 share name 共同构成一个 volum
- 目录名字
- 文件名字


`\\system07\C$\`

The root directory of the `C:` drive on `system07`.

`\\Server2\Share\Test\Foo.txt`

The `Foo.txt` file in the Test directory of the `\\Server2\Share` volume.

# DOS device paths

形如
`\\.\C:\Test\Foo.txt`   `\\?\C:\Test\Foo.txt`
或通过卷 guid 指定盘符
`\\.\Volume{b75e2c83-0000-0000-0000-602f00000000}\Test\Foo.txt` `\\?\Volume{b75e2c83-0000-0000-0000-602f00000000}\Test\Foo.txt`

DOS device path 包括：

- dos device path 指定符号 `\\.\` 或 ` \\?\`
- 一个指向目标设备符号链接 `\\?\C:\`。同样可以使用 UNC 路径` \\.\UNC\Server\Share\Test\Foo.txt ` ` \\?\UNC\Server\Share\Test\Foo.txt`。
    没看懂的部分：
> For device UNCs, the server/share portion forms the volume. For example, in `\\?\server1\e:\utilities\\filecomparer\`, the server/share portion is ` server1\utilities`. This is significant when calling a method such as [Path.GetFullPath(String, String)](https://docs.microsoft.com/en-us/dotnet/api/system.io.path.getfullpath#System_IO_Path_GetFullPath_System_String_System_String_) with relative directory segments; it is never possible to navigate past the volume.

[windows - Path prefixes \??\ and \\?\ - Stack Overflow](https://stackoverflow.com/questions/23041983/path-prefixes-and)
- The straight-forward case is a path that's prefixed by either "\\\\.\\" or "\\\\?\\". This is a local device path, not a UNC path. (Strictly speaking it's in the form of a UNC path, but "." and "?" are reserved device domains.) For this case, the prefix is simply replaced by NT "\\??\\".

dos device path 严格来说属于一种 UNC path 的形式，"?"为保留设备名。这两个前缀被简单替换为 `\??\`

有歧义的地方：

DOS device path 不允许使用 `.` `..`
[File path formats on Windows systems | Microsoft Docs](https://docs.microsoft.com/en-us/dotnet/standard/io/file-path-formats#dos-device-paths)
- DOS device paths are fully qualified by definition. Relative directory segments (`.` and `..`) are not allowed. Current directories never enter into their usage.

[Naming Files, Paths, and Namespaces - Win32 apps | Microsoft Docs](https://docs.microsoft.com/en-us/windows/win32/fileio/naming-a-file#win32-file-namespaces)
- For file I/O, the "\\\\?\\" prefix to a path string tells the Windows APIs to disable all string parsing and to send the string that follows it straight to the file system. For example, if the file system supports large paths and file names, you can exceed the MAX\_PATH limits that are otherwise enforced by the Windows APIs. For more information about the normal maximum path limitation, see the previous section [Maximum Path Length Limitation](#maximum-path-length-limitation).
- Because it turns off automatic expansion of the path string, the "\\?\" prefix also allows the use of ".." and "." in the path names, which can be useful if you are attempting to perform operations on a file with these otherwise reserved relative path specifiers as part of the fully qualified path.

当使用 `\\?\`的时候，windows api 不会对传入的路径做任何 normalization 处理，而使用` \\.\` 的时候会进行 normalization 
```cpp
//失败
	HANDLE hFile = CreateFileA(R"(\\?\D:\.\file.txt)", GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
//成功
	HANDLE hFile = CreateFileA(R"(\\.\D:\.\file.txt)", GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
```

关于 Device path normalization：

[windows - Path prefixes \??\ and \\?\ - Stack Overflow](https://stackoverflow.com/questions/23041983/path-prefixes-and)
- Device path normalization resolves "." and ".." components, replaces forward slashes with backslashes, and strips trailing spaces and dots from the final path component. Because forward slashes are translated to backslashes, the prefix of a normalized device path can be "//./" or "//?/" or any combination of slashes and backslashes, except for exactly "\\\\?\\".

normalization 会处理 "." 和 ".."，并且将 "/" 替换为 "\\"，并将尾随的 "." 和空格删除。因为会将斜杠转为反斜杠，因此 "//./" 和 "//?/" 都是可行的，但是 "\\\\?\\" 不行，因为这会禁止 normalization

# \\??\ Prefix

`\??\`指示对象管理器在调用者的 local device directory 搜索（也包括在 Global 中搜索），也就是` \Sessions\0\DosDevices\[Logon Authentication ID] `。当调用者为 system 时，则在` \Global?? `中搜索。每个 local device directory 下有一个 Global 符号链接链接到` \Global??`

```cpp
//以下两种均可以成功
	HANDLE hFile = CreateFileA(R"(\??\Global\D:\file.txt)", GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
	HANDLE hFile = CreateFileA(R"(\??\D:\file.txt)", GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
```

`\DosDevice` 链接到 `\??`
