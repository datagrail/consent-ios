import Foundation

/// Actions for the save_open endpoint
public enum OpenAction: String {
    case open
    case nonOpen = "non_open"
    case showLayer = "show_layer"
    case setHidden = "set_hidden"
}
