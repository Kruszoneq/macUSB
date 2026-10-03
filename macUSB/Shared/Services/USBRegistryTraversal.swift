/// Traverses acquired parent references without consuming the caller's reference.
enum USBRegistryTraversal {
    static func firstValue<Entry, Value>(
        from entry: Entry,
        retain: (Entry) -> Bool,
        release: (Entry) -> Void,
        parent: (Entry) -> Entry?,
        value: (Entry) -> Value?
    ) -> Value? {
        guard retain(entry) else { return nil }
        var current = entry
        defer { release(current) }

        while let next = parent(current) {
            if let result = value(next) {
                release(next)
                return result
            }
            release(current)
            current = next
        }
        return nil
    }
}
