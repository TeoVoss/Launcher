import SwiftUI
import Foundation
import Combine

/// 防抖动器 - 用于延迟执行代码，避免过于频繁触发某些操作
class Debouncer {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?
    
    /// 初始化防抖动器
    /// - Parameter delay: 延迟执行的时间（秒）
    init(delay: TimeInterval) {
        self.delay = delay
    }
    
    /// 执行操作，如果在延迟时间内再次调用，则取消之前的操作并重新计时
    /// - Parameter action: 需要执行的闭包
    func run(action: @escaping () -> Void) {
        // 取消之前未执行的动作
        workItem?.cancel()
        
        // 创建新的工作项
        let newWorkItem = DispatchWorkItem(block: action)
        workItem = newWorkItem
        
        // 延迟执行
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: newWorkItem)
    }
    
    /// 立即执行当前排队的操作（如果有的话）
    func executeNow() {
        workItem?.perform()
        workItem?.cancel()
        workItem = nil
    }
    
    /// 取消所有待执行的操作
    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
} 