# Emacs TUI 配置

一套面向终端（SSH、WezTerm、tmux）的 Emacs 配置：日常编辑、补全、语言服务、Markdown 阅读器与终端键盘协议适配。配置按功能区分块，缺失的可选包会回退到内置功能，不会阻止启动。

## 仓库结构

```text
.
├── early-init.el              # 包目录、镜像源、native-comp 策略
├── init.el                    # 主配置（16 个功能区）
├── modules/
│   └── lsp-config.el          # lsp-bridge、语言服务器路由与弹窗
├── bin/
│   ├── emacs-tui              # emacsclient 包装（自动拉起 daemon）
│   ├── install-ink-emacs      # 下载固定上游版本、打补丁并编译
│   └── ink-emacs.patch        # Ink 的 S-expression 输出补丁
├── scripts/
│   ├── install-lsp-bridge.sh  # 固定版本 lsp-bridge 与 Python 依赖
│   └── tui-batch-init.el      # 安装任务用的显式加载入口
├── rust-src/                  # Ink S-expression 扩展的源码快照
├── themes/
│   └── mood-one-theme/        # 内置主题（vendor）
├── tests/                     # 启动、阅读器、LSP、颜色、客户端检查
└── test-files/                # 测试用 Markdown 样例
```

`elpa/`、`lsp-bridge/`、`.cache/`、`eln-cache/`、`tree-sitter/` 都是生成目录，不入库。

## 依赖

| 工具 | 用途 |
| --- | --- |
| Emacs 31.1+ | 终端真彩色、动态模块、Tree-sitter |
| Git、C/C++ 编译器、cmake、libtool | vterm 模块与 Tree-sitter 语法 |
| Rust / cargo | 编译 Ink 阅读器 |
| Python 3 | lsp-bridge 依赖 |
| WezTerm（推荐） | 支持 Kitty keyboard protocol 与真彩色 |

## 首次安装

```bash
# 1. 把仓库放到 ~/.emacs.d（或建立符号链接）
ln -s "$PWD" ~/.emacs.d

# 2. 安装可选包（首次需要网络）
emacs -Q --batch -l scripts/tui-batch-init.el --eval '(my-tui-install-packages)'

# 3. 安装 lsp-bridge 与 Python 依赖
./scripts/install-lsp-bridge.sh

# 4. 编译并安装带 S-expression 输出的 Ink
./bin/install-ink-emacs

# 5. 启动终端 Emacs
./bin/emacs-tui
```

`bin/emacs-tui` 会自动启动 daemon 并复用；`bin/install-ink-emacs` 只安装 `ink-emacs`，保留系统里原有的 `ink` 命令。

## 常用功能

- **编辑**：Helm 导航、项目搜索、多光标、smartparens、yasnippet、magit、undo 树。
- **语言**：lsp-bridge 负责补全与诊断，Tree-sitter 只提供缩进与折叠结构，保留传统字体高亮。
- **终端**：真彩色、语法亮度微调、vterm/Eat、Dashboard 启动页、只读阅读工作流。
- **键盘**：终端支持 Kitty keyboard protocol 时通过 `kkp` 区分 `C-h`/`DEL`、`C-m`/`RET`、`C-[`/`ESC` 等；不支持的终端自动退化为普通编码。
- **主题**：内置 mood-one（来自 [jessiehildebrandt/mood-one-theme](https://github.com/jessiehildebrandt/mood-one-theme)）。

## Ink 阅读器

Markdown 预览由 Ink 生成 S-expression，Emacs 侧读取后再插入 buffer。阅读 buffer 中的按键：

| 键 | 作用 |
| --- | --- |
| `w` | 设置渲染宽度（20–1000） |
| `t` | 显示/隐藏目录侧栏 |
| `g` | 按当前窗口宽度重新渲染 |
| `s` | 回到 Markdown 源码 |
| `q` | 关闭预览 |

宽度会被限制在 `min(my-tui-ink-width, window-body-width - 1)`；默认跟随窗口，可用 `(setq-default my-tui-ink-width 140)` 固定。

校验阶段会把渲染文本一次性插入临时 buffer，用 `buffer-substring-no-properties` 比较代码片段（协议 offset 从 0 开始，buffer 位置加 1），避免对大字符串反复扫描字符偏移；代码源码仍用 `substring`。临时 buffer 在成功和异常时都会清理。

## 测试

```bash
emacs -Q --batch -l tests/tui-startup-smoke.el
emacs -Q --batch -l tests/tui-ink-sexp-smoke.el
emacs -Q --batch -l tests/tui-lsp-bridge-smoke.el
emacs -Q --batch -l tests/tui-colors-smoke.el
python3 tests/tui-client-launcher-smoke.py
```

当前结果：启动 19/19、LSP 8/8、颜色 4/4、客户端 2/2、Ink 17/19。Ink 的两条失败是终端宽度断言，在 `--batch` 的窄假帧下不成立，需要在真实终端（≥100 列）里验证。

## 说明

- 配置只包含可直接运行的源码与测试，不含包缓存、编译产物或本机路径。
- lsp-bridge 的 Python 依赖安装在 `.cache/python-tools`，不进入全局 PATH。
- 安装脚本只读取上游源码与依赖，不向外部发布任何内容。
