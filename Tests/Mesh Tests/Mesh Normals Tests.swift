import Mesh
import Testing

extension `Mesh Tests` {
    @Suite
    struct `Mesh triangle counts, polygon meshes and smoothed face normals` {
        typealias Position = Point<3, Double>

        static func quad(_ x: Double, _ y: Double, _ z: Double, size: Double) -> Polygon<Position> {
            Polygon(
                Position(x: x, y: y, z: z),
                Position(x: x + size, y: y, z: z),
                Position(x: x + size, y: y + size, z: z + size / 2),
                Position(x: x, y: y + size, z: z + size / 2)
            )
        }

        static let quads = [quad(0, 0, 0, size: 1), quad(2, -1, 3, size: 0.5), quad(-4, 2, 1, size: 2.5)]

        static func total(_ areas: [Vector<3, Double>]) -> Vector<3, Double> {
            areas.reduce(Vector(repeating: 0), +)
        }

        static func cross(_ a: Vector<3, Double>, _ b: Vector<3, Double>) -> Vector<3, Double> {
            Vector(x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x)
        }

        static func angle(_ a: Vector<3, Double>, _ b: Vector<3, Double>) -> Double {
            let cross = cross(a, b)
            return Double.atan2(cross.dot(cross).squareRoot(), a.dot(b))
        }

        @Test(arguments: [(3, 2), (8, 5), (24, 12), (48, 24), (192, 96)])
        func `Every vertex normal of a sphere is its direction from the centre`(meridians: Int, parallels: Int) {
            let sphere = Mesh<Position>.sphere(
                radius: 1.5,
                meridians: Cardinal(UInt(meridians)),
                parallels: Cardinal(UInt(parallels))
            )
            let normals: [Vector<3, Double>] = sphere.normals(per: .vertex)
            zip(sphere.vertices, normals).forEach { vertex, normal in
                #expect(abs(normal.dot(normal) - 1) < 1e-12)
                // Measured worst case on these spheres: under 1e-14 radians.
                #expect(Self.angle(normal, vertex.coordinates) < 1e-12)
            }
        }

