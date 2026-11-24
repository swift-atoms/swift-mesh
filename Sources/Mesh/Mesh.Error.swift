extension Mesh {
    @frozen
    public enum Error: Swift::Error, Equatable, Sendable {
        case indexOutOfBounds
        /// An outline to mesh is empty, or a curve of it does not end exactly where the next one starts.
        case openOutline
        /// An outline to mesh is not seen whole from its centre: a ray from the centre does not cross it exactly once.
        case outlineNotStarShaped
        /// A face of a mesh fitted to an outline turned over or has no area; more cells may fit it.
        case folded
    }
}
