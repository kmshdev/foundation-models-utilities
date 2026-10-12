import EngineeringServices
import EngineeringCore
import Foundation

package enum PlannerFailure: Error, LocalizedError {
    case unavailable(String), model(String), onDevice(String), session(String), invalidOwner(String)
    package var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "On-device planning is unavailable: \(reason)"
        case .model(let reason): "The model could not complete this request: \(reason)"
        case .onDevice(let reason): "Apple Intelligence could not complete this request: \(reason)"
        case .session(let reason): "The planning session could not continue: \(reason)"
        case .invalidOwner(let owner): "The model returned an unknown specialty: \(owner)"
        }
    }
}
