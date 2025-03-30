# Launcher - macOS智能快捷启动器

## 项目概述

Launcher是一款macOS平台的智能快捷启动器应用，灵感来源于Spotlight和Alfred等工具。它允许用户通过全局快捷键快速调出搜索界面，支持应用搜索、文件搜索、快捷指令等多种功能，同时集成了AI辅助能力，旨在提升用户的工作效率。

核心特点：
- 全局快捷键激活（默认⌘Space）
- 多模态搜索（应用、文件、快捷指令等）
- 响应式UI设计
- AI集成辅助
- 状态栏便捷访问
- 智能计算器（支持公式计算、复合表达式汇率换算、亲戚关系计算）

## 架构设计

### 核心架构

项目采用MVVM（Model-View-ViewModel）架构模式，结合SwiftUI和Combine框架实现响应式UI：

- **视图层（Views）**：使用SwiftUI构建的界面组件
- **视图模型层（ViewModels）**：处理业务逻辑和数据转换
- **模型层（Models）**：定义数据结构和领域模型
- **服务层（Services）**：提供核心功能实现
- **工具层（Utils）**：提供通用工具和辅助功能

### 数据流动

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    Views    │◄───►│  ViewModels │◄───►│   Services  │
└─────────────┘    └─────────────┘    └─────────────┘
       ▲                   ▲                  ▲
       │                   │                  │
       └───────────────────┼──────────────────┘
                           │
                     ┌─────▼─────┐
                     │   Models  │
                     └───────────┘
```

### 模块交互流程

```
┌─────────────┐  快捷键触发  ┌─────────────┐  查询请求  ┌─────────────┐
│  键盘监听系统  │───────────►│ 搜索协调服务  │─────────►│ 搜索子系统   │
└─────────────┘            │ (SearchService) │◄────────┴─────────────┘
                           │                 │         │ 并发执行
                           │ 结果聚合/缓存   │◄───────┐
                           └─────────────┘         │ 应用搜索
                                              │ 文件搜索
                                              │ 快捷指令搜索
                                              ▼ 计算器服务
```

## 核心组件详解

### 1. 主视图模型（MainViewModel）

MainViewModel是应用的核心视图模型，负责：

- 管理搜索文本和结果
- 协调不同模块的展示状态
- 处理用户交互和选择
- 管理AI响应流程

主要属性和方法：
- `modules`：各功能模块的数据
- `searchText`：当前搜索文本
- `selectedItemIndex`：当前选中项
- `updateSearchResults`：更新搜索结果
- `handleItemSelection`：处理项目选择

### 2. 搜索服务（SearchService）

SearchService是搜索功能的核心，采用组合模式整合多种搜索能力：

- **应用搜索**：通过ApplicationSearchService实现
- **快捷指令搜索**：通过ShortcutSearchService实现
- **文件搜索**：通过FileSearchService实现
- **计算器服务**：通过CalculatorService实现

搜索服务使用Swift Concurrency实现并发搜索，并通过NSCache缓存结果提升性能。

### 3. AI服务（AIService）

AIService提供AI辅助功能，主要特性：

- 支持流式响应
- 管理对话历史
- 处理AI设置和配置
- 提供响应生成和取消能力

### 4. 界面组件

- **MainView**：应用主界面，整合搜索栏和结果显示
- **SearchBarView**：搜索输入组件
- **ModuleSectionView**：模块化结果显示组件
- **AIResponseView**：AI响应界面，支持富文本和代码块显示
- **CalculatorView**：计算器结果显示，支持公式和结果并排展示
- **SettingsView**：设置界面

### 5. 智能计算器功能

计算器功能是Launcher的一个强大辅助工具，可以直接在搜索界面进行各种计算：

- **基础数学计算**：支持加减乘除、指数、开根及常见数学函数
- **公式美化显示**：将用户输入转换为标准数学符号（如 * 转为 ×，/ 转为 ÷）
- **复合汇率换算**：支持多种国际货币到人民币的换算，可处理带有数学表达式的货币查询（如5USD*6）
- **亲戚关系计算**：支持中国亲戚关系推导，例如"爸爸的妈妈"="奶奶"，支持上下五代、旁系多层复杂关系

计算器功能通过以下组件实现：
- **CalculatorService**：核心计算逻辑，包括表达式求值、汇率换算和关系推导
- **CalculatorView**：专门的结果显示界面，支持公式与结果并排显示
- **CalculatorItem**：对应的数据模型，实现SelectableItem接口

用户可以通过Enter键复制计算结果到剪贴板，方便在其他应用中使用。

#### 汇率换算示例：
- 支持多种输入格式：`$50`、`USD50`、`50USD`
- 支持复合表达式：`$5*10`、`USD50/5`、`6*5EUR`

#### 亲戚关系计算示例：
- 基础关系：`爸爸的爸爸`→`爷爷`、`妈妈的爸爸`→`外公`
- 复杂关系：`爸爸的哥哥的儿子`→`堂兄弟`、`妈妈的姐姐的女儿`→`表姐妹`
- 支持四代以上亲戚：`爷爷的爸爸`→`曾祖父`、`外公的妈妈`→`外曾祖母`

## 项目结构

```
Launcher/
├── Assets.xcassets          # 资源文件
├── Info.plist               # 应用配置
├── LauncherApp.swift        # 应用入口
├── Models/                  # 数据模型
│   ├── AISettings.swift     # AI设置模型
│   ├── ModuleItems.swift    # 模块项目模型
│   └── SearchResult.swift   # 搜索结果模型
├── Services/                # 服务层
│   ├── AIService.swift      # AI服务
│   ├── ApplicationSearchService.swift # 应用搜索
│   ├── BaseSearchService.swift        # 基础搜索
│   ├── CalculatorService.swift        # 计算器服务
│   ├── FileSearchService.swift        # 文件搜索
│   ├── SearchService.swift            # 搜索服务聚合
│   └── ShortcutSearchService.swift    # 快捷指令搜索
├── Utils/                   # 基础工具层
│   ├── Debouncer.swift      # 搜索防抖
│   ├── DebugTools.swift     # 调试工具
│   ├── KeyboardHandler.swift # 全局快捷键监听
│   └── WindowCoordinator.swift # 窗口生命周期管理
├── ViewModels/              # 视图模型层
│   └── MainViewModel.swift  # 核心视图模型
└── Views/                   # 视图层
    ├── AIResponseView.swift # AI响应视图
    ├── MainView.swift       # 主界面
    ├── Modules/             # 模块组件
    │   ├── CalculatorView.swift      # 计算器视图
    │   ├── ModuleSectionView.swift   # 模块区域视图
    │   └── SelectableItemView.swift  # 可选择项视图
    ├── SearchBar/           # 搜索栏组件
    │   └── SearchBarView.swift       # 搜索栏视图
    └── SettingsView.swift   # 设置界面
