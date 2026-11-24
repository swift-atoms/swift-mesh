extension Mesh {

    /// The disk of `radius` about the origin in the x–y plane, as quadrilaterals that meet exactly at every seam.
    ///
    /// A square of half-side 0.4 `radius` in the middle is cut into `cells` × `cells` quads, and each of the four
    /// regions between a side of the square and the circle into `cells` × `cells` more: each point of the side is
    /// carried outward along its ray from the origin onto the circle, in `cells` equal steps. The five grids are
    /// welded, so the disk has 5 `cells`² faces and 5 `cells`² + 2 `cells` + 1 vertices, and its outline is 4
    /// `cells` edges with their vertices on the circle. Every face is counterclockwise.
    ///
    /// A point j of n along a side sits at (2j − n) / n of the half-side, not at −1 + 2j / n: the first is exact
    /// at both ends and gives j and n − j opposite values exactly, so grids built from mirrored sides meet at
    /// equal vertices, which `welded` joins. The second does not, and leaves cracks. It traps for no cells.
    @inlinable
    public static func disk<Scalar: BinaryFloatingPoint>(
        radius: Scalar,
        cells: Cardinal
    ) -> Self where Vertex == Point<2, Scalar> {
        precondition(cells >= .one, "A disk needs at least one cell")
        let count = Int(bitPattern: cells)
        let half = radius * 2 / 5
        func parameter(_ index: Ordinal) -> Scalar {
            Scalar(2 * Int(bitPattern: index) - count) / Scalar(count)
        }
        var disk = Self(columns: cells, rows: cells) { column, row in
            Point(x: half * parameter(column), y: half * parameter(row))
        }
        // Each side's columns run so that the column direction, then the outward one, turn counterclockwise.
        let sides: [(Scalar) -> (x: Scalar, y: Scalar)] = [
            { t in (half, -(half * t)) },
            { t in (half * t, half) },
            { t in (-half, half * t) },
            { t in (-(half * t), -half) },
        ]
        for side in sides {
            disk = disk.appending(
                Self(columns: cells, rows: cells) { column, row in
                    let (x, y) = side(parameter(column))
                    let share = Scalar(Int(bitPattern: row)) / Scalar(count)
                    let scale = radius / (x * x + y * y).squareRoot()
                    return Point(x: (1 - share) * x + share * (scale * x), y: (1 - share) * y + share * (scale * y))
                }
            )
        }
        return disk.welded
    }
}
