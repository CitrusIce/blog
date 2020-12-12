---
layout: post
title: "自动化信息收集框架：设计框架"
date: 2020-03-20 21:33:52 +0800
categories: information-gathering
---

如果想要将各个信息收集工具整合到一起，就需要为他们封装出统一的接口，我把这些具有统一接口的对象定义为Module类。Module类具有三个抽象方法需要在封装模块的时候实现：

- exec

  启动模块

- get_output

  获取模块执行结果

- update_databse

  将结果输出到数据库

```python
class Module(metaclass=ABCMeta):
    def __init__(self, pipe=None):
        self.pipe_list = []
        self.task_list = []
        if isinstance(pipe, list):
            self.pipe_list = pipe[:]
        elif isinstance(pipe, Module):
            self.pipe_list.append(pipe)
        elif pipe is None:
            pass
        else:
            raise TypeError("Expected a List or Pipe type")

    def add_task(self, task):
        self.task_list.append(task)

    def register_pipe(self, pipe):
        if not isinstance(pipe, Pipe):
            raise TypeError("Expected a Pipe")
        else:
            self.pipe_list.append(pipe)

    def send_to_pipe(self, data=None):
        if data is None:
            for pipe in self.pipe_list:
                pipe.send(self.get_output())
        else:
            for pipe in self.pipe_list:
                pipe.send(data)

    def run(self):
        self.exec()
        data = self.get_output()
        self.update_database(data)
        self.send_to_pipe(data)
        pass

    @abstractmethod
    def exec(self):
        pass

    @abstractmethod
    def get_output(self):
        pass

    @abstractmethod
    def update_database(self, data):
        pass
```

Pipe类用作模块与模块之间的通信，每个Module具有一个task_list和一个pipe_list。task_list作为Module的输入，当模块运行后将从task_list中获取任务然后执行，pipe_list中的Pipe对象是模块的数据出口，当模块执行完毕后，通过get_output()获取数据然后通过send_to_pipe()将数据送到各个pipe中去，而pipe将数据处理为下一个模块所需的特定格式后转送到下一个模块的task_list。

```python
class Pipe:
    def __init__(self, func=None, module=None):
        if func is not None:
            if not callable(func):
                raise TypeError("Expected a function")
            if len(getargspec(func).args) > 1:
                raise Exception("function should have only one parameter")
            self.process_data = func
        else:
            self.process_data = None
        self.module_list = []
        if isinstance(module, list):
            self.module_list = module[:]
        elif isinstance(module, Module):
            self.module_list.append(module)
        elif module is None:
            pass
        else:
            raise TypeError("Expected a List or Module type")

    def send(self, data):
        if self.process_data is not None:
            data = self.process_data(data)
        for module in self.module_list:
            module.add_task(data)

    def register_module(self, module):
        if not isinstance(module, Module):
            raise TypeError("Expected a Module")
        else:
            self.module_list.append(module)
            
```

最后的问题是这些模块将如何被调度，最开始我的想法是为每个模块单开一个线程，每当有数据传送进来就立即处理。但是这样做感觉会增加服务器的负担，大多数模块都是以多线程是运行的，因此当模块同时运行时对cpu产生很大的负担。我定义了一个Controller类来调度各个模块，根据各个模块的task_list长度决定先运行哪个module，在一个模块停止运行之前第二个模块不会运行。

```python
class Controller:
    def __init__(self):
        self.module_list = []

    def push(self, module):
        heapq.heappush(self.module_list, module)

    def run(self):
        heapq.heapify(self.module_list)
        while len(self.module_list[0].task_list) != 0:
            self.module_list[0].run()
            heapq.heapify(self.module_list)
```

PS:

虽然很想讲点理论的东西，但是我从未接触过程序设计方面的内容，绞尽脑汁才想出了框架的轮廓。在设计框架的时候我的不足也立马显现了出来，我时常问自己，“我要做什么”，“我为什么要这样做”，但往往给不出完美的答案。不过秉着尽量可以重复利用代码的原则，我大体还是把它构思完了，不过以后如果有空还是应该多读一下设计模式方面的书籍。

