import Foundation
import SwiftUI
import JavaScriptCore
import Combine

class CalculatorService: ObservableObject {
    // 单例实例
    static let shared = CalculatorService()
    @Published public private(set) var calculatorResult: [SearchResult] = []
    
    private var hasOperator: Bool = false
    
    private var hasNumber: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
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
        // 父系关系
        "爸爸": ["我":"爸爸", "爸爸": "爷爷", "妈妈": "奶奶", "儿子": "兄弟", "女儿": "姐妹", "哥哥": "伯父", "弟弟": "叔叔", "姐姐": "姑姑", "妹妹": "姑姑", "爷爷": "曾祖父", "奶奶": "曾祖母", "伯父": "堂伯", "叔叔": "堂叔", "姑姑": "姑表姑", "舅舅": "姑表舅", "姨妈": "姑表姨"],
        "妈妈": ["我":"妈妈", "爸爸": "外公", "妈妈": "外婆", "儿子": "兄弟", "女儿": "姐妹", "哥哥": "舅舅", "弟弟": "舅舅", "姐姐": "姨妈", "妹妹": "姨妈", "外公": "外曾祖父", "外婆": "外曾祖母", "伯父": "姨表伯", "叔叔": "姨表叔", "姑姑": "姨表姑", "舅舅": "姨表舅", "姨妈": "姨表姨"],
        
        // 子女关系
        "儿子": ["我":"儿子", "爸爸": "我", "妈妈": "妻子", "儿子": "孙子", "女儿": "孙女", "哥哥": "侄子", "弟弟": "侄子", "姐姐": "外甥", "妹妹": "外甥", "妻子": "儿媳", "孙子": "曾孙"],
        "女儿": ["我":"女儿", "爸爸": "我", "妈妈": "妻子", "儿子": "外孙", "女儿": "外孙女", "哥哥": "侄女", "弟弟": "侄女", "姐姐": "外甥女", "妹妹": "外甥女", "丈夫": "女婿", "外孙": "外曾孙"],
        
        // 兄弟姐妹关系
        "哥哥": ["我":"哥哥", "爸爸": "爸爸", "妈妈": "妈妈", "儿子": "侄子", "女儿": "侄女", "哥哥": "堂哥", "弟弟": "堂弟", "姐姐": "堂姐", "妹妹": "堂妹", "妻子": "嫂子"],
        "弟弟": ["我":"弟弟", "爸爸": "爸爸", "妈妈": "妈妈", "儿子": "侄子", "女儿": "侄女", "哥哥": "堂哥", "弟弟": "堂弟", "姐姐": "堂姐", "妹妹": "堂妹", "妻子": "弟媳"],
        "姐姐": ["我":"姐姐", "爸爸": "爸爸", "妈妈": "妈妈", "儿子": "外甥", "女儿": "外甥女", "哥哥": "表哥", "弟弟": "表弟", "姐姐": "表姐", "妹妹": "表妹", "丈夫": "姐夫"],
        "妹妹": ["我":"妹妹", "爸爸": "爸爸", "妈妈": "妈妈", "儿子": "外甥", "女儿": "外甥女", "哥哥": "表哥", "弟弟": "表弟", "姐姐": "表姐", "妹妹": "表妹", "丈夫": "妹夫"],
        
        // 祖父母关系
        "爷爷": ["我":"爷爷", "爸爸": "曾祖父", "妈妈": "曾祖母", "儿子": "父亲", "女儿": "姑姑", "哥哥": "伯祖父", "弟弟": "叔祖父", "姐姐": "姑祖母", "妹妹": "姑祖母"],
        "奶奶": ["我":"奶奶", "爸爸": "曾祖父", "妈妈": "曾祖母", "儿子": "父亲", "女儿": "姑姑", "哥哥": "舅祖父", "弟弟": "舅祖父", "姐姐": "姨祖母", "妹妹": "姨祖母"],
        "外公": ["我":"外公", "爸爸": "外曾祖父", "妈妈": "外曾祖母", "儿子": "舅舅", "女儿": "母亲", "哥哥": "伯外祖父", "弟弟": "叔外祖父", "姐姐": "姑外祖母", "妹妹": "姑外祖母"],
        "外婆": ["我":"外婆", "爸爸": "外曾祖父", "妈妈": "外曾祖母", "儿子": "舅舅", "女儿": "母亲", "哥哥": "舅外祖父", "弟弟": "舅外祖父", "姐姐": "姨外祖母", "妹妹": "姨外祖母"],
        
