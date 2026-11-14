@frozen
public struct Mesh<Vertex> {
    public let vertices: [Vertex]
    public let faces: [Polygon<Index<Vertex>>]

    @inlinable
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

    @inlinable
    public var reversed: Self { Self(validated: vertices, faces: faces.map(\.reversed)) }

    @inlinable
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

    @inlinable
    public func polygon(at face: Index<Polygon<Index<Vertex>>>) -> Polygon<Vertex> {
        faces[face].map { vertices[$0] }
    }

    @inlinable
    public func map<Result, Failure: Swift::Error>(
        _ transform: (Vertex) throws(Failure) -> Result
    ) throws(Failure) -> Mesh<Result> {
        var result: [Result] = []
        result.reserveCapacity(vertices.count)
        for vertex in vertices { result.append(try transform(vertex)) }
        return Mesh<Result>(validated: result, faces: faces.map { face in face.map { $0.retag(Result.self) } })
    }

    @inlinable
    public func appending(_ other: Self) -> Self {
        let offset = vertices.count
        return Self(
            validated: vertices + other.vertices,
            faces: faces + other.faces.map { face in face.map { Self.index(Int(bitPattern: $0) + offset) } }
        )
    }
}

extension Mesh {

    /// The mesh whose faces are the polygons in order, each with vertices of its own: the vertices of the
    /// first polygon, then of the second, and so on, so `polygon(at:)` of face i is polygon i. A mesh of
    /// quads is this with four vertices to a polygon. Vertices that polygons share are listed once for each;
    /// `welded` joins them.
    @inlinable
    public init(_ polygons: [Polygon<Vertex>]) {
        var vertices: [Vertex] = []
        var faces: [Polygon<Index<Vertex>>] = []
        faces.reserveCapacity(polygons.count)
        polygons.forEach { polygon in
            var next = vertices.count
            faces.append(
                polygon.map { _ in
                    defer { next += 1 }
                    return Self.index(next)
                }
            )
            vertices.append(contentsOf: polygon.vertices)
        }
        self.init(validated: vertices, faces: faces)
    }

    /// The number of triangles `triangulated` gives, without building them: n − 2 for each face of n
    /// vertices.
    @inlinable
    public var triangles: Cardinal {
        Cardinal(UInt(faces.reduce(0) { $0 + $1.vertices.count - 2 }))
    }
}

extension Mesh where Vertex: Hashable {
    @inlinable
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

    @inlinable
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

    @inlinable
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

    /// The unit normal of each face, or of each vertex. Per `.face` it is the face's vector area,
    /// `areas()`, at unit length. Per `.vertex` it sums, over every corner of a face at the vertex, the
    /// cross product of the corner's two edges divided by the product of their squared lengths (Max's
    /// weights, 1999), and takes the unit vector. When the vertex and the neighbours its edges reach lie on
    /// one sphere, as on `sphere` and at the corners of a cube, that sum points along the sphere's own
    /// normal exactly: inverting about the vertex carries the sphere onto a plane, and each corner's term is
    /// the cross product of two inverted neighbours, so the terms add up to the area vector of a polygon in
    /// that plane. Weighting by face area or by the angle at the corner leans where small and large faces
    /// meet, as at a pole. A corner with an edge of zero length, or a term that is not finite, adds nothing.
    @inlinable
    public func normals<Scalar: BinaryFloatingPoint>(
        per element: Element
    ) -> [Vector<3, Scalar>] where Vertex == Point<3, Scalar> {
        switch element {
        case .face:
            return areas().map(Self.unit)

        case .vertex:
            var sums = [Vector<3, Scalar>](repeating: Vector(repeating: 0), count: vertices.count)
            faces.forEach { face in
                let indices = face.vertices
                let count = indices.count
                indices.indices.forEach { corner in
                    let here = vertices[indices[corner]].coordinates
                    let next = vertices[indices[(corner + 1) % count]].coordinates - here
                    let previous = vertices[indices[(corner + count - 1) % count]].coordinates - here
                    let weight = next.dot(next) * previous.dot(previous)
                    guard weight > 0, weight.isFinite else { return }
                    let term = Vector<3, Scalar>(
                        x: (next.y * previous.z - next.z * previous.y) / weight,
                        y: (next.z * previous.x - next.x * previous.z) / weight,
                        z: (next.x * previous.y - next.y * previous.x) / weight
                    )
                    guard term.x.isFinite, term.y.isFinite, term.z.isFinite else { return }
                    sums[Int(bitPattern: indices[corner])] += term
                }
            }
            return sums.map(Self.unit)
        }
    }

