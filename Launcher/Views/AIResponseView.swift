import SwiftUI
import AppKit

// 创建一个 PreferenceKey 来传递内容高度
struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// 处理链接点击
struct LinkHandlingView: NSViewRepresentable {
    let attributedString: NSAttributedString
    let fontSize: CGFloat
    let textColor: NSColor
    
    init(attributedString: NSAttributedString, fontSize: CGFloat = 14, textColor: NSColor = .labelColor) {
        self.attributedString = attributedString
        self.fontSize = fontSize
        self.textColor = textColor
    }
    
    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = textColor
        textView.delegate = context.coordinator
        
        return textView
    }
    
    func updateNSView(_ nsView: NSTextView, context: Context) {
        let newAttrString = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: newAttrString.length)
        
        // 应用统一的字体和颜色
        newAttrString.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize), range: fullRange)
        newAttrString.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        
        // 保留链接属性
        attributedString.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            if let url = value {
                newAttrString.addAttribute(.link, value: url, range: range)
                // 添加链接样式
                newAttrString.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
                newAttrString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        
        nsView.textStorage?.setAttributedString(newAttrString)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            } else if let urlString = link as? String, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }
}

// 实现代码块解析和渲染
struct CodeBlockView: View {
    let content: String
    let language: String?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // 显示语言标签
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                        .padding(.bottom, 2)
                }
                
                // 显示代码内容
                Text(content)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .lineSpacing(2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.textBackgroundColor).opacity(0.6))
            .cornerRadius(4)
        }
    }
}

// 列表项渲染视图
struct ListItemView: View {
    let marker: String
    let content: String
    let indentLevel: Int
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(.system(size: 14))
                .frame(width: 16, alignment: .leading)
                .padding(.leading, CGFloat(indentLevel * 16))
            
            // 使用Markdown渲染来支持加粗、斜体等格式
            Text(markdown: content)
                .font(.system(size: 14))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Markdown元素枚举
enum MarkdownElement {
    case text(String)
    case codeBlock(String, String?)
    case list([(marker: String, content: String, level: Int)])
    case heading(String, Int) // 新增：标题内容和级别
}

// Markdown文本解析器
struct MarkdownTextParser {
    static func parse(text: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        var inCodeBlock = false
        var codeBlockContent = ""
        var codeBlockLanguage: String? = nil
        
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        var i = 0
        
        while i < lines.count {
            let lineStr = lines[i]
            
            // 检测代码块的开始和结束
            if lineStr.hasPrefix("```") {
                if !inCodeBlock {
                    // 在进入代码块之前，处理已收集的文本
                    if i > 0 {
                        let textBlockLines = lines[0..<i]
                        let textBlock = textBlockLines.joined(separator: "\n")
                        if !textBlock.isEmpty {
                            let parsed = parseTextWithLists(textBlock)
                            elements.append(contentsOf: parsed)
                        }
                    }
                    
                    inCodeBlock = true
                    // 获取语言类型
                    let langPart = lineStr.dropFirst(3)
                    codeBlockLanguage = langPart.isEmpty ? nil : String(langPart)
                    i += 1
                    
                    // 收集代码块内容直到结束标记
                    codeBlockContent = ""
                    while i < lines.count && !lines[i].hasPrefix("```") {
                        if !codeBlockContent.isEmpty {
                            codeBlockContent += "\n"
                        }
                        codeBlockContent += lines[i]
                        i += 1
                    }
                    
                    // 添加代码块并跳过结束标记
                    elements.append(.codeBlock(codeBlockContent, codeBlockLanguage))
                    if i < lines.count { // 跳过结束的 ```
                        i += 1
                    }
                    
                    // 重置状态，准备处理后续内容
                    inCodeBlock = false
                    codeBlockContent = ""
                    codeBlockLanguage = nil
                    
                    // 移除已处理的行
                    if i < lines.count {
                        let remainingLines = Array(lines[i...])
                        return elements + parse(text: remainingLines.joined(separator: "\n"))
                    }
                }
            } else {
                i += 1
            }
        }
        
        // 处理最后一部分文本（如果有）
        if !inCodeBlock && !lines.isEmpty {
            let textBlock = lines.joined(separator: "\n")
            if !textBlock.isEmpty {
                let parsed = parseTextWithLists(textBlock)
                elements.append(contentsOf: parsed)
            }
        }
        
        return elements
    }
    
