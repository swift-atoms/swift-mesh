extension Mesh {
    /// Maps points of the unit cube to places on a mesh's surface so that evenly spread points give evenly
    /// spread places: every part of the surface as likely as its share of the whole area.
    ///
    /// It cuts each face into the triangles fanned from its first vertex and adds up their areas once, so
    /// that each place is a search. A place is a ``Location``: a face and a weight for each of its vertices,
    /// with which any value given per vertex, such as a position or a normal, is interpolated there. The
    /// three coordinates may come from any source: a random number generator, a stratified grid or a
    /// low-discrepancy sequence.
    public struct Sampler<Scalar: BinaryFloatingPoint> {
        /// The mesh it maps to.
        public let mesh: Mesh

        /// The whole area of the mesh's surface: the sum of its fanned triangles' areas.
        public let area: Scalar

        /// Each fanned triangle: its face, and the corner of the face it takes after the first.
        @usableFromInline
        let triangles: [(face: Int, corner: Int)]

        /// The area of the triangles up to and including each triangle, in order.
        @usableFromInline
        let running: [Scalar]

        /// A sampler over a mesh's surface; nil when it has no faces or no area, or an area that is not finite.
        @inlinable
        public init?(_ mesh: Mesh) where Vertex == Point<3, Scalar> {
            var triangles: [(face: Int, corner: Int)] = []
            var running: [Scalar] = []
            var total: Scalar = 0
            for (face, polygon) in mesh.faces.enumerated() {
                let corners = polygon.vertices.map { mesh.vertices[Int(bitPattern: $0)].coordinates }
                let origin = corners[0]
                for (corner, (second, third)) in zip(corners.dropFirst(), corners.dropFirst(2)).enumerated() {
                    let (p, q) = (second - origin, third - origin)
                    let (x, y, z) = (p.y * q.z - p.z * q.y, p.z * q.x - p.x * q.z, p.x * q.y - p.y * q.x)
                    total += (x * x + y * y + z * z).squareRoot() / 2
                    triangles.append((face, corner + 1))
                    running.append(total)
                }
            }
            guard total > 0, total.isFinite else { return nil }
            self.mesh = mesh
            self.area = total
            self.triangles = triangles
            self.running = running
        }
    }
}

extension Mesh.Sampler: Sendable where Vertex: Sendable, Scalar: Sendable {}

extension Mesh.Sampler {
    /// The place for a point (u, v, w) of the unit cube, each coordinate held to 0…1.
    ///
    /// u times the area picks the first fanned triangle whose running area reaches it. (v, w) place it on that
    /// triangle, folded back across its diagonal when v + w > 1: weight 1 − v − w on the face's first vertex,
    /// v on the triangle's second corner and w on its third, and 0 on the face's other vertices.
    @inlinable
    public func location(_ u: Scalar, _ v: Scalar, _ w: Scalar) -> Location {
        let lot = held(u) * area
        let candidates = running.dropLast()
        var (from, to) = (candidates.startIndex, candidates.endIndex)
        while from < to {
            let middle = from + (to - from) / 2
            if candidates[middle] < lot { from = middle + 1 } else { to = middle }
        }
        let triangle = triangles[from]
        let (v, w) = (held(v), held(w))
        let (a, b) = v + w > 1 ? (1 - v, 1 - w) : (v, w)
        var weights = [Scalar](repeating: 0, count: mesh.faces[triangle.face].vertices.count)
        weights[0] = 1 - a - b
        weights[triangle.corner] = a
        weights[triangle.corner + 1] = b
        return Location(face: Index(_unchecked: Ordinal(UInt(triangle.face))), weights: weights)
    }

    /// A vector given per vertex, such as `mesh.normals(per: .vertex)`, interpolated at a location: the
    /// face's vertices' vectors weighted by its weights, in the face's order. A normal so found is not of
    /// unit length in general.
    @inlinable
    public func interpolate(_ values: [Vector<3, Scalar>], at location: Location) -> Vector<3, Scalar> {
        var sum = Vector<3, Scalar>(repeating: 0)
        for (index, weight) in zip(mesh.faces[location.face].vertices, location.weights) {
            let value = values[Int(bitPattern: index)]
            sum.x += weight * value.x
            sum.y += weight * value.y
            sum.z += weight * value.z
        }
        return sum
    }

    @inlinable
    internal func held(_ coordinate: Scalar) -> Scalar {
        Swift.min(Swift.max(coordinate, 0), 1)
    }
}

extension Mesh.Sampler where Vertex == Point<3, Scalar> {
    /// The face's vertex positions weighted by the location's weights: the place on the surface.
    @inlinable
    public func position(of location: Location) -> Point<3, Scalar> {
        var sum = Vector<3, Scalar>(repeating: 0)
        for (index, weight) in zip(mesh.faces[location.face].vertices, location.weights) {
            let value = mesh.vertices[Int(bitPattern: index)].coordinates
            sum.x += weight * value.x
            sum.y += weight * value.y
            sum.z += weight * value.z
        }
        return Point(coordinates: sum)
    }
}
