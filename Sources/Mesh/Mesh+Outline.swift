extension Mesh {

    /// The outline: every edge that only one face uses, as the segment between its two vertices.
    ///
    /// Edges are compared without their direction, so an edge two faces share counts twice whichever way each
    /// face runs. Each outline edge is listed in face order, then in the order of its face's edges, and runs the
    /// way its face does: on a mesh whose faces are counterclockwise, the outline runs counterclockwise around the
    /// mesh and clockwise around each hole. A closed surface has none.
    @inlinable
    public var outline: [Segment<Index<Vertex>>] {
        func key(_ edge: Segment<Index<Vertex>>) -> Segment<Int> {
            let (start, end) = (Int(bitPattern: edge.start), Int(bitPattern: edge.end))
            return Segment(start: Swift.min(start, end), end: Swift.max(start, end))
        }
        var uses: [Segment<Int>: Int] = [:]
        faces.forEach { face in
            face.edges.forEach { uses[key($0), default: 0] += 1 }
        }
        return faces.flatMap { face in face.edges.filter { uses[key($0)] == 1 } }
    }
}
