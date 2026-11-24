extension Mesh {
    /// A body as data: a list of vertices and a list of hexahedral cells that name them by index, the solid
    /// counterpart of a mesh of faces.
    @frozen
    public struct Volume {
        public let vertices: [Vertex]
        public let cells: [Cell]

        /// A volume from its vertices and cells; it fails with `.indexOutOfBounds` when a cell names an index outside
        /// `vertices`.
        @inlinable
        public init(vertices: [Vertex], cells: [Cell]) throws(Mesh.Error) {
            let valid = cells.allSatisfy { cell in
                cell.corners.allSatisfy { vertices.indices.contains(Int(bitPattern: $0)) }
            }
            guard valid else { throw .indexOutOfBounds }
            self.vertices = vertices
            self.cells = cells
        }

        @inlinable
        internal init(validated vertices: [Vertex], cells: [Cell]) {
            self.vertices = vertices
            self.cells = cells
        }
    }
}

extension Mesh.Volume {
    /// Every cell turned inside out.
    @inlinable
    public var reversed: Self { Self(validated: vertices, cells: cells.map(\.reversed)) }

    /// The faces only one cell uses, compared without direction or starting corner, each as its cell gives it, in
    /// cell order and then in the order of `Cell.faces`, over the same vertices. When every cell is turned the right
    /// way, they face outward, and they close: every edge of them is used once in each direction.
    @inlinable
    public var boundary: Mesh<Vertex> {
        func key(_ face: Polygon<Index<Vertex>>) -> [Int] {
            face.vertices.map { Int(bitPattern: $0) }.sorted()
        }
        var uses: [[Int]: Int] = [:]
        cells.forEach { cell in
            cell.faces.forEach { uses[key($0), default: 0] += 1 }
        }
        return Mesh(
            validated: vertices,
            faces: cells.flatMap { cell in cell.faces.filter { uses[key($0)] == 1 } }
        )
    }

    @inlinable
    internal static func index(_ position: Int) -> Index<Vertex> {
        Index(_unchecked: Ordinal(UInt(position)))
    }
}

extension Mesh.Volume where Vertex: Hashable {
    /// Vertices that are equal merged into the first of them, in the order of first occurrence, with the cells'
    /// corners renamed.
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
        return Self(
            validated: kept,
            cells: cells.map { cell in Cell(validated: cell.corners.map { renamed[Int(bitPattern: $0)] }) }
        )
    }
}

extension Mesh.Volume: Equatable where Vertex: Equatable {}
extension Mesh.Volume: Hashable where Vertex: Hashable {}
extension Mesh.Volume: Sendable where Vertex: Sendable {}

extension Mesh.Volume {

    /// The signed volume of each cell, in cell order: the integral of the trilinear map's Jacobian determinant over
    /// the cube [−1, 1]³, by the 2 × 2 × 2 Gauss rule, which is exact for it, so a cell with flat faces, a
    /// parallelepiped or a frustum, gets its volume up to rounding. It is positive for a cell turned the right way.
    @inlinable
    public func volumes<Scalar: BinaryFloatingPoint>() -> [Scalar] where Vertex == Point<3, Scalar> {
        let signs: [(x: Scalar, y: Scalar, z: Scalar)] = [
            (-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
            (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1),
        ]
        let gauss = 1 / Scalar(3).squareRoot()
        let points = signs.map { (x: $0.x * gauss, y: $0.y * gauss, z: $0.z * gauss) }
        return cells.map { cell in
            let corners = cell.corners.map { vertices[$0].coordinates }
            return points.reduce(Scalar(0)) { sum, point in
                var columns = (
                    x: Vector<3, Scalar>(repeating: 0),
                    y: Vector<3, Scalar>(repeating: 0),
                    z: Vector<3, Scalar>(repeating: 0)
                )
                zip(corners, signs).forEach { corner, sign in
                    let (u, v, w) = (1 + sign.x * point.x, 1 + sign.y * point.y, 1 + sign.z * point.z)
                    columns.x += corner.scaled(by: sign.x * v * w / 8)
                    columns.y += corner.scaled(by: sign.y * u * w / 8)
                    columns.z += corner.scaled(by: sign.z * u * v / 8)
                }
                let (a, b, c) = columns
                return sum + a.x * (b.y * c.z - b.z * c.y) - a.y * (b.x * c.z - b.z * c.x)
                    + a.z * (b.x * c.y - b.y * c.x)
            }
        }
    }
}

extension Mesh.Volume {

