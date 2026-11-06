import SwiftData
import SwiftUI

struct PromotionNotificationDestination: View {
    @Query private var promotions: [Promotion]

    init(promotionID: UUID) {
        _promotions = Query(filter: #Predicate<Promotion> { $0.id == promotionID })
    }

    var body: some View {
        if let promotion = promotions.first {
            PromotionDetailView(promotion: promotion)
        } else {
            ContentUnavailableView("无法打开活动", systemImage: "gift",
                description: Text("活动可能已删除或被恢复的数据替换。请返回查看当前促销。"))
        }
    }
}
