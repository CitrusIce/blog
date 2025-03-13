---
layout: post
title: "将书签导入Zotero"
date: 2021-09-02 14:17:40 +0800
categories: develop
---

接触安全已有两年，这期间看了大量的文章，其中大部分都使用浏览器的收藏夹来保存，还有一小部分用印象笔记的网页剪藏。以书签的方式保存文章并不可靠，经常会遇到文章被删或者由于一些博主换了博客主题而导致之前的url不可用。印象笔记的剪藏固然很好，然而我并不敢投入太多在印象笔记之中（并不是很满意印象笔记，一直在搜寻可替代的软件，投入太多会导致迁移成本的增加），直到朋友向我推荐了Zotero。

Zotero是一个用于文档管理的开源软件，并且提供浏览器插件用于保存网页，但是并没有提供批量导入的功能，因此只有通过自己实现了。

Zotero本身提供了一些javscript的接口用于操作Zotero中的item，可以实现增删查改，但是用于保存网页并不方便。而Zotero本身提供了插件用于剪藏，如果能直接调用插件功能来批量导入是最轻松的实现，因此最终我决定使用python操作浏览器，然后通过在页面中执行js代码来调用插件的功能来导入网页。

## 分析Chrome插件

首先可以通过这个网址将crx格式的插件下载下来，插件名为zotero-connector https://chrome-extension-downloader.com/

crx格式的文件可以同过7z直接打开，解压出来后是一个文件夹。其中manifest.json包含了插件的相关信息

简单了解一下Chrome插件，插件代码可以分为5种：

- injected script 
- content-script 
- popup js 
- background js 
- devtools js 

不同的种的js代码有不同的权限，同时可以访问不同的api，插件的各种功能的实现需要靠这些不同js代码相互协作。

既然想通过调用插件的功能来实现将网页导入Zotero，首先要找到插件实现功能的位置。一开始想找到单击事件触发的函数，但是由于对Chrome插件的不熟悉不知道该如何找起。于是换了一种思路：从不同js代码之间的通信开始。全局搜索addListener函数，根据文件名/代码上下文找到一些看起来有意思的地方下断，几次测试之后很快就找到了关键位置，在messaging_inject.js中尾部定义了一个Listener用于监听消息。

![image-20210902104536543](/assets/images/image-20210902104536543.png)

在_messageListeners中定义了事件对应的函数，继续调试几次，找出了其中的重要事件：

- translate：调用translator保存网页
- saveAsWebpage：直接保存网页
- update：设置保存条目的属性、位置

## 魔改插件

至此我们已经找到了我们需要的函数，但是这些函数是无法通过js直接调用的。因为这些函数属于content-script，正如插件中使用chrome.runtime.onMessage.addListener通过监听消息来通信一样，我们同样需要通过消息来与content-script通信。普通js要与content-script进行通信需要使用window.addEventListener以及window.postMessage进行通信，在messaging_inject.js中新增以下代码：

```javascript
window.addEventListener("message", async function (event) {
			if (event.data.type && (event.data.type == "save")) {
				console.log("Content script received message: " + event.data.content.title);
				if (Zotero.Inject.translators.length != 0) {
					await Zotero.Inject.translate(Zotero.Inject.translators[0].translatorID);
				}
				else {
					await Zotero.Inject.saveAsWebpage([event.data.content.title, { snapshot: true }]);
				}
				if (event.data.content.collection) {
					var response = await Zotero.Connector.callMethod("getSelectedCollection", {})
					var target = response.targets.find((target) => { return target.name == event.data.content.collection })
					if (!target) {
						return;
					}
					await _messageListeners["progressWindowIframe.updated"]({ "target": target, "tags": event.data.content.tags });

				}
				var data = { type: "finish"};
				window.postMessage(data, "*");
			}
			else if (event.data.type && (event.data.type == "update")) {
				var response = await Zotero.Connector.callMethod("getSelectedCollection", {})
				var target = response.targets.find((target) => { return target.name == event.data.text.collection })
				if (!target) {
					return;
				}
				_messageListeners["progressWindowIframe.updated"]({ "target": target, "tags": event.data.text.tags });

			}
		})

```

在js控制台中通过类似以下代码即可调用Zotero导入网页：

```javascript
var data = { type: "save", content: {title:"test",collection:"test",tags:"asdf23,444"}};
window.postMessage(data, "*");
```

同时由于消息的通信都是异步的，我们无法得知插件何时将网页导入完毕，在未导入完毕的情况下关闭页面会导致导入失败，因此我们需要在导入完毕后通知控制端（python）网页导入完毕。由于postMessage是异步的，不存在返回值，我们没法在执行js完毕后返回网页导入完毕的信息。最终的解决方案是在向content-script发送消息前再定义一个Listener，content-script在导入完毕后向这个Listener发送一个message告知导入完毕，这个Listener操作dom在页面中加入一个特殊标签，控制端就不断的检测页面上是否存在这个特殊标签，如果存在则导入完毕、关闭当前页面。

## 频繁关闭/新建tab导致的卡死

操作浏览器使用的库是pyppeteer，是puppeteer的python实现，支持异步。原本的逻辑是如果要导入一个网页则新建一个tab并进行导入操作，导入完毕后则关闭tab，实际测试中发现存在一些协程会一直卡死在关闭tab的函数中，不知道是库实现的问题还是其他的。最终改变了思路，使用"池"的方法解决了该问题。类似线程池一样，在导入网页的时候不再新建tab，而是从tab池中获取一个空tab，导入完毕后也不再关闭，而是将tab置空再重新放入tab池中。这种方法不但解决了卡死问题，同时避免了新建/关闭tab时的开销。

## 结尾

项目已上传github，同时欢迎pull request https://github.com/CitrusIce/ImportBookmarksToZotero