    /// The body below a planar mesh of quadrilaterals, such as a soundboard's: each vertex of `top` dropped
    /// straight down in `layers` equal steps to `depth` below it, and each face swept down into one column of cells.
    ///
    /// The top lies at z = 0 and the body below it. Vertex i of `top` is vertex i of the volume, at z = 0, and the
    /// vertices of each lower layer follow in the same order, layer by layer, so vertex ℓ v + i is vertex i at
    /// `depth` × ℓ / `layers` below the top, for v vertices. Cells follow layer by layer from the top, so cell f of
    /// the first layer lies below face f and its upper face, corners 4 to 7, is face f exactly: the volume's face at
    /// the top is `top`, vertex for vertex, as a body coupled to a plate meshed as `top` needs. A guitar's box is its
    /// top's mesh with the depth of its sides, which may change along the outline and arch across the back.
    ///
    /// Faces must be quadrilaterals, counterclockwise seen from above. It fails with `.notQuadrilateral` for any
    /// other face, and with `.folded` when a cell would turn over or have no volume, as it does for a face that turns
    /// clockwise or a depth that is not positive. It traps for no layers.
    @inlinable
    public init<Scalar: BinaryFloatingPoint>(
        below top: Mesh<Point<2, Scalar>>,
        layers: Cardinal,
        depth: (Point<2, Scalar>) -> Scalar
    ) throws(Mesh.Error) where Vertex == Point<3, Scalar> {
        precondition(layers >= .one, "A volume below a mesh needs at least one layer")
        guard top.faces.allSatisfy({ $0.vertices.count == 4 }) else { throw .notQuadrilateral }
        let count = Int(bitPattern: layers)
        let depths = top.vertices.map(depth)
        guard depths.allSatisfy({ $0 > 0 && $0.isFinite }) else { throw .folded }
        let width = top.vertices.count
        var vertices: [Vertex] = []
        vertices.reserveCapacity(width * (count + 1))
        (0...count).forEach { layer in
            let share = Scalar(-layer) / Scalar(count)
            zip(top.vertices, depths).forEach { point, depth in
                vertices.append(Point(x: point.x, y: point.y, z: depth * share))
            }
        }
        var cells: [Cell] = []
        cells.reserveCapacity(top.faces.count * count)
        (0..<count).forEach { layer in
            top.faces.forEach { face in
                let upper = face.vertices.map { Self.index(layer * width + Int(bitPattern: $0)) }
                let lower = face.vertices.map { Self.index((layer + 1) * width + Int(bitPattern: $0)) }
                cells.append(Cell(validated: lower + upper))
            }
        }
        let volume = Self(validated: vertices, cells: cells)
        guard volume.volumes().allSatisfy({ $0 > 0 }) else { throw .folded }
        self = volume
    }
}

extension Mesh.Volume {