        // 曾祖父母关系
        "曾祖父": ["我":"曾祖父", "儿子": "爷爷", "女儿": "姑奶奶"],
        "曾祖母": ["我":"曾祖母", "儿子": "爷爷", "女儿": "姑奶奶"],
        "外曾祖父": ["我":"外曾祖父", "儿子": "外公", "女儿": "姑外婆"],
        "外曾祖母": ["我":"外曾祖母", "儿子": "外公", "女儿": "姑外婆"],
        
        // 叔伯姑舅姨关系
        "伯父": ["我":"伯父", "爸爸": "爷爷", "妈妈": "奶奶", "儿子": "堂兄弟", "女儿": "堂姐妹", "妻子": "伯母"],
        "叔叔": ["我":"叔叔", "爸爸": "爷爷", "妈妈": "奶奶", "儿子": "堂兄弟", "女儿": "堂姐妹", "妻子": "婶婶"],
        "姑姑": ["我":"姑姑", "爸爸": "爷爷", "妈妈": "奶奶", "儿子": "表兄弟", "女儿": "表姐妹", "丈夫": "姑父"],
        "舅舅": ["我":"舅舅", "爸爸": "外公", "妈妈": "外婆", "儿子": "表兄弟", "女儿": "表姐妹", "妻子": "舅妈"],
        "姨妈": ["我":"姨妈", "爸爸": "外公", "妈妈": "外婆", "儿子": "表兄弟", "女儿": "表姐妹", "丈夫": "姨父"],
        
        // 夫妻关系
        "丈夫": ["我":"丈夫", "爸爸": "公公", "妈妈": "婆婆", "哥哥": "大伯子", "弟弟": "小叔子", "姐姐": "大姑子", "妹妹": "小姑子"],
        "妻子": ["我":"妻子", "爸爸": "岳父", "妈妈": "岳母", "哥哥": "大舅子", "弟弟": "小舅子", "姐姐": "大姨子", "妹妹": "小姨子"],
        
