// Canonical list of work on the board. Seeded as stickies on the
// "features-wanted" tab. Ids are stable so reopening does not duplicate.

import Foundation

public struct WantedFeature: Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String

    public var stickyID: String { "pp_fw_\(id)" }
}

public enum FeaturesWanted {
    public static let tabID = "tab_features-wanted"
    public static let tabTitle = "features-wanted"
    public static let tabColor = "#C45C26"

    public static let all: [WantedFeature] = [
        WantedFeature(
            id: "durable",
            title: "Durable notebook",
            body: "Stickies live in this app forever, encrypted on this Mac."
        ),
        WantedFeature(
            id: "touchid",
            title: "Touch ID on open only",
            body: "Fingerprint when the window opens. That is the only auth gate."
        ),
        WantedFeature(
            id: "llc-sign",
            title: "Signed Eidos AGI LLC",
            body: "Developer ID Application: Eidos AGI LLC (Y6CQ4SWPWM)."
        ),
        WantedFeature(
            id: "stickies",
            title: "Miro-style stickies",
            body: "Click anywhere and drop. Paper stickies, not a table."
        ),
        WantedFeature(
            id: "timestamps",
            title: "Timestamp every drop",
            body: "Every sticky shows when it landed."
        ),
        WantedFeature(
            id: "pastes",
            title: "Paste secrets",
            body: "Whatever you pasted is stored encrypted. Peek to reveal."
        ),
        WantedFeature(
            id: "key-detect",
            title: "Detect API keys vs prose",
            body: "Prefixes, PEM, JWT, hex, entropy. English stays a note."
        ),
        WantedFeature(
            id: "voice-caption",
            title: "Ask what you pasted",
            body: "Speak: What did you just paste? Whisper tiny.en writes the caption."
        ),
        WantedFeature(
            id: "notes",
            title: "Text notes",
            body: "Double-click the board for a sticky you can type on."
        ),
        WantedFeature(
            id: "audio",
            title: "Audio notes",
            body: "Record a voice sticky. Encrypted on disk."
        ),
        WantedFeature(
            id: "pictures",
            title: "Pictures and screenshots",
            body: "Paste or drop images. Encrypted blobs, shown on the sticky."
        ),
        WantedFeature(
            id: "big-tabs",
            title: "Big browser tabs",
            body: "Fat tabs at the top so a sticky can land on them."
        ),
        WantedFeature(
            id: "new-tab",
            title: "+ name and color a tab",
            body: "Plus button: name it, color it, it shows up like a browser tab."
        ),
        WantedFeature(
            id: "drag-tag",
            title: "Drag onto a tab to tag",
            body: "That is how a note gets a tab. Drag the sticky onto the tab."
        ),
        WantedFeature(
            id: "drag-feel",
            title: "Drag that does not blow",
            body: "Lift the sticky, follow the pointer, commit on drop. No disk write per pixel."
        ),
        WantedFeature(
            id: "idle-cover",
            title: "Cover when idle",
            body: "No cover while you are working. Cover when you stop or leave the window."
        ),
        WantedFeature(
            id: "local-ai",
            title: "Local chat with notes",
            body: "Settings: a local model only. No online APIs."
        ),
        WantedFeature(
            id: "low-mem",
            title: "Low memory",
            body: "Decrypt on demand. Whisper tiny.en. No Electron."
        ),
        WantedFeature(
            id: "no-capture",
            title: "Window not shareable",
            body: "sharingType none. Screen share does not get the board."
        ),
        WantedFeature(
            id: "calendar-drawer",
            title: "Calendar drawer",
            body: "Calendar button opens a right-side drawer."
        ),
        WantedFeature(
            id: "filter-dwmy",
            title: "Filter D W M Y",
            body: "Drawer filters cards by day, week, month, or year."
        ),
        WantedFeature(
            id: "view-layout",
            title: "Layout view",
            body: "Cards stay where you dragged them."
        ),
        WantedFeature(
            id: "view-timeline",
            title: "Time view",
            body: "Cards spaced on a timeline by day."
        ),
        WantedFeature(
            id: "view-week",
            title: "Week view",
            body: "Cards for the week, one column per day."
        ),
        WantedFeature(
            id: "view-month",
            title: "Month view",
            body: "Cards laid on the month. Year is the same idea."
        ),
        WantedFeature(
            id: "convert-to",
            title: "Convert to…",
            body: "Button on every sticky: Docket task or Paseo agent. Convert creates the thing and the card keeps the link."
        ),
    ]
}
