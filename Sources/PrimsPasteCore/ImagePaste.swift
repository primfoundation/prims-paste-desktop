// Where a clipboard/drop image should land. Payload never logged.

public enum ImagePaste {
    /// ⌘V / paste with a note selected attaches to that note.
    /// Empty selection (or anything else) makes a new image sticky.
    public static func attachToSelected(_ kind: ItemKind?) -> Bool {
        kind == .note
    }
}
