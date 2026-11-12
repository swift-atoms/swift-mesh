public struct Mesh<Vertex> {
    public let vertices: [Vertex]
    public let faces: [Polygon<Index<Vertex>>]

    public init(vertices: [Vertex], faces: [Polygon<Index<Vertex>>]) throws(Error) {
        let valid = faces.allSatisfy { face in
            face.vertices.allSatisfy { vertices.indices.contains(Int(bitPattern: $0)) }
        }
        guard valid else { throw .indexOutOfBounds }
        self.vertices = vertices
        self.faces = faces
    }
}

extension Mesh {
    public static var empty: Self { Self(validated: [], faces: []) }

    public var reversed: Self { Self(validated: vertices, faces: faces.map(\.reversed)) }

    public var triangulated: Self {
        var triangles: [Polygon<Index<Vertex>>] = []
        triangles.reserveCapacity(faces.count)
        faces.forEach { face in
            let indices = face.vertices
            zip(indices.dropFirst(), indices.dropFirst(2)).forEach { second, third in
                triangles.append(Polygon(indices[0], second, third))
            }
        }
        return Self(validated: vertices, faces: triangles)
    }

    public func polygon(at face: Index<Polygon<Index<Vertex>>>) -> Polygon<Vertex> {
        faces[face].map { vertices[$0] }
    }

    public func map<Result, Failure: Swift::Error>(
        _ transform: (Vertex) throws(Failure) -> Result
    ) throws(Failure) -> Mesh<Result> {
        var result: [Result] = []
        result.reserveCapacity(vertices.count)
        for vertex in vertices { result.append(try transform(vertex)) }
        return Mesh<Result>(validated: result, faces: faces.map { face in face.map { $0.retag(Result.self) } })
    }

    public func appending(_ other: Self) -> Self {
        let offset = vertices.count
        return Self(
            validated: vertices + other.vertices,
            faces: faces + other.faces.map { face in face.map { Self.index(Int(bitPattern: $0) + offset) } }
        )
    }
}

extension Mesh where Vertex: Hashable {
    public var welded: Self {
        var first: [Vertex: Int] = [:]
        var kept: [Vertex] = []
        var renamed: [Index<Vertex>] = []
        renamed.reserveCapacity(vertices.count)
        vertices.forEach { vertex in
            if let index = first[vertex] {
                renamed.append(Self.index(index))
            } else {
                first[vertex] = kept.count
                renamed.append(Self.index(kept.count))
                kept.append(vertex)
            }
        }
        return Self(validated: kept, faces: faces.map { face in face.map { renamed[$0] } })
    }
}

extension Mesh: Equatable where Vertex: Equatable {}
extension Mesh: Hashable where Vertex: Hashable {}
extension Mesh: Sendable where Vertex: Sendable {}

extension Mesh {

    public init<Failure: Swift::Error>(
        columns: Cardinal,
        rows: Cardinal,
        seams: (columns: Seam, rows: Seam) = (.open, .open),
        vertex: (_ column: Ordinal, _ row: Ordinal) throws(Failure) -> Vertex
    ) throws(Failure) {
        precondition(columns >= .one && rows >= .one, "A mesh grid needs at least one column and one row")
        let columnCells = Int(bitPattern: columns)
        let rowCells = Int(bitPattern: rows)
        let columnLines = seams.columns == .closed ? columnCells : columnCells + 1
        let rowLines = seams.rows == .closed ? rowCells : rowCells + 1
        var vertices: [Vertex] = []
        vertices.reserveCapacity(columnLines * rowLines)
        for row in 0..<rowLines {
            for column in 0..<columnLines {
                vertices.append(try vertex(Ordinal(UInt(column)), Ordinal(UInt(row))))
            }
        }
        var faces: [Polygon<Index<Vertex>>] = []
        faces.reserveCapacity(columnCells * rowCells)
        (0..<rowCells).forEach { row in
            let next = (row + 1) % rowLines
            (0..<columnCells).forEach { column in
                let after = (column + 1) % columnLines
                faces.append(
                    Polygon(
                        Self.index(row * columnLines + column),
                        Self.index(row * columnLines + after),
                        Self.index(next * columnLines + after),
                        Self.index(next * columnLines + column)
                    )
                )
            }
        }
        self.init(validated: vertices, faces: faces)
    }
}

extension Mesh {

