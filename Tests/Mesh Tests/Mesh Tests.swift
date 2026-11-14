import Foundation
public import Mesh
import Testing

extension Double: @retroactive Trigonometry.Circular {
    public static func sin(_ x: Double) -> Double { Foundation.sin(x) }
    public static func cos(_ x: Double) -> Double { Foundation.cos(x) }
    public static func tan(_ x: Double) -> Double { Foundation.tan(x) }
    public static func asin(_ x: Double) -> Double { Foundation.asin(x) }
    public static func acos(_ x: Double) -> Double { Foundation.acos(x) }
    public static func atan(_ x: Double) -> Double { Foundation.atan(x) }
    public static func atan2(_ y: Double, _ x: Double) -> Double { Foundation.atan2(y, x) }
}

enum `Mesh Tests` {}

extension `Mesh Tests` {
    fileprivate typealias Position = Point<3, Double>

    fileprivate struct Edge: Hashable {
        let from: Int
        let to: Int
    }

    /// Directed edges of every face, with how often each occurs.
    fileprivate static func edges<Vertex>(_ mesh: Mesh<Vertex>) -> [Edge: Int] {
        var result: [Edge: Int] = [:]
        for face in mesh.faces {
            for edge in face.edges {
                result[Edge(from: Int(bitPattern: edge.start), to: Int(bitPattern: edge.end)), default: 0] += 1
            }
        }
        return result
    }

    /// True when every edge is used once in each direction: a closed, consistently oriented surface.
    fileprivate static func isClosed<Vertex>(_ mesh: Mesh<Vertex>) -> Bool {
        let edges = edges(mesh)
        return edges.allSatisfy { $0.value == 1 && edges[Edge(from: $0.key.to, to: $0.key.from)] == 1 }
    }

    fileprivate static func characteristic<Vertex>(_ mesh: Mesh<Vertex>) -> Int {
        let undirected = Set(edges(mesh).keys.map { Edge(from: min($0.from, $0.to), to: max($0.from, $0.to)) })
        return mesh.vertices.count - undirected.count + mesh.faces.count
    }

    fileprivate static func faces<Vertex>(_ mesh: Mesh<Vertex>) -> [Index<Polygon<Index<Vertex>>>] {
        mesh.faces.indices.map { Index(_unchecked: Ordinal(UInt($0))) }
    }

    fileprivate static func cube() throws(Mesh<Position>.Error) -> Mesh<Position> {
        try Mesh(
            vertices: [
                Point(x: 0, y: 0, z: 0), Point(x: 1, y: 0, z: 0), Point(x: 1, y: 1, z: 0), Point(x: 0, y: 1, z: 0),
                Point(x: 0, y: 0, z: 1), Point(x: 1, y: 0, z: 1), Point(x: 1, y: 1, z: 1), Point(x: 0, y: 1, z: 1),
            ],
            faces: [
                Polygon(0, 3, 2, 1), Polygon(4, 5, 6, 7), Polygon(0, 1, 5, 4),
                Polygon(2, 3, 7, 6), Polygon(1, 2, 6, 5), Polygon(0, 4, 7, 3),
            ]
        )
    }

    fileprivate static func length(_ vector: Vector<3, Double>) -> Double { vector.dot(vector).squareRoot() }
}

