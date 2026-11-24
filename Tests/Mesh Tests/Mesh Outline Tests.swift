import Mesh
import Testing

extension `Mesh Tests` {
    @Suite struct Outline {}
}

extension `Mesh Tests`.Outline {
    typealias Plane = Point<2, Double>

    /// Twice the signed area of each face, by the shoelace formula.
    static func areas(_ mesh: Mesh<Plane>) -> [Double] {
        mesh.faces.map { face in
            let corners = face.vertices.map { mesh.vertices[$0] }
            return corners.indices.reduce(0.0) { sum, index in
                let (a, b) = (corners[index], corners[(index + 1) % corners.count])
                return sum + a.x * b.y - b.x * a.y
            } / 2
        }
    }

    static func characteristic<Vertex>(_ mesh: Mesh<Vertex>) -> Int {
        var edges = Set<Segment<Int>>()
        for face in mesh.faces {
            for edge in face.edges {
                let (a, b) = (Int(bitPattern: edge.start), Int(bitPattern: edge.end))
                edges.insert(Segment(start: min(a, b), end: max(a, b)))
            }
        }
        return mesh.vertices.count - edges.count + mesh.faces.count
    }

    /// A guitar's outline: eight cubic curves through points on its edge, smooth where they meet (Catmull–Rom),
    /// counterclockwise, with its waist at y ≈ 0.25.
    static let guitar: [Bezier<Plane>] = {
        let through: [Plane] = [
            Point(x: 0, y: -1.6), Point(x: 1.0, y: -0.75), Point(x: 0.68, y: 0.25), Point(x: 0.8, y: 0.95),
            Point(x: 0, y: 1.4), Point(x: -0.8, y: 0.95), Point(x: -0.68, y: 0.25), Point(x: -1.0, y: -0.75),
        ]
        let count = through.count
        func at(_ index: Int) -> Plane { through[(index + count) % count] }
        return (0..<count).map { index in
            let (before, start, end, after) = (at(index - 1), at(index), at(index + 1), at(index + 2))
            return Bezier(
                start: start,
                control1: Point(x: start.x + (end.x - before.x) / 6, y: start.y + (end.y - before.y) / 6),
                control2: Point(x: end.x - (after.x - start.x) / 6, y: end.y - (after.y - start.y) / 6),
                end: end
            )
        }
    }()

    static func point(_ curve: Bezier<Plane>, _ parameter: Double) -> Plane {
        curve.value(at: parameter) { $0.interpolated(to: $1, at: $2) }
    }

    /// The outline as a fine polygon.
    static func polygon(_ outline: [Bezier<Plane>]) -> [Plane] {
        outline.flatMap { curve in (0..<512).map { point(curve, Double($0) / 512) } }
    }

    static func distance(_ point: Plane, to polygon: [Plane]) -> Double {
        polygon.indices.map { index in
            let (a, b) = (polygon[index], polygon[(index + 1) % polygon.count])
            let (dx, dy) = (b.x - a.x, b.y - a.y)
            let share = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)))
            return point.distance(to: Point(x: a.x + share * dx, y: a.y + share * dy))
        }.min()!
    }

    static func isInside(_ point: Plane, _ polygon: [Plane]) -> Bool {
        var inside = false
        for index in polygon.indices {
            let (a, b) = (polygon[index], polygon[(index + 1) % polygon.count])
            if (a.y > point.y) != (b.y > point.y), point.x < a.x + (b.x - a.x) * (point.y - a.y) / (b.y - a.y) {
                inside.toggle()
            }
        }
        return inside
    }

    static func polygonArea(_ polygon: [Plane]) -> Double {
        polygon.indices.reduce(0.0) { sum, index in
            let (a, b) = (polygon[index], polygon[(index + 1) % polygon.count])
            return sum + a.x * b.y - b.x * a.y
        } / 2
    }
}

// MARK: - The outline

extension `Mesh Tests`.Outline {
    @Test
    func `A closed surface has no outline`() {
        #expect(Mesh<Point<3, Double>>.sphere(radius: 1, meridians: 8, parallels: 5).outline.isEmpty)
        #expect(Mesh<Point<3, Double>>.torus(major: 2, minor: 1, segments: 8, sides: 6).outline.isEmpty)
        #expect(Mesh.box(lower: Point<3, Double>(x: 0, y: 0, z: 0), upper: Point(x: 1, y: 2, z: 3)).outline.isEmpty)
        #expect(Mesh<Plane>.empty.outline.isEmpty)
    }