    public func areas<Scalar: BinaryFloatingPoint>() -> [Vector<3, Scalar>] where Vertex == Point<3, Scalar> {
        faces.map { face in
            let origin = vertices[face.vertices[0]].coordinates
            let corners = face.vertices.map { vertices[$0].coordinates - origin }
            var sum = Vector<3, Scalar>(repeating: 0)
            zip(corners, corners.dropFirst() + corners.prefix(1)).forEach { current, next in
                sum.x += (current.y - next.y) * (current.z + next.z)
                sum.y += (current.z - next.z) * (current.x + next.x)
                sum.z += (current.x - next.x) * (current.y + next.y)
            }
            return sum.scaled(by: 1 / 2)
        }
    }

    public func normals<Scalar: BinaryFloatingPoint>(
        per element: Element
    ) -> [Vector<3, Scalar>] where Vertex == Point<3, Scalar> {
        let areas = areas()
        switch element {
        case .face:
            return areas.map(Self.unit)

        case .vertex:
            var sums = [Vector<3, Scalar>](repeating: Vector(repeating: 0), count: vertices.count)
            zip(faces, areas).forEach { face, area in
                face.vertices.forEach { index in
                    let position = Int(bitPattern: index)
                    sums[position] += area
                }
            }
            return sums.map(Self.unit)
        }
    }

    public static func torus<Scalar: BinaryFloatingPoint & Trigonometry.Circular>(
        major: Scalar,
        minor: Scalar,
        segments: Cardinal,
        sides: Cardinal
    ) -> Self where Vertex == Point<3, Scalar> {
        let turn = 2 * Scalar.pi
        let segmentCount = Scalar(Int(bitPattern: segments))
        let sideCount = Scalar(Int(bitPattern: sides))
        return Self(columns: segments, rows: sides, seams: (.closed, .closed)) { segment, side in
            let around = turn * Scalar(Int(bitPattern: segment)) / segmentCount
            let tube = turn * Scalar(Int(bitPattern: side)) / sideCount
            let distance = major + minor * Scalar.cos(tube)
            return Point(
                x: distance * Scalar.cos(around),
                y: distance * Scalar.sin(around),
                z: minor * Scalar.sin(tube)
            )
        }
    }

    public static func sphere<Scalar: BinaryFloatingPoint & Trigonometry.Circular>(
        radius: Scalar,
        meridians: Cardinal,
        parallels: Cardinal
    ) -> Self where Vertex == Point<3, Scalar> {
        precondition(meridians >= 3 && parallels >= 2, "A sphere needs at least three meridians and two parallels")
        let around = Int(bitPattern: meridians)
        let bands = Int(bitPattern: parallels)
        var vertices: [Vertex] = [Point(x: 0, y: 0, z: -radius)]
        vertices.reserveCapacity(around * bands + 2)
        (1..<bands).forEach { parallel in
            let latitude = Scalar.pi * Scalar(parallel) / Scalar(bands) - Scalar.pi / 2
            let distance = radius * Scalar.cos(latitude)
            let height = radius * Scalar.sin(latitude)
            (0..<around).forEach { meridian in
                let longitude = 2 * Scalar.pi * Scalar(meridian) / Scalar(around)
                vertices.append(
                    Point(x: distance * Scalar.cos(longitude), y: distance * Scalar.sin(longitude), z: height)
                )
            }
        }
        vertices.append(Point(x: 0, y: 0, z: radius))
        let south = Self.index(0)
        let north = Self.index(vertices.endIndex - 1)
        func ring(_ parallel: Int, _ meridian: Int) -> Index<Vertex> {
            Self.index(1 + (parallel - 1) * around + meridian % around)
        }
        var faces: [Polygon<Index<Vertex>>] = []
        faces.reserveCapacity(around * bands)
        (0..<around).forEach { meridian in
            faces.append(Polygon(south, ring(1, meridian + 1), ring(1, meridian)))
        }
        (1..<(bands - 1)).forEach { parallel in
            (0..<around).forEach { meridian in
                faces.append(
                    Polygon(
                        ring(parallel, meridian),
                        ring(parallel, meridian + 1),
                        ring(parallel + 1, meridian + 1),
                        ring(parallel + 1, meridian)
                    )
                )
            }
        }
        (0..<around).forEach { meridian in
            faces.append(Polygon(ring(bands - 1, meridian), ring(bands - 1, meridian + 1), north))
        }
        return Self(validated: vertices, faces: faces)
    }
}

