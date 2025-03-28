import Foundation
import SwiftUI
import JavaScriptCore

class CalculatorService {
    // 单例实例
    static let shared = CalculatorService()
    
    // JavaScript引擎，用于表达式求值
    private let context = JSContext()
    
    // 汇率相关常量
    private struct Currency {
        let symbol: String      // 符号，如 $ ¥ €
        let code: String        // 代码，如 USD CNY EUR
        let rate: Double        // 兑换成人民币的汇率
        let name: String        // 货币名称
    }
    
    // 支持的货币列表
    private var currencies: [Currency] = [
        Currency(symbol: "¥", code: "CNY", rate: 1.0, name: "人民币"),
        Currency(symbol: "$", code: "USD", rate: 7.22, name: "美元"),
        Currency(symbol: "€", code: "EUR", rate: 7.83, name: "欧元"),
        Currency(symbol: "£", code: "GBP", rate: 9.15, name: "英镑"),
        Currency(symbol: "¥", code: "JPY", rate: 0.047, name: "日元"),
        Currency(symbol: "₩", code: "KRW", rate: 0.0053, name: "韩元"),
        Currency(symbol: "₽", code: "RUB", rate: 0.077, name: "俄罗斯卢布"),
        Currency(symbol: "₹", code: "INR", rate: 0.086, name: "印度卢比"),
        Currency(symbol: "A$", code: "AUD", rate: 4.75, name: "澳元"),
        Currency(symbol: "C$", code: "CAD", rate: 5.29, name: "加元"),
        Currency(symbol: "HK$", code: "HKD", rate: 0.92, name: "港币")
    ]
    
    // 亲戚关系图谱
    private var relationshipMap: [String: [String: String]] = [
        "爸爸": ["我":"爸爸", "爸爸": "爷爷", "妈妈": "奶奶", "儿子": "兄弟", "女儿": "姐妹", "哥哥": "伯父", "弟弟": "叔叔", "姐姐": "姑姑", "妹妹": "姑姑"],
        "妈妈": ["我":"妈妈", "爸爸": "外公", "妈妈": "外婆", "儿子": "哥哥", "女儿": "姐姐", "哥哥": "舅舅", "弟弟": "舅舅", "姐姐": "姨妈", "妹妹": "姨妈"],
        "儿子": ["我":"儿子", "爸爸": "我", "妈妈": "妻子", "儿子": "孙子", "女儿": "孙女"],
        "女儿": ["我":"女儿", "爸爸": "我", "妈妈": "妻子", "儿子": "外孙", "女儿": "外孙女"],
        "哥哥": ["我":"哥哥", "爸爸": "爸爸", "妈妈": "妈妈", "儿子": "侄子", "女儿": "侄女"],
        "弟弟": ["我":"弟弟", "爸爸": "爸爸", "妈妈": "妈妈", "儿子": "侄子", "女儿": "侄女"],
        "姐姐": ["我":"姐姐", "爸爸": "爸爸", "妈妈": "妈妈", "儿子": "外甥", "女儿": "外甥女"],
        "妹妹": ["我":"妹妹", "爸爸": "爸爸", "妈妈": "妈妈", "儿子": "外甥", "女儿": "外甥女"],
        "爷爷": ["我":"爷爷", "爸爸": "曾祖父", "妈妈": "曾祖母"],
        "奶奶": ["我":"奶奶", "爸爸": "曾祖父", "妈妈": "曾祖母"],
        "外公": ["我":"外公", "爸爸": "曾外祖父", "妈妈": "曾外祖母"],
        "外婆": ["我":"外婆", "爸爸": "曾外祖父", "妈妈": "曾外祖母"]
    ]
    
    private init() {
        // 初始化JavaScript上下文并添加数学函数
        setupMathFunctions()
    }
    
