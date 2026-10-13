import SwiftUI

package struct SectionEyebrow: View {
    package let text: String
    package init(text: String) { self.text = text }
    package var body: some View { Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
}