extension Mesh {
    /// The box with its edges along the axes between two opposite corners: eight vertices and six quads.
    ///
    /// The vertices are the corners in the order of a count in binary, x changing first:
    /// (x₀, y₀, z₀), (x₁, y₀, z₀), (x₀, y₁, z₀), (x₁, y₁, z₀), and the same four at z₁, where the first of
    /// each pair is `lower`'s coordinate and the second `upper`'s. The faces are listed as the sides toward
    /// lower x, upper x, lower y, upper y, lower z and upper z, each counterclockwise seen from outside
    /// when `lower` is below `upper` along every axis. It is closed and has twelve distinct edges.
    public static func box<Scalar: BinaryFloatingPoint>(
        lower: Point<3, Scalar>,
        upper: Point<3, Scalar>
    ) -> Self where Vertex == Point<3, Scalar> {
        let vertices: [Vertex] = (0..<8).map { corner in
            Point(
                x: corner & 1 == 0 ? lower.x : upper.x,
                y: corner & 2 == 0 ? lower.y : upper.y,
                z: corner & 4 == 0 ? lower.z : upper.z
            )
        }
        let sides = [[0, 4, 6, 2], [1, 3, 7, 5], [0, 1, 5, 4], [2, 6, 7, 3], [0, 2, 3, 1], [4, 5, 7, 6]]
        let faces = sides.map { side in
            Polygon(Self.index(side[0]), Self.index(side[1]), Self.index(side[2]), Self.index(side[3]))
        }
        return Self(validated: vertices, faces: faces)
    }
}

extension Mesh {

    /// Martin Newell's teapot of 1975 as he drew it: thirty-two bicubic Bézier patches, each cut into
    /// `divisions` by `divisions` quadrilaterals, with a bottom added.
    ///
    /// It stands on the plane z = 0 around the z axis and is 3.15 high. The body is 2 at its widest, the
    /// spout reaches x = 3.525 and the handle x = −3.0, and y → −y maps the teapot onto itself.
    ///
    /// The patches follow one another in this order: four of the rim, eight of the body, four of the handle,
    /// four of the spout, eight of the lid and four of the bottom. Each brings its own
    /// (`divisions` + 1)² vertices, so vertices on an edge two patches share are listed once for each.
    /// Every face is counterclockwise seen from outside the teapot. A quarter of a circle is Newell's own: its
    /// control points stand at 0.56 of the radius, not at the 0.5523 that fits a circle best.
    public static func teapot<Scalar: BinaryFloatingPoint>(divisions: Cardinal) -> Self where Vertex == Point<3, Scalar> {
        typealias Profile = [(radius: Scalar, height: Scalar)]
        typealias Rib = (inner: (x: Scalar, z: Scalar), outer: (x: Scalar, z: Scalar), half: Scalar)

        let roundness: Scalar = 0.56

        let rim: Profile = [(1.4, 2.4), (1.3375, 2.53125), (1.4375, 2.53125), (1.5, 2.4)]
        let shoulder: Profile = [(1.5, 2.4), (1.75, 1.875), (2, 1.35), (2, 0.9)]
        let belly: Profile = [(2, 0.9), (2, 0.45), (1.5, 0.225), (1.5, 0.15)]
        let knob: Profile = [(0, 3.15), (0.8, 3.15), (0, 2.85), (0.2, 2.7)]
        let cover: Profile = [(0.2, 2.7), (0.4, 2.55), (1.3, 2.55), (1.3, 2.4)]
        let bottom: Profile = [(1.5, 0.15), (1.5, 0.075), (1.425, 0), (0, 0)]

        let grip: [Rib] = [
            ((-1.6, 2.025), (-1.5, 2.25), 0.3),
            ((-2.3, 2.025), (-2.5, 2.25), 0.3),
            ((-2.7, 2.025), (-3.0, 2.25), 0.3),
            ((-2.7, 1.8), (-3.0, 1.8), 0.3),
        ]
        let hold: [Rib] = [
            ((-2.7, 1.8), (-3.0, 1.8), 0.3),
            ((-2.7, 1.575), (-3.0, 1.35), 0.3),
            ((-2.5, 1.125), (-2.65, 0.9375), 0.3),
            ((-2.0, 0.9), (-1.9, 0.6), 0.3),
        ]
        let neck: [Rib] = [
            ((1.7, 1.425), (1.7, 0.6), 0.66),
            ((2.6, 1.425), (3.1, 0.825), 0.66),
            ((2.3, 2.1), (2.4, 2.025), 0.25),
            ((2.7, 2.4), (3.3, 2.4), 0.25),
        ]
        let lip: [Rib] = [
            ((2.7, 2.4), (3.3, 2.4), 0.25),
            ((2.8, 2.475), (3.525, 2.49375), 0.25),
            ((2.9, 2.475), (3.45, 2.5125), 0.15),
            ((2.8, 2.4), (3.2, 2.4), 0.15),
        ]

        /// A profile turned a quarter of the way round the z axis, `quarter` quarter turns on.
        func turned(_ profile: Profile, quarter: Int) -> [[Vertex]] {
            profile.map { radius, height in
                let arc: [(x: Scalar, y: Scalar)] = [
                    (radius, 0), (radius, -roundness * radius), (roundness * radius, -radius), (0, -radius),
                ]
                return arc.map { point in
                    switch quarter % 4 {
                    case 1: return Point(x: point.y, y: -point.x, z: height)
                    case 2: return Point(x: -point.x, y: -point.y, z: height)
                    case 3: return Point(x: -point.y, y: point.x, z: height)
                    default: return Point(x: point.x, y: point.y, z: height)
                    }
                }
            }
        }

        /// Half of a tube along ribs in the plane y = 0: the side at negative y, or its mirror image.
        func swept(_ ribs: [Rib], mirrored: Bool) -> [[Vertex]] {
            ribs.map { inner, outer, half in
                let row: [Vertex] = [
                    Point(x: inner.x, y: 0, z: inner.z), Point(x: inner.x, y: -half, z: inner.z),
                    Point(x: outer.x, y: -half, z: outer.z), Point(x: outer.x, y: 0, z: outer.z),
                ]
                return mirrored ? row.reversed().map { Point(x: $0.x, y: -$0.y, z: $0.z) } : row
            }
        }

        func mix(_ from: Vertex, _ to: Vertex, _ parameter: Scalar) -> Vertex {
            Point(
                x: from.x * (1 - parameter) + to.x * parameter,
                y: from.y * (1 - parameter) + to.y * parameter,
                z: from.z * (1 - parameter) + to.z * parameter
            )
        }

        /// The point of a cubic Bézier curve through four control points at a parameter.
        func curve(_ points: [Vertex], _ parameter: Scalar) -> Vertex {
            let first = mix(mix(points[0], points[1], parameter), mix(points[1], points[2], parameter), parameter)
            let second = mix(mix(points[1], points[2], parameter), mix(points[2], points[3], parameter), parameter)
            return mix(first, second, parameter)
        }

        let quarters = [0, 1, 2, 3]
        var nets: [[[Vertex]]] = []
        for profile in [rim, shoulder, belly] {
            nets += quarters.map { turned(profile, quarter: $0) }
        }
        for ribs in [grip, hold, neck, lip] {
            nets.append(swept(ribs, mirrored: false))
            nets.append(swept(ribs, mirrored: true))
        }
        for profile in [knob, cover, bottom] {
            nets += quarters.map { turned(profile, quarter: $0) }
        }

        let cells = Scalar(Int(bitPattern: divisions))
        var teapot = Self.empty
        for net in nets {
            let patch = Self(columns: divisions, rows: divisions) { column, row in
                let along = Scalar(Int(bitPattern: column)) / cells
                let across = Scalar(Int(bitPattern: row)) / cells
                return curve(net.map { curve($0, along) }, across)
            }
            teapot = teapot.appending(patch)
        }
        return teapot
    }
}

