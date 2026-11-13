pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    // 1990s Macintosh Platinum: one neutral surface, one black accent.
    readonly property color platinum: "#c0c0c0"
    readonly property color silver: "#d7d7d7"
    readonly property color paper: "#eeeeee"
    readonly property color white: "#ffffff"
    readonly property color ink: "#000000"
    readonly property color gray: "#666666"
    readonly property color shadow: "#808080"
    property int phase: 0
    property var alerts: []

    Layout.minimumWidth: 320
    Layout.maximumWidth: 320
    Layout.minimumHeight: 224
    Layout.maximumHeight: 224
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
        if (status === "acknowledged") return "·"
        if (status === "dismissed") return "x"
        return "·"
    }

    function triggerName(item) {
        if (item.trigger === "boot") return "at startup"
        if (item.trigger === "wifi") return "when online"
        if (!item.due) return "now"
        return String(item.due).slice(11, 16) + " utc"
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
                    console.log("agent pulse parse error: " + error)
                }
            }
            disconnectSource(sourceName)
        }
    }

    Timer { id: refreshTimer; interval: 700; repeat: false; onTriggered: root.refresh() }
    Timer { interval: 5000; running: true; repeat: true; onTriggered: root.refresh() }
    Timer { interval: 500; running: true; repeat: true; onTriggered: root.phase += 1 }
    Component.onCompleted: root.refresh()
    preferredRepresentation: fullRepresentation

    fullRepresentation: Rectangle {
        id: window
        width: 320
        height: 224
        color: root.platinum
        border.color: root.ink
        border.width: 1

        // Outer bevel: a single-pixel construction, deliberately not a shadow.
        Rectangle { x: 1; y: 1; width: parent.width - 2; height: 1; color: root.white }
        Rectangle { x: 1; y: 1; width: 1; height: parent.height - 2; color: root.white }
        Rectangle { x: 1; y: parent.height - 2; width: parent.width - 2; height: 1; color: root.shadow }
        Rectangle { x: parent.width - 2; y: 1; width: 1; height: parent.height - 2; color: root.shadow }

        // Classic striped title bar.
        Rectangle { x: 3; y: 3; width: parent.width - 6; height: 18; color: root.platinum; border.color: root.ink; border.width: 1 }
        Repeater {
            model: 8
            delegate: Rectangle {
                required property int index
                x: 4; y: 5 + index * 2; width: window.width - 8; height: 1
                color: index % 2 ? root.platinum : root.white
                opacity: 0.9
            }
        }
        Rectangle { x: 8; y: 8; width: 10; height: 10; color: root.platinum; border.color: root.ink; border.width: 1 }
        Rectangle { x: 9; y: 9; width: 8; height: 8; color: root.white; border.color: root.shadow; border.width: 1 }
        Rectangle { x: window.width - 18; y: 8; width: 10; height: 10; color: root.platinum; border.color: root.ink; border.width: 1 }
        Rectangle { x: window.width - 17; y: 9; width: 8; height: 8; color: root.white; border.color: root.shadow; border.width: 1 }
        Rectangle { x: 122; y: 5; width: 76; height: 14; color: root.platinum; border.color: root.ink; border.width: 1 }
        Text { x: 128; y: 5; text: "agent pulse"; color: root.ink; font.family: "Noto Sans"; font.pixelSize: 11; font.bold: true }

        Rectangle { x: 5; y: 27; width: parent.width - 10; height: parent.height - 40; color: root.paper; border.color: root.ink; border.width: 1 }

        RowLayout {
            x: 12; y: 34; width: parent.width - 24; height: 15
            Text { text: "alerts"; color: root.ink; font.family: "Noto Sans"; font.pixelSize: 11; font.bold: true; Layout.fillWidth: true }
            Text { text: root.alerts.length + " queued"; color: root.gray; font.family: "Noto Sans"; font.pixelSize: 9 }
            Text { text: (root.phase % 4 < 2) ? "▐" : " " ; color: root.ink; font.family: "monospace"; font.pixelSize: 9 }
        }

        ColumnLayout {
            x: 12; y: 53; width: parent.width - 24; spacing: 3
            Repeater {
                model: Math.min(root.alerts.length, 4)
                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 31
                    color: index % 2 ? root.silver : root.paper
                    border.color: root.shadow
                    border.width: 1

                    Rectangle { x: 1; y: 1; width: parent.width - 2; height: 1; color: root.white }
                    Rectangle { x: 1; y: parent.height - 2; width: parent.width - 2; height: 1; color: root.shadow }

                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 5
                        spacing: 5
                        Text { text: root.glyph(modelData.status); color: root.ink; font.family: "monospace"; font.bold: true; font.pixelSize: 12 }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            Text { text: String(modelData.title); color: root.ink; font.family: "Noto Sans"; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: String(modelData.agent) + " · " + root.triggerName(modelData); color: root.gray; font.family: "Noto Sans"; font.pixelSize: 8; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        Rectangle {
                            visible: modelData.status === "fired" && !!modelData.resume_command
                            Layout.preferredWidth: 48; Layout.preferredHeight: 20
                            color: root.platinum; border.color: root.ink; border.width: 1
                            Rectangle { x: 1; y: 1; width: parent.width - 2; height: 1; color: root.white }
                            Rectangle { x: 1; y: parent.height - 2; width: parent.width - 2; height: 1; color: root.shadow }
                            Text { anchors.centerIn: parent; text: "resume"; color: root.ink; font.family: "Noto Sans"; font.pixelSize: 8 }
                            MouseArea { anchors.fill: parent; onClicked: root.act("resume", modelData.id) }
                        }
                        Rectangle {
                            visible: !(modelData.status === "fired" && !!modelData.resume_command)
                            Layout.preferredWidth: 38; Layout.preferredHeight: 20
                            color: root.platinum; border.color: root.ink; border.width: 1
                            Rectangle { x: 1; y: 1; width: parent.width - 2; height: 1; color: root.white }
                            Rectangle { x: 1; y: parent.height - 2; width: parent.width - 2; height: 1; color: root.shadow }
                            Text { anchors.centerIn: parent; text: "ack"; color: root.ink; font.family: "Noto Sans"; font.pixelSize: 8 }
                            MouseArea { anchors.fill: parent; onClicked: root.act("ack", modelData.id) }
                        }
                    }
                }
            }
            Text {
                visible: root.alerts.length === 0
                text: "there are no alerts."
                color: root.gray; font.family: "Noto Sans"; font.pixelSize: 9
            }
        }

        Rectangle { x: 5; y: parent.height - 12; width: parent.width - 10; height: 1; color: root.shadow }
        Text { x: 10; y: parent.height - 11; text: "agent alert service"; color: root.gray; font.family: "Noto Sans"; font.pixelSize: 8 }
        Text { x: parent.width - 42; y: parent.height - 13; text: "◢"; color: root.ink; font.family: "monospace"; font.pixelSize: 13; opacity: 0.7 }
    }
}
