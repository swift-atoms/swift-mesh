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
        typealias Plane = Point<2, Scalar>
        typealias Offset = (x: Scalar, y: Scalar)
        typealias Step = (curve: Int, step: Int, from: Offset, to: Offset)

        guard !outline.isEmpty,
            zip(outline, outline.dropFirst() + outline.prefix(1)).allSatisfy({ $0.end == $1.start })
        else { throw .openOutline }

        func point(_ curve: Bezier<Plane>, _ parameter: Scalar) -> Plane {
            curve.value(at: parameter) { $0.interpolated(to: $1, at: $2) }
        }
        func offset(_ point: Plane) -> Offset { (point.x - centre.x, point.y - centre.y) }
        func cross(_ a: Offset, _ b: Offset) -> Scalar { a.x * b.y - a.y * b.x }

        // WHY: steps as a list, not a walk taking a typed-throws closure: SILGen crash, swift-institute/Issues#340
        let samples = 64
        func steps(_ curves: [Bezier<Plane>]) -> [Step] {
            curves.enumerated().flatMap { curve, bezier in
                let row = (0...samples).map { offset(point(bezier, Scalar($0) / Scalar(samples))) }
                return zip(row, row.dropFirst()).enumerated().map { step, pair in
                    (curve: curve, step: step, from: pair.0, to: pair.1)
                }
            }
        }
        var curves = outline
        var walk = steps(curves)
        let area = walk.reduce(Scalar(0)) { $0 + cross($1.from, $1.to) }
        guard area.isFinite, area != 0 else { throw .outlineNotStarShaped }
        if area < 0 {
            curves = curves.reversed().map(\.reversed)
            walk = steps(curves)
        }

        // WHY: seen whole, every step turns counterclockwise about the centre, and one step crosses the ray along +x
        guard walk.allSatisfy({ cross($0.from, $0.to) > 0 }),
            walk.filter({ step in
                step.from.y < 0 && step.to.y >= 0
                    && step.from.x + (step.to.x - step.from.x) * (-step.from.y / (step.to.y - step.from.y)) > 0
            }).count == 1
        else { throw .outlineNotStarShaped }

        /// Where the ray from the centre along `direction` crosses the outline: on the one step at which the cross
        /// product with the direction turns from not positive to positive, refined on its curve by halving.
        func crossing(_ direction: Offset) throws(Error) -> Plane {
            guard let found = walk.first(where: { cross(direction, $0.from) <= 0 && cross(direction, $0.to) > 0 })
            else { throw .outlineNotStarShaped }
            var lower = Scalar(found.step) / Scalar(samples)
            var upper = Scalar(found.step + 1) / Scalar(samples)
            while true {
                let middle = (lower + upper) / 2
                guard middle > lower, middle < upper else { break }
                if cross(direction, offset(point(curves[found.curve], middle))) <= 0 {
                    lower = middle
                } else {
                    upper = middle
                }
            }
            return point(curves[found.curve], lower)
        }

        let unit = Self.disk(radius: 1, cells: cells)
        let rim = Set(unit.outline.map { Int(bitPattern: $0.start) })
        var vertices: [Plane] = []
        vertices.reserveCapacity(unit.vertices.count)
        for (index, vertex) in unit.vertices.enumerated() {
            let share = (vertex.x * vertex.x + vertex.y * vertex.y).squareRoot()
            guard share > 0 else {
                vertices.append(centre)
                continue
            }
            let edge = try crossing((vertex.x, vertex.y))
            if rim.contains(index) {
                vertices.append(edge)
            } else {
                vertices.append(
                    Point(
                        x: centre.x + share * (edge.x - centre.x),
                        y: centre.y + share * (edge.y - centre.y)
                    )
                )
            }
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
