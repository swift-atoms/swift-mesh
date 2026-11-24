import Mesh
import Testing

extension `Mesh Tests` {
    @Suite struct Volume {}
}

extension `Mesh Tests`.Volume {
    typealias Plane = Point<2, Double>
    typealias Space = Point<3, Double>

    static func total(_ volume: Mesh<Space>.Volume) -> Double { volume.volumes().reduce(0, +) }

    /// The volume the boundary encloses, by the divergence theorem: a third of the flux of the position through
    /// each face, every face taken as the bilinear patch through its four corners, by the 2 × 2 Gauss rule, which
    /// is exact for it. Cells with these faces enclose exactly this.
    static func enclosed(_ surface: Mesh<Space>) -> Double {
        let gauss = [0.5 - 0.5 / 3.0.squareRoot(), 0.5 + 0.5 / 3.0.squareRoot()]
        return surface.faces.reduce(0.0) { sum, face in
            let c = face.vertices.map { surface.vertices[$0].coordinates }
            var flux = 0.0
            for u in gauss {
                for v in gauss {
                    let x =
                        c[0].scaled(by: (1 - u) * (1 - v)) + c[1].scaled(by: u * (1 - v))
                        + c[2].scaled(by: u * v) + c[3].scaled(by: (1 - u) * v)
                    let du = (c[1] - c[0]).scaled(by: 1 - v) + (c[2] - c[3]).scaled(by: v)
                    let dv = (c[3] - c[0]).scaled(by: 1 - u) + (c[2] - c[1]).scaled(by: u)
                    let normal = Vector<3, Double>(
                        x: du.y * dv.z - du.z * dv.y,
                        y: du.z * dv.x - du.x * dv.z,
                        z: du.x * dv.y - du.y * dv.x
                    )
                    flux += x.dot(normal) / 4
                }
            }
            return sum + flux / 3
        }
    }

    /// Every edge of the surface is used once in each direction.
    static func isClosed(_ surface: Mesh<Space>) -> Bool {
        var uses: [Segment<Int>: Int] = [:]
        for face in surface.faces {
            for edge in face.edges {
                uses[Segment(start: Int(bitPattern: edge.start), end: Int(bitPattern: edge.end)), default: 0] += 1
            }
        }
        return uses.allSatisfy { edge, count in count == 1 && uses[Segment(start: edge.end, end: edge.start)] == 1 }
    }

    /// Vertices − edges + faces − cells over the vertices the cells use, each edge and face counted once.
    static func characteristic(_ volume: Mesh<Space>.Volume) -> Int {
        var used = Set<Int>()
        var edges = Set<Segment<Int>>()
        var faces = Set<[Int]>()
        for cell in volume.cells {
            for face in cell.faces {
                let indices = face.vertices.map { Int(bitPattern: $0) }
                used.formUnion(indices)
                faces.insert(indices.sorted())
                for edge in face.edges {
                    let (a, b) = (Int(bitPattern: edge.start), Int(bitPattern: edge.end))
                    edges.insert(Segment(start: min(a, b), end: max(a, b)))
                }
            }
        }
        return used.count - edges.count + faces.count - volume.cells.count
    }

    /// The laws every body here keeps: each cell's volume positive, every vertex used, the boundary closed and
    /// facing outward, enclosing what the cells fill, and the cells one ball.
    static func expectSound(_ volume: Mesh<Space>.Volume, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(volume.volumes().allSatisfy { $0 > 0 }, sourceLocation: sourceLocation)
        let used = Set(volume.cells.flatMap { $0.corners.map { Int(bitPattern: $0) } })
        #expect(used.count == volume.vertices.count, sourceLocation: sourceLocation)
        let boundary = volume.boundary
        #expect(isClosed(boundary), sourceLocation: sourceLocation)
        #expect(boundary.outline.isEmpty, sourceLocation: sourceLocation)
        let filled = total(volume)
        #expect(abs(enclosed(boundary) - filled) <= 1e-12 * max(1, filled), sourceLocation: sourceLocation)
        let sum = boundary.areas().reduce(Vector<3, Double>(repeating: 0), +)
        #expect(sum.dot(sum).squareRoot() <= 1e-12 * max(1, filled), sourceLocation: sourceLocation)
        #expect(characteristic(volume) == 1, sourceLocation: sourceLocation)
    }

    static func grid(columns: Int, rows: Int, width: Double, height: Double) -> Mesh<Plane> {
        Mesh(columns: Cardinal(UInt(columns)), rows: Cardinal(UInt(rows))) { column, row in
            Point(
                x: width * Double(Int(bitPattern: column)) / Double(columns),
                y: height * Double(Int(bitPattern: row)) / Double(rows)
            )
        }
    }

    static func square(_ half: Double) -> [Bezier<Plane>] {
        let corners: [Plane] = [
            Point(x: -half, y: -half), Point(x: half, y: -half), Point(x: half, y: half), Point(x: -half, y: half),
        ]
        return corners.indices.map { Bezier(start: corners[$0], end: corners[($0 + 1) % 4]) }
    }
}

