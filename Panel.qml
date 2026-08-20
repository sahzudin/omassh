import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.sahzudin.omassh"
  ipcTarget: moduleName
  manageIpc: false

  property var hosts: []
  property var errors: []
  property var watchedFiles: []
  property string query: ""
  property int selectedIndex: 0
  property bool loading: false
  property bool refreshPending: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string configuredPath: String(setting("configPath", "~/.ssh/config"))
  readonly property string configPath: configuredPath.indexOf("~/") === 0
    ? home + configuredPath.substring(1)
    : configuredPath
  readonly property int maximumHosts: Math.max(10, Number(setting("maxHosts", 200)))
  readonly property int refreshInterval: Math.max(5, Number(setting("refreshIntervalSec", 30))) * 1000
  readonly property var filteredHosts: Model.filterHosts(hosts, query)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function helperPath() {
    var url = String(Qt.resolvedUrl("bin/omassh-hosts"))
    return decodeURIComponent(url.replace(/^file:\/\//, ""))
  }

  function refresh() {
    if (hostProcess.running) {
      refreshPending = true
      return
    }
    loading = true
    refreshPending = false
    hostProcess.command = [
      helperPath(), "list", "--config", configPath,
      "--limit", String(maximumHosts)
    ]
    hostProcess.running = true
  }

  function applyResult(raw) {
    try {
      var result = JSON.parse(String(raw || "{}"))
      hosts = result.hosts instanceof Array ? result.hosts : []
      errors = result.errors instanceof Array ? result.errors : []
      watchedFiles = result.files instanceof Array ? result.files : []
    } catch (error) {
      hosts = []
      errors = ["Could not parse the SSH host list"]
    }
    ensureSelection()
  }

  function ensureSelection() {
    if (filteredHosts.length === 0) selectedIndex = 0
    else selectedIndex = Math.max(0, Math.min(selectedIndex, filteredHosts.length - 1))
  }

  function moveSelection(delta) {
    if (filteredHosts.length === 0) return
    selectedIndex = Math.max(0, Math.min(filteredHosts.length - 1, selectedIndex + delta))
    scrollSelectionIntoView()
  }

  function select(index) {
    selectedIndex = Math.max(0, Math.min(filteredHosts.length - 1, index))
  }

  function selectedHost() {
    if (filteredHosts.length === 0) return null
    return filteredHosts[Math.max(0, Math.min(selectedIndex, filteredHosts.length - 1))]
  }

  function connect(host) {
    if (!host || !host.alias) return
    var alias = String(host.alias)
    Quickshell.execDetached([helperPath(), "record", "--alias", alias])
    close()
    Quickshell.execDetached(["omarchy-launch-terminal", "ssh", "--", alias])
  }

  function activateSelection() {
    connect(selectedHost())
  }

  function scrollSelectionIntoView() {
    if (!hostColumn || selectedIndex < 0 || selectedIndex >= hostColumn.children.length) return
    var item = hostColumn.children[selectedIndex]
    Qt.callLater(function() {
      if (!item) return
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var margin = Style.space(6)
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onFilteredHostsChanged: {
    selectedIndex = 0
    if (panelFlick) panelFlick.contentY = 0
  }
  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() {
      searchField.forceActiveFocus()
      searchField.selectAll()
    })
  } else {
    query = ""
  }
  onConfigPathChanged: refresh()
  onMaximumHostsChanged: refresh()

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function count(): int { return root.hosts.length }
  }

  Process {
    id: hostProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyResult(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.errors = [message]
      }
    }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0 && root.errors.length === 0)
        root.errors = ["Could not read the SSH configuration"]
      if (root.refreshPending) Qt.callLater(root.refresh)
    }
  }

  FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  Timer {
    interval: root.refreshInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰣀"
    active: root.opened
    tooltipText: root.hosts.length > 0
      ? "SSH hosts (" + root.hosts.length + ")"
      : "SSH hosts"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(580))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveSelection(dy) }
      onActivateRequested: root.activateSelection()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        root.query += text
        searchField.forceActiveFocus()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: panelFlick.width
          spacing: Style.space(10)

          RowLayout {
            width: parent.width
            spacing: Style.space(10)

            Text {
              text: "󰣀"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              Text {
                text: "SSH connections"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.weight: Font.DemiBold
              }
              Text {
                text: root.loading
                  ? "Reading " + root.configuredPath + "…"
                  : root.hosts.length + (root.hosts.length === 1 ? " host" : " hosts")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Text {
              visible: root.loading
              text: "󰔟"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          TextField {
            id: searchField
            width: parent.width
            foreground: root.foreground
            placeholderText: "Search aliases, users, hosts…"
            text: root.query
            onTextChanged: root.query = text
            onAccepted: root.activateSelection()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Down) {
                root.moveSelection(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.moveSelection(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                if (text !== "") text = ""
                else root.close()
                event.accepted = true
              }
            }
          }

          Text {
            visible: root.errors.length > 0
            width: parent.width
            text: root.errors.length > 0 ? String(root.errors[0]) : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            foreground: root.foreground
          }

          Text {
            visible: !root.loading && root.filteredHosts.length === 0
            width: parent.width
            topPadding: Style.space(18)
            bottomPadding: Style.space(18)
            text: root.hosts.length === 0
              ? "No literal Host aliases found"
              : "No matching SSH hosts"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            id: hostColumn
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.filteredHosts

              CursorSurface {
                id: hostRow
                required property var modelData
                required property int index
                width: hostColumn.width
                implicitHeight: Style.space(50)
                hasCursor: index === root.selectedIndex
                foreground: root.foreground

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(10)

                  Text {
                    Layout.preferredWidth: Style.space(18)
                    text: modelData.recentAt ? "󰋚" : "󰒍"
                    color: modelData.recentAt ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    horizontalAlignment: Text.AlignHCenter
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                      Layout.fillWidth: true
                      text: String(modelData.alias || "")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.weight: Font.DemiBold
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: String(modelData.details || modelData.alias || "")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    text: "󰁔"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.select(hostRow.index)
                  onClicked: root.connect(hostRow.modelData)
                }
              }
            }
          }

          Text {
            visible: root.filteredHosts.length > 0
            width: parent.width
            text: "↑↓ select   Enter connect   Esc close   Right-click icon refreshes"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
