pragma Singleton

import QtQuick

// core/design: the only place a colour, a face or a size is written down (VAS architecture). Every leaf reads `accent`; none names one.
QtObject {
    id: theme

    // #region ── ground and structure ──────────────────────────────────────────────────────────
    readonly property color ground: "#181818"
    readonly property color panel: Qt.rgba(18 / 255, 18 / 255, 18 / 255, 0.85)
    readonly property color panelSolid: "#121212"
    readonly property color sunkenDeep: "#0e0e0e"
    readonly property color sunken: "#1c1c1c"
    readonly property color raised: "#232323"
    readonly property color raisedHigh: "#2a2a2a"
    readonly property color border: "#262626"
    readonly property color borderStrong: "#2c2c2c"
    readonly property color borderControl: "#3a3a3a"
    readonly property color borderHover: "#5a5a5a"
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── text ramp ──────────────────────────────────────────────────────────────────────
    readonly property color textPrimary: Qt.rgba(1, 1, 1, 0.87)
    readonly property color textBright: "#f0f0f0"
    readonly property color textBody: "#d8d8d8"
    readonly property color textMuted: "#acacac"
    readonly property color textLabel: "#8a8a8a"
    readonly property color textIcon: "#6a6a6a"
    readonly property color textFaint: "#4a4a4a"
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── danger and marks ───────────────────────────────────────────────────────────────
    readonly property color danger: "#ff6b6b"
    readonly property color dangerHard: "#DC143C"
    readonly property color dangerExtreme: "#ff2b2b"
    readonly property color link: "#6fb3ff"
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── accents ───────────────────────────────────────────────────────────────────────
    // One accent per place, the way VAS gives one per screen: a folder takes the colour of the room it is in. The registry key comes from PlacesModel; the colour lives only here.
    readonly property var placeAccents: ({
        "home": "#5bfd5b",
        "desktop": "#f09b3a",
        "documents": "#FFDD1B",
        "downloads": "#0040ff",
        "system": "#8a2be2",
        "trash": "#DC143C",
        "pictures": "#ff2e88",
        "music": "#0bc993",
        "videos": "#2ee6ff",
        "drive": "#4db8ff"
    })
    readonly property color defaultAccent: "#5bfd5b"

    // The accent now; changed by the workspace on the cut, never on the click (VAS palette: the accent changes on the cut).
    property color accent: defaultAccent
    // The same accent lifted toward white when it is too dark to read as a stroke on the ground; derived, never authored.
    readonly property color accentInk: inkFor(accent)

    function accentFor(key: string): color {
        return placeAccents[key] !== undefined ? placeAccents[key] : defaultAccent
    }

    function inkFor(base: color): color {
        return luminance(base) < 0.35 ? mix(base, "#ffffff", 0.6) : base
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── derived colour ─────────────────────────────────────────────────────────────────
    // color-mix(in srgb, first amount, second): `amount` is the share of `first`.
    function mix(first: color, second: color, amount: real): color {
        return Qt.rgba(first.r * amount + second.r * (1 - amount),
                       first.g * amount + second.g * (1 - amount),
                       first.b * amount + second.b * (1 - amount),
                       first.a * amount + second.a * (1 - amount))
    }

    function alpha(base: color, value: real): color {
        return Qt.rgba(base.r, base.g, base.b, value)
    }

    function luminance(base: color): real {
        return base.r * 0.299 + base.g * 0.587 + base.b * 0.114
    }

    function isLightColor(base: color): bool {
        return luminance(base) > 0.5
    }

    // Blends toward its own luminance grey, so an accent can recede without shifting hue.
    function desaturate(base: color, amount: real): color {
        const grey = luminance(base)
        return Qt.rgba(base.r + (grey - base.r) * amount, base.g + (grey - base.g) * amount, base.b + (grey - base.b) * amount, base.a)
    }

    function hex(base: color): string {
        const channel = value => ("0" + Math.round(value * 255).toString(16)).slice(-2)
        return channel(base.r) + channel(base.g) + channel(base.b)
    }
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── faces ─────────────────────────────────────────────────────────────────────────
    // Roles first, faces cast into them (VAS typography). A face that is not installed falls back to the nearest cast face, never to an arbitrary system font.
    readonly property var installedFamilies: Qt.fontFamilies()
    function firstInstalled(candidates: var): string {
        for (const candidate of candidates)
            if (installedFamilies.indexOf(candidate) !== -1)
                return candidate
        return "monospace"
    }
    readonly property string mono: firstInstalled(["Space Mono", "SpaceMono", "Adwaita Mono", "DejaVu Sans Mono"])
    readonly property string heading: firstInstalled(["Audiowide", mono])
    readonly property string display: firstInstalled(["Wosker", "Striker", "Audiowide", mono])
    // #endregion ───────────────────────────────────────────────────────────────────────────────

    // #region ── scale ─────────────────────────────────────────────────────────────────────────
    // The single scale lever (VAS layout): a pure ratio of the screen, no constant term, 1440p as the reference. It reads the monitor and not the window, because a tool tiled to half the screen must not shrink its type.
    property real screenWidth: 1920
    property real userScale: 1.0
    readonly property real rem: Math.max(16, Math.min(40, screenWidth * 0.0108)) * userScale

    // Superellipse corners read smaller than circular ones at the same radius; the factor keeps 0.75rem looking like 0.75rem (VAS law 4: corners are squircle).
    readonly property real squircle: rem * 0.75 * 1.45
    readonly property real squircleSmall: rem * 0.5 * 1.45
    readonly property real gap: rem * 0.75
    readonly property real labelSize: rem * 0.72
    readonly property real labelSpacing: rem * 0.19
    readonly property real bodySize: rem * 0.84
    readonly property real smallSize: rem * 0.74
    readonly property real captionSize: rem * 0.76
    // #endregion ───────────────────────────────────────────────────────────────────────────────
}