        @Test
        func `Every vertex normal of a flat grid is the plane's`() {
            let (along, across) = (Vector<3, Double>(x: 1, y: -1, z: 0.5), Vector<3, Double>(x: 1, y: 2, z: -0.25))
            let grid = Mesh<Position>(columns: 7, rows: 4) { column, row in
                let (u, v) = (Double(Int(bitPattern: column)), Double(Int(bitPattern: row)))
                let (s, t) = (0.3 * u * u + u, v + 0.1 * v * v * v)
                return Position(x: along.x * s + across.x * t, y: along.y * s + across.y * t, z: along.z * s + across.z * t + 1)
            }
            let plane = Self.cross(along, across)
            let normals: [Vector<3, Double>] = grid.normals(per: .vertex)
            normals.forEach { normal in #expect(Self.angle(normal, plane) < 1e-12) }
        }

        @Test
        func `The corner normals of a cube are its diagonals`() {
            let cube = Mesh<Position>.box(lower: Position(x: -3, y: 1, z: 2), upper: Position(x: -1, y: 3, z: 4))
            let centre = Vector<3, Double>(x: -2, y: 2, z: 3)
            let normals: [Vector<3, Double>] = cube.normals(per: .vertex)
            zip(cube.vertices, normals).forEach { vertex, normal in
                #expect(Self.angle(normal, vertex.coordinates - centre) < 1e-15)
            }
        }

        @Test
        func `Degenerate faces add nothing to a vertex normal`() throws {
            let vertices = [
                Position(x: 0, y: 0, z: 0), Position(x: 1, y: 0, z: 0), Position(x: 0, y: 1, z: 0),
                Position(x: 2, y: 0, z: 0), Position(x: -1, y: -1, z: 0),
            ]
            let plain = try Mesh(vertices: vertices, faces: [Polygon(0, 1, 2)])
            let degenerate = try Mesh(
                vertices: vertices,
                faces: [Polygon(0, 1, 2), Polygon(0, 1, 3), Polygon(0, 0, 2), Polygon(0, 0, 0), Polygon(0, 4, 4)]
            )
            let expected: [Vector<3, Double>] = plain.normals(per: .vertex)
            let normals: [Vector<3, Double>] = degenerate.normals(per: .vertex)
            #expect(normals[0] == expected[0])
            normals.forEach { normal in #expect(normal.x.isFinite && normal.y.isFinite && normal.z.isFinite) }
        }

        @Test
        func `A box has twelve triangles`() {
            let box = Mesh<Position>.box(lower: Position(x: 0, y: 0, z: 0), upper: Position(x: 1, y: 2, z: 3))
            #expect(box.triangles == 12)
            #expect(box.triangles == Cardinal(UInt(box.triangulated.faces.count)))
        }

        @Test
        func `The triangle count is what triangulating gives, for faces of any size`() {
            let sphere = Mesh<Position>.sphere(radius: 1, meridians: 8, parallels: 5)
            #expect(sphere.triangles == Cardinal(UInt(sphere.triangulated.faces.count)))
            #expect(Mesh<Position>.empty.triangles == 0)
        }

        @Test
        func `A mesh of polygons gives each its own vertices, in order`() {
            let mesh = Mesh(Self.quads)
            #expect(mesh.vertices.count == 12)
            #expect(mesh.faces.count == 3)
            for (index, quad) in Self.quads.enumerated() {
                #expect(mesh.polygon(at: Index(_unchecked: Ordinal(UInt(index)))) == quad)
            }
            #expect(Mesh<Position>([]) == .empty)
        }

        @Test
        func `A mesh of quads has twice as many triangles as quads and the same surface`() {
            let mesh = Mesh(Self.quads)
            #expect(mesh.triangles == Cardinal(UInt(2 * Self.quads.count)))
            let whole = Self.total(mesh.areas())
            let split = Self.total(mesh.triangulated.areas())
            (0..<3).forEach { axis in #expect(abs(whole[axis] - split[axis]) < 1e-12) }
        }

        @Test
        func `Smoothed face normals on a sphere are unit and point outward`() {
            let sphere = Mesh<Position>.sphere(radius: 2, meridians: 24, parallels: 12)
            let normals: [Vector<3, Double>] = sphere.normals(per: .face, from: .vertex)
            #expect(normals.count == sphere.faces.count)
            zip(sphere.faces, normals).forEach { face, normal in
                #expect(abs(normal.dot(normal) - 1) < 1e-12)
                let centre = face.vertices.reduce(Vector<3, Double>(repeating: 0)) { $0 + sphere.vertices[$1].coordinates }
                #expect(normal.dot(centre) > 0)
            }
        }

        @Test
        func `Smoothed face normals differ from flat ones only where faces share vertices`() {
            let separate = Mesh(Self.quads)
            let smoothed: [Vector<3, Double>] = separate.normals(per: .face, from: .vertex)
            let flat: [Vector<3, Double>] = separate.normals(per: .face)
            zip(smoothed, flat).forEach { a, b in (0..<3).forEach { #expect(abs(a[$0] - b[$0]) < 1e-12) } }
            let box = Mesh<Position>.box(lower: Position(x: 0, y: 0, z: 0), upper: Position(x: 1, y: 1, z: 1))
            let rounded: [Vector<3, Double>] = box.normals(per: .face, from: .vertex)
            let sides: [Vector<3, Double>] = box.normals(per: .face)
            zip(rounded, sides).forEach { a, b in
                #expect(abs(a.dot(a) - 1) < 1e-12)
                #expect(abs(a.dot(b) - 1) < 1e-12)
            }
            #expect((box.normals(per: .vertex, from: .face) as [Vector<3, Double>]) == box.normals(per: .vertex))
        }
    }
}
