extension Mesh {
    @frozen
    public enum Element: Hashable, Sendable, CaseIterable {
        case face
        case vertex
    }
}