    @Test
    func `A grid's outline is its border, counterclockwise, each vertex on two of its edges`() {
        let grid = Mesh(columns: 4, rows: 3) { column, row in
            Plane(x: Double(Int(bitPattern: column)), y: Double(Int(bitPattern: row)))
        }
        let outline = grid.outline
        #expect(outline.count == 2 * (4 + 3))
        var ends: [Int: Int] = [:]
        for edge in outline {
            let (start, end) = (grid.vertices[edge.start], grid.vertices[edge.end])
            for vertex in [start, end] {
                #expect(vertex.x == 0 || vertex.x == 4 || vertex.y == 0 || vertex.y == 3)
            }
            // Counterclockwise around the grid: the inside is to the left of every edge.
            let middle = Plane(
                x: (start.x + end.x) / 2 - (end.y - start.y) / 4,
                y: (start.y + end.y) / 2 + (end.x - start.x) / 4
            )
            #expect(middle.x > 0 && middle.x < 4 && middle.y > 0 && middle.y < 3)
            ends[Int(bitPattern: edge.start), default: 0] += 1
            ends[Int(bitPattern: edge.end), default: 0] += 1
        }
        #expect(ends.count == outline.count && ends.values.allSatisfy { $0 == 2 })
    }

    @Test
    func `Reversing a mesh reverses its outline, and an edge shared either way round is inside`() throws {
        let grid = Mesh(columns: 2, rows: 2) { column, row in
            Plane(x: Double(Int(bitPattern: column)), y: Double(Int(bitPattern: row)))
        }
        #expect(grid.reversed.outline.count == grid.outline.count)
        #expect(Set(grid.reversed.outline) == Set(grid.outline.map(\.reversed)))
        let mixed = try Mesh(vertices: grid.vertices, faces: [grid.faces[0], grid.faces[1].reversed])
        #expect(mixed.outline.count == 6)
    }
}

// MARK: - The disk

extension `Mesh Tests`.Outline {
    @Test(arguments: [1, 2, 3, 7, 8, 16])
    func `A disk welds at every seam: 5n² faces, 5n² + 2n + 1 vertices, and a disk's characteristic`(cells: Int) {
        let disk = Mesh<Plane>.disk(radius: 0.3, cells: Cardinal(UInt(cells)))
        #expect(disk.faces.count == 5 * cells * cells)
        let vertices = 5 * cells * cells + 2 * cells + 1
        #expect(disk.vertices.count == vertices)
        #expect(Self.characteristic(disk) == 1)
        #expect(Self.areas(disk).allSatisfy { $0 > 0 })
    }

    @Test(arguments: [1, 4, 9])
    func `A disk's outline is 4n edges on the circle`(cells: Int) {
        let disk = Mesh<Plane>.disk(radius: 2.5, cells: Cardinal(UInt(cells)))
        let outline = disk.outline
        #expect(outline.count == 4 * cells)
        for edge in outline {
            #expect(abs(disk.vertices[edge.start].distance(to: Point(x: 0, y: 0)) - 2.5) < 1e-12)
        }
    }

    @Test
    func `A disk's area tends to πr² from below, the error falling by more than three each time the cells double`() {
        let radius = 1.7
        let exact = Double.pi * radius * radius
        let errors = [2, 4, 8, 16, 32].map { cells in
            exact - Self.areas(Mesh<Plane>.disk(radius: radius, cells: Cardinal(UInt(cells)))).reduce(0, +)
        }
        #expect(errors.allSatisfy { $0 > 0 })
        for (coarse, fine) in zip(errors, errors.dropFirst()) { #expect(coarse / fine > 3) }
        #expect(errors.last! / exact < 1e-3)
    }
}

// MARK: - A meshed outline

extension `Mesh Tests`.Outline {
    @Test(arguments: [2, 6, 12])
    func `Every face of a meshed guitar outline lies inside it, with positive area`(cells: Int) throws {
        let mesh = try Mesh(inside: Self.guitar, around: Point(x: 0, y: 0.2), cells: Cardinal(UInt(cells)))
        let polygon = Self.polygon(Self.guitar)
        #expect(mesh.faces.count == 5 * cells * cells)
        #expect(Self.areas(mesh).allSatisfy { $0 > 0 })
        for vertex in mesh.vertices {
            #expect(Self.isInside(vertex, polygon) || Self.distance(vertex, to: polygon) < 1e-5)
        }
        for face in mesh.faces {
            let corners = face.vertices.map { mesh.vertices[$0] }
            let centroid = Plane(
                x: corners.map(\.x).reduce(0, +) / Double(corners.count),
                y: corners.map(\.y).reduce(0, +) / Double(corners.count)
            )
            #expect(Self.isInside(centroid, polygon))
        }
    }

