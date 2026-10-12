import EngineeringWorkflows
import StudioServices
import EngineeringServices
import EngineeringCore
import Foundation
import Observation

@MainActor @Observable
package final class OutcomeDraft {
    package var text: String {
        didSet { if text != oldValue { didChange?() } }
    }
    @ObservationIgnored package var didChange: (@MainActor () -> Void)?
    package init(text: String = "", didChange: (@MainActor () -> Void)? = nil) {
        self.text = text
        self.didChange = didChange
    }
}
