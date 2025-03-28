# Launcher - macOS智能快捷启动器

## 项目概述
Launcher是一款macOS平台的智能快捷启动器，类似于Spotlight，但提供了更强大的功能和更友好的用户界面。它支持应用搜索、文件搜索、AI辅助等多种功能，旨在提高用户的工作效率。

## 技术架构

### 整体架构
- **SwiftUI**: 用于构建现代化、响应式的用户界面
- **Combine**: 用于处理异步事件和数据流
- **MVVM模式**: 采用Model-ViewModel-View架构模式，实现关注点分离
- **模块化设计**: 将功能划分为多个独立模块，便于维护和扩展

### 核心组件
1. **AppManager**: 单例管理器，负责管理全局状态和设置
2. **SearchService**: 搜索服务的统一接口，协调各种专门的搜索服务
3. **ViewModels**: 包括SpotlightViewModel和ModuleViewModel，负责管理UI状态和业务逻辑
4. **WindowCoordinator**: 管理应用窗口的显示和隐藏

## 核心模块实现

### 1. 快捷键系统
- 基于HotKey库实现全局快捷键监听
- KeyboardHandler工具类处理键盘事件，支持方向键导航、Enter确认和Escape取消等操作
- 支持自定义快捷键配置

### 2. 智能搜索系统
- **BaseSearchService**: 提供基础搜索功能和相关性评分算法
- **ApplicationSearchService**: 负责应用程序搜索，支持多语言名称匹配
- **FileSearchService**: 负责文件搜索，使用NSMetadataQuery实现高效文件索引
- **ShortcutSearchService**: 负责快捷方式搜索
- **SearchService**: 统一搜索接口，协调各种搜索服务，实现结果缓存和异步搜索

### 3. AI辅助系统
- **AIService**: 提供AI对话功能，支持流式响应
- **AISettings**: 管理AI相关设置，如API密钥、模型选择等
- **AIResponseView**: 展示AI响应结果的专用视图

### 4. 界面渲染系统
- **SpotlightView**: 主搜索界面，支持多种搜索模式
- **ModularSpotlightView**: 模块化搜索界面，支持动态调整模块顺序和显示
- **SearchBarView**: 搜索输入框组件
- **ResultListView**: 搜索结果列表组件
- **SelectableItemView**: 可选择项组件，支持高亮和选中状态

## 项目结构

### Models
- **SearchResult**: 搜索结果模型，包含名称、路径、类型、图标等信息
- **ModuleItems**: 模块项模型，用于模块化界面
- **AISettings**: AI设置模型

### ViewModels
- **SpotlightViewModel**: 管理搜索视图状态和逻辑
- **ModuleViewModel**: 管理模块化视图状态和逻辑

### Views
- **SpotlightView**: 主搜索界面
- **ModularSpotlightView**: 模块化搜索界面
- **AIResponseView**: AI响应界面
- **SearchBar/**: 搜索栏相关组件
- **ResultList/**: 结果列表相关组件
- **Modules/**: 模块化界面相关组件

### Services
- **SearchService**: 统一搜索服务
- **BaseSearchService**: 基础搜索服务
- **ApplicationSearchService**: 应用搜索服务
- **FileSearchService**: 文件搜索服务
- **ShortcutSearchService**: 快捷方式搜索服务
- **AIService**: AI服务

### Utils
- **Debouncer**: 防抖动工具，避免频繁搜索
- **DebugTools**: 调试工具
- **KeyboardHandler**: 键盘事件处理工具
- **LauncherSize**: 界面尺寸常量
- **WindowCoordinator**: 窗口协调器

## 开发指南

### 1. 环境设置
- 确保安装最新版本的Xcode
- 使用Swift Package Manager管理依赖
- 项目使用SwiftUI构建，需要macOS 11.0或更高版本

### 2. 代码规范
- 遵循MVVM架构模式
- 使用Combine进行响应式编程
- 使用@MainActor确保UI操作在主线程执行
- 使用Task进行异步操作

### 3. 扩展开发
- **添加新的搜索服务**: 继承BaseSearchService并实现相应的搜索方法
- **添加新的UI模块**: 在ModuleItems中添加新的模块类型，并创建对应的视图组件
- **自定义搜索结果处理**: 在SearchService中添加新的结果处理逻辑

### 4. 已知问题和优化方向
- **FileSearchService**: 存在search和searchFiles两个方法，外部调用混乱
- **SearchService**: 实现的SearchFiles和SearchMoreFiles功能与FileSearchService功能有重复，且SearchMoreFiles存在bug
- **UI组件抽象**: 需要将不同类型的显示项内容抽象为统一的RowView，使其可以动态调整顺序，并支持更多类型的选择交互
- **性能优化**: 大量文件搜索时的性能问题需要进一步优化
- **AI响应**: 可以进一步优化AI响应的展示方式和交互体验

## 贡献指南
- 提交PR前请确保代码通过所有测试
- 新功能请先创建Issue讨论
- 遵循项目的代码风格和架构模式
- 提供详细的注释和文档
