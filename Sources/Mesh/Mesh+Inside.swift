extension Mesh {

    /// Quadrilaterals filling a planar outline drawn from Bézier curves, such as a soundboard's, laid out as
    /// `disk(radius:cells:)` is and carried onto the outline along rays from `centre`.
    ///
    /// The outline is the curves in turn, each ending exactly where the next starts and the last where the first
    /// starts; it may run either way round. Every ray from `centre` must cross it once: the outline is seen whole
    /// from there, as a disk, an ellipse, a lute's or a guitar's outline is from a point near its middle. A vertex
    /// v of the unit disk with `cells` becomes the point a share |v| of the way from `centre` to where the ray
    /// through v crosses the outline, found on the curve itself by halving. The vertices of the unit disk's outline
    /// become those crossings, so the mesh's outline vertices lie on the curves. The mesh therefore has the disk's
    /// faces, 5 `cells`², all counterclockwise, and its outline is 4 `cells` edges, and an outline that is a circle
    /// about `centre` gives `disk(radius:cells:)` moved to `centre`, up to rounding.
    ///
    /// It fails with `.openOutline` for no curves or a gap between two, with `.outlineNotStarShaped` when, at 64
    /// points along each curve, the outline does not turn steadily once around `centre`, and with `.folded` when a
    /// face would turn over or have no area, as a coarse mesh can where the outline bends sharply.
    @inlinable
    public init<Scalar: BinaryFloatingPoint>(
        inside outline: [Bezier<Point<2, Scalar>>],
        around centre: Point<2, Scalar>,
        cells: Cardinal
    ) throws(Error) where Vertex == Point<2, Scalar> {
        let star = try Star(outline, around: centre)
        let unit = Self.disk(radius: 1, cells: cells)
        let rim = Set(unit.outline.map { Int(bitPattern: $0.start) })
        var vertices: [Vertex] = []
        vertices.reserveCapacity(unit.vertices.count)
        for (index, vertex) in unit.vertices.enumerated() {
            vertices.append(try star.carry(vertex.x, vertex.y, onto: rim.contains(index)))
        }
        for face in unit.faces {
            let corners = face.vertices.map { vertices[$0] }
            var twice: Scalar = 0
            for (index, corner) in corners.enumerated() {
                let next = corners[(index + 1) % corners.count]
                twice += corner.x * next.y - next.x * corner.y
            }
            guard twice > 0 else { throw .folded }
        }
        self.init(validated: vertices, faces: unit.faces)
    }
}

extension Mesh {

    /// A closed outline seen whole from a centre, and where each ray from the centre crosses it.
    @usableFromInline
    internal struct Star<Scalar: BinaryFloatingPoint> {
        @usableFromInline let curves: [Bezier<Plane>]
        @usableFromInline let centre: Plane
        @usableFromInline let walk: [Step]

        @inlinable
        init(_ outline: [Bezier<Plane>], around centre: Plane) throws(Error) {
            guard !outline.isEmpty,
                zip(outline, outline.dropFirst() + outline.prefix(1)).allSatisfy({ $0.end == $1.start })
            else { throw .openOutline }
            var curves = outline
            var walk = Self.steps(curves, around: centre)
            let area = walk.reduce(Scalar(0)) { $0 + Self.cross($1.from, $1.to) }
            guard area.isFinite, area != 0 else { throw .outlineNotStarShaped }
            if area < 0 {
                curves = curves.reversed().map { $0.reversed }
                walk = Self.steps(curves, around: centre)
            }
            // WHY: seen whole, every step turns counterclockwise about the centre, and one step crosses the ray along +x
            guard walk.allSatisfy({ Self.cross($0.from, $0.to) > 0 }),
                walk.filter({ step in
                    step.from.y < 0 && step.to.y >= 0
                        && step.from.x + (step.to.x - step.from.x) * (-step.from.y / (step.to.y - step.from.y)) > 0
                }).count == 1
            else { throw .outlineNotStarShaped }
            self.curves = curves
            self.centre = centre
            self.walk = walk
        }
    }
}

extension Mesh.Star {
    @usableFromInline typealias Plane = Point<2, Scalar>
    @usableFromInline typealias Offset = (x: Scalar, y: Scalar)
    @usableFromInline typealias Step = (curve: Int, step: Int, from: Offset, to: Offset)

    @usableFromInline static var samples: Int { 64 }

    @inlinable
    static func point(_ curve: Bezier<Plane>, _ parameter: Scalar) -> Plane {
        curve.value(at: parameter) { $0.interpolated(to: $1, at: $2) }
    }

    @inlinable
    static func cross(_ a: Offset, _ b: Offset) -> Scalar { a.x * b.y - a.y * b.x }

    // WHY: steps as a list, not a walk taking a typed-throws closure: SILGen crash, swift-institute/Issues#340
    @inlinable
    static func steps(_ curves: [Bezier<Plane>], around centre: Plane) -> [Step] {
        curves.enumerated().flatMap { curve, bezier in
            let row = (0...samples).map { index in
                let point = point(bezier, Scalar(index) / Scalar(samples))
                return (x: point.x - centre.x, y: point.y - centre.y)
            }
            return zip(row, row.dropFirst()).enumerated().map { step, pair in
                (curve: curve, step: step, from: pair.0, to: pair.1)
            }
        }
    }

    /// Where the ray from the centre along `direction` crosses the outline: on the one step at which the cross
    /// product with the direction turns from not positive to positive, refined on its curve by halving.
    @inlinable
    func crossing(_ direction: Offset) throws(Mesh.Error) -> Plane {
        func offset(_ point: Plane) -> Offset { (point.x - centre.x, point.y - centre.y) }
        guard
            let found = walk.first(where: {
                Self.cross(direction, $0.from) <= 0 && Self.cross(direction, $0.to) > 0
            })
        else { throw .outlineNotStarShaped }
        var lower = Scalar(found.step) / Scalar(Self.samples)
        var upper = Scalar(found.step + 1) / Scalar(Self.samples)
        while true {
            let middle = (lower + upper) / 2
            guard middle > lower, middle < upper else { break }
            if Self.cross(direction, offset(Self.point(curves[found.curve], middle))) <= 0 {
                lower = middle
            } else {
                upper = middle
            }
        }
        return Self.point(curves[found.curve], lower)
    }

    /// The point (x, y) of the unit disk carried onto the outline: a share |(x, y)| of the way from the centre
    /// to where the ray through it crosses the outline, or that crossing itself when `rim`.
    @inlinable
    func carry(_ x: Scalar, _ y: Scalar, onto rim: Bool) throws(Mesh.Error) -> Plane {
        let share = (x * x + y * y).squareRoot()
        guard share > 0 else { return centre }
        let edge = try crossing((x, y))
        guard !rim else { return edge }
        return Point(
            x: centre.x + share * (edge.x - centre.x),
            y: centre.y + share * (edge.y - centre.y)
        )
    }
}