extension Mesh {
    internal init(validated vertices: [Vertex], faces: [Polygon<Index<Vertex>>]) {
        self.vertices = vertices
        self.faces = faces
    }

    internal static func index(_ position: Int) -> Index<Vertex> {
        Index(_unchecked: Ordinal(UInt(position)))
    }

    private static func unit<Scalar: BinaryFloatingPoint>(_ vector: Vector<3, Scalar>) -> Vector<3, Scalar> {
        let length = vector.dot(vector).squareRoot()
        guard length > 0, length.isFinite else { return Vector(repeating: 0) }
        return vector.map { $0 / length }
    }
}

#if !hasFeature(Embedded)
    extension Mesh {
        private enum CodingKeys: String, CodingKey {
            case vertices, faces
        }
    }

    extension Mesh: Encodable where Vertex: Encodable {
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(vertices, forKey: .vertices)
            try container.encode(faces.map { face in face.vertices.map { Int(bitPattern: $0) } }, forKey: .faces)
        }
    }

    extension Mesh: Decodable where Vertex: Decodable {
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let vertices = try container.decode([Vertex].self, forKey: .vertices)
            let faces = try container.decode([Polygon<UInt>].self, forKey: .faces)
            do throws(Error) {
                try self.init(
                    vertices: vertices,
                    faces: faces.map { face in face.map { Index(_unchecked: Ordinal($0)) } }
                )
            } catch {
                throw DecodingError.dataCorruptedError(
                    forKey: .faces,
                    in: container,
                    debugDescription: "A mesh face names a vertex index outside the vertex list"
                )
            }
        }
    }
#endif
