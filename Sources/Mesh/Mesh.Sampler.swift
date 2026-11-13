extension Mesh {
    /// Draws places on a mesh's surface, each face as likely as its share of the whole area.
    ///
    /// It adds up the faces' areas once, so that each draw is a search. A place is a ``Location``: a face
    /// and a weight for each of its vertices, with which any value given per vertex, such as a position or
    /// a normal, is interpolated there.
    public struct Sampler<Scalar: BinaryFloatingPoint> {
        /// The mesh it draws from.
        public let mesh: Mesh

        /// The area of the faces up to and including each face, in face order.
        public let running: [Scalar]

        /// A sampler over a mesh's surface; nil when it has no faces or no area, or an area that is not finite.
        public init?(_ mesh: Mesh) where Vertex == Point<3, Scalar> {
            var running: [Scalar] = []
            running.reserveCapacity(mesh.faces.count)
            var total: Scalar = 0
            for area in mesh.areas() as [Vector<3, Scalar>] {
                total += (area.x * area.x + area.y * area.y + area.z * area.z).squareRoot()
                running.append(total)
            }
            guard total > 0, total.isFinite else { return nil }
            self.mesh = mesh
            self.running = running
        }
    }
}

extension Mesh.Sampler: Sendable where Vertex: Sendable, Scalar: Sendable {}

extension Mesh.Sampler {
    /// The whole area of the mesh's surface.
    public var area: Scalar { running[running.count - 1] }
}

extension Mesh.Sampler where Vertex == Point<3, Scalar> {

    /// A place on the surface from three unit draws of a generator, in this order: one picks the face by
    /// area, and two place it on the face. A triangle is filled evenly, the draws (u, v) folded back across
    /// its diagonal when u + v > 1 and weighted (1 − u − v, u, v). A quad is weighted bilinearly,
    /// ((1 − u)(1 − v), u(1 − v), uv, (1 − u)v), which is even for a parallelogram. A larger face is fanned
    /// from its first vertex into triangles, the one the first draw falls in by its share of the face's
    /// area, and that triangle filled evenly.
    public func location<Generator: Swift.RandomNumberGenerator>(using generator: inout Generator) -> Location {
        let lot = Scalar(generator.unit()) * area
        var (from, to) = (0, running.count - 1)
        while from < to {
            let middle = (from + to) / 2
            if running[middle] < lot { from = middle + 1 } else { to = middle }
        }
        let face = Index<Polygon<Index<Vertex>>>(_unchecked: Ordinal(UInt(from)))
        let (u, v) = (Scalar(generator.unit()), Scalar(generator.unit()))
        let count = mesh.faces[from].vertices.count
        switch count {
        case 3:
            let (a, b) = u + v > 1 ? (1 - u, 1 - v) : (u, v)
            return Location(face: face, weights: [1 - a - b, a, b])

        case 4:
            return Location(face: face, weights: [(1 - u) * (1 - v), u * (1 - v), u * v, (1 - u) * v])

        default:
            let start: Scalar = from == 0 ? 0 : running[from - 1]
            let share = (lot - start) / (running[from] - start)
            let triangle = fan(of: from, at: share)
            let (a, b) = u + v > 1 ? (1 - u, 1 - v) : (u, v)
            var weights = [Scalar](repeating: 0, count: count)
            weights[0] = 1 - a - b
            weights[triangle] = a
            weights[triangle + 1] = b
            return Location(face: face, weights: weights)
        }
    }

    /// The vertex positions of the location's face, weighted by its weights: the place on the surface.
    public func position(of location: Location) -> Point<3, Scalar> {
        Point(coordinates: interpolate(mesh.vertices.map(\.coordinates), at: location))
    }

}

extension Mesh.Sampler {
    /// A vector given per vertex, such as `mesh.normals(per: .vertex)`, interpolated at a location: the
    /// face's vertices' vectors weighted by its weights, in the face's order. A normal so found is not of
    /// unit length in general.
    public func interpolate(_ values: [Vector<3, Scalar>], at location: Location) -> Vector<3, Scalar> {
        var sum = Vector<3, Scalar>(repeating: 0)
        for (index, weight) in zip(mesh.faces[location.face].vertices, location.weights) {
            let value = values[Int(bitPattern: index)]
            sum.x = sum.x + weight * value.x
            sum.y = sum.y + weight * value.y
            sum.z = sum.z + weight * value.z
        }
        return sum
    }
}

extension Mesh.Sampler where Vertex == Point<3, Scalar> {
    /// The second corner of the triangle, fanned from a face's first vertex, that a share of the face's area falls in.
    private func fan(of face: Int, at share: Scalar) -> Int {
        let corners = mesh.faces[face].vertices.map { Int(bitPattern: $0) }
        let vertices = mesh.vertices
        let origin = vertices[corners[0]].coordinates
        let areas = (1..<(corners.count - 1)).map { second -> Scalar in
            let p = vertices[corners[second]].coordinates - origin
            let q = vertices[corners[second + 1]].coordinates - origin
            let (x, y, z) = (p.y * q.z - p.z * q.y, p.z * q.x - p.x * q.z, p.x * q.y - p.y * q.x)
            return (x * x + y * y + z * z).squareRoot()
        }
        let total = areas.reduce(0, +)
        var reached: Scalar = 0
        for (offset, area) in areas.enumerated() {
            reached += area
            if share * total < reached { return offset + 1 }
        }
        return corners.count - 2
    }
}
