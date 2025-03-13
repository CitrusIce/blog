---
layout: post
title: "Termius破解小记"
date: 2025-03-13 13:22:55 +0800
categories: re
---

因为windows上一直用的win terminal，但是这玩意用ssh的时候传文件不方便所以就想换个工具。其实一直有在用mobaXterm，但是这个免费版有session上限，而且我垂涎termius和tabby的ui很久了，就准备换一下。tabby这东西bug有点多，根本没法用公私钥连接我的服务器，应该是跟windows生成的密钥有关系，所以只好选择termius。

termius的问题在于他现在打开就让你注册登录，实在是不想为了个ssh工具搞一个账号，于是准备破解一下。

![image-20250312164827250](/assets/images/image-20250312164827250.png)

termius是基于electron的，之前并没有接触过，网上稍微翻了翻，先解个包：

```powershell
npx @electron/asar extract app.asar app
```

解码出来后把原始的asar备份一下删除，这样electron应用会自动从app文件夹都读取代码加载，方便调试。

调试有两种，一种是开remote debug，在命令行中启动electron应用，加上参数`--remote-debugging-port=xxxx`就打开了远程调试端口，然后在chrome `chrome://inspect/`页面就可以附加上去。

另外一种是修改代码开启控制台，electron中要打开控制台要使用BrowserWindow来开启

```js
BrowserWindow().webContents.openDevTools()
```

于是全局搜`BrowserWindow(`来找到创建窗口的代码，定位到这里：

```js
        yt.linux() && (p.icon = Ch),
            yt.macOS() &&
                ((p.titleBarStyle = "customButtonsOnHover"),
                this.type === "primary" &&
                    (p.trafficLightPosition = { x: 9, y: 17 }),
                this.type === "primary" &&
                    ((p.show = !1),
                    (p.vibrancy = "hud"),
                    (p.backgroundColor = "#00000000"),
                    (p.visualEffectState = "active"))),
            (this.browserWindow = new q.BrowserWindow(p)),
            PE.enable(this.browserWindow.webContents),
            // 添加：this.browserWindow.webContents.openDevTools(),
            (this.id = this.browserWindow.id),
            this.browserWindow.on("page-title-updated", (v) =>
                v.preventDefault()
            ),
            this.browserWindow.webContents.setWindowOpenHandler(
```

至此可以开启窗口进行调试。

在调试Termius的过程中遇到了断点触发后就crash的问题，我也没搞清除是有反调试机制还是怎么回事，研究了半天调试最后其实没怎么用上，最后还是通过搜字符串定位的关键代码。

![image-20250312133351683](/assets/images/image-20250312133351683.png)

搜索界面上的字符串定位到文件reconnectSaga

![image-20250312133406053](/assets/images/image-20250312133406053.png)

压缩的js很大，需要先格式化一下，vscode默认的格式化不行，全选代码用命令 Format Selection With 选择Prettier进行格式化。

然后就是慢慢分析代码了，我对electron整个技术只有基本的了解，对vue以及js稍微懂一点，大概分析下来，这个文件每个function基本都是一个窗口，然后根据状态机去显示某个窗口，我们要做的就是找到termius最开始显示初次使用的窗口的位置然后进行patch，详细分析的过程很复杂，还要结合调试来判断代码功能。

最终追踪到了这么个函数：

```js
function* PGt(e, t) {
    const n = IGt(SGt),
        r = yield* wte(n, { from: e }, void 0, t);
    eM.userJustSawSuggestionToTryPremium(),
        r === "continue-without-account" && (yield* Wn(wEe()));
}
```

通过符号也能判断这里最后`yield* Wn(wEe())`的逻辑是不需要账户就继续使用的，于是我们进行patch。

```js
function* PGt(e, t) {
    // const n = IGt(SGt),
    //     r = yield* wte(n, { from: e }, void 0, t);
    // eM.userJustSawSuggestionToTryPremium(),
        // r === "continue-without-account" && (yield* Wn(wEe()));
  yield* Wn(wEe());
}
```

成功进入主界面：

![image-20250312134547498](/assets/images/image-20250312134547498.png)