        // 表亲关系
        "堂兄弟": ["我":"堂兄弟", "爸爸": "伯父或叔叔", "妈妈": "伯母或婶婶"],
        "堂姐妹": ["我":"堂姐妹", "爸爸": "伯父或叔叔", "妈妈": "伯母或婶婶"],
        "表兄弟": ["我":"表兄弟", "爸爸": "姑父或舅舅或姨父", "妈妈": "姑姑或舅妈或姨妈"],
        "表姐妹": ["我":"表姐妹", "爸爸": "姑父或舅舅或姨父", "妈妈": "姑姑或舅妈或姨妈"]
    ]
    
    init() {
        // 初始化JavaScript上下文并添加数学函数
        setupMathFunctions()
    }
    
    private func updateResults(formula: String, result: String) {
        if formula.isEmpty {
            clearResults()
            return
        }
        let calcIcon = NSImage(systemSymbolName: "equal.circle.fill", accessibilityDescription: nil) ?? NSImage()
        let calculatorResult = [SearchResult(
            id: UUID(),
            name: formula,
            path: "",
            type: .calculator,
            category: "计算器",
            icon: calcIcon,
            subtitle: result,
            lastUsedDate: Date(),  // 更新使用时间
            relevanceScore: 100,
            calculationResult: result,
            formula: formula
        )]
        self.calculatorResult = calculatorResult
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
        hasOperator = trimmed.contains("+") || trimmed.contains("-") ||
                         trimmed.contains("*") || trimmed.contains("/") ||
                         trimmed.contains("、") || trimmed.contains("\\") ||
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
        
        hasNumber = trimmed.contains("0-9")
        
        return hasOperator && hasNumber
    }
    
    // 计算表达式结果
    func calculate(_ input: String) {
        if !isCalculation(input) {
            if self.calculatorResult.isEmpty {
                return
            }
            clearResults()
            return
        }
        // 检查是否是货币查询
        if let currencyResult = processCurrencyQuery(input) {
            self.updateResults(formula:currencyResult.formula, result:currencyResult.result)
            return
        }
        
        // 检查是否是亲戚关系查询
        if let relationshipResult = processRelationshipQuery(input) {
            self.updateResults(formula:relationshipResult.formula, result:relationshipResult.result)
            return
        }
        
        // 处理数学表达式
        if let mathResult = calculateMathExpression(input) {
            self.updateResults(formula:mathResult.formula, result:mathResult.result)
            return
        }
        self.updateResults(formula:input, result:input)
    }
    
    // 计算数学表达式
    private func calculateMathExpression(_ input: String) -> (formula: String, result: String)? {
        // 美化公式，如将5*6转换为5×6
        let beautifiedFormula = beautifyFormula(input)
        
        // 准备JavaScript可以执行的表达式
        let jsExpression = beautifiedFormula
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
            .replacingOccurrences(of: "、", with: "÷")
            .replacingOccurrences(of: "\\", with: "÷")
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
        // 先检查是否包含货币符号或代码
        var matchedCurrency: Currency?
        var inputWithoutCurrency = input
        
        // 查找货币符号或代码
        for currency in currencies {
            if currency.symbol != "¥" && input.contains(currency.symbol) { // 避免¥符号匹配歧义
                matchedCurrency = currency
                inputWithoutCurrency = input.replacingOccurrences(of: currency.symbol, with: "")
                break
            } else if input.uppercased().contains(currency.code) {
                matchedCurrency = currency
                inputWithoutCurrency = input.uppercased().replacingOccurrences(of: currency.code, with: "")
                break
            }
        }
        
        guard let currency = matchedCurrency else {
            return nil
        }
        
        // 处理输入中的数学表达式
        let cleanedInput = inputWithoutCurrency.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var amount: Double = 0
        
        if hasOperator {
            // 提取数学表达式并计算结果
            if let mathResult = calculateMathExpression(cleanedInput) {
                if let resultValue = Double(mathResult.result.replacingOccurrences(of: ",", with: "")) {
                    amount = resultValue
                }
            } else {
                // 尝试直接提取数字
                let numberPattern = try? NSRegularExpression(pattern: "[0-9]+(\\.[0-9]+)?")
                guard let matches = numberPattern?.matches(in: cleanedInput, range: NSRange(cleanedInput.startIndex..., in: cleanedInput)),
                      !matches.isEmpty else {
                    return nil
                }
                
                // 提取第一个数字
                if let match = matches.first, let range = Range(match.range, in: cleanedInput) {
                    let amountStr = String(cleanedInput[range])
                    guard let extractedAmount = Double(amountStr) else {
                        return nil
                    }
                    amount = extractedAmount
                } else {
                    return nil
                }
            }
        } else {
            // 直接提取数字
            let numberPattern = try? NSRegularExpression(pattern: "[0-9]+(\\.[0-9]+)?")
            guard let matches = numberPattern?.matches(in: cleanedInput, range: NSRange(cleanedInput.startIndex..., in: cleanedInput)),
                  !matches.isEmpty else {
                return nil
            }
            
            // 提取第一个数字
            if let match = matches.first, let range = Range(match.range, in: cleanedInput) {
                let amountStr = String(cleanedInput[range])
                guard let extractedAmount = Double(amountStr) else {
                    return nil
                }
                amount = extractedAmount
            } else {
                return nil
            }
        }
        
        // 计算兑换成人民币的结果
        let cnyAmount = amount * currency.rate
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        let formattedAmount = formatter.string(from: NSNumber(value: amount)) ?? String(amount)
        let formattedCNY = formatter.string(from: NSNumber(value: cnyAmount)) ?? String(cnyAmount)
        
        // 构建公式和结果
        let formula: String
        if hasOperator {
            formula = "\(currency.symbol)\(formattedAmount) "
        } else {
            formula = "\(currency.symbol)\(formattedAmount)"
        }
        
        let result = "¥\(formattedCNY)"
        
        return (formula, result)
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
    
    func clearResults() {
        self.calculatorResult = []
    }
}
