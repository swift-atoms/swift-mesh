extension Mesh {
    /// What one quad of `cells(on:columns:rows:inset:per:including:)` covers.
    public enum Span: Hashable, Sendable, CaseIterable {
        /// One inset quad for each chosen cell.
        case cell

        /// One inset strip for each row with a chosen cell, from the first chosen cell of the row to the last:
        /// the coarser level of detail, for a face seen from far away.
        case row
    }
}