    // 设置JavaScript环境中的数学函数
    private func setupMathFunctions() {
        let script = """
        function sin(x) { return Math.sin(x); }
        function cos(x) { return Math.cos(x); }
        function tan(x) { return Math.tan(x); }
        function asin(x) { return Math.asin(x); }
        function acos(x) { return Math.acos(x); }
        function atan(x) { return Math.atan(x); }
        function sqrt(x) { return Math.sqrt(x); }
        function pow(x, y) { return Math.pow(x, y); }
        function log(x) { return Math.log(x); }
        function log10(x) { return Math.log10(x); }
        function exp(x) { return Math.exp(x); }
        function abs(x) { return Math.abs(x); }
        function round(x) { return Math.round(x); }
        function floor(x) { return Math.floor(x); }
        function ceil(x) { return Math.ceil(x); }
        function PI() { return Math.PI; }
        function E() { return Math.E; }
        """
        context?.evaluateScript(script)
    }
    
    // 检查输入是否是一个计算表达式
    func isCalculation(_ input: String) -> Bool {
        // 去除空格
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 检查是否包含数学运算符号
        let hasOperator = trimmed.contains("+") || trimmed.contains("-") || 
                         trimmed.contains("*") || trimmed.contains("/") ||
                         trimmed.contains("^") || trimmed.contains("%") ||
                         trimmed.contains("sqrt") || trimmed.contains("sin") ||
                         trimmed.contains("cos") || trimmed.contains("tan")
        
        // 检查是否是货币查询
        if isCurrencyQuery(trimmed) {
            return true
        }
        
        // 检查是否是亲戚关系查询
        if isRelationshipQuery(trimmed) {
            return true
        }
        
        return hasOperator
    }
    
    // 计算表达式结果
    func calculate(_ input: String) -> (formula: String, result: String)? {
        // 检查是否是货币查询
        if let currencyResult = processCurrencyQuery(input) {
            return currencyResult
        }
        
        // 检查是否是亲戚关系查询
        if let relationshipResult = processRelationshipQuery(input) {
            return relationshipResult
        }
        
        // 处理数学表达式
        if let mathResult = calculateMathExpression(input) {
            return mathResult
        }
        return nil
    }
    
    // 计算数学表达式
    private func calculateMathExpression(_ input: String) -> (formula: String, result: String)? {
        // 美化公式，如将5*6转换为5×6
        let beautifiedFormula = beautifyFormula(input)
        
        // 准备JavaScript可以执行的表达式
        var jsExpression = input
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "^", with: "**")
            .replacingOccurrences(of: "%", with: "/100")
        
        // 计算结果
        guard let result = context?.evaluateScript(jsExpression) else {
            return nil
        }
        
