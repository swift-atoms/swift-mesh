extension Mesh {

    public init<Parameter: BinaryFloatingPoint, Failure: Swift::Error>(
        _ patch: Bezier<Vertex>.Patch,
        columns: Cardinal,
        rows: Cardinal,
        interpolating interpolate: (Vertex, Vertex, Parameter) throws(Failure) -> Vertex
    ) throws(Failure) {
        precondition(columns >= .one && rows >= .one, "A mesh grid needs at least one column and one row")
        let columnCells = Int(bitPattern: columns)
        let rowCells = Parameter(Int(bitPattern: rows))
        var curves: [Bezier<Vertex>] = []
        curves.reserveCapacity(columnCells + 1)
        for column in 0...columnCells {
            curves.append(
                try patch.column(at: Parameter(column) / Parameter(columnCells), interpolating: interpolate)
            )
        }
        try self.init(columns: columns, rows: rows) { (column, row) throws(Failure) in
            try curves[column].value(at: Parameter(Int(bitPattern: row)) / rowCells, interpolating: interpolate)
        }
    }
}
