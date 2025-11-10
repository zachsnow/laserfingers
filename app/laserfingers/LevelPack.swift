import Foundation

struct LevelPack: Identifiable, Hashable {
    let directoryName: String
    let name: String
    let levels: [Level]
    
    var id: String { directoryName }
}
