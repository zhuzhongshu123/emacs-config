---
title: Ink Showcase
author: TUI smoke test
---

# Ink 阅读器样例

用于验证 S-expression 协议、中文宽度、ZWJ Emoji、代码 fragment 映射与目录生成。
注意这里的组合 Emoji：👨‍👩‍👧‍👦 与 🧑‍💻。

## 1. 段落与行内样式

普通段落，包含 **粗体**、*斜体*、`inline code` 与 [链接](https://example.com)。
中文标点：，。；：「」『』——…… 应与半角字符混排正常。

## 2. Rust 代码

```rust
fn main() {
    let xs = [1, 2, 3];
    println!("{:?}", xs.iter().sum::<i32>());
}
```

## 3. Python 代码

```python
def greet(name: str) -> str:
    return f"你好，{name}"
```

## 4. Shell 代码

```bash
for i in 1 2 3; do
  echo "第 $i 行"
done
```

## 5. Go 代码

```go
package main

import "fmt"

func main() { fmt.Println("你好") }
```

## 6. C 代码

```c
#include <stdio.h>
int main(void) { puts("hello"); return 0; }
```

## 7. JavaScript 代码

```js
const add = (a, b) => a + b;
console.log(add(1, 2));
```

## 8. 表格

| 名称 | 宽度 | 说明 |
| --- | --- | --- |
| 中文 | 2 | 全角字符 |
| ASCII | 1 | 半角字符 |

## 9. 列表

1. 第一项
2. 第二项
   - 子项 A
   - 子项 B

## 10. 引用

> 引用块里也可以有 `code`，以及中文。
> 第二行。

## 11. 脚注

这里有一个脚注引用[^1]，以及另一个[^note]。

[^1]: 第一条脚注。
[^note]: 第二条脚注，含 **样式**。

## 12. 结束

最后一段，用来确认文档尾部也能正常渲染。
