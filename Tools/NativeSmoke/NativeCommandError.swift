enum NativeCommandError: Error, CustomStringConvertible {
    case timedOut(String, Double)
    case failed(String, Int32, String)
    case invalidOutput(String)

    var description: String {
        switch self {
        case let .timedOut(label, seconds): "\(label) exceeded its \(seconds)-second deadline; see retained command logs."
        case let .failed(label, status, detail): "\(label) exited with status \(status). \(detail)"
        case let .invalidOutput(label): "\(label) returned invalid or oversized output."
        }
    }
}
