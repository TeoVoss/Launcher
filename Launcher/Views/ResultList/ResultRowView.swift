import SwiftUI

struct ResultRowView: View {
    let result: SearchResult
    let isSelected: Bool
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            if result.type == .calculator {
                Image(systemName: result.type.systemImage)
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .frame(width: 32, height: 32)
            } else {
                Image(nsImage: result.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.system(size: 14))
                
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Text(result.type.categoryTitle)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                )
                .foregroundColor(Color.gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? 
                      Color.blue.opacity(0.15) : 
                      (isHovered ? Color.gray.opacity(0.08) : Color.clear))
        )
        .overlay(
            isSelected ?
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                : nil
        )
        .onHover { hover in
            isHovered = hover
        }
    }
} 