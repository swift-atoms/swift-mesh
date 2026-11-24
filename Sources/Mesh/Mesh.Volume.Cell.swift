extension Mesh.Volume {
    /// A hexahedron of a volume: eight corners, the four of its lower face counterclockwise seen from above, then
    /// the four above them in the same order. It is the image of the cube [−1, 1]³ under the trilinear map through
    /// its corners: corner 0 is the image of (−1, −1, −1), 1 of (1, −1, −1), 2 of (1, 1, −1), 3 of (−1, 1, −1), and
    /// 4 to 7 the same at z = 1.
    @frozen
    public struct Cell {
        /// The eight corners, as indices into the volume's vertices.
        public let corners: [Index<Vertex>]

        /// A cell from its eight corners; it fails with `.notHexahedron` for any other count.
        @inlinable
        public init(corners: [Index<Vertex>]) throws(Mesh.Error) {
            guard corners.count == 8 else { throw .notHexahedron }
            self.corners = corners
        }

        @inlinable
        internal init(validated corners: [Index<Vertex>]) { self.corners = corners }
    }
}

extension Mesh.Volume.Cell {
    /// The six faces, each counterclockwise seen from outside the cell when the cell is turned the right way: below
    /// (0, 3, 2, 1), above (4, 5, 6, 7), then the four sides (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6) and
    /// (3, 0, 4, 7).
    @inlinable
    public var faces: [Polygon<Index<Vertex>>] {
        let c = corners
        return [
            Polygon(c[0], c[3], c[2], c[1]),
            Polygon(c[4], c[5], c[6], c[7]),
            Polygon(c[0], c[1], c[5], c[4]),
            Polygon(c[1], c[2], c[6], c[5]),
            Polygon(c[2], c[3], c[7], c[6]),
            Polygon(c[3], c[0], c[4], c[7]),
        ]
    }

    /// The same cell turned inside out: its upper and lower faces swapped.
    @inlinable
    public var reversed: Self {
        Self(validated: Array(corners[4..<8]) + Array(corners[0..<4]))
    }
}

extension Mesh.Volume.Cell: Equatable {}
extension Mesh.Volume.Cell: Hashable {}
extension Mesh.Volume.Cell: Sendable {}
