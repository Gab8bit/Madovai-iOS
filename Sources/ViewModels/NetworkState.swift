enum NetworkState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case error(String)
}