    // 解析文本块，处理可能包含的列表和标题
    static func parseTextWithLists(_ text: String) -> [MarkdownElement] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        var elements: [MarkdownElement] = []
        var currentParagraph = ""
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            
            // 检查是否是标题
            if let (headingText, level) = parseHeading(line) {
                // 先处理之前收集的段落
                if !currentParagraph.isEmpty {
                    elements.append(.text(currentParagraph))
                    currentParagraph = ""
                }
                
                // 添加标题
                elements.append(.heading(headingText, level))
                i += 1
                continue
            }
            
            // 收集当前行到段落
            if !currentParagraph.isEmpty {
                currentParagraph += "\n"
            }
            currentParagraph += line
            i += 1
        }
        
        // 处理剩余的段落
        if !currentParagraph.isEmpty {
            // 检查是否包含列表
            let listElement = parseListsInText(currentParagraph)
            elements.append(listElement)
        }
        
        return elements
    }
    
    // 解析文本中的列表
    static func parseListsInText(_ text: String) -> MarkdownElement {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        
        // 检查是否包含列表项
        var hasListItems = false
        var consecutiveListItems = 0
        
        for line in lines {
            if isListItem(line) {
                hasListItems = true
                consecutiveListItems += 1
                if consecutiveListItems >= 2 { // 至少需要两个连续的列表项才被视为列表
                    break
                }
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                consecutiveListItems = 0
            }
        }
        
        // 如果确定包含列表，那么处理列表
        if hasListItems && consecutiveListItems >= 2 {
            var listItems: [(marker: String, content: String, level: Int)] = []
            var currentItems: [(marker: String, content: String, level: Int)] = []
            var currentText = ""
            var inList = false
            
            for line in lines {
                if let (marker, content, level) = parseListItem(line) {
                    // 如果有已收集的文本，先添加为普通文本
                    if !currentText.isEmpty {
                        listItems.append(("", currentText, 0))
                        currentText = ""
                    }
                    
                    inList = true
                    currentItems.append((marker, content, level))
                } else if inList && line.trimmingCharacters(in: .whitespaces).isEmpty {
                    // 保留列表内的空行
                    currentItems.append(("", "", 0))
                } else if inList {
                    // 列表结束，处理已收集的列表项
                    listItems.append(contentsOf: currentItems)
                    currentItems = []
                    inList = false
                    currentText = line
                } else {
                    // 收集普通文本
                    if !currentText.isEmpty {
                        currentText += "\n"
                    }
                    currentText += line
                }
            }
            
            // 处理最后可能剩余的列表项或文本
            if inList && !currentItems.isEmpty {
                listItems.append(contentsOf: currentItems)
            } else if !currentText.isEmpty {
                listItems.append(("", currentText, 0))
            }
            
            return .list(listItems)
        } else {
            // 不是列表，直接返回普通文本
            return .text(text)
        }
    }
    
    // 解析标题
    static func parseHeading(_ line: String) -> (content: String, level: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // 匹配Markdown标题格式 (# 标题1, ## 标题2, 等)
        if let match = trimmed.range(of: "^#{1,6}\\s+", options: .regularExpression) {
            let marker = String(trimmed[match.lowerBound..<match.upperBound])
            let level = marker.trimmingCharacters(in: .whitespaces).count
            let content = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            
            return (content, level)
        }
        
        return nil
    }
    
    // 检查是否是列表项
    static func isListItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // 匹配无序列表项 (*, -, +)
        if trimmed.range(of: "^[*\\-+]\\s+", options: .regularExpression) != nil {
            return true
        }
        
        // 匹配有序列表项 (1., 2., etc)
        if trimmed.range(of: "^\\d+\\.\\s+", options: .regularExpression) != nil {
            return true
        }
        
        return false
    }
    
    // 解析单行，检查是否是列表项
    static func parseListItem(_ line: String) -> (marker: String, content: String, level: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // 计算缩进级别（简化）
        let indentLevel = line.prefix(while: { $0.isWhitespace }).count / 2
        
        // 匹配无序列表项 (*, -, +)
        if let match = trimmed.range(of: "^[*\\-+]\\s+", options: .regularExpression) {
            let marker = String(trimmed[match.lowerBound..<match.upperBound]).trimmingCharacters(in: .whitespaces)
            let content = String(trimmed[match.upperBound...])
            return (marker, content, indentLevel)
        }
        
        // 匹配有序列表项 (1., 2., etc)
        if let match = trimmed.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
            let marker = String(trimmed[match.lowerBound..<match.upperBound]).trimmingCharacters(in: .whitespaces)
            let content = String(trimmed[match.upperBound...])
            return (marker, content, indentLevel)
        }
        
        return nil
    }
}