extension `Mesh Tests`.Volume {

    @Test func `A cell has eight corners, faces outward and turns inside out`() throws {
        #expect(throws: Mesh<Space>.Error.notHexahedron) {
            try Mesh<Space>.Volume.Cell(corners: (0..<7).map { Index(_unchecked: Ordinal(UInt($0))) })
        }
        let cube = Mesh<Space>.box(lower: Point(x: 0, y: 0, z: 0), upper: Point(x: 2, y: 3, z: 4))
        // The box counts its corners in binary; a cell goes round the lower face, then the upper.
        let order = [0, 1, 3, 2, 4, 5, 7, 6]
        let cell = try Mesh<Space>.Volume.Cell(corners: order.map { Index(_unchecked: Ordinal(UInt($0))) })
        let volume = try Mesh<Space>.Volume(vertices: cube.vertices, cells: [cell])
        #expect(abs(volume.volumes()[0] - 24) < 1e-12)
        #expect(abs(volume.reversed.volumes()[0] + 24) < 1e-12)
        #expect(cell.reversed.reversed == cell)
        let centre = Vector<3, Double>(x: 1, y: 1.5, z: 2)
        let faces = try Mesh(vertices: cube.vertices, faces: cell.faces)
        for (face, area) in zip(faces.faces, faces.areas()) {
            let middle = face.vertices.map { cube.vertices[$0].coordinates }.reduce(Vector(repeating: 0), +)
                .scaled(by: 1.0 / 4)
            #expect((middle - centre).dot(area) > 0)
        }
        #expect(volume.boundary.faces == cell.faces)
        #expect(throws: Mesh<Space>.Error.indexOutOfBounds) {
            try Mesh<Space>.Volume(vertices: Array(cube.vertices.prefix(7)), cells: [cell])
        }
    }

    @Test func `A cell's volume is exact for a sheared frustum`() throws {
        // A frustum: the lower face 2 × 2, the upper 1 × 1 moved sideways, 3 apart; (h / 3)(A + √(A a) + a).
        let points: [Space] = [
            Point(x: 0, y: 0, z: 0), Point(x: 2, y: 0, z: 0), Point(x: 2, y: 2, z: 0), Point(x: 0, y: 2, z: 0),
            Point(x: 1, y: 0.5, z: 3), Point(x: 2, y: 0.5, z: 3), Point(x: 2, y: 1.5, z: 3), Point(x: 1, y: 1.5, z: 3),
        ]
        let cell = try Mesh<Space>.Volume.Cell(corners: (0..<8).map { Index(_unchecked: Ordinal(UInt($0))) })
        let volume = try Mesh<Space>.Volume(vertices: points, cells: [cell])
        #expect(abs(volume.volumes()[0] - (4 + 2 + 1)) < 1e-12)
    }
}

extension `Mesh Tests`.Volume {

    @Test func `A body below a rectangle fills the prism exactly and keeps the top`() throws {
        let top = Self.grid(columns: 3, rows: 2, width: 2, height: 1)
        let volume = try Mesh<Space>.Volume(below: top, layers: 2) { 1 + 0.25 * $0.x }
        Self.expectSound(volume)
        #expect(volume.cells.count == 12)
        #expect(volume.vertices.count == 3 * top.vertices.count)
        // The integral of 1 + x/4 over [0, 2] × [0, 1]; a bilinear cell reproduces a linear depth exactly.
        #expect(abs(Self.total(volume) - 2.5) < 1e-12)
        for (index, point) in top.vertices.enumerated() {
            #expect(volume.vertices[index] == Point(x: point.x, y: point.y, z: 0))
            #expect(volume.vertices[2 * top.vertices.count + index].z == -(1 + 0.25 * point.x))
        }
        for (index, face) in top.faces.enumerated() {
            #expect(Array(volume.cells[index].corners[4..<8]) == face.vertices.map { $0.retag(Space.self) })
            #expect(volume.boundary.faces.contains(face.map { $0.retag(Space.self) }))
        }
    }

    @Test func `A guitar's box keeps its top vertex for vertex`() throws {
        for cells in [2, 6] {
            let top = try Mesh(
                inside: `Mesh Tests`.Outline.guitar,
                around: Point(x: 0, y: 0.25),
                cells: Cardinal(UInt(cells))
            )
            // Sides 0.6 deep at the tail and 0.5 at the neck, and a back arched by 0.05 at the middle.
            let volume = try Mesh<Space>.Volume(below: top, layers: 3) { point in
                0.55 - 0.03 * point.y + 0.05 * (1 - (point.x * point.x) / 1.1)
            }
            Self.expectSound(volume)
            #expect(volume.cells.count == 3 * top.faces.count)
            let lifted = top.vertices.map { Point(x: $0.x, y: $0.y, z: 0.0) }
            #expect(Array(volume.vertices.prefix(top.vertices.count)) == lifted)
            let upper = volume.cells.prefix(top.faces.count).map { Array($0.corners[4..<8]) }
            #expect(upper == top.faces.map { face in face.vertices.map { $0.retag(Space.self) } })
        }
    }

