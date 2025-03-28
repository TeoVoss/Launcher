import SwiftUI

struct CalculatorView: View {
    let formula: String
    let result: String
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing:0) {
                // 左边显示公式
                VStack {
                    Text(formula)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                
                VStack {
                    Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                    Text("→")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxHeight: .infinity)
                    
                    Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                }
                
                HStack {
                    Text(result)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            }
            
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? 
                          Color.gray.opacity(0.2) :
                          (isHovered ? Color.gray.opacity(0.08) : Color.clear))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover in
            isHovered = hover
        }
    }
}

// 适配CalculatorItem到视图
extension CalculatorItem {
    func createView(isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        CalculatorView(
            formula: formula,
            result: result,
            isSelected: isSelected,
            onSelect: onSelect
        )
    }
}

#Preview {
    VStack(spacing: 10) {
        CalculatorView(
            formula: "1.229-0.765",
            result: "0.464",
            isSelected: false,
            onSelect: {}
        )
        
        CalculatorView(
            formula: "5×6",
            result: "30",
            isSelected: true,
            onSelect: {}
        )
        
        CalculatorView(
            formula: "$100 (美元)",
            result: "¥722.00 (人民币)",
            isSelected: false,
            onSelect: {}
        )
    }
    .padding()
    .frame(width: 500)
} 
