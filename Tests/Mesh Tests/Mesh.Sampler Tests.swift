import Mesh
import Testing

private typealias Position = Point<3, Double>
private typealias Sampler = Mesh<Position>.Sampler<Double>

private struct Mixer: Swift.RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func at(_ x: Double, _ y: Double, _ z: Double) -> Position { Position(coordinates: Vector(x: x, y: y, z: z)) }

@Suite
struct `Mesh.Sampler Tests` {
    @Test
    func `A location is a face drawn by area and a place on it from the next two unit draws`() throws {
        let mesh = Mesh<Position>.teapot(divisions: 4)
        let sampler = try #require(Sampler(mesh))
        var generator = Mixer(state: 7)
        var copy = generator
        var running: [Double] = []
        var total = 0.0
        for area in mesh.areas() as [Vector<3, Double>] {
            total += (area.x * area.x + area.y * area.y + area.z * area.z).squareRoot()
            running.append(total)
        }
        #expect(sampler.running == running && sampler.area == total)
        for _ in 0..<500 {
            let lot = copy.unit() * total
            let face = try #require(running.firstIndex { $0 >= lot })
            let (u, v) = (copy.unit(), copy.unit())
            let location = sampler.location(using: &generator)
            #expect(Int(bitPattern: location.face) == face)
            #expect(location.weights == [(1 - u) * (1 - v), u * (1 - v), u * v, (1 - u) * v])
            var place = (x: 0.0, y: 0.0, z: 0.0)
            for (corner, weight) in zip(mesh.faces[face].vertices, location.weights) {
                let c = mesh.vertices[corner].coordinates
                place = (place.x + weight * c.x, place.y + weight * c.y, place.z + weight * c.z)
            }
            let position = sampler.position(of: location)
            #expect(position.x == place.x && position.y == place.y && position.z == place.z)
        }
        #expect(generator.state == copy.state)
    }

    @Test
    func `Faces are drawn in proportion to their area`() throws {
        let mesh = try Mesh(
            vertices: [at(0, 0, 0), at(1, 0, 0), at(0, 2, 0), at(5, 0, 0), at(8, 0, 0), at(5, 2, 0)],
            faces: [Polygon(0, 1, 2), Polygon(3, 4, 5)]
        )
        let sampler = try #require(Sampler(mesh))
        var generator = Mixer(state: 1)
        var first = 0
        let draws = 40_000
        for _ in 0..<draws where Int(bitPattern: sampler.location(using: &generator).face) == 0 { first += 1 }
        #expect(abs(Double(first) / Double(draws) - 0.25) < 0.01)
    }

    @Test
    func `A place on a triangle lies inside it, with weights that add up to one`() throws {
        let mesh = try Mesh(vertices: [at(0, 0, 0), at(4, 0, 0), at(0, 4, 0)], faces: [Polygon(0, 1, 2)])
        let sampler = try #require(Sampler(mesh))
        var generator = Mixer(state: 3)
        for _ in 0..<2000 {
            let location = sampler.location(using: &generator)
            #expect(location.weights.allSatisfy { $0 >= 0 })
            #expect(abs(location.weights.reduce(0, +) - 1) < 1e-12)
            let place = sampler.position(of: location)
            #expect(place.x >= 0 && place.y >= 0 && place.x + place.y <= 4 + 1e-12 && place.z == 0)
        }
    }

    @Test
    func `A larger face is fanned from its first vertex, each triangle by its area`() throws {
        let mesh = try Mesh(
            vertices: [at(0, 0, 0), at(1, 0, 0), at(1, 1, 0), at(-2, 4, 0), at(-2, 0.5, 0)],
            faces: [Polygon(0, 1, 2, 3, 4)]
        )
        let sampler = try #require(Sampler(mesh))
        var generator = Mixer(state: 11)
        var counts = [0, 0, 0, 0]
        let draws = 30_000
        for _ in 0..<draws {
            let location = sampler.location(using: &generator)
            let used = location.weights.indices.filter { $0 > 0 && location.weights[$0] > 0 }
            let triangle = try #require(used.first)
            #expect(used.allSatisfy { $0 == triangle || $0 == triangle + 1 })
            #expect(abs(location.weights.reduce(0, +) - 1) < 1e-12)
            counts[triangle] += 1
        }
        let areas = [0.5, 3.0, 3.5]
        let total = areas.reduce(0, +)
        for (offset, area) in areas.enumerated() {
            #expect(abs(Double(counts[offset + 1]) / Double(draws) - area / total) < 0.015)
        }
    }

    @Test
    func `Values given per vertex are interpolated with the weights`() throws {
        let mesh = Mesh<Position>.sphere(radius: 2, meridians: 12, parallels: 8)
        let sampler = try #require(Sampler(mesh))
        let normals: [Vector<3, Double>] = mesh.normals(per: .vertex)
        var generator = Mixer(state: 5)
        for _ in 0..<200 {
            let location = sampler.location(using: &generator)
            let normal = sampler.interpolate(normals, at: location)
            let place = sampler.position(of: location).coordinates
            #expect(normal.dot(place) > 0)
        }
    }

    @Test
    func `A mesh without area has no sampler`() throws {
        #expect(Sampler(.empty) == nil)
        let flat = try Mesh(vertices: [at(0, 0, 0), at(1, 0, 0), at(2, 0, 0)], faces: [Polygon(0, 1, 2)])
        #expect(Sampler(flat) == nil)
    }
}