// 标题视图
struct HeadingView: View {
    let content: String
    let level: Int
    
    var body: some View {
        // 使用markdown初始化器来渲染标题内容中的格式标记
        Text(markdown: content)
            .font(fontForLevel(level))
            .fontWeight(.bold)
            .padding(.bottom, 4)
            .padding(.top, 6)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func fontForLevel(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 24)
        case 2: return .system(size: 20)
        case 3: return .system(size: 18)
        case 4: return .system(size: 16)
        case 5: return .system(size: 14)
        case 6: return .system(size: 13)
        default: return .system(size: 14)
        }
    }
}

// 渲染Markdown的视图
struct MarkdownContentView: View {
    let content: String
    
    var body: some View {
        let elements = MarkdownTextParser.parse(text: content)
        
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<elements.count, id: \.self) { index in
                switch elements[index] {
                case .text(let text):
                    let attributedString = try! NSAttributedString(
                        markdown: text,
                        options: AttributedString.MarkdownParsingOptions(
                            allowsExtendedAttributes: true,
                            interpretedSyntax: .inlineOnlyPreservingWhitespace
                        )
                    )
                    
                    // 检查是否包含链接
                    let containsLink = checkContainsLink(attributedString)
                    
                    if containsLink {
                        // 使用改进的LinkHandlingView处理链接
                        LinkHandlingView(attributedString: attributedString)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: estimateHeight(for: text))
                    } else {
                        // 普通文本使用SwiftUI Text
                        Text(markdown: text)
                            .font(.system(size: 14))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                
                case .codeBlock(let code, let language):
                    CodeBlockView(content: code, language: language)
                
                case .heading(let text, let level):
                    HeadingView(content: text, level: level)
                    
                case .list(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<items.count, id: \.self) { i in
                            let item = items[i]
                            if item.marker.isEmpty && item.content.isEmpty {
                                Spacer().frame(height: 4) // 空行
                            } else if item.marker.isEmpty {
                                // 非列表项文本
                                Text(markdown: item.content)
                                    .font(.system(size: 14))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                // 列表项
                                ListItemView(marker: item.marker, content: item.content, indentLevel: item.level)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // 检查NSAttributedString是否包含链接
    private func checkContainsLink(_ attributedString: NSAttributedString) -> Bool {
        let fullRange = NSRange(location: 0, length: attributedString.length)
        var containsLink = false
        
        attributedString.enumerateAttribute(.link, in: fullRange) { value, range, stop in
            if value != nil {
                containsLink = true
                stop.pointee = true
            }
        }
        
        return containsLink
    }
    
    // 估计文本高度的函数
    private func estimateHeight(for text: String) -> CGFloat {
        let charCount = text.count
        let avgCharsPerLine: CGFloat = 60 // 估计每行平均字符数
        let lineHeight: CGFloat = 20 // 每行高度
        
        return ceil(CGFloat(charCount) / avgCharsPerLine) * lineHeight + 10
    }
}

// 扩展来渲染Markdown内容
extension Text {
    init(markdown: String) {
        do {
            // 创建AttributedString并设置Markdown解析选项
            let attributedString = try AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
            self.init(attributedString)
        } catch {
            // 如果解析失败，降级为普通文本
            self.init(markdown)
        }
    }
}

struct AIResponseView: View {
    @ObservedObject var aiService: AIService
    let prompt: String
    let onEscape: () -> Void
    // 添加高度变化回调函数
    var onHeightChange: ((CGFloat) -> Void)? = nil
    // 添加引用回调，用于外部获取视图实例
    var onViewCreated: ((AIResponseView) -> Void)? = nil
    @State private var scrollViewHeight: CGFloat = 0
    @State private var currentPrompt: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 单一消息流视图
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 显示所有对话（包括正在进行的对话）
                        ForEach(aiService.conversationHistory) { message in
                            // 根据消息类型设置不同的样式
                            if message.role == "user" {
                                // 用户消息
                                Text(message.content)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                    .padding(.bottom, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, aiService.conversationHistory.firstIndex(of: message)! > 0 && 
                                             aiService.conversationHistory[aiService.conversationHistory.firstIndex(of: message)! - 1].role == "assistant" ? 20 : 4) // 增加问题之间的间距
                                    .id(message.id)
                            } else {
                                // AI回复
                                let index = aiService.conversationHistory.firstIndex(of: message)!
                                if message.content.isEmpty && index == aiService.activeResponseIndex {
                                    // 显示"正在思考中"状态
                                    HStack(spacing: 4) {
                                        Text("正在思考中...")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                        
                                        ProgressView()
                                            .scaleEffect(0.5)
                                            .frame(height: 16)
                                    }
                                    .id("thinking_\(index)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                                } else {
                                    // 使用增强的Markdown渲染视图
                                    MarkdownContentView(content: message.content)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .id(message.id)
                                        .padding(.bottom, 4)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: ContentHeightPreferenceKey.self,
                            value: geo.size.height
                        )
                    })
                    .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
                        scrollViewHeight = height
                        updateTotalHeight()
                    }
                }
                .onChange(of: aiService.conversationHistory) { newValue in
                    // 当对话历史更新时（添加新消息或现有消息更新内容），滚动到最新消息
                    if !newValue.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(newValue.last!.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear {
            // 第一次显示视图时，记录当前提示并发送请求
            currentPrompt = prompt
            
            // 调用回调，使外部能引用此视图
            onViewCreated?(self)
            
            Task { @MainActor in
                await aiService.streamChat(prompt: prompt)
            }
        }
        .onChange(of: prompt) { newValue in
            // 更新当前记录的提示，但不触发请求
            // 请求将由SpotlightView的handleSubmit方法在用户按下Enter时触发
            currentPrompt = newValue
        }
        .onDisappear {
            aiService.cancelStream()
        }
    }
    
    // 添加一个方法来手动发送请求
    func sendRequest() async {
        if !aiService.isStreaming {
            await aiService.streamChat(prompt: currentPrompt)
        }
    }
    
    private func updateTotalHeight() {
        let totalHeight = min(scrollViewHeight + 20, 500) // 滚动视图高度 + 上下内边距，最大高度限制
        
        // 设置一个最小高度，即使内容很少也保持合理的窗口大小
        let minHeight: CGFloat = 250
        let effectiveHeight = max(totalHeight, minHeight)
        
        // 通知父视图更新高度
        onHeightChange?(effectiveHeight)
    }
} 