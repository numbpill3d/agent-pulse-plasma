pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    readonly property color paper: "#f0f0df"
    readonly property color ink: "#111111"
    readonly property color dim: "#77776e"
    readonly property color line: "#b4b4a5"
    readonly property color black: "#080808"
    readonly property color amber: "#d8c56a"
    property int phase: 0
    property var alerts: []

    Layout.minimumWidth: 300
    Layout.maximumWidth: 300
    Layout.minimumHeight: 204
    Layout.maximumHeight: 204
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    function scriptPath(name) {
        return decodeURIComponent(Qt.resolvedUrl("../../scripts/" + name).toString().replace(/^file:\/\//, ""))
    }

    function command(commandLine) {
        source.connectSource(commandLine)
    }

    function refresh() {
        command("python3 \"" + scriptPath("agent_alertctl.py") + "\" list")
    }

    function act(op, id) {
        command("python3 \"" + scriptPath("agent_alertctl.py") + "\" " + op + " " + id)
        refreshTimer.restart()
    }

    function glyph(status) {
        if (status === "fired") return "!"
        if (status === "acted") return ">"
        if (status === "acknowledged") return "."
        if (status === "dismissed") return "x"
        return "*"
    }

    function shortTime(item) {
        if (item.trigger === "boot") return "BOOT"
        if (item.trigger === "wifi") return "WIFI"
        if (!item.due) return "NOW"
        return String(item.due).slice(11, 16) + "Z"
    }

    P5Support.DataSource {
        id: source
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            if (data["exit code"] === 0 && data.stdout) {
                try {
                    var parsed = JSON.parse(data.stdout)
                    if (parsed.alerts) root.alerts = parsed.alerts
                } catch (error) {
                    console.log("Agent Pulse parse error: " + error)
                }
            }
            disconnectSource(sourceName)
        }
    }

    Timer { id: refreshTimer; interval: 1000; repeat: false; onTriggered: root.refresh() }
    Timer { interval: 4000; running: true; repeat: true; onTriggered: root.refresh() }
    Timer { interval: 240; running: true; repeat: true; onTriggered: root.phase += 1 }
    Component.onCompleted: root.refresh()
    preferredRepresentation: fullRepresentation

    fullRepresentation: Rectangle {
        id: panel
        width: 300
        height: 204
        color: root.paper
        border.color: root.ink
        border.width: 2

        // Dithered Macintosh-style field: restrained, visible, and cheap.
        Repeater {
            model: 32
            delegate: Rectangle {
                required property int index
                x: 5 + (index % 8) * 36
                y: 30 + Math.floor(index / 8) * 41
                width: 1
                height: 1
                color: root.line
                opacity: 0.25 + ((index + root.phase) % 3) * 0.08
            }
        }

        Rectangle { x: 0; y: 25; width: parent.width; height: 1; color: root.ink }
        Rectangle { x: 0; y: 26; width: parent.width; height: 1; color: root.line }

        RowLayout {
            x: 8; y: 4; width: parent.width - 16; height: 18
            Text { text: "AGENT_PULSE"; color: root.ink; font.family: "monospace"; font.bold: true; font.pixelSize: 12; Layout.fillWidth: true }
            Text { text: root.alerts.length.toString().padStart(2, "0"); color: root.ink; font.family: "monospace"; font.pixelSize: 11 }
            Text { text: (root.phase % 8 < 4) ? "_" : " "; color: root.ink; font.family: "monospace"; font.pixelSize: 11 }
        }

        ColumnLayout {
            x: 8; y: 32; width: parent.width - 16; spacing: 4
            Text { text: "LOCAL SIGNAL BUS // " + ((root.phase % 16 < 8) ? "LISTENING" : "LISTENI‧G"); color: root.dim; font.family: "monospace"; font.pixelSize: 9 }
            Repeater {
                model: Math.min(root.alerts.length, 4)
                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 29
                    color: index % 2 ? "#e7e7d8" : "#f4f4e5"
                    border.color: modelData.status === "fired" ? root.amber : root.line
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 4
                        spacing: 5
                        Text { text: root.glyph(modelData.status); color: root.ink; font.family: "monospace"; font.bold: true; font.pixelSize: 13 }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            Text { text: String(modelData.title).toUpperCase(); color: root.ink; font.family: "monospace"; font.pixelSize: 8; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: String(modelData.agent).toUpperCase() + " // " + root.shortTime(modelData); color: root.dim; font.family: "monospace"; font.pixelSize: 7; Layout.fillWidth: true }
                        }
                        Text { text: modelData.resume_command ? "R" : "·"; color: root.ink; font.family: "monospace"; font.pixelSize: 9 }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (modelData.status === "fired" && modelData.resume_command) root.act("resume", modelData.id)
                            else root.act("ack", modelData.id)
                        }
                    }
                }
            }
            Text {
                visible: root.alerts.length === 0
                text: "[ no queued signals ]"
                color: root.dim; font.family: "monospace"; font.pixelSize: 9
            }
            Text { text: "CLICK FIRED ROW = RESUME  //  OTHERWISE ACK"; color: root.dim; font.family: "monospace"; font.pixelSize: 7 }
        }
    }
}