    @Test func `A body below a mesh refuses what it cannot fill`() throws {
        let top = Self.grid(columns: 2, rows: 2, width: 1, height: 1)
        #expect(throws: Mesh<Space>.Error.notQuadrilateral) { try Mesh<Space>.Volume(below: top.triangulated, layers: 1) { _ in 1 } }
        #expect(throws: Mesh<Space>.Error.folded) { try Mesh<Space>.Volume(below: top, layers: 1) { _ in 0 } }
        #expect(throws: Mesh<Space>.Error.folded) { try Mesh<Space>.Volume(below: top, layers: 1) { _ in -1 } }
        #expect(throws: Mesh<Space>.Error.folded) { try Mesh<Space>.Volume(below: top.reversed, layers: 1) { _ in 1 } }
    }
}

extension `Mesh Tests`.Volume {

    @Test(arguments: [1, 2, 3, 4])
    func `A bowl welds into one ball whose top is the disk`(cells: Int) {
        let count = Cardinal(UInt(cells))
        let bowl = Mesh<Space>.Volume.bowl(radius: 2, cells: count)
        Self.expectSound(bowl)
        #expect(bowl.cells.count == 6 * cells * cells * cells)
        let disk = Mesh<Plane>.disk(radius: 2, cells: count)
        #expect(Array(bowl.vertices.prefix(disk.vertices.count)) == disk.vertices.map { Point(x: $0.x, y: $0.y, z: 0) })
        #expect(bowl.vertices.dropFirst(disk.vertices.count).allSatisfy { $0.z < 0 })
        #expect(bowl.vertices.allSatisfy { $0.coordinates.dot($0.coordinates) <= 4 * (1 + 1e-12) })
    }

    @Test func `A bowl's volume tends to the half ball's from below at second order`() {
        let exact = 2.0 / 3 * Double.pi * 8
        let errors = [2, 4, 8].map { exact - Self.total(Mesh<Space>.Volume.bowl(radius: 2, cells: Cardinal(UInt($0)))) }
        #expect(errors.allSatisfy { $0 > 0 })
        #expect(errors[0] / errors[1] > 3)
        #expect(errors[1] / errors[2] > 3)
    }

    @Test func `A body under an outline keeps the top that fills it, vertex for vertex`() throws {
        let centre: Plane = Point(x: 0, y: 0.25)
        for cells in [2, 4, 6] {
            let count = Cardinal(UInt(cells))
            let top = try Mesh(inside: `Mesh Tests`.Outline.guitar, around: centre, cells: count)
            let volume = try Mesh<Space>.Volume(under: `Mesh Tests`.Outline.guitar, around: centre, depth: 0.7, cells: count)
            Self.expectSound(volume)
            #expect(volume.cells.count == 6 * cells * cells * cells)
            let lifted = top.vertices.map { Point(x: $0.x, y: $0.y, z: 0.0) }
            #expect(Array(volume.vertices.prefix(top.vertices.count)) == lifted)
            #expect(volume.vertices.dropFirst(top.vertices.count).allSatisfy { $0.z < 0 })
            // The top's faces are the boundary's faces at z = 0, as the top gives them.
            let flat = volume.boundary.faces.filter { face in face.vertices.allSatisfy { volume.vertices[$0].z == 0 } }
            #expect(Set(flat) == Set(top.faces.map { face in face.map { $0.retag(Space.self) } }))
        }
    }

    @Test func `A body under an outline tends to two thirds of its depth times its area`() throws {
        // A square of side 2 about its centre: ⅔ × 0.5 × 4.
        let exact = 2.0 / 3 * 0.5 * 4
        let errors = try [2, 4, 8].map { cells in
            let volume = try Mesh<Space>.Volume(
                under: Self.square(1),
                around: Point(x: 0, y: 0),
                depth: 0.5,
                cells: Cardinal(UInt(cells))
            )
            return abs(exact - Self.total(volume))
        }
        #expect(errors[0] / errors[1] > 3)
        #expect(errors[1] / errors[2] > 3)
        #expect(errors[2] < 0.01 * exact)
    }

    @Test func `A body under an outline refuses what it cannot fill`() {
        let centre: Plane = Point(x: 0, y: 0)
        #expect(throws: Mesh<Space>.Error.folded) {
            try Mesh<Space>.Volume(under: Self.square(1), around: centre, depth: 0, cells: 2)
        }
        #expect(throws: Mesh<Space>.Error.openOutline) {
            try Mesh<Space>.Volume(under: Array(Self.square(1).dropLast()), around: centre, depth: 1, cells: 2)
        }
        #expect(throws: Mesh<Space>.Error.outlineNotStarShaped) {
            try Mesh<Space>.Volume(under: Self.square(1), around: Point(x: 3, y: 0), depth: 1, cells: 2)
        }
    }
}
