import Foundation
import Combine

final class LevelEditorViewModel: ObservableObject, Identifiable {
    enum Mode {
        case creating
        case editing(Level)
    }
    
    let id = UUID()
    let mode: Mode
    let sourceLevel: Level?
    
    init(level: Level?) {
        if let level {
            mode = .editing(level)
            sourceLevel = level
        } else {
            mode = .creating
            sourceLevel = nil
        }
    }
    
    var headerTitle: String {
        switch mode {
        case .creating:
            return "New Level"
        case .editing(let level):
            return "Editing \(level.title)"
        }
    }
    
    var headerSubtitle: String {
        switch mode {
        case .creating:
            return "Start from a clean slate."
        case .editing(let level):
            return "Source level ID: \(level.id)"
        }
    }
}
