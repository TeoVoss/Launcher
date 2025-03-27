# Launcher - macOS智能快捷启动器

## 技术架构
```mermaid
flowchart TD
    A[HotKey 全局快捷键] --> B(事件监听)
    B --> C{搜索类型判断}
    C -->|应用搜索| D[ApplicationSearchService]
    C -->|文件搜索| E[FileSearchService]
    C -->|AI指令| F[AIService]
    D --> |NSWorkspace| G[SearchResultManager]
    E --> |Spotlight| G
    F --> |GPT-3.5| G
    G --> |ObservableObject| H[SpotlightViewModel]
    H --> |SwiftUI| I[[SpotlightView UI]]
```

## 核心模块实现
### 1. 快捷键系统
- **实现路径**：`/Launcher/LauncherApp.swift`
- **技术选型**：基于HotKey库实现全局快捷键监听
- **核心流程**：
  ```swift
  // 注册Command + Control + 1快捷键
  hotKey = HotKey(key: .one, modifiers: [.command, .control]) { [weak self] in
      self?.toggleWindow()
  }
  ```

### 2. 智能搜索系统
| 服务类型 | 实现类 | 核心算法 | 性能优化 |
|---------|--------|----------|----------|
| 应用搜索 | ApplicationSearchService | NSWorkspace实时枚举 | 后台缓存+增量更新 |
| 文件搜索 | FileSearchService | Spotlight元数据查询 | 异步加载+结果限流 |
| AI指令解析 | AIService | OpenAI GPT-3.5 Turbo | 本地缓存+流式响应 |

### 3. 界面渲染系统
- **架构模式**：MVVM (SwiftUI + Combine)
- **核心组件**：
  - `SpotlightViewModel`: 状态管理与数据绑定
  - `SearchBar`: 模糊搜索输入框
  - `ResultList`: 虚拟列表优化
  - `AIResponseView`: 代码高亮与Markdown渲染

## 项目结构
```
Launcher/
├── Services/               # 核心业务逻辑
│   ├── BaseSearchService.swift    - 搜索服务基类协议
│   ├── AIService.swift           - OpenAI集成实现
│   ├── SearchResultManager.swift  - 结果聚合与排序
│   └── KeyboardHandler.swift     - 快捷键管理
├── ViewModels/             # 状态管理
│   └── SpotlightViewModel.swift  - MVVM核心
└── Views/                  # UI组件
    ├── SpotlightView.swift       - 主界面容器
    └── AIResponseView.swift      - AI响应渲染
```

## 开发指南
### 1. 环境配置
```bash
# 依赖版本
- Xcode 15+
- Swift 5.9
- macOS 13.5+

# 项目初始化
git clone https://github.com/your-repo/Launcher.git
cd Launcher
xcodebuild -scheme Launcher
```

### 2. 调试模式
```bash
# 开启详细日志
DEBUG_MODE=1 xcodebuild test

# 性能分析
xcodebuild -scheme Launcher -configuration Release
instruments -t Time\ Profiler Launcher.app
```

### 3. 扩展开发
- **新增搜索类型**
  ```swift
  class CustomSearchService: BaseSearchService {
      func search(_ query: String) async throws -> [SearchResult] {
          // 实现自定义搜索逻辑
      }
  }
  ```
- **UI定制**：基于SwiftUI组件化设计，支持主题定制
- **性能优化**：已集成XCTest性能测试框架

> 完整API文档与性能优化指南参见：`/Docs/API.md`

### 4. TODO
FileSearchService 里有 search 和 searchFiles 两个方法，外部调用混乱
SearchService 中，实现的 SearchFiles 和 SearchMoreFiles 功能和 FileSearchService 的功能有一些重复，而且 SearchMoreFiles 还有 bug

把不同类型的显示项内容都抽象为 rowview，使之可以动态调整顺序，以及支持更多类型的选择交互
