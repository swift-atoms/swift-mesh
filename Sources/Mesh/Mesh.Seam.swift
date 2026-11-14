extension Mesh {
    @frozen
    public enum Seam: Hashable, Sendable, CaseIterable {
        case open
        case closed
    }
}
