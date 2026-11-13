import Mesh
import Testing

private typealias Position = Point<3, Double>
private typealias Sampler = Mesh<Position>.Sampler<Double>

private struct Mixer {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) * 0x1p-53 }

    mutating func location(on sampler: Sampler) -> Sampler.Location {
        let (u, v, w) = (unit(), unit(), unit())
        return sampler.location(u, v, w)
    }
}

private func at(_ x: Double, _ y: Double, _ z: Double) -> Position { Position(coordinates: Vector(x: x, y: y, z: z)) }

@Suite
struct `Mesh.Sampler Tests` {
    @Test
    func `The first coordinate picks a fanned triangle by area, the other two place it there`() throws {
        let mesh = try Mesh(vertices: [at(0, 0, 0), at(1, 0, 0), at(1, 1, 0), at(0, 1, 0)], faces: [Polygon(0, 1, 2, 3)])
        let sampler = try #require(Sampler(mesh))
        #expect(sampler.area == 1)
        let near = sampler.location(0.25, 0.25, 0.5)
        #expect(Int(bitPattern: near.face) == 0 && near.weights == [0.25, 0.25, 0.5, 0])
        let far = sampler.location(0.75, 0.75, 0.5)
        #expect(far.weights == [0.25, 0, 0.25, 0.5])
        let position = sampler.position(of: far)
        #expect(position.x == 0.25 && position.y == 0.75 && position.z == 0)
        #expect(sampler.location(-3, 2, -1).weights == sampler.location(0, 1, 0).weights)
    }

    @Test
    func `Evenly spread points give evenly spread places, also on a face that is no parallelogram`() throws {
        let mesh = try Mesh(vertices: [at(0, 0, 0), at(4, 0, 0), at(3, 1, 0), at(1, 1, 0)], faces: [Polygon(0, 1, 2, 3)])
        let sampler = try #require(Sampler(mesh))
        #expect(sampler.area == 3)
        var generator = Mixer(state: 1)
        let draws = 60_000
        var left = 0
        for _ in 0..<draws where sampler.position(of: generator.location(on: sampler)).x < 2 { left += 1 }
        #expect(abs(Double(left) / Double(draws) - 0.5) < 0.01)
        var low = 0
        for _ in 0..<draws where sampler.position(of: generator.location(on: sampler)).y < 0.5 { low += 1 }
        #expect(abs(Double(low) / Double(draws) - 1.75 / 3) < 0.01)
    }

    @Test
    func `Faces are drawn in proportion to their area`() throws {
        let mesh = try Mesh(
            vertices: [at(0, 0, 0), at(1, 0, 0), at(0, 2, 0), at(5, 0, 0), at(8, 0, 0), at(5, 2, 0)],
            faces: [Polygon(0, 1, 2), Polygon(3, 4, 5)]
        )
        let sampler = try #require(Sampler(mesh))
        let steps = 1000
        let first = (0..<steps).filter { step in
            Int(bitPattern: sampler.location((Double(step) + 0.5) / Double(steps), 0, 0).face) == 0
        }
        #expect(first.count == 250)
    }

    @Test
    func `A place on a triangle lies inside it, with weights that add up to one`() throws {
        let mesh = try Mesh(vertices: [at(0, 0, 0), at(4, 0, 0), at(0, 4, 0)], faces: [Polygon(0, 1, 2)])
        let sampler = try #require(Sampler(mesh))
        var generator = Mixer(state: 3)
        for _ in 0..<2000 {
            let location = generator.location(on: sampler)
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
        #expect(abs(sampler.area - 7) < 1e-12)
        var generator = Mixer(state: 11)
        var counts = [0, 0, 0, 0]
        let draws = 30_000
        for _ in 0..<draws {
            let location = generator.location(on: sampler)
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
            let location = generator.location(on: sampler)
            let normal = sampler.interpolate(normals, at: location)
            let place = sampler.position(of: location).coordinates
            #expect(normal.dot(place) > 0)
            let positions = mesh.vertices.map(\.coordinates)
            let interpolated = sampler.interpolate(positions, at: location)
            #expect(interpolated.x == place.x && interpolated.y == place.y && interpolated.z == place.z)
        }
    }

    @Test
    func `A mesh without area has no sampler`() throws {
        #expect(Sampler(.empty) == nil)
        let flat = try Mesh(vertices: [at(0, 0, 0), at(1, 0, 0), at(2, 0, 0)], faces: [Polygon(0, 1, 2)])
        #expect(Sampler(flat) == nil)
    }
}
