# Nimi 可行性原型

这些是验证 macOS 关键路径的最小 Nim 程序,不依赖 cgo、Objective-C 源文件或第三方绑定。

环境:Nim 2.4.0、macOS 12+、Xcode Command Line Tools。

| 目录 | 验证 | 运行 |
|---|---|---|
| `objc_hello` | ObjC runtime、NSWindow、运行时类、NSTimer、事件循环 | `nim c -r --mm:orc spike.nim` |
| `wkwebview` | WKWebView、WKScriptMessageHandler、JS→Nim、eval | `nim c -r --mm:orc spike_webview.nim` |
| `coretext` | CoreText shaping、CGBitmapContext、PNG | `nim c -r --mm:orc spike_coretext.nim` |
| `nim_meta` | 宏读 proc 签名、生成 TS、JSON 往返 | `nim c -r --mm:orc spike_meta.nim` |
| `metal` | CAMetalLayer、MTLDevice/Queue、render pass、present | `nim c -r --mm:orc spike_metal.nim` |
| `blocks` | 纯 Nim 构造 ObjC global block、异步 completion | `nim c -r --mm:orc spike_blocks.nim` |
| `threads` | arc/orc/atomicArc/yrc、跨线程 ref | `nim c -r --threads:on --mm:atomicArc spike_threads.nim` |

## 预期输出

### objc_hello

```text
objc runtime: true, appkit: true
NSString roundtrip: hello from Nim
starting NSApplication run loop (window closes itself in 1s)
```

### wkwebview

```text
webkit loaded: true
running NSApplication
page loaded; evaluating JavaScript
JS -> Nim: {
    hello = "from the page";
    n = 42;
}
quitting
```

### coretext

```text
line width=680.62 ascent=42.4 descent=13.6 leading=5.42
lit pixels: 6781
wrote coretext.png: true
```

生成 `coretext.png`,含拉丁/中日韩/阿拉伯混排。

### nim_meta

```text
GENERATED TYPESCRIPT:
export interface Api {
  greet(self: Greeter, name: string, times: number): Promise<string>;
  save(self: Greeter, note: Note): Promise<number>;
}
to json: {"id":7,"title":"hello","done":true}
from json: (id: 7, title: "hello", done: true)
OK
```

### metal

```text
metal loaded: true, quartz: true
running; expected 20 Metal frames
first nextDrawable non-nil: true
drew 20 frames; clear colour presented
```

### blocks

```text
global block isa: true
navigation finished; evaluating JS with a Nim-made block
block called: result=answer: 42 error=false
```

### threads

```text
shared: 42 hello (from worker)
```

## 注意

- 原型会短暂打开窗口(1–6 秒)然后自动退出。
- 这些代码是可行性验证,不是生产实现;错误处理/内存管理/ABI 覆盖不完整。
- 生产设计见 `docs/`。