```

## 关键技术点

### 1. 响应式编程

项目大量使用Combine框架实现响应式编程：

- 使用`@Published`属性包装器发布状态变化
- 通过`.sink`订阅状态变化并响应
- 使用`.debounce`实现搜索防抖

### 2. 并发搜索

使用Swift Concurrency实现高效并发搜索：

- 使用`Task`管理异步搜索任务
- 通过`async/await`简化异步代码
- 实现任务取消机制避免资源浪费

### 3. 模块化设计

采用模块化设计提高代码可维护性：

- 各搜索服务遵循共同接口
- 使用组合模式整合多种搜索能力
- 视图组件高度可复用

### 4. 高级计算器功能

计算器功能采用多种高级技术：

- 使用JavaScriptCore引擎计算数学表达式
- 采用正则表达式提取数值和运算符
- 使用复杂关系图谱处理亲戚关系计算
- 通过NSPasteboard实现结果复制功能

## 优化方向

### 1. 架构优化

- **重构SearchService**：进一步分离职责，避免与FileSearchService功能重叠
- **统一搜索接口**：确保所有搜索服务遵循一致的接口和返回格式
- **引入依赖注入**：减少组件间的硬编码依赖

### 2. 性能优化

- **改进缓存策略**：实现更智能的缓存机制，区分不同搜索类型
- **优化搜索算法**：提高搜索精度和速度
- **实现结果分页**：处理大量搜索结果的场景

### 3. 功能扩展

- **增强AI集成**：提供更多AI辅助功能
- **添加插件系统**：支持第三方功能扩展
- **增加自定义快捷键**：允许用户自定义操作快捷键
- **实现实时汇率更新**：通过API获取最新汇率数据
- **增强计算器功能**：支持更多科学计算和单位换算

## 开发指南

### 环境设置

1. 确保安装最新版Xcode
2. 克隆仓库
3. 使用Xcode打开Launcher.xcodeproj
4. 构建并运行项目

### 添加新搜索服务

1. 在Services目录下创建新的服务类，继承BaseSearchService
2. 实现search(query:)方法
3. 在SearchService中注册并集成新服务
4. 更新SearchResult.Type枚举以支持新的结果类型

### 扩展计算器功能

1. 在CalculatorService中添加新的计算方法
2. 更新isCalculation方法以识别新的计算模式
3. 在calculate方法中集成新功能
4. 如需添加新的UI效果，修改CalculatorView

### 代码规范

- 使用SwiftUI的声明式语法构建界面
- 遵循MVVM设计模式
- 优先使用Swift的现代特性（如async/await）
- 为公共API添加文档注释
