import Foundation

protocol ClipLibrary {
    var files: [VideoFile] { get }
    func randomClip(clipLength: Double) -> VideoClip?
}