    @Test
    func `A meshed outline's own outline lies on the curves, and its area tends to the outline's`() throws {
        let polygon = Self.polygon(Self.guitar)
        let exact = Self.polygonArea(polygon)
        var errors: [Double] = []
        for cells in [4, 8, 16] {
            let mesh = try Mesh(inside: Self.guitar, around: Point(x: 0, y: 0.2), cells: Cardinal(UInt(cells)))
            #expect(mesh.outline.count == 4 * cells)
            for edge in mesh.outline { #expect(Self.distance(mesh.vertices[edge.start], to: polygon) < 1e-5) }
            errors.append(abs(exact - Self.areas(mesh).reduce(0, +)))
        }
        for (coarse, fine) in zip(errors, errors.dropFirst()) { #expect(coarse / fine > 3) }
    }

    @Test
    func `An outline of straight sides is covered exactly, whichever way round it runs`() throws {
        let corners: [Plane] = [Point(x: -1, y: -1), Point(x: 1, y: -1), Point(x: 1, y: 1), Point(x: -1, y: 1)]
        let square = corners.indices.map { Bezier(start: corners[$0], end: corners[($0 + 1) % 4]) }
        let clockwise = square.reversed().map(\.reversed)
        for outline in [square, clockwise] {
            let mesh = try Mesh(inside: outline, around: Point(x: 0, y: 0), cells: 5)
            let areas = Self.areas(mesh)
            #expect(areas.allSatisfy { $0 > 0 })
            #expect(abs(areas.reduce(0, +) - 4) < 1e-12)
        }
    }

    @Test
    func `A circle's outline gives the disk about its centre, as far as the curves are a circle`() throws {
        // Four cubic quarter circles of radius 2, k = 4(√2 − 1)/3, which stray at most 2.7 × 10⁻⁴ of the radius.
        let (radius, centre) = (2.0, Plane(x: 0.25, y: -0.5))
        let k = 4 * (2.0.squareRoot() - 1) / 3
        func at(_ x: Double, _ y: Double) -> Plane { Point(x: centre.x + radius * x, y: centre.y + radius * y) }
        let directions: [(Double, Double)] = [(1, 0), (0, 1), (-1, 0), (0, -1)]
        let outline = directions.indices.map { index in
            let (from, to) = (directions[index], directions[(index + 1) % 4])
            return Bezier(
                start: at(from.0, from.1),
                control1: at(from.0 + k * to.0, from.1 + k * to.1),
                control2: at(to.0 + k * from.0, to.1 + k * from.1),
                end: at(to.0, to.1)
            )
        }
        let disk = Mesh<Plane>.disk(radius: radius, cells: 6)
        let mesh = try Mesh(inside: outline, around: centre, cells: 6)
        #expect(mesh.faces == disk.faces)
        for (fitted, vertex) in zip(mesh.vertices, disk.vertices) {
            #expect(fitted.distance(to: Point(x: vertex.x + centre.x, y: vertex.y + centre.y)) < 2.8e-4 * radius)
        }
    }

    @Test
    func `An outline with a gap, none, or not seen whole from its centre is refused`() {
        let square: [Plane] = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1)]
        let open = (0..<3).map { Bezier(start: square[$0], end: square[$0 + 1]) }
        #expect(throws: Mesh<Plane>.Error.openOutline) {
            try Mesh(inside: open, around: Point(x: 0.5, y: 0.5), cells: 2)
        }
        #expect(throws: Mesh<Plane>.Error.openOutline) { try Mesh(inside: [], around: Point(x: 0.5, y: 0.5), cells: 2) }
        let closed = (0..<4).map { Bezier(start: square[$0], end: square[($0 + 1) % 4]) }
        #expect(throws: Mesh<Plane>.Error.outlineNotStarShaped) {
            try Mesh(inside: closed, around: Point(x: 2, y: 0.5), cells: 2)
        }
        // A C shape: from its centre, the inner side hides part of the outer one.
        let c: [Plane] = [
            Point(x: 0, y: 0), Point(x: 3, y: 0), Point(x: 3, y: 1), Point(x: 1, y: 1),
            Point(x: 1, y: 2), Point(x: 3, y: 2), Point(x: 3, y: 3), Point(x: 0, y: 3),
        ]
        let shape = c.indices.map { Bezier(start: c[$0], end: c[($0 + 1) % c.count]) }
        #expect(throws: Mesh<Plane>.Error.outlineNotStarShaped) {
            try Mesh(inside: shape, around: Point(x: 0.5, y: 1.5), cells: 2)
        }
    }
}
