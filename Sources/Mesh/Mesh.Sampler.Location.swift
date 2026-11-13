extension Mesh.Sampler {
    /// A place on a mesh's surface: a face, and a weight for each of its vertices in the face's order. The
    /// weights are not negative and add up to one, up to rounding.
    public struct Location {
        /// The face the place lies on.
        public let face: Index<Polygon<Index<Vertex>>>

        /// The weight of each of the face's vertices.
        public let weights: [Scalar]

        /// A place from a face and its vertices' weights.
        public init(face: Index<Polygon<Index<Vertex>>>, weights: [Scalar]) {
            self.face = face
            self.weights = weights
        }
    }
}

extension Mesh.Sampler.Location: Equatable {}
extension Mesh.Sampler.Location: Hashable {}
extension Mesh.Sampler.Location: Sendable where Scalar: Sendable {}
