import Foundation
import AppKit

// 基础搜索服务 - 为所有搜索服务提供共享功能
class BaseSearchService {
    // 计算字符串相关性分数的共享方法
    func calculateRelevanceScore(name: String, query: String) -> Int {
        let lowercaseName = name.lowercased()
        let lowercaseQuery = query.lowercased()
        
        // 完全匹配，最高优先级
        if lowercaseName == lowercaseQuery {
            return 100
        }
        
        // 开头匹配，次高优先级
        if lowercaseName.hasPrefix(lowercaseQuery) {
            return 80
        }
        
        // 单词开头匹配，例如在"Safari浏览器"中匹配"Safari"
        let words = lowercaseName.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            if word.hasPrefix(lowercaseQuery) {
                return 70
            }
        }
        
        // 中文特殊处理 - 为中文查询提供更高的包含匹配分数
        if containsChineseCharacters(query) {
            if lowercaseName.contains(lowercaseQuery) {
                // 字符匹配在靠前的位置，根据匹配位置给分
                if let range = lowercaseName.range(of: lowercaseQuery) {
                    let distance = lowercaseName.distance(from: lowercaseName.startIndex, to: range.lowerBound)
                    return max(30, 65 - distance) // 中文匹配位置越靠前，分数越高
                }
                return 60 // 默认中文包含匹配分数
            }
        }
        
        // 字符匹配在靠前的位置，根据匹配位置给分
        if let range = lowercaseName.range(of: lowercaseQuery) {
            let distance = lowercaseName.distance(from: lowercaseName.startIndex, to: range.lowerBound)
            return max(10, 60 - distance * 2) // 匹配位置越靠前，分数越高
        }
        
        // 默认分数
        return 0
    }
    
    // 检查字符串是否匹配查询
    func nameMatchesQuery(name: String, query: String) -> Bool {
        let lowercaseName = name.lowercased()
        let lowercaseQuery = query.lowercased()
        
        // 完全匹配
        if lowercaseName == lowercaseQuery {
            return true
        }
        
        // 前缀匹配
        if lowercaseName.hasPrefix(lowercaseQuery) {
            return true
        }
        
        // 忽略英文单词之间的空格的匹配
        let nameNoSpaces = lowercaseName.replacingOccurrences(of: " ", with: "")
        let queryNoSpaces = lowercaseQuery.replacingOccurrences(of: " ", with: "")
        
        if nameNoSpaces == queryNoSpaces || nameNoSpaces.hasPrefix(queryNoSpaces) {
            return true
        }
        
        // 单词匹配（对英文更有效）
        let words = lowercaseName.components(separatedBy: .whitespacesAndNewlines)
        for word in words where word.hasPrefix(lowercaseQuery) {
            return true
        }
        
        // 中文匹配 - 对中文字符进行特殊处理
        if containsChineseCharacters(query) {
            // 对于中文查询，支持任意位置匹配
            if lowercaseName.contains(lowercaseQuery) {
                return true
            }
        }
        // 英文匹配，至少3个字符才做包含匹配
        else if query.count >= 3 && lowercaseName.contains(lowercaseQuery) {
            return true
        }
        
        return false
    }
    
    // 检查字符串是否包含中文字符
    func containsChineseCharacters(_ text: String) -> Bool {
        let pattern = "\\p{Han}"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: text.utf16.count)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
        return false
    }
    
    // 排序搜索结果
    func sortSearchResults(_ results: [SearchResult]) -> [SearchResult] {
        results.sorted { (result1, result2) in
            // 首先比较最近使用时间
            if let date1 = result1.lastUsedDate, let date2 = result2.lastUsedDate {
                if date1 != date2 {
                    return date1 > date2
                }
            } else if result1.lastUsedDate != nil {
                return true
            } else if result2.lastUsedDate != nil {
                return false
            }
            
            // 时间相同或无法比较时，比较相关性分数
            return result1.relevanceScore > result2.relevanceScore
        }
    }
    
    // 为搜索字符串构建Spotlight谓词
    func buildSearchPredicates(forQuery query: String) -> NSPredicate {
        let queryWords = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        
        if queryWords.isEmpty {
            return NSPredicate(value: false)
        }
        
        var predicates: [NSPredicate] = []
        
        // 1. 精确匹配 - 名称完全等于查询
        let exactNamePredicate = NSPredicate(format: "kMDItemDisplayName ==[cd] %@", query)
        predicates.append(exactNamePredicate)
        
        // 2. 名称开头匹配 - 比普通包含更有针对性
        let nameStartsPredicate = NSPredicate(format: "kMDItemDisplayName BEGINSWITH[cd] %@", query)
        predicates.append(nameStartsPredicate)
        
        // 3. 文件名开头匹配 - 比普通包含更有针对性
        let fileNameStartsPredicate = NSPredicate(format: "kMDItemFSName BEGINSWITH[cd] %@", query)
        predicates.append(fileNameStartsPredicate)
        
        // 4. 单词匹配 - 匹配名称中的单词
        for word in queryWords {
            if word.count >= 2 { // 只匹配长度大于等于2的单词
                // 匹配以这个词开头的应用
                let wordStartPredicate = NSPredicate(format: "kMDItemDisplayName BEGINSWITH[cd] %@", word)
                predicates.append(wordStartPredicate)
                
                if word.count >= 3 {
                    let wordWithSpacePredicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", " " + word + " ")
                    predicates.append(wordWithSpacePredicate)
                    
                    // 匹配位于开头的单词
                    let wordAtStartPredicate = NSPredicate(format: "kMDItemDisplayName BEGINSWITH[cd] %@", word + " ")
                    predicates.append(wordAtStartPredicate)
                    
                    // 匹配位于结尾的单词
                    let wordAtEndPredicate = NSPredicate(format: "kMDItemDisplayName ENDSWITH[cd] %@", " " + word)
                    predicates.append(wordAtEndPredicate)
                }
            }
        }
        
        // 5. 宽松匹配 - 为长查询字符串提供匹配机会
        if query.count >= 3 { // 只对长度大于等于3的查询使用CONTAINS
            let containsNamePredicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", query)
            predicates.append(containsNamePredicate)
            
            // 只匹配不以 .app 结尾的文件名
            if !query.lowercased().hasSuffix(".app") {
                let containsFileNamePredicate = NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@", query)
                predicates.append(containsFileNamePredicate)
            }
        }
        
        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }
} 