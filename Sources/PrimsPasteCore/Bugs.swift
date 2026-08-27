// Bugs become stickies on the "bugs" tab, then convert into docket tasks.

import Foundation

public enum Bugs {
    public static let tabID = "tab_bugs"
    public static let tabTitle = "bugs"
    public static let tabColor = "#8B2E2E"

    public static let all: [WantedFeature] = [
        WantedFeature(
            id: "cover-on-touchid",
            title: "Cover blacks the board on Touch ID",
            body: "Touch ID resigns the window. Cover treated not-active as cover-now, so unlock painted a black shutter. Fix: no cover before unlock; resign needs a 2s grace."
        ),
        WantedFeature(
            id: "empty-payload-on-open",
            title: "empty payload alert on open",
            body: "With the shutter on, note editors read payload as empty and saved empty blobs. That threw empty payload. Fix: payload still reads while covered; empty saves are ignored."
        ),
        WantedFeature(
            id: "drag-fought-scroll",
            title: "Drag fought the board",
            body: "Click-drag wrote the index every mouse move and battled ScrollView. Fix: lift transform, commit on drop, disable scroll while dragging, persist z-order."
        ),
        WantedFeature(
            id: "convert-was-stub",
            title: "Convert did not create the thing",
            body: "Convert to Docket/Paseo only stored a local ref. Fix: docket-prim task-create into ~/.prims-paste/docket and paseo run --background, caption only."
        ),
        WantedFeature(
            id: "no-control-api",
            title: "No CLI to control the app",
            body: "Could not add stickies, list tabs, or convert from a script. Fix: prims-paste CLI on the same notebook store."
        ),
    ]
}

public extension WantedFeature {
    var bugStickyID: String { "pp_bug_\(id)" }
}
