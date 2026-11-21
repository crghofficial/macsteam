import Foundation

struct StepFailure: Error, LocalizedError {
    let step: String
    let detail: String
    var errorDescription: String? { L10n.format("%1$@: %2$@", step, detail) }
}
