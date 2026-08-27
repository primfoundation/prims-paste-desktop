// How a sticky shows a secret. Never returns the payload.

public enum SecretFace {
    /// True → do not put the payload on screen.
    public static func hidesPayload(looksLikeKey: Bool, revealed: Bool, shuttered: Bool) -> Bool {
        if shuttered { return true }
        if looksLikeKey && !revealed { return true }
        return false
    }

    /// Copy / reveal sit on the card. Covered board has neither.
    public static func showsCopyReveal(looksLikeKey: Bool, shuttered: Bool) -> Bool {
        looksLikeKey && !shuttered
    }
}
