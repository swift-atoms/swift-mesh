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

        guard !outline.isEmpty,
            outline.indices.allSatisfy({ outline[$0].start == outline[($0 + outline.count - 1) % outline.count].end })
        else { throw .openOutline }

        func point(_ curve: Bezier<Plane>, _ parameter: Scalar) -> Plane {
            curve.value(at: parameter) { $0.interpolated(to: $1, at: $2) }
        }
        func offset(_ point: Plane) -> Offset { (point.x - centre.x, point.y - centre.y) }
        func cross(_ a: Offset, _ b: Offset) -> Scalar { a.x * b.y - a.y * b.x }

        let samples = 64
        func sampled(_ curves: [Bezier<Plane>]) -> [[Plane]] {
            curves.map { curve in (0...samples).map { point(curve, Scalar($0) / Scalar(samples)) } }
        }
        var curves = outline
        var points = sampled(curves)
        func steps(_ body: (_ curve: Int, _ step: Int, _ from: Offset, _ to: Offset) throws(Error) -> Void)
            throws(Error)
        {
            for (curve, row) in points.enumerated() {
                for step in 0..<samples { try body(curve, step, offset(row[step]), offset(row[step + 1])) }
            }
        }

        var area: Scalar = 0
        try steps { _, _, from, to in area += cross(from, to) }
        guard area.isFinite, area != 0 else { throw .outlineNotStarShaped }
        if area < 0 {
            curves = curves.reversed().map(\.reversed)
            points = sampled(curves)
        }

        // Seen whole: every step turns counterclockwise about the centre, and the steps pass the ray along +x once.
        var turns = 0
        try steps { _, _, from, to throws(Error) in
            guard cross(from, to) > 0 else { throw .outlineNotStarShaped }
            if from.y < 0, to.y >= 0, from.x + (to.x - from.x) * (-from.y / (to.y - from.y)) > 0 { turns += 1 }
        }
        guard turns == 1 else { throw .outlineNotStarShaped }

        /// Where the ray from the centre along `direction` crosses the outline: on the one step at which the cross
        /// product with the direction turns from not positive to positive, refined on its curve by halving.
        func crossing(_ direction: Offset) throws(Error) -> Plane {
            for (curve, row) in points.enumerated() {
                for step in 0..<samples
                where cross(direction, offset(row[step])) <= 0 && cross(direction, offset(row[step + 1])) > 0 {
                    var lower = Scalar(step) / Scalar(samples)
                    var upper = Scalar(step + 1) / Scalar(samples)
                    while true {
                        let middle = (lower + upper) / 2
                        guard middle > lower, middle < upper else { break }
                        if cross(direction, offset(point(curves[curve], middle))) <= 0 {
                            lower = middle
                        } else {
                            upper = middle
                        }
                    }
                    return point(curves[curve], lower)
                }
            }
            throw .outlineNotStarShaped
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
                    Point(x: centre.x + share * (edge.x - centre.x), y: centre.y + share * (edge.y - centre.y)))
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
