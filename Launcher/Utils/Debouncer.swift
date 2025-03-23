import SwiftUI
import Foundation
import Combine

/// 用于延迟执行函数的防抖工具类
/// 常用于处理搜索输入等需要防止频繁触发的场景
class Debouncer {
    private var task: DispatchWorkItem?
    private let delay: TimeInterval
    
    /// 初始化防抖工具
    /// - Parameter delay: 延迟执行的时间（秒）
    init(delay: TimeInterval = 0.3) {
        self.delay = delay
    }
    
    /// 防抖执行操作
    /// - Parameter action: 需要执行的闭包
    func debounce(action: @escaping () -> Void) {
        // 取消之前的任务
        task?.cancel()
        
        // 创建新任务
        let newTask = DispatchWorkItem { action() }
        self.task = newTask
        
        // 延迟执行
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: newTask)
    }
    
    /// 立即取消当前排队的所有任务
    func cancel() {
        task?.cancel()
        task = nil
    }
} 