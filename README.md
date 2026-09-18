# Anythings

Anythings 是一款面向 macOS 平台原生开发的文件检索工具。使用 SwiftUI 构建，为你自选的文件夹建立本地索引，并结合 macOS Spotlight 提供即时检索，输入关键词即可快速过滤出结果。

本项目为个人兴趣开发，仅供个人学习与使用，不用于任何商业用途。

详细功能说明请见 [FEATURES.md](FEATURES.md)，版本迭代历史请见 [CHANGELOG.md](CHANGELOG.md)。

## 功能概览

- 原生 SwiftUI macOS 应用。
- 用户自选文件夹索引，支持添加与单独移除。
- 本地索引 + Spotlight 双引擎即时检索，后台异步计算，输入不卡顿。
- Everything 风格的通配符（`*`、`?`）与引号短语匹配，支持全路径匹配、大小写敏感切换。
- Finder 集成：打开文件、在 Finder 中显示、打开所在目录、复制路径。
- 默认自动隐藏系统/日志/临时文件（如 `.log`、`.tmp`、`.cache`、`.DS_Store`），可在侧边栏关闭。
- 多选、全选、取消全选、反选（工具栏菜单、菜单栏 `Selection` 菜单，或快捷键 `⌘A` / `⇧⌘A` / `⌘I`）。
- 将选中的结果复制或移动到目标文件夹。
- 多种结果视图：详情（可排序表格）、大图标、小图标。
- 支持按名称、路径、修改日期、大小排序，可升序/降序切换。
- 高级文件类型筛选器：PDF、文档、图片、音频、视频、压缩包、代码、应用程序共 8 大类别，另支持自定义扩展名。
- 程序化生成的搜索主题应用图标。

## 运行环境要求

- macOS 13 或更高版本
- Xcode Command Line Tools
- Swift 5.9 或更高版本

## 从源码运行

```bash
swift run Anythings
```

## 打包为 `.dmg`

在 macOS 上执行：

```bash
bash scripts/package-dmg.sh
```

生成的安装镜像位于：

```text
dist/Anythings.dmg
```

该脚本会构建 Release 版本、封装为 `Anythings.app`，并使用 `hdiutil` 打包为 DMG。

你也可以直接运行仓库中的 "Build macOS DMG" GitHub Actions 工作流，在 macOS Runner 上自动完成构建，并将生成的 DMG 作为工作流产物下载。

## 说明

应用仅索引你显式添加的文件夹。与 Windows 上的 Everything 不同，macOS 未对外暴露类似 NTFS USN 日志的底层文件变更接口，因此 Anythings 使用原生 macOS 文件系统 API 枚举所选目录，并结合 Spotlight 提供即时检索能力，所有检索均在本机完成。