        // 处理结果
        if result.isNumber {
            let doubleValue = result.toDouble()
            
            // 格式化结果，处理小数
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 8
            
            if let formattedResult = formatter.string(from: NSNumber(value: doubleValue)) {
                return (beautifiedFormula, formattedResult)
            } else {
                return (beautifiedFormula, String(doubleValue))
            }
        } else if isCalculation(input) {
            return (input, input)
        } else {
            return nil
        }
    }
    
    // 美化公式显示，如将*转换为×
    private func beautifyFormula(_ input: String) -> String {
        return input
            .replacingOccurrences(of: "*", with: "×")
            .replacingOccurrences(of: "/", with: "÷")
    }
    
    // 检查是否是货币查询
    private func isCurrencyQuery(_ input: String) -> Bool {
        // 检查是否包含货币符号或代码
        for currency in currencies {
            if input.contains(currency.symbol) || input.uppercased().contains(currency.code) {
                return true
            }
        }
        return false
    }
    
    // 处理货币查询
    private func processCurrencyQuery(_ input: String) -> (formula: String, result: String)? {
        // 提取数字
        let numberPattern = try? NSRegularExpression(pattern: "[0-9]+(\\.[0-9]+)?")
        guard let matches = numberPattern?.matches(in: input, range: NSRange(input.startIndex..., in: input)),
              let match = matches.first,
              let range = Range(match.range, in: input) else {
            return nil
        }
        
        let amountStr = String(input[range])
        guard let amount = Double(amountStr) else {
            return nil
        }
        
        // 查找货币符号或代码
        var matchedCurrency: Currency?
        for currency in currencies {
            if input.contains(currency.symbol) && currency.symbol != "¥" { // 避免¥符号匹配歧义
                matchedCurrency = currency
                break
            } else if input.uppercased().contains(currency.code) {
                matchedCurrency = currency
                break
            }
        }
        
        // 如果找到货币，计算兑换成人民币的结果
        if let currency = matchedCurrency {
            let cnyAmount = amount * currency.rate
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            
            let formattedAmount = formatter.string(from: NSNumber(value: amount)) ?? String(amount)
            let formattedCNY = formatter.string(from: NSNumber(value: cnyAmount)) ?? String(cnyAmount)
            
            let formula = "\(currency.symbol)\(formattedAmount) (\(currency.name))"
            let result = "¥\(formattedCNY) (人民币)"
            
            return (formula, result)
        }
        
        return nil
    }
    
    // 检查是否是亲戚关系查询
    private func isRelationshipQuery(_ input: String) -> Bool {
        // 检查是否包含常见亲戚称谓和关系词
        let relationshipTerms = ["爸爸", "妈妈", "父亲", "母亲", "儿子", "女儿", "哥哥", "弟弟", "姐姐", "妹妹", "爷爷", "奶奶", "外公", "外婆"]
        let relationshipConnectors = ["的", "是", "叫什么", "称为", "称作"]
        
        var hasRelationshipTerm = false
        for term in relationshipTerms {
            if input.contains(term) {
                hasRelationshipTerm = true
                break
            }
        }
        
        var hasConnector = false
        for connector in relationshipConnectors {
            if input.contains(connector) {
                hasConnector = true
                break
            }
        }
        
        return hasRelationshipTerm && hasConnector
    }
    
    // 处理亲戚关系查询
    private func processRelationshipQuery(_ input: String) -> (formula: String, result: String)? {
        // 先尝试简单的"A的B"模式
        let components = input.components(separatedBy: "的")
        if components.count >= 2 {
            var relationChain: [String] = []
            
            // 从右到左构建关系链
            for i in 0..<(components.count - 1) {
                // 清理并提取关系词
                let relation = cleanupRelationTerm(components[i])
                if !relation.isEmpty {
                    relationChain.append(relation)
                }
            }
            
            let target = cleanupRelationTerm(components.last ?? "")
            
            // 计算最终关系
            if !relationChain.isEmpty && !target.isEmpty {
                if let result = calculateRelationship(relationChain, target) {
                    // 构建公式和结果
                    let formula = relationChain.joined(separator: "的") + "的" + target
                    return (formula, result)
                }
            }
        }
        
        return nil
    }
    
    // 清理并提取亲戚关系词
    private func cleanupRelationTerm(_ term: String) -> String {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 映射常见的别名
        let mappings = [
            "父亲": "爸爸",
            "母亲": "妈妈",
            "父": "爸爸",
            "母": "妈妈",
            "老爸": "爸爸",
            "老妈": "妈妈",
            "爸": "爸爸",
            "妈": "妈妈",
            "大哥": "哥哥",
            "二哥": "哥哥",
            "大姐": "姐姐",
            "二姐": "姐姐",
            "儿": "儿子",
            "子": "儿子",
            "女": "女儿"
        ]
        
        // 检查并返回标准关系词
        for (alias, standard) in mappings {
            if term.contains(alias) {
                return standard
            }
        }
        
        // 检查原始关系图中的关系词
        for key in relationshipMap.keys {
            if term.contains(key) {
                return key
            }
        }
        
        // 处理"叫什么"、"是什么"等查询模式
        if term.contains("叫什么") || term.contains("叫") || term.contains("是什么") || term.contains("是") {
            return ""
        }
        
        return term
    }
    
    // 计算复杂的亲戚关系
    private func calculateRelationship(_ relationChain: [String], _ target: String) -> String? {
        // 从"我"开始，依次应用关系
        var currentRelation = "我"
        
        for relation in relationChain.reversed() {
            if let nextMap = relationshipMap[relation], let next = nextMap[currentRelation] {
                currentRelation = next
            } else {
                return nil // 关系图中没有此关系
            }
        }
        
        // 最后一步，计算目标关系
        if currentRelation == "我" {
            return target
        } else if let targetMap = relationshipMap[currentRelation], let result = targetMap[target] {
            return result
        }
        
        return nil
    }
    
    // 获取最新汇率
    func updateCurrencyRates() {
        // 在实际应用中，这里应该调用API获取实时汇率
        // 为了演示，我们使用固定汇率
    }
} 
