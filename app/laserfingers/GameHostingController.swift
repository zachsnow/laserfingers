import SwiftUI
import UIKit

final class GameHostingController<Content: View>: UIHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.isMultipleTouchEnabled = true
    }
}
