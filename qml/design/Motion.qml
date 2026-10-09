pragma Singleton

import QtQuick
import Vados

// The house tempo, at the tool ceiling VAD/OS TERMINAL set: nothing in the output path past 0.3s, chrome to 0.4s. The launch is the one moment that runs at the portfolio's full tempo, because it happens once.
QtObject {
    // #region ── precedence ────────────────────────────────────────────────────────────────────
    // The one function every motion path reads (VAS motion §9). Never computed twice.
    readonly property bool isLite: Settings.isLiteMode || System.prefersReducedMotion
    readonly property bool isReduced: System.prefersReducedMotion
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── curves ────────────────────────────────────────────────────────────────────────
    // GSAP names, Qt curves: power2 is quad, power3 cubic, power4 quart, back is back with GSAP's 1.70158.
    readonly property int enterProminent: Easing.OutBack
    readonly property int enter: Easing.OutQuad
    readonly property int leaveLarge: Easing.InBack
    readonly property int leave: Easing.InQuad
    readonly property int sweep: Easing.InOutCubic
    readonly property int idle: Easing.InOutSine
    readonly property int state: Easing.OutCubic
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── clocks (ms) ───────────────────────────────────────────────────────────────────
    readonly property int hover: 220
    readonly property int press: 120
    readonly property int stateChange: 220

    // Folder navigation: the screen change of a tool.
    readonly property int navigateLeave: isLite ? 120 : 130
    readonly property int navigateEnter: isLite ? 200 : 260
    readonly property int navigateStaggerVertical: isLite ? 0 : 170
    readonly property int navigateStaggerHorizontal: isLite ? 0 : 60
    readonly property int navigateRevealGrow: 180
    readonly property int navigateRevealRetract: 220

    // Overlays: menus, sheets, previews (VAS glass sheet: arrive 240 on the overshoot, leave 140).
    readonly property int overlayEnter: 240
    readonly property int overlayLeave: 140
    readonly property int pillEnter: 240
    readonly property int pillLeave: 140

    // The background slices, the room's colour arriving.
    readonly property int sliceEnter: 450
    readonly property int sliceLeave: 220
    readonly property int sliceLayerOffset: 100

    // Launch, at the portfolio tempo (VAS motion §3).
    readonly property int launchDelay: 120
    readonly property int launchPanelEnter: 340
    readonly property int launchStaggerVertical: 280
    readonly property int launchStaggerHorizontal: 100
    readonly property int revealGrow: 420
    readonly property int revealRetract: 500
    readonly property int revealLeave: 300

    // Undo stays long enough to notice a wrong destination; a trash keeps the file anyway, so it gets out of the way sooner (VAS confirm and undo).
    readonly property int undoMove: 4500
    readonly property int undoTrash: 2500
    readonly property int springLoad: 850
    readonly property int idleDrift: 3000
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── stagger ───────────────────────────────────────────────────────────────────────
    // The positional stagger: one scalar from the distance to the top-left corner, vertical weighted about three times horizontal, so a view assembles diagonally like a display powering on.
    function positionalDelay(x: real, y: real, width: real, height: real, vertical: int, horizontal: int): int {
        const yFraction = Math.max(0, Math.min(1, y / Math.max(1, height)))
        const xFraction = Math.max(0, Math.min(1, x / Math.max(1, width)))
        return Math.round(yFraction * vertical + xFraction * horizontal)
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────
}
