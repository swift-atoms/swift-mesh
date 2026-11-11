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
                    sums[position] = sums[position] + area
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
