import Foundation

@MainActor
final class BarcodeEjectController: ObservableObject {
    @Published var isPresenting = false

    func presentEject() {
        isPresenting = true
    }

    func dismiss() {
        isPresenting = false
    }
}
