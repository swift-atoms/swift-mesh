extension Mesh {
    @frozen
    public enum Error: Swift::Error, Equatable, Sendable {
        case indexOutOfBounds
        /// An outline to mesh is empty, or a curve of it does not end exactly where the next one starts.
        case openOutline
        /// An outline to mesh is not seen whole from its centre: a ray from the centre does not cross it exactly once.
        case outlineNotStarShaped
        /// A face of a mesh fitted to an outline, or a cell of a volume, turned over or has no area or volume; more
        /// cells may fit it.
        case folded
        /// A face to build cells on is not a quadrilateral.
        case notQuadrilateral
        /// A cell of a volume does not have eight corners.
        case notHexahedron
    }
}