    /// The normals of one element summed from those of another: per `.face` from `.vertex`, each face's
    /// normal is the unit vector of the sum of its vertices' normals, `normals(per: .vertex)`, in face order.
    /// That is the face's shade when the surface is drawn smooth but its faces are drawn flat. It smooths only
    /// over vertices the faces share, so weld a mesh first; a face whose vertices are its own keeps its own
    /// normal. Per `.vertex` from `.face` is `normals(per: .vertex)`, and from an element to itself is
    /// `normals(per:)` of it. A zero or non-finite sum gives the zero vector.
    @inlinable
    public func normals<Scalar: BinaryFloatingPoint>(
        per element: Element,
        from source: Element
    ) -> [Vector<3, Scalar>] where Vertex == Point<3, Scalar> {
        guard element == .face, source == .vertex else { return normals(per: element) }
        let smooth: [Vector<3, Scalar>] = normals(per: .vertex)
        return faces.map { face in
            var sum = Vector<3, Scalar>(repeating: 0)
            face.vertices.forEach { index in sum += smooth[Int(bitPattern: index)] }
            return Self.unit(sum)
        }
    }

    @inlinable
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

    @inlinable
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
    @inlinable
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
    /// A four-sided face cut into `columns` × `rows` cells, with an inset quad for each cell `including`
    /// chooses, or with one inset strip for each row that has a chosen cell.
    ///
    /// The face's corners are taken in order: columns run from the first corner toward the second, and rows
    /// from the first toward the fourth, so cell (0, 0) touches the first corner. The point of the face at
    /// (u, v), each from 0 to 1, is the bilinear mix of the corners, which for a flat parallelogram, such as
    /// a side of `box(lower:upper:)`, is the corner plus u times the first edge plus v times the last. The
    /// quad of cell (c, r) has the corners at (c + w, r + h), (c + 1 − w, r + h), (c + 1 − w, r + 1 − h) and
    /// (c + w, r + 1 − h), in cells, where (w, h) is `inset`: the share of a cell's width cut from each side
    /// along the row and the share of its height cut from top and bottom. Per `.row`, a row's strip runs from
    /// the left edge of its first chosen cell's quad to the right edge of its last chosen cell's quad.
    ///
    /// Each quad has four vertices of its own and turns the same way as the face, so it faces the same side.
    /// Quads are listed row by row from row 0, and along a row from column 0. `including` is asked once for
    /// each cell, in that order. Nothing is checked: an inset outside 0 to ½ gives quads that leave their
    /// cells or turn inside out.
    @inlinable
    public static func cells<Scalar: BinaryFloatingPoint, Failure: Swift::Error>(
        on face: Ngon<4, Point<3, Scalar>>,
        columns: Cardinal,
        rows: Cardinal,
        inset: (width: Scalar, height: Scalar),
        per span: Span = .cell,
        including: (_ column: Ordinal, _ row: Ordinal) throws(Failure) -> Bool
    ) throws(Failure) -> Self where Vertex == Point<3, Scalar> {
        let corners = face.vertices.map(\.coordinates)
        let width = Scalar(Int(bitPattern: columns))
        let height = Scalar(Int(bitPattern: rows))
        func point(_ u: Scalar, _ v: Scalar) -> Vertex {
            let (s, t) = (u / width, v / height)
            let bottom = corners[0] + (corners[1] - corners[0]).scaled(by: s)
            let top = corners[3] + (corners[2] - corners[3]).scaled(by: s)
            return Point(coordinates: bottom + (top - bottom).scaled(by: t))
        }
        var vertices: [Vertex] = []
        var faces: [Polygon<Index<Vertex>>] = []
        func quad(from left: Scalar, to right: Scalar, row: Scalar) {
            let (lower, upper) = (row + inset.height, row + 1 - inset.height)
            let first = vertices.count
            vertices += [point(left, lower), point(right, lower), point(right, upper), point(left, upper)]
            faces.append(Polygon(Self.index(first), Self.index(first + 1), Self.index(first + 2), Self.index(first + 3)))
        }
        let lines = (0..<Int(bitPattern: rows)).map { row in
            (0..<Int(bitPattern: columns)).map { column in (column: column, row: row) }
        }
        for line in lines {
            var chosen: [Int] = []
            for cell in line where try including(Ordinal(UInt(cell.column)), Ordinal(UInt(cell.row))) {
                chosen.append(cell.column)
            }
            guard let first = chosen.first, let last = chosen.last, let row = line.first?.row else { continue }
            switch span {
            case .cell:
                chosen.forEach { column in
                    quad(from: Scalar(column) + inset.width, to: Scalar(column + 1) - inset.width, row: Scalar(row))
                }

            case .row:
                quad(from: Scalar(first) + inset.width, to: Scalar(last + 1) - inset.width, row: Scalar(row))
            }
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
    @inlinable
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
    @inlinable
    internal init(validated vertices: [Vertex], faces: [Polygon<Index<Vertex>>]) {
        self.vertices = vertices
        self.faces = faces
    }

    @inlinable
    internal static func index(_ position: Int) -> Index<Vertex> {
        Index(_unchecked: Ordinal(UInt(position)))
    }

    @inlinable
    internal static func unit<Scalar: BinaryFloatingPoint>(_ vector: Vector<3, Scalar>) -> Vector<3, Scalar> {
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