    /// The half ball of `radius` below the x–y plane about the origin, as hexahedra that meet exactly at every seam,
    /// whose face at the top is `Mesh.disk(radius:cells:)`, vertex for vertex.
    ///
    /// It is `disk`'s layout taken into the third dimension. A half cube of half-side 0.4 `radius` and as deep is cut
    /// into `cells` × `cells` × `cells` hexahedra, and each of the five regions between a face of it and the sphere
    /// below the plane into as many more: each point of the face carried outward along its ray from the origin onto
    /// the sphere in `cells` equal steps, the four sides as `disk` carries the sides of its square. The six blocks are
    /// welded, so the cells meet at equal vertices, and the first vertices, at z = 0, are `disk`'s in its order. It
    /// has 6 `cells`³ cells, every one turned the right way, and its boundary is closed. Its volume is below ⅔ π r³
    /// and tends to it at second order. It traps for no cells.
    @inlinable
    public static func bowl<Scalar: BinaryFloatingPoint>(
        radius: Scalar,
        cells: Cardinal
    ) -> Self where Vertex == Point<3, Scalar> {
        precondition(cells >= .one, "A bowl needs at least one cell")
        let count = Int(bitPattern: cells)
        let half = radius * 2 / 5
        func parameter(_ index: Int) -> Scalar { Scalar(2 * index - count) / Scalar(count) }
        func depth(_ index: Int) -> Scalar { half * (Scalar(-index) / Scalar(count)) }
        func carry(_ x: Scalar, _ y: Scalar, _ z: Scalar, _ step: Int) -> Vertex {
            let share = Scalar(step) / Scalar(count)
            let scale = radius / (x * x + y * y + z * z).squareRoot()
            return Point(
                x: (1 - share) * x + share * (scale * x),
                y: (1 - share) * y + share * (scale * y),
                z: (1 - share) * z + share * (scale * z)
            )
        }
        let sides: [(Scalar) -> (x: Scalar, y: Scalar)] = [
            { t in (half, -(half * t)) },
            { t in (half * t, half) },
            { t in (-half, half * t) },
            { t in (-(half * t), -half) },
        ]
        var blocks: [(Int, Int, Int) -> Vertex] = [
            { i, j, k in Point(x: half * parameter(i), y: half * parameter(j), z: depth(k)) },
            { i, j, step in carry(half * parameter(i), half * parameter(j), depth(count), step) },
        ]
        for side in sides {
            blocks.append { i, k, step in
                let (x, y) = side(parameter(i))
                return carry(x, y, depth(k), step)
            }
        }
        let disk = Mesh<Point<2, Scalar>>.disk(radius: radius, cells: cells)
        var vertices = disk.vertices.map { Point(x: $0.x, y: $0.y, z: 0) }
        var cellList: [Cell] = []
        cellList.reserveCapacity(6 * count * count * count)
        let lines = count + 1
        for block in blocks {
            let start = vertices.count
            (0...count).forEach { k in
                (0...count).forEach { j in
                    (0...count).forEach { i in vertices.append(block(i, j, k)) }
                }
            }
            func at(_ i: Int, _ j: Int, _ k: Int) -> Index<Vertex> {
                Self.index(start + (k * lines + j) * lines + i)
            }
            var made: [Cell] = []
            (0..<count).forEach { k in
                (0..<count).forEach { j in
                    (0..<count).forEach { i in
                        made.append(
                            Cell(validated: [
                                at(i, j, k), at(i + 1, j, k), at(i + 1, j + 1, k), at(i, j + 1, k),
                                at(i, j, k + 1), at(i + 1, j, k + 1), at(i + 1, j + 1, k + 1), at(i, j + 1, k + 1),
                            ])
                        )
                    }
                }
            }
            let turned = Self(validated: vertices, cells: [made[0]]).volumes()[0] < 0
            cellList.append(contentsOf: turned ? made.map(\.reversed) : made)
        }
        return Self(validated: vertices, cells: cellList).welded
    }

    /// The body under a planar outline drawn from Bézier curves, such as a lute's: a bowl whose face at the top is
    /// `Mesh(inside: outline, around: centre, cells: cells)`, vertex for vertex, and which meets the top at a right
    /// angle all round, as the ribs of a lute meet its soundboard.
    ///
    /// It is `bowl(radius: 1, cells:)` carried as that mesh carries the unit disk: a vertex (x, y, z) goes to the
    /// point a share |(x, y)| of the way from `centre` to where the ray through (x, y) crosses the outline, and to
    /// `depth` × z below the top. Its depth along each ray is therefore `depth` × √(1 − s²) at a share s of the way
    /// out, and its volume tends to ⅔ `depth` times the area inside the outline. Its first vertices are the top's
    /// in its order at z = 0, and the volume has `bowl`'s cells.
    ///
    /// It fails as `Mesh(inside:around:cells:)` does, and with `.folded` when a cell would turn over or have no
    /// volume, as a depth that is not positive gives.
    @inlinable
    public init<Scalar: BinaryFloatingPoint>(
        under outline: [Bezier<Point<2, Scalar>>],
        around centre: Point<2, Scalar>,
        depth: Scalar,
        cells: Cardinal
    ) throws(Mesh.Error) where Vertex == Point<3, Scalar> {
        guard depth > 0, depth.isFinite else { throw .folded }
        let star = try Mesh.Star(outline, around: centre)
        let unit = Self.bowl(radius: 1, cells: cells)
        let disk = Mesh<Point<2, Scalar>>.disk(radius: 1, cells: cells)
        let rim = Set(disk.outline.map { Int(bitPattern: $0.start) })
        let top = disk.vertices.count
        var vertices: [Vertex] = []
        vertices.reserveCapacity(unit.vertices.count)
        for (index, vertex) in unit.vertices.enumerated() {
            let plane = try star.carry(vertex.x, vertex.y, onto: rim.contains(index))
            vertices.append(Point(x: plane.x, y: plane.y, z: index < top ? 0 : depth * vertex.z))
        }
        let volume = Self(validated: vertices, cells: unit.cells)
        guard volume.volumes().allSatisfy({ $0 > 0 }) else { throw .folded }
        self = volume
    }
}
