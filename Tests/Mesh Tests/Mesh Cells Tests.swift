import Mesh
import Testing

extension `Mesh Tests` {
    @Suite
    struct `Mesh cells contracts` {
        private typealias Position = Point<3, Double>

        /// The box whose sides are cut into cells: 2 deep in x, 3 high in y, 4 wide in z.
        private let box = Mesh<Position>.box(lower: Point(x: 0, y: 0, z: 0), upper: Point(x: 2, y: 3, z: 4))

        /// The side toward lower x: columns run along z, four of them, and rows along y, three of them.
        private var side: Ngon<4, Position> {
            get throws { try Ngon(box.polygon(at: Index(Ordinal(0)))) }
        }

        /// A pattern of cells: none in row 1, and gaps elsewhere.
        private static func chosen(_ column: Ordinal, _ row: Ordinal) -> Bool {
            let (c, r) = (Int(bitPattern: column), Int(bitPattern: row))
            return r != 1 && (c + r) % 3 != 2
        }

        private static let inset = (width: 0.25, height: 0.125)

        private func cells(per span: Mesh<Position>.Span) throws -> Mesh<Position> {
            try Mesh<Position>.cells(on: side, columns: 4, rows: 3, inset: Self.inset, per: span, including: Self.chosen)
        }

        @Test
        func `Each chosen cell gives one quad of four vertices of its own, row by row`() throws {
            var asked: [[Int]] = []
            let mesh = try Mesh<Position>.cells(on: side, columns: 4, rows: 3, inset: Self.inset) { column, row in
                asked.append([Int(bitPattern: column), Int(bitPattern: row)])
                return Self.chosen(column, row)
            }
            #expect(asked == [0, 1, 2].flatMap { row in [0, 1, 2, 3].map { column in [column, row] } })
            let count = asked.filter { Self.chosen(Ordinal(UInt($0[0])), Ordinal(UInt($0[1]))) }.count
            #expect(mesh.faces.count == count)
            #expect(mesh.vertices.count == 4 * count)
            #expect(Set(mesh.faces.flatMap(\.vertices)).count == 4 * count)
            let none = try Mesh<Position>.cells(on: side, columns: 4, rows: 3, inset: Self.inset) { _, _ in false }
            #expect(none == .empty)
        }

        @Test
        func `Every quad lies inside its cell by the inset`() throws {
            let mesh = try cells(per: .cell)
            var expected: [(left: Double, right: Double, lower: Double, upper: Double)] = []
            for row in [0, 1, 2] {
                for column in [0, 1, 2, 3] where Self.chosen(Ordinal(UInt(column)), Ordinal(UInt(row))) {
                    let (c, r) = (Double(column), Double(row))
                    expected.append((left: c + 0.25, right: c + 0.75, lower: r + 0.125, upper: r + 0.875))
                }
            }
            #expect(mesh.faces.count == expected.count)
            zip(mesh.faces, expected).forEach { face, cell in
                let corners = face.vertices.map { mesh.vertices[$0] }
                #expect(corners.allSatisfy { $0.x == 0 })
                #expect(corners.map(\.z) == [cell.left, cell.right, cell.right, cell.left])
                #expect(corners.map(\.y) == [cell.lower, cell.lower, cell.upper, cell.upper])
            }
        }

        @Test
        func `Winding and normals agree with the face on every side of a box`() throws {
            let normals = box.normals(per: .face) as [Vector<3, Double>]
            for (position, normal) in zip(box.faces.indices, normals) {
                let face = try Ngon<4, Position>(box.polygon(at: Index(Ordinal(UInt(position)))))
                for span in Mesh<Position>.Span.allCases {
                    let mesh = Mesh<Position>.cells(on: face, columns: 3, rows: 2, inset: (0.1, 0.2), per: span) { _, _ in true }
                    let quads: [Vector<3, Double>] = mesh.normals(per: .face)
                    #expect(quads.count == (span == .cell ? 6 : 2))
                    for quad in quads {
                        let difference = quad - normal
                        #expect(abs(difference.x) <= 1e-12 && abs(difference.y) <= 1e-12 && abs(difference.z) <= 1e-12)
                    }
                }
            }
        }

        @Test
        func `The strip level covers the same rows from the first chosen cell to the last`() throws {
            let detailed = try cells(per: .cell)
            let strips = try cells(per: .row)
            let rows = Set(detailed.vertices.map { ($0.y - 0.125).rounded(.down) })
            #expect(strips.faces.count == rows.count)
            #expect(strips.vertices.count == 4 * rows.count)
            strips.faces.forEach { face in
                let corners = face.vertices.map { strips.vertices[$0] }
                let row = (corners[0].y - 0.125).rounded(.down)
                let quads = detailed.vertices.filter { ($0.y - 0.125).rounded(.down) == row }
                #expect(corners.map(\.y) == [row + 0.125, row + 0.125, row + 0.875, row + 0.875])
                #expect(corners[0].z == quads.map(\.z).min())
                #expect(corners[1].z == quads.map(\.z).max())
                #expect(corners.allSatisfy { $0.x == 0 })
            }
        }

        @Test
        func `A failing choice stops with its own error`() throws {
            struct Stop: Swift.Error, Equatable {}
            #expect(throws: Stop()) {
                try Mesh<Position>.cells(on: side, columns: 4, rows: 3, inset: Self.inset) { (_, row) throws(Stop) -> Bool in
                    if Int(bitPattern: row) == 2 { throw Stop() }
                    return true
                }
            }
        }
    }
}
