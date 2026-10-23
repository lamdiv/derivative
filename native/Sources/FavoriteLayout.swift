import Foundation

// Keep the last row useful: two tiles share it, and four tiles form a 2×2 grid.
func favoriteRowSizes(_ count: Int) -> [Int] {
    var remaining = max(0, min(12, count)), rows: [Int] = []
    while remaining > 0 {
        let size = remaining == 4 ? 2 : min(3, remaining)
        rows.append(size); remaining -= size
    }
    return rows
}