extension `Mesh Tests` {
    @Suite
    struct `Mesh contracts` {
        @Test
        func `Faces must name existing vertices`() throws {
            #expect(throws: Mesh<String>.Error.indexOutOfBounds) {
                try Mesh(vertices: ["a", "b", "c"], faces: [Polygon(0, 1, 3)])
            }
            #expect(throws: Mesh<String>.Error.indexOutOfBounds) {
                try Mesh(vertices: ["a", "b", "c"], faces: [Polygon(0, 1, 2), Polygon(1, 2, 1_099_511_627_776)])
            }
            let mesh = try Mesh(vertices: ["a", "b", "c", "unused"], faces: [Polygon(0, 1, 2), Polygon(2, 2, 0)])
            #expect(mesh.vertices.count == 4)
            #expect(mesh.faces.count == 2)
            #expect(Mesh<String>.empty.vertices.isEmpty && Mesh<String>.empty.faces.isEmpty)
            #expect(try Mesh<String>(vertices: [], faces: []) == .empty)
        }

        @Test
        func `A face resolves to the polygon of its vertices`() throws {
            let mesh = try Mesh(vertices: ["a", "b", "c", "d"], faces: [Polygon(0, 1, 2), Polygon(3, 2, 1, 0)])
            #expect(mesh.polygon(at: 0).vertices == ["a", "b", "c"])
            #expect(mesh.polygon(at: 1).vertices == ["d", "c", "b", "a"])
        }

        @Test
        func `Mapping keeps the faces and stops on typed failure`() throws {
            struct Failure: Swift::Error, Equatable {}
            let mesh = try Mesh(vertices: [1, 2, 3], faces: [Polygon(0, 1, 2)])
            let mapped = mesh.map { String($0) }
            #expect(mapped.vertices == ["1", "2", "3"])
            #expect(mapped.faces.map(\.vertices) == [[0, 1, 2]])
            var visited: [Int] = []
            func transform(_ value: Int) throws(Failure) -> Int {
                visited.append(value)
                if value == 2 { throw Failure() }
                return value
            }
            #expect(throws: Failure()) { try mesh.map(transform) }
            #expect(visited == [1, 2])
        }

        @Test
        func `Reversal flips every face and is its own inverse`() throws {
            let cube = try `Mesh Tests`.cube()
            #expect(cube.reversed.vertices == cube.vertices)
            #expect(cube.reversed.faces[0].vertices == [0, 1, 2, 3])
            #expect(cube.reversed.reversed == cube)
            #expect(cube.reversed != cube)
            #expect(`Mesh Tests`.isClosed(cube.reversed))
        }

        @Test
        func `Triangulation fans each face from its first vertex and keeps orientation`() throws {
            let mesh = try Mesh(
                vertices: Array(0..<7),
                faces: [Polygon(0, 1, 2), Polygon(2, 3, 4, 5, 6), Polygon(0, 2, 6, 1)]
            )
            let triangles = mesh.triangulated
            #expect(triangles.vertices == mesh.vertices)
            #expect(
                triangles.faces.map(\.vertices) == [
                    [0, 1, 2], [2, 3, 4], [2, 4, 5], [2, 5, 6], [0, 2, 6], [0, 6, 1],
                ]
            )
            #expect(triangles.triangulated == triangles)
            let cube = try `Mesh Tests`.cube()
            #expect(cube.triangulated.faces.count == 12)
            #expect(`Mesh Tests`.isClosed(cube.triangulated))
            #expect(cube.triangulated.normals(per: .face).count == 12)
            for (triangle, normal) in cube.triangulated.normals(per: .face).enumerated() {
                #expect(normal == cube.normals(per: .face)[triangle / 2])
            }
        }

        @Test
        func `Appending keeps both meshes and shifts the second one's indices`() throws {
            let first = try Mesh(vertices: ["a", "b", "c"], faces: [Polygon(0, 1, 2)])
            let second = try Mesh(vertices: ["d", "e", "f", "g"], faces: [Polygon(3, 2, 1, 0)])
            let both = first.appending(second)
            #expect(both.vertices == ["a", "b", "c", "d", "e", "f", "g"])
            #expect(both.faces.map(\.vertices) == [[0, 1, 2], [6, 5, 4, 3]])
            #expect(first.appending(.empty) == first)
            #expect(Mesh.empty.appending(first) == first)
        }

        @Test
        func `Welding merges equal vertices into their first occurrence`() throws {
            let mesh = try Mesh(
                vertices: ["a", "b", "c", "b", "a", "d"],
                faces: [Polygon(0, 1, 2), Polygon(4, 3, 5), Polygon(1, 3, 2)]
            )
            let welded = mesh.welded
            #expect(welded.vertices == ["a", "b", "c", "d"])
            #expect(welded.faces.map(\.vertices) == [[0, 1, 2], [0, 1, 3], [1, 1, 2]])
            #expect(welded.welded == welded)
            for face in `Mesh Tests`.faces(mesh) {
                #expect(welded.polygon(at: face) == mesh.polygon(at: face))
            }
        }

        @Test
        func `Value conformances compare vertices and faces as given`() throws {
            func requireSendable<T: Sendable>(_ value: T) {}
            let mesh = try Mesh(vertices: [1, 2, 3], faces: [Polygon(0, 1, 2)])
            let shifted = try Mesh(vertices: [1, 2, 3], faces: [Polygon(1, 2, 0)])
            requireSendable(mesh)
            #expect(Set([mesh, mesh, shifted]).count == 2)
        }

        @Test
        func `A mesh codes as its vertices and faces and decoding keeps its invariant`() throws {
            let mesh = try Mesh(vertices: [10, 20, 30, 40], faces: [Polygon(0, 1, 2), Polygon(0, 2, 3)])
            let data = try JSONEncoder().encode(mesh)
            #expect(try JSONDecoder().decode(Mesh<Int>.self, from: data) == mesh)
            let valid = Data(#"{"vertices":[1,2,3],"faces":[[2,1,0]]}"#.utf8)
            #expect(try JSONDecoder().decode(Mesh<Int>.self, from: valid).faces[0].vertices == [2, 1, 0])
            let invalid = Data(#"{"vertices":[1,2,3],"faces":[[0,1,3]]}"#.utf8)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(Mesh<Int>.self, from: invalid) }
            let short = Data(#"{"vertices":[1,2,3],"faces":[[0,1]]}"#.utf8)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(Mesh<Int>.self, from: short) }
        }
    }
}

extension `Mesh Tests` {
    @Suite
    struct `Mesh normal contracts` {
        @Test
        func `A counterclockwise face has its area vector on the side it is seen from`() throws {
            let square = try Mesh<Position>(
                vertices: [
                    Point(x: 0, y: 0, z: 5), Point(x: 2, y: 0, z: 5), Point(x: 2, y: 3, z: 5), Point(x: 0, y: 3, z: 5),
                ],
                faces: [Polygon(0, 1, 2, 3), Polygon(0, 1, 2), Polygon(1, 3, 2, 0)]
            )
            #expect(square.areas() == [Vector(x: 0, y: 0, z: 6), Vector(x: 0, y: 0, z: 3), Vector(x: 0, y: 0, z: 0)])
            #expect(square.normals(per: .face) == [Vector(x: 0, y: 0, z: 1), Vector(x: 0, y: 0, z: 1), .zero])
        }

        @Test
        func `Reversing a mesh negates every normal`() throws {
            let cube = try `Mesh Tests`.cube()
            for element in Mesh<Position>.Element.allCases {
                let normals = cube.normals(per: element)
                let reversed = cube.reversed.normals(per: element)
                #expect(normals.count == reversed.count)
                for (normal, opposite) in zip(normals, reversed) { #expect(normal + opposite == .zero) }
            }
        }

        @Test
        func `Normals are unit vectors that point out of a counterclockwise closed surface`() throws {
            let cube = try `Mesh Tests`.cube()
            #expect(
                cube.normals(per: .face) == [
                    Vector(x: 0, y: 0, z: -1), Vector(x: 0, y: 0, z: 1), Vector(x: 0, y: -1, z: 0),
                    Vector(x: 0, y: 1, z: 0), Vector(x: 1, y: 0, z: 0), Vector(x: -1, y: 0, z: 0),
                ]
            )
            let third = (1.0 / 3).squareRoot()
            for (vertex, normal) in zip(cube.vertices, cube.normals(per: .vertex)) {
                #expect(abs(`Mesh Tests`.length(normal) - 1) < 1e-15)
                (0..<3).forEach { axis in
                    #expect(abs(normal[axis] - (vertex[axis] == 1 ? third : -third)) < 1e-15)
                }
            }
        }

        @Test
        func `Vertex normals weigh each corner by its edges' cross product over their squared lengths`() throws {
            let mesh = try Mesh<Position>(
                vertices: [
                    Point(x: 0, y: 0, z: 0), Point(x: 3, y: 0, z: 0), Point(x: 0, y: 3, z: 0),
                    Point(x: 0, y: 0, z: 1), Point(x: 0, y: 1, z: 0),
                ],
                faces: [Polygon(0, 1, 2), Polygon(0, 4, 3)]
            )
            // (3, 0, 0) × (0, 3, 0) / 81 = (0, 0, 1/9) and (0, 1, 0) × (0, 0, 1) / 1 = (1, 0, 0).
            let normal = mesh.normals(per: .vertex)[0]
            let length = (1 + 1.0 / 81).squareRoot()
            #expect(abs(normal.x - 1 / length) < 1e-15)
            #expect(normal.y == 0)
            #expect(abs(normal.z - 1.0 / 9 / length) < 1e-15)
        }

        @Test
        func `Degenerate faces and unused vertices have the zero normal`() throws {
            let mesh = try Mesh<Position>(
                vertices: [
                    Point(x: 0, y: 0, z: 0), Point(x: 1, y: 1, z: 1), Point(x: 2, y: 2, z: 2), Point(x: 9, y: 9, z: 9),
                ],
                faces: [Polygon(0, 1, 2), Polygon(1, 1, 1)]
            )
            #expect(mesh.normals(per: .face) == [.zero, .zero])
            #expect(mesh.normals(per: .vertex) == [.zero, .zero, .zero, .zero])
            #expect(Mesh<Position>.empty.normals(per: .face).isEmpty)
        }

        @Test
        func `Normals do not depend on where the mesh sits`() throws {
            let cube = try `Mesh Tests`.cube()
            let moved = cube.map { Point(x: $0.x + 1024, y: $0.y - 4096, z: $0.z + 65536) }
            #expect(moved.normals(per: .face) == cube.normals(per: .face))
            #expect(moved.areas() == cube.areas())
        }
    }
}

extension `Mesh Tests` {
    @Suite
    struct `Mesh surface contracts` {
        private struct Cell: Hashable {
            let column: Ordinal
            let row: Ordinal
        }

        @Test
        func `An open grid has one more line of vertices than cells in each direction`() {
            let grid = Mesh(columns: 3, rows: 2) { column, row in Cell(column: column, row: row) }
            #expect(grid.vertices.count == 4 * 3)
            #expect(grid.faces.count == 3 * 2)
            #expect(grid.vertices[0] == Cell(column: 0, row: 0))
            #expect(grid.vertices[1] == Cell(column: 1, row: 0))
            #expect(grid.vertices[4] == Cell(column: 0, row: 1))
            #expect(
                grid.polygon(at: 4).vertices == [
                    Cell(column: 1, row: 1), Cell(column: 2, row: 1), Cell(column: 2, row: 2), Cell(column: 1, row: 2),
                ]
            )
            #expect(`Mesh Tests`.characteristic(grid) == 1)
            let single = Mesh(columns: 1, rows: 1) { column, row in Cell(column: column, row: row) }
            #expect(single.faces.map(\.vertices) == [[0, 1, 3, 2]])
        }

        @Test
        func `Closing a direction joins its last line of cells to its first`() {
            let tube = Mesh(columns: 4, rows: 2, seams: (.closed, .open)) { column, row in
                Cell(column: column, row: row)
            }
            #expect(tube.vertices.count == 4 * 3)
            #expect(tube.faces.count == 8)
            #expect(tube.faces[3].vertices == [3, 0, 4, 7])
            #expect(`Mesh Tests`.characteristic(tube) == 0)
            #expect(!`Mesh Tests`.isClosed(tube))

            let band = Mesh(columns: 2, rows: 3, seams: (.open, .closed)) { column, row in
                Cell(column: column, row: row)
            }
            #expect(band.vertices.count == 3 * 3)
            #expect(band.faces[4].vertices == [6, 7, 1, 0])

            let closed = Mesh(columns: 4, rows: 3, seams: (.closed, .closed)) { column, row in
                Cell(column: column, row: row)
            }
            #expect(closed.vertices.count == 12)
            #expect(closed.faces.count == 12)
            #expect(`Mesh Tests`.isClosed(closed))
            #expect(`Mesh Tests`.characteristic(closed) == 0)
        }

        @Test
        func `A grid visits its vertices row by row and stops on typed failure`() {
            struct Failure: Swift::Error, Equatable {}
            var visited: [Cell] = []
            func vertex(_ column: Ordinal, _ row: Ordinal) throws(Failure) -> Cell {
                visited.append(Cell(column: column, row: row))
                if row == 1 { throw Failure() }
                return Cell(column: column, row: row)
            }
            #expect(throws: Failure()) { try Mesh(columns: 2, rows: 2, vertex: vertex) }
            #expect(visited.map(\.row) == [0, 0, 0, 1])
            #expect(visited.map(\.column) == [0, 1, 2, 0])
        }

        @Test(arguments: [(3, 3), (8, 5), (24, 12)] as [(Cardinal, Cardinal)])
        func `A torus is a closed surface of genus one around the z axis`(segments: Cardinal, sides: Cardinal) {
            let torus = Mesh<Position>.torus(major: 3, minor: 1, segments: segments, sides: sides)
            let count = Int(bitPattern: segments) * Int(bitPattern: sides)
            #expect(torus.vertices.count == count)
            #expect(torus.faces.count == count)
            #expect(torus.faces.allSatisfy { $0.vertexCount == 4 })
            #expect(`Mesh Tests`.isClosed(torus))
            #expect(`Mesh Tests`.characteristic(torus) == 0)
            #expect(torus.vertices[0] == Point(x: 4, y: 0, z: 0))
            let normals = torus.normals(per: .vertex)
            for (vertex, normal) in zip(torus.vertices, normals) {
                let radial = (vertex.x * vertex.x + vertex.y * vertex.y).squareRoot()
                let fromCircle = Vector<3, Double>(
                    x: vertex.x - 3 * vertex.x / radial,
                    y: vertex.y - 3 * vertex.y / radial,
                    z: vertex.z
                )
                #expect(abs(`Mesh Tests`.length(fromCircle) - 1) < 1e-12)
                #expect(abs(`Mesh Tests`.length(normal) - 1) < 1e-12)
                #expect(normal.dot(fromCircle) > 0.5)
            }
            for (face, normal) in zip(`Mesh Tests`.faces(torus), torus.normals(per: .face)) {
                let corner = torus.polygon(at: face).vertices[0]
                let radial = (corner.x * corner.x + corner.y * corner.y).squareRoot()
                let outward = Vector<3, Double>(
                    x: corner.x - 3 * corner.x / radial,
                    y: corner.y - 3 * corner.y / radial,
                    z: corner.z
                )
                #expect(normal.dot(outward) > 0)
            }
        }

        @Test(arguments: [(3, 2), (4, 3), (16, 8), (32, 16)] as [(Cardinal, Cardinal)])
        func `A sphere is a closed surface of genus zero with one vertex at each pole`(
            meridians: Cardinal,
            parallels: Cardinal
        ) {
            let sphere = Mesh<Position>.sphere(radius: 2, meridians: meridians, parallels: parallels)
            let around = Int(bitPattern: meridians)
            let bands = Int(bitPattern: parallels)
            #expect(sphere.vertices.count == around * (bands - 1) + 2)
            #expect(sphere.faces.count == around * bands)
            #expect(sphere.faces.count { $0.vertexCount == 3 } == 2 * around)
            #expect(`Mesh Tests`.isClosed(sphere))
            #expect(`Mesh Tests`.characteristic(sphere) == 2)
            #expect(sphere.vertices.first == Point(x: 0, y: 0, z: -2))
            #expect(sphere.vertices.last == Point(x: 0, y: 0, z: 2))
            for (vertex, normal) in zip(sphere.vertices, sphere.normals(per: .vertex)) {
                #expect(abs(`Mesh Tests`.length(vertex.coordinates) - 2) < 1e-12)
                #expect(normal.dot(vertex.coordinates) > 0)
            }
            for (face, normal) in zip(`Mesh Tests`.faces(sphere), sphere.normals(per: .face)) {
                #expect(abs(`Mesh Tests`.length(normal) - 1) < 1e-12)
                for corner in sphere.polygon(at: face).vertices { #expect(normal.dot(corner.coordinates) > 0) }
            }
        }
    }
}

extension `Mesh Tests` {
    @Suite
    struct `Mesh Bezier patch contracts` {
        private func mix(_ a: Position, _ b: Position, _ t: Double) -> Position {
            Point(
                x: a.x * (1 - t) + b.x * t,
                y: a.y * (1 - t) + b.y * t,
                z: a.z * (1 - t) + b.z * t
            )
        }

        /// A bicubic patch over the square from `x` to `x + 3`, bulging in z.
        private func patch(from x: Double) throws -> Bezier<Position>.Patch {
            try Bezier<Position>.Patch(
                controlPoints: (0..<4).map { row in
                    (0..<4).map { column in
                        let inside = (1...2).contains(row) && (1...2).contains(column)
                        return Point(x: x + Double(column), y: Double(row), z: inside ? 2 : 0)
                    }
                }
            )
        }

        @Test
        func `A patch becomes an open grid whose vertices are the patch's values`() throws {
            let patch = try patch(from: 0)
            let mesh = Mesh(patch, columns: 4, rows: 2, interpolating: mix)
            #expect(mesh.vertices.count == 5 * 3)
            #expect(mesh.faces.count == 8)
            #expect(mesh.faces[0].vertices == [0, 1, 6, 5])
            #expect(mesh.faces[7].vertices == [8, 9, 14, 13])
            (0...2).forEach { row in
                (0...4).forEach { column in
                    let value = patch.value(at: Double(column) / 4, Double(row) / 2, interpolating: mix)
                    #expect(mesh.vertices[row * 5 + column] == value)
                }
            }
        }

        @Test
        func `Corners and boundaries of the mesh lie exactly on the patch's corners and boundary curves`() throws {
            let patch = try patch(from: 0)
            let mesh = Mesh(patch, columns: 6, rows: 6, interpolating: mix)
            #expect(mesh.vertices[0] == Point(x: 0, y: 0, z: 0))
            #expect(mesh.vertices[6] == Point(x: 3, y: 0, z: 0))
            #expect(mesh.vertices[42] == Point(x: 0, y: 3, z: 0))
            #expect(mesh.vertices[48] == Point(x: 3, y: 3, z: 0))
            (0...6).forEach { step in
                let t = Double(step) / 6
                #expect(mesh.vertices[step] == patch.rows[0].value(at: t, interpolating: mix))
                #expect(mesh.vertices[42 + step] == patch.rows[3].value(at: t, interpolating: mix))
                #expect(mesh.vertices[step * 7] == patch.columns[0].value(at: t, interpolating: mix))
                #expect(mesh.vertices[step * 7 + 6] == patch.columns[3].value(at: t, interpolating: mix))
            }
        }

        @Test
        func `The mesh faces the side from which u then v turn counterclockwise`() throws {
            let mesh = Mesh(try patch(from: 0), columns: 5, rows: 5, interpolating: mix)
            for normal in mesh.normals(per: .face) { #expect(normal.z > 0.5) }
        }

        @Test
        func `Patches that share an edge weld into one surface, as a consumer's patch data would`() throws {
            let left = Mesh(try patch(from: 0), columns: 4, rows: 4, interpolating: mix)
            let right = Mesh(try patch(from: 3), columns: 4, rows: 4, interpolating: mix)
            let both = left.appending(right)
            #expect(both.vertices.count == 50)
            let welded = both.welded
            #expect(welded.vertices.count == 45)
            #expect(welded.faces.count == 32)
            #expect(`Mesh Tests`.characteristic(welded) == 1)
            let seam = welded.normals(per: .vertex)[4 + 2 * 5]
            #expect(seam.x == 0)
            #expect(seam.z > 0.9)
        }

        @Test
        func `Tessellation propagates the interpolation error`() throws {
            struct Failure: Swift::Error, Equatable {}
            let patch = try patch(from: 0)
            func fail(_ a: Position, _ b: Position, _ t: Double) throws(Failure) -> Position { throw Failure() }
            #expect(throws: Failure()) { try Mesh(patch, columns: 2, rows: 2, interpolating: fail) }
        }
    }
}

extension `Mesh Tests` {
    @Suite
    struct `Mesh teapot contracts` {
        /// The faces of the patches in a range, of a teapot cut `divisions` times along each side of a patch.
        private func faces(of patches: Range<Int>, divisions: Int) -> Range<Int> {
            (patches.lowerBound * divisions * divisions)..<(patches.upperBound * divisions * divisions)
        }

        private func centre(_ polygon: Polygon<Position>) -> Vector<3, Double> {
            var sum = Vector<3, Double>(repeating: 0)
            for corner in polygon.vertices { sum += corner.coordinates }
            return sum.scaled(by: 1 / Double(polygon.vertices.count))
        }

        @Test(arguments: [1, 4, 9] as [Cardinal])
        func `Thirty-two patches, each a grid of its own`(divisions: Cardinal) {
            let teapot = Mesh<Position>.teapot(divisions: divisions)
            let cells = Int(bitPattern: divisions)
            #expect(teapot.vertices.count == 32 * (cells + 1) * (cells + 1))
            #expect(teapot.faces.count == 32 * cells * cells)
            #expect(teapot.faces.allSatisfy { $0.vertices.count == 4 })
        }

        @Test
        func `It stands on z = 0, is 3.15 high and reaches from the handle at x = -3 to the spout`() {
            let teapot = Mesh<Position>.teapot(divisions: 8)
            let xs = teapot.vertices.map(\.x)
            let ys = teapot.vertices.map(\.y)
            let zs = teapot.vertices.map(\.z)
            #expect(zs.min() == 0)
            #expect(zs.max() == 3.15)
            #expect(xs.min() == -3)
            #expect((xs.max() ?? 0) > 3.3 && (xs.max() ?? 0) < 3.525)
            #expect(ys.min() == -2 && ys.max() == 2)
        }

        @Test
        func `The corners of Newell's patches are vertices`() {
            let teapot = Mesh<Position>.teapot(divisions: 3)
            let vertices = Set(teapot.vertices)
            let corners: [Position] = [
                Point(x: 0, y: 0, z: 3.15), Point(x: 0, y: 0, z: 0), Point(x: 1.4, y: 0, z: 2.4), Point(x: 0, y: -1.5, z: 2.4),
                Point(x: -2, y: 0, z: 0.9), Point(x: 0, y: 1.5, z: 0.15), Point(x: 0.2, y: 0, z: 2.7), Point(x: 0, y: 1.3, z: 2.4),
                Point(x: -1.6, y: 0, z: 2.025), Point(x: -3, y: 0, z: 1.8), Point(x: -1.9, y: 0, z: 0.6),
                Point(x: 1.7, y: 0, z: 1.425), Point(x: 1.7, y: 0, z: 0.6), Point(x: 3.3, y: 0, z: 2.4), Point(x: 2.8, y: 0, z: 2.4),
                Point(x: 3.2, y: 0, z: 2.4),
            ]
            for corner in corners { #expect(vertices.contains(corner)) }
        }

        @Test
        func `Turning y into -y maps the teapot onto itself`() {
            let teapot = Mesh<Position>.teapot(divisions: 5)
            for vertex in teapot.vertices {
                let mirrored = teapot.vertices.contains { other in
                    abs(other.x - vertex.x) < 1e-12 && abs(other.y + vertex.y) < 1e-12 && abs(other.z - vertex.z) < 1e-12
                }
                #expect(mirrored)
            }
        }

        @Test
        func `The body and the lid face away from the axis, the cover up and the bottom down`() {
            let divisions = 6
            let teapot = Mesh<Position>.teapot(divisions: 6)
            let normals: [Vector<3, Double>] = teapot.normals(per: .face)
            for face in faces(of: 4..<12, divisions: divisions) {
                let centre = centre(teapot.polygon(at: `Mesh Tests`.faces(teapot)[face]))
                #expect(normals[face].x * centre.x + normals[face].y * centre.y > 0)
            }
            for face in faces(of: 24..<28, divisions: divisions) { #expect(normals[face].z > 0) }
            for face in faces(of: 28..<32, divisions: divisions) { #expect(normals[face].z < 0) }
        }

        @Test
        func `The handle and the spout face away from the plane y = 0, each half the mirror image of the other`() {
            let divisions = 6
            let teapot = Mesh<Position>.teapot(divisions: 6)
            let areas: [Vector<3, Double>] = teapot.areas()
            for face in faces(of: 12..<18, divisions: divisions) {
                let centre = centre(teapot.polygon(at: `Mesh Tests`.faces(teapot)[face]))
                #expect(areas[face].y * centre.y > 0)
            }
            for pair in [12, 14, 16, 18] {
                var near = Vector<3, Double>(repeating: 0)
                var far = Vector<3, Double>(repeating: 0)
                for face in faces(of: pair..<(pair + 1), divisions: divisions) { near += areas[face] }
                for face in faces(of: (pair + 1)..<(pair + 2), divisions: divisions) { far += areas[face] }
                #expect(near.y < 0)
                #expect(abs(near.x - far.x) < 1e-9 && abs(near.y + far.y) < 1e-9 && abs(near.z - far.z) < 1e-9)
            }
        }
    }
}

extension `Mesh Tests` {
    @Suite
    struct `Mesh box contracts` {
        private let box = Mesh<Position>.box(lower: Point(x: -1, y: 2, z: 0.5), upper: Point(x: 3, y: 2.5, z: 4))

        @Test
        func `Eight corners in binary order, x changing first`() {
            #expect(box.vertices.count == 8)
            #expect(box.vertices.first == Point(x: -1, y: 2, z: 0.5))
            #expect(box.vertices[1] == Point(x: 3, y: 2, z: 0.5))
            #expect(box.vertices[2] == Point(x: -1, y: 2.5, z: 0.5))
            #expect(box.vertices[4] == Point(x: -1, y: 2, z: 4))
            #expect(box.vertices.last == Point(x: 3, y: 2.5, z: 4))
            #expect(Set(box.vertices).count == 8)
        }

        @Test
        func `Six quads, closed, of genus zero, with twelve edges`() {
            #expect(box.faces.count == 6)
            #expect(box.faces.allSatisfy { $0.vertices.count == 4 })
            #expect(`Mesh Tests`.isClosed(box))
            #expect(`Mesh Tests`.characteristic(box) == 2)
            #expect(`Mesh Tests`.edges(box).count == 24)
        }

        @Test
        func `The sides face outward, toward lower and upper x, y and z in that order`() {
            let expected: [Vector<3, Double>] = [
                Vector([-1, 0, 0]), Vector([1, 0, 0]), Vector([0, -1, 0]), Vector([0, 1, 0]), Vector([0, 0, -1]), Vector([0, 0, 1]),
            ]
            #expect(box.normals(per: .face) == expected)
            let areas: [Vector<3, Double>] = box.areas()
            #expect(areas.map { `Mesh Tests`.length($0) } == [1.75, 1.75, 14, 14, 2, 2])
        }

        @Test
        func `Corners given the other way round turn the box inside out`() {
            let turned = Mesh<Position>.box(lower: Point(x: 3, y: 2.5, z: 4), upper: Point(x: -1, y: 2, z: 0.5))
            #expect(Set(turned.vertices) == Set(box.vertices))
            #expect(`Mesh Tests`.isClosed(turned))
            let outward: [Vector<3, Double>] = box.normals(per: .face)
            let inward: [Vector<3, Double>] = turned.normals(per: .face)
            #expect(inward == outward)
        }

        @Test
        func `A box with no depth along an axis still has eight vertices and six faces`() {
            let flat = Mesh<Position>.box(lower: Point(x: 0, y: 0, z: 0), upper: Point(x: 1, y: 1, z: 0))
            #expect(flat.vertices.count == 8)
            #expect(flat.faces.count == 6)
            #expect(flat.welded.vertices.count == 4)
        }
    }
}
