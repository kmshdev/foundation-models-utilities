import EngineeringCore
import SwiftUI

package enum StudioTypography {
    package static let title = Font.title2.weight(.semibold)
    package static let heading = Font.headline
    package static let label = Font.subheadline.weight(.semibold)
    package static let secondary = Font.callout
    package static let caption = Font.caption
    package static var body: Font {
        #if os(macOS)
        .system(size: 15)
        #else
        .body
        #endif
    }
}
