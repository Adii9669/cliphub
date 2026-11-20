import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ClipboardModel.js" as ClipboardModel
import "EmojiSearch.js" as EmojiSearch

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false
  property string activeTab: "clipboard" // "clipboard" | "emoji"

  // clipboard state
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool clearConfirmOpen: false
  property var history: []
  property int unpinnedLimit: 200

  // emoji state
  property string emojiFilterText: ""
  property int emojiSelectedIndex: 0
  property bool emojiCursorActive: false
  property var emojis: []

  property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-hub"
  property string historyPath: stateDir + "/history.json"
  property string imageDir: stateDir + "/images"
  property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/adii9669.clipboard-hub"
  property string captureScript: pluginDir + "/capture.sh"
  property string pasteTextScript: pluginDir + "/paste-text.sh"
  property string emojiInsertScript: pluginDir + "/insert-emoji.sh"

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  // Semi-transparent selection highlight so it's not a harsh solid block.
  property color selectionBackground: Util.alpha(root.foreground, 0.20)
  property color selectionText: root.foreground
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  // Compact sizing
  // Small-screen layout: collapse the detail pane and use the full width for
  // the list, with an eye/back button in the header to toggle it.
  property bool compactLayout: cardWidth < Style.space(560)
  property bool compactPreview: false
  property int contentMargin: compactLayout ? Style.space(8) : Style.space(10)
  property int headerHeight: Math.max(Style.space(30), Style.font.body + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.space(6)
  property int cardWidth: Math.min(Style.space(680), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(460), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(compactLayout ? Style.space(42) : Style.space(46), Style.font.body + Style.spacing.rowPaddingX + Style.space(8))
  property int actionButtonWidth: compactLayout ? Style.space(24) : Style.space(28)
  property int rowThumbSize: compactLayout ? Style.space(28) : Style.space(40)

  // Emoji cells adapt to the available width. The column count is taken from
  // the GridView itself so arrow-key navigation always matches what is drawn.
  property int emojiCellWidth: Math.max(Style.space(44), Math.min(Style.space(68), Math.floor((cardWidth - contentMargin * 2) / 5)))
  property int emojiCellHeight: emojiCellWidth
  property int emojiColumns: Math.max(1, Math.floor(emojiGrid.width / emojiCellWidth))

  function open(payloadJson) {
    var payload = {}
    try { payload = payloadJson ? JSON.parse(payloadJson) : {} } catch (e) { payload = {} }
    var requestedTab = String(payload.tab || root.activeTab || "clipboard")
    if (requestedTab !== "emoji" && requestedTab !== "clipboard") requestedTab = "clipboard"

    if (root.opened && requestedTab === root.activeTab) {
      root.close()
      return
    }

    root.opened = true
    root.activeTab = requestedTab
    root.compactPreview = false
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.emojiFilterText = ""
    root.emojiSelectedIndex = 0
    root.emojiCursorActive = true
    root.disarmPointer()
    root.rebuildClipboardDisplay()
    root.rebuildEmojiDisplay()
    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  onFilterTextChanged: if (root.activeTab === "clipboard" && filterInput.text !== filterText) filterInput.text = filterText
  onEmojiFilterTextChanged: if (root.activeTab === "emoji" && filterInput.text !== emojiFilterText) filterInput.text = emojiFilterText
  onActiveTabChanged: {
    filterInput.text = root.activeTab === "clipboard" ? root.filterText : root.emojiFilterText
    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  onCompactLayoutChanged: if (!compactLayout) compactPreview = false

  function close() {
    root.cancelClearUnpinned()
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function setTab(tab) {
    var next = String(tab || "clipboard")
    if (next !== "emoji" && next !== "clipboard") next = "clipboard"
    root.activeTab = next
    root.compactPreview = false
    if (next === "clipboard") {
      root.rebuildClipboardDisplay()
    } else {
      root.rebuildEmojiDisplay()
    }
    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  function loadHistory(raw) {
    root.history = ClipboardModel.parseHistory(raw)
    if (root.opened) root.rebuildClipboardDisplay()
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(root.history, null, 2) + "\n")
  }

  function addClipboardEntry(entry) {
    var normalized = ClipboardModel.normalizeEntry(entry)
    if (!normalized) return
    root.history = ClipboardModel.addEntry(root.history, normalized, root.unpinnedLimit)
    root.saveHistory()
    if (root.opened) root.rebuildClipboardDisplay()
  }

  function addClipboardJson(line) {
    root.addClipboardEntry(ClipboardModel.parseEntryJson(line))
  }

  function rebuildClipboardDisplay() {
    var rows = ClipboardModel.flatDisplayRows(root.history, root.filterText, 100)
    clipboardModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      clipboardModel.append({
        entryType: row.entryType,
        fullText: row.fullText,
        previewText: row.previewText,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        path: row.path,
        mime: row.mime,
        historyIndex: row.historyIndex,
        pinned: !!row.pinned,
        section: String(row.section || "recent")
      })
    }
    if (clipboardModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= clipboardModel.count) selectedIndex = clipboardModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (clipboardModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function rebuildEmojiDisplay() {
    var out = EmojiSearch.filterEmojis(root.emojis, root.emojiFilterText, 1000)
    emojiModel.clear()
    for (var i = 0; i < out.length; i++) {
      emojiModel.append({ emoji: out[i].e, index: i })
    }
    if (emojiModel.count === 0) emojiSelectedIndex = 0
    else if (emojiSelectedIndex >= emojiModel.count) emojiSelectedIndex = emojiModel.count - 1
    else if (emojiSelectedIndex < 0) emojiSelectedIndex = 0
    emojiCursorActive = emojiModel.count > 0
    Qt.callLater(function() {
      if (emojiModel.count > 0) emojiGrid.positionViewAtIndex(root.emojiSelectedIndex, GridView.Contain)
    })
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function setClipboardFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildClipboardDisplay()
  }

  function setEmojiFilter(nextFilter) {
    root.emojiFilterText = nextFilter
    root.emojiSelectedIndex = 0
    root.emojiCursorActive = true
    root.rebuildEmojiDisplay()
  }

  function selectClipboard(delta) {
    if (clipboardModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? clipboardModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + clipboardModel.count) % clipboardModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectClipboardAbsolute(index) {
    if (clipboardModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, clipboardModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function currentClipboardRow() {
    if (clipboardModel.count === 0 || root.selectedIndex < 0 || root.selectedIndex >= clipboardModel.count) return null
    return clipboardModel.get(root.selectedIndex)
  }

  function activateClipboardIndex(index) {
    if (index < 0 || index >= clipboardModel.count) return
    var row = clipboardModel.get(index)
    root.applyClipboardRow(row)
  }

  function copyClipboardIndex(index) {
    if (index < 0 || index >= clipboardModel.count) return
    var row = clipboardModel.get(index)
    root.copyClipboardRow(row)
  }

  function openClipboardIndex(index) {
    if (index < 0 || index >= clipboardModel.count) return
    var row = clipboardModel.get(index)
    root.openClipboardRow(row)
  }

  function applyClipboardRow(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", row.mime, row.path])
    } else {
      Quickshell.execDetached([root.pasteTextScript, "--shift-insert", "--history-index", String(row.historyIndex)])
    }
  }

  function copyClipboardRow(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", "--copy-only", row.mime, row.path])
    } else {
      Quickshell.execDetached([root.pasteTextScript, "--copy-only", "--history-index", String(row.historyIndex)])
    }
  }

  function openClipboardRow(row) {
    if (!row) return
    root.opened = false
    // Reuse system helper for text/file/image open semantics by synthesizing temp handling when possible.
    // For history-backed behavior we fall back to writing temp for text-like rows and using omasnap/editor/browser via a helper script would be overkill;
    // easiest: copy-only + open is not needed; use existing helper by pointing to a temp json index is not available.
    // Instead handle common cases inline-ish via commands.
    if (row.entryType === "image" && row.path) {
      Quickshell.execDetached([root.omarchyPath + "/bin/omasnap", "--notify", row.path])
    } else {
      var text = String(row.fullText || "")
      if (!text) return
      // let omarchy-clipboard-open logic be approximated: write temp then open editor
      Quickshell.execDetached(["bash", "-lc", "set -euo pipefail; d=\"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/clipboard-hub/open\"; mkdir -p \"$d\"; f=$(mktemp --tmpdir=\"$d\" clipboard.XXXXXX.txt); printf '%s' \"$1\" > \"$f\"; exec omarchy-launch-editor \"$f\"", "bash", text])
    }
  }

  function togglePinAtDisplayIndex(index) {
    if (index < 0 || index >= clipboardModel.count) return
    var row = clipboardModel.get(index)
    root.history = ClipboardModel.togglePinned(root.history, row.historyIndex)
    root.saveHistory()
    root.disarmPointer()
    root.rebuildClipboardDisplay()
  }

  function removeAtDisplayIndex(index) {
    if (index < 0 || index >= clipboardModel.count) return
    var row = clipboardModel.get(index)
    root.history = ClipboardModel.removeEntryAt(root.history, row.historyIndex)
    root.saveHistory()
    root.disarmPointer()
    if (clipboardModel.count <= 1) root.selectedIndex = 0
    else if (root.selectedIndex >= clipboardModel.count - 1) root.selectedIndex = Math.max(0, clipboardModel.count - 2)
    root.rebuildClipboardDisplay()
  }

  function requestClearUnpinned() {
    if (ClipboardModel.unpinnedCount(root.history) === 0) return
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function cancelClearUnpinned() {
    root.clearConfirmOpen = false
    root.disarmPointer()
    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  function confirmClearUnpinned() {
    root.history = ClipboardModel.clearUnpinned(root.history)
    root.saveHistory()
    root.clearConfirmOpen = false
    root.selectedIndex = 0
    root.cursorActive = clipboardModel.count > 0
    root.disarmPointer()
    root.rebuildClipboardDisplay()
    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  function loadEmojis(raw) {
    root.emojis = EmojiSearch.parseEmojis(raw)
    if (root.opened) root.rebuildEmojiDisplay()
  }

  function selectEmoji(delta) {
    if (emojiModel.count === 0) return
    if (!emojiCursorActive) {
      emojiCursorActive = true
      emojiSelectedIndex = delta < 0 ? emojiModel.count - 1 : 0
    } else {
      emojiSelectedIndex = (emojiSelectedIndex + delta + emojiModel.count) % emojiModel.count
    }
    emojiGrid.positionViewAtIndex(emojiSelectedIndex, GridView.Contain)
  }

  function selectEmojiRow(delta) {
    if (emojiModel.count === 0) return
    if (!emojiCursorActive) {
      emojiCursorActive = true
      emojiSelectedIndex = delta < 0 ? emojiModel.count - 1 : 0
      emojiGrid.positionViewAtIndex(emojiSelectedIndex, GridView.Contain)
      return
    }
    var newIndex = emojiSelectedIndex + delta * emojiColumns
    if (newIndex < 0) newIndex = 0
    if (newIndex >= emojiModel.count) newIndex = emojiModel.count - 1
    emojiSelectedIndex = newIndex
    emojiGrid.positionViewAtIndex(emojiSelectedIndex, GridView.Contain)
  }

  function selectEmojiPage(delta) {
    if (emojiModel.count === 0) return
    if (!emojiCursorActive) {
      emojiCursorActive = true
      emojiSelectedIndex = delta < 0 ? emojiModel.count - 1 : 0
      emojiGrid.positionViewAtIndex(emojiSelectedIndex, GridView.Contain)
      return
    }
    var visibleRows = Math.max(1, Math.floor(emojiGrid.height / emojiCellHeight))
    var newIndex = emojiSelectedIndex + delta * emojiColumns * visibleRows
    if (newIndex < 0) newIndex = 0
    if (newIndex >= emojiModel.count) newIndex = emojiModel.count - 1
    emojiSelectedIndex = newIndex
    emojiGrid.positionViewAtIndex(emojiSelectedIndex, GridView.Contain)
  }

  function activateEmojiIndex(index) {
    if (index < 0 || index >= emojiModel.count) return
    var row = emojiModel.get(index)
    if (!row || !row.emoji) return
    root.opened = false
    Quickshell.execDetached([root.emojiInsertScript, row.emoji])
  }

  Component.onCompleted: initProc.running = true

  ListModel { id: clipboardModel }
  ListModel { id: emojiModel }

  PointerMoveGate { id: pointerGate; referenceItem: card }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
    onFileChanged: reload()
  }

  FileView {
    path: root.omarchyPath + "/shell/plugins/emojis/emojis.json"
    onLoaded: root.loadEmojis(text())
  }

  Process {
    id: initProc
    command: ["pkill", "-f", "wl-paste .*--watch .*clipboard-hub/capture\\.sh"]
    onExited: {
      currentProc.running = true
      textWatchProc.running = true
      imageWatchProc.running = true
    }
  }

  Process {
    id: currentProc
    command: [root.captureScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addClipboardJson(text)
    }
  }

  Process {
    id: textWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Process {
    id: imageWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.captureScript, "image/png"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Timer {
    id: watchRestartTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!textWatchProc.running) textWatchProc.running = true
      if (!imageWatchProc.running) imageWatchProc.running = true
    }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "clipboard-hub"

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.clearConfirmOpen ? 20 : 0
        // Focus is on filterInput, which forwards every key here first.
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.activeTab === "clipboard" && root.clearConfirmOpen) {
            if (clearConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (event.key === Qt.Key_Escape) {
            if (root.activeTab === "clipboard" && root.filterText) root.setClipboardFilter("")
            else if (root.activeTab === "emoji" && root.emojiFilterText) root.setEmojiFilter("")
            else root.close()
            event.accepted = true
            return
          }

          if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ControlModifier)) {
            root.setTab(root.activeTab === "clipboard" ? "emoji" : "clipboard")
            event.accepted = true
            return
          }

          if (root.activeTab === "clipboard") {
            if (Util.editsFilter(event, root.filterText)) {
              root.setClipboardFilter(Util.editedFilter(event, root.filterText))
              event.accepted = true
            } else if (event.key === Qt.Key_Delete) {
              if (event.modifiers & Qt.ShiftModifier) root.requestClearUnpinned()
              else root.removeAtDisplayIndex(root.selectedIndex)
              event.accepted = true
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P) {
              root.togglePinAtDisplayIndex(root.selectedIndex)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.selectClipboard(-1); event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.selectClipboard(1); event.accepted = true
            } else if (event.key === Qt.Key_PageUp) {
              root.selectClipboard(-6); event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
              root.selectClipboard(6); event.accepted = true
            } else if (event.key === Qt.Key_Home) {
              root.selectClipboardAbsolute(0); event.accepted = true
            } else if (event.key === Qt.Key_End) {
              root.selectClipboardAbsolute(clipboardModel.count - 1); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (root.cursorActive && (event.modifiers & Qt.AltModifier)) root.openClipboardIndex(root.selectedIndex)
              else if (root.cursorActive && (event.modifiers & Qt.ShiftModifier)) root.copyClipboardIndex(root.selectedIndex)
              else if (root.cursorActive) root.activateClipboardIndex(root.selectedIndex)
              else if (clipboardModel.count > 0) root.cursorActive = true
              event.accepted = true
            }
          } else {
            if (Util.editsFilter(event, root.emojiFilterText)) {
              root.setEmojiFilter(Util.editedFilter(event, root.emojiFilterText))
              event.accepted = true
            } else if (Util.readingKey(event) === Qt.Key_Left) {
              root.selectEmoji(-1); event.accepted = true
            } else if (Util.readingKey(event) === Qt.Key_Right) {
              root.selectEmoji(1); event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.selectEmojiRow(-1); event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.selectEmojiRow(1); event.accepted = true
            } else if (event.key === Qt.Key_PageUp) {
              root.selectEmojiPage(-1); event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
              root.selectEmojiPage(1); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (root.emojiCursorActive) root.activateEmojiIndex(root.emojiSelectedIndex)
              else if (emojiModel.count > 0) root.emojiCursorActive = true
              event.accepted = true
            }
          }
        }

        ConfirmDialog {
          id: clearConfirm
          anchors.fill: parent
          opened: root.clearConfirmOpen
          z: 10
          message: "Clear all unpinned clipboard items? Pinned items will be kept."
          confirmText: "Clear"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelClearUnpinned()
          onConfirmed: root.confirmClearUnpinned()
        }

        Column {
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          spacing: root.contentSpacing

          Item {
            width: parent.width
            height: root.headerHeight

            Rectangle {
              id: clipboardTab
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: root.headerHeight
              height: parent.height
              radius: root.cornerRadius
              color: root.activeTab === "clipboard" ? root.selectionBackground : "transparent"
              border.width: root.activeTab === "clipboard" ? 0 : 1
              border.color: Util.alpha(root.border, 0.25)

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "󰅌"
                color: root.activeTab === "clipboard" ? root.selectionText : root.foreground
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.heading
              }
              MouseArea { anchors.fill: parent; onClicked: root.setTab("clipboard") }
            }

            Rectangle {
              id: emojiTab
              anchors.left: clipboardTab.right
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              width: root.headerHeight
              height: parent.height
              radius: root.cornerRadius
              color: root.activeTab === "emoji" ? root.selectionBackground : "transparent"
              border.width: root.activeTab === "emoji" ? 0 : 1
              border.color: Util.alpha(root.border, 0.25)

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "󰞅"
                color: root.activeTab === "emoji" ? root.selectionText : root.foreground
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.heading
              }
              MouseArea { anchors.fill: parent; onClicked: root.setTab("emoji") }
            }

            Rectangle {
              id: clearBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: root.activeTab === "clipboard"
              width: root.compactLayout ? root.headerHeight : Math.max(Style.space(58), clearLabel.implicitWidth + Style.space(10))
              height: parent.height
              radius: root.cornerRadius
              color: clearMouse.containsMouse ? Util.alpha(root.selectionBackground, 0.5) : "transparent"
              border.width: 1
              border.color: Util.alpha(root.border, 0.25)
              opacity: ClipboardModel.unpinnedCount(root.history) > 0 ? 1 : 0.45

              Text {
                id: clearLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.compactLayout ? "󰆴" : "Clear all"
                color: root.foreground
                font.family: root.compactLayout ? "JetBrainsMono Nerd Font" : root.fontFamily
                font.pixelSize: root.compactLayout ? Style.font.iconLarge : Style.font.body
              }
              MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: ClipboardModel.unpinnedCount(root.history) > 0
                onClicked: root.requestClearUnpinned()
              }
            }

            Rectangle {
              id: detailBtn
              visible: root.activeTab === "clipboard" && root.compactLayout
              anchors.right: clearBtn.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: root.headerHeight
              height: parent.height
              radius: root.cornerRadius
              color: detailMouse.containsMouse ? Util.alpha(root.selectionBackground, 0.35) : "transparent"
              border.width: 1
              border.color: Util.alpha(root.border, 0.25)

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.compactPreview ? "󰅁" : "󰈈"
                color: root.foreground
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.iconLarge
              }
              MouseArea {
                id: detailMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.compactPreview = !root.compactPreview
              }
            }

            Rectangle {
              id: searchBox
              anchors.left: emojiTab.right
              anchors.leftMargin: Style.space(8)
              anchors.right: root.activeTab === "clipboard" ? (root.compactLayout ? detailBtn.left : clearBtn.left) : parent.right
              anchors.rightMargin: root.activeTab === "clipboard" ? Style.space(8) : 0
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height
              radius: root.cornerRadius
              color: "transparent"

              TextInput {
                id: filterInput
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                focus: true
                clip: true
                Keys.priority: Keys.BeforeItem
                Keys.forwardTo: [keyCatcher]
                Keys.onPressed: function(event) {
                  if (event.modifiers & (Qt.AltModifier | Qt.MetaModifier)) event.accepted = true
                }
                maximumLength: 200
                selectByMouse: true
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                onTextChanged: {
                  if (root.activeTab === "clipboard") {
                    if (text !== root.filterText) root.setClipboardFilter(text)
                  } else {
                    if (text !== root.emojiFilterText) root.setEmojiFilter(text)
                  }
                }
              }

              Text {
                anchors.fill: filterInput
                verticalAlignment: Text.AlignVCenter
                visible: !(root.activeTab === "clipboard" ? root.filterText : root.emojiFilterText) && !filterInput.preeditText
                textFormat: Text.PlainText
                text: root.activeTab === "clipboard" ? "Search clipboard…" : "Search emoji…"
                color: root.foreground
                opacity: 0.58
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
            }
          }

          Item {
            width: parent.width
            height: parent.height - root.headerHeight - root.contentSpacing

            // Clipboard view
            Item {
              anchors.fill: parent
              visible: root.activeTab === "clipboard"

              Row {
                anchors.fill: parent
                spacing: 0

                Item {
                  width: root.compactLayout ? parent.width : (root.compactPreview ? 0 : parent.width * 0.68)
                  visible: width > 0
                  height: parent.height
                  clip: true

                  ListView {
                    id: resultList
                    anchors.fill: parent
                    anchors.rightMargin: root.contentMargin
                    model: clipboardModel
                    clip: true
                    spacing: Style.space(4)
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                      id: rowItem
                      required property int index
                      required property string entryType
                      required property string previewText
                      required property string fullText
                      required property string previewImage
                      required property string path
                      required property string mime
                      required property int historyIndex
                      required property bool pinned
                      required property string section

                      readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
                      readonly property bool showPinnedHeader: {
                        if (!pinned) return false
                        if (index <= 0 || index - 1 >= clipboardModel.count) return true
                        var previous = clipboardModel.get(index - 1)
                        return !previous || !previous.pinned
                      }
                      readonly property bool showRecentHeader: {
                        if (pinned) return false
                        if (index <= 0 || index - 1 >= clipboardModel.count) return ClipboardModel.pinnedCount(root.history) > 0
                        var previous = clipboardModel.get(index - 1)
                        return !previous || !!previous.pinned
                      }

                      width: ListView.view.width
                      height: root.rowHeight + ((showPinnedHeader || showRecentHeader) ? Style.space(16) : 0)
                      radius: root.cornerRadius
                      color: "transparent"

                      Column {
                        anchors.fill: parent
                        spacing: 0

                        Item {
                          visible: rowItem.showPinnedHeader || rowItem.showRecentHeader
                          width: parent.width
                          height: visible ? Style.space(16) : 0
                          Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Style.space(6)
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: rowItem.showPinnedHeader ? "Pinned" : "Recent"
                            color: root.foreground
                            opacity: 0.65
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                        }

                        Rectangle {
                          width: parent.width
                          height: root.rowHeight
                          radius: root.cornerRadius
                          color: rowItem.hasCursor ? root.selectionBackground : "transparent"

                          Row {
                            anchors.fill: parent
                            anchors.leftMargin: Style.space(8)
                            anchors.rightMargin: Style.space(6)
                            anchors.topMargin: Style.space(3)
                            anchors.bottomMargin: Style.space(3)
                            spacing: Style.space(2)

                            SizedImage {
                              id: rowThumb
                              visible: rowItem.previewImage.length > 0
                              width: visible ? Math.min(parent.height, root.rowThumbSize) : 0
                              height: parent.height
                              url: rowItem.previewImage
                              asynchronous: true
                              smooth: true
                            }

                            Text {
                              textFormat: Text.PlainText
                              width: parent.width - (rowItem.previewImage.length > 0 ? rowThumb.width + parent.spacing : 0) - copyBtn.width - pinBtn.width - delBtn.width - parent.spacing * 3
                              height: parent.height
                              text: rowItem.previewText
                              color: rowItem.hasCursor ? root.selectionText : root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              opacity: rowItem.entryType === "image" || rowItem.entryType === "file" ? 0.78 : 1.0
                              elide: Text.ElideRight
                              wrapMode: Text.NoWrap
                              verticalAlignment: Text.AlignVCenter
                            }

                            Rectangle {
                              id: copyBtn
                              width: root.actionButtonWidth
                              height: parent.height
                              radius: root.cornerRadius
                              color: copyMouse.containsMouse ? Util.alpha(root.foreground, 0.08) : "transparent"
                              Text {
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: "󰆏"
                                color: rowItem.hasCursor ? root.selectionText : root.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Style.font.iconLarge
                              }
                              MouseArea {
                                id: copyMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.copyClipboardIndex(rowItem.index)
                              }
                            }

                            Rectangle {
                              id: pinBtn
                              width: root.actionButtonWidth
                              height: parent.height
                              radius: root.cornerRadius
                              color: pinMouse.containsMouse ? Util.alpha(root.foreground, 0.08) : "transparent"
                              Text {
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: rowItem.pinned ? "󰐄" : "󰤱"
                                color: rowItem.pinned
                                  ? Commons.Color.accent
                                  : (rowItem.hasCursor ? root.selectionText : root.foreground)
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Style.font.iconLarge
                              }
                              MouseArea {
                                id: pinMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.togglePinAtDisplayIndex(rowItem.index)
                              }
                            }

                            Rectangle {
                              id: delBtn
                              width: root.actionButtonWidth
                              height: parent.height
                              radius: root.cornerRadius
                              color: delMouse.containsMouse ? Util.alpha(root.foreground, 0.08) : "transparent"
                              Text {
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: "󰆴"
                                color: rowItem.hasCursor ? root.selectionText : root.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Style.font.iconLarge
                              }
                              MouseArea {
                                id: delMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.removeAtDisplayIndex(rowItem.index)
                              }
                            }
                          }

                          MouseArea {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.rightMargin: copyBtn.width + pinBtn.width + delBtn.width + Style.space(24)
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: function(mouse) { root.selectFromPointer(rowItem.index, rowItem, mouse) }
                            onClicked: {
                              root.cursorActive = true
                              root.selectedIndex = rowItem.index
                              root.copyClipboardIndex(rowItem.index)
                            }
                          }
                        }
                      }
                    }
                  }
                }

                Item {
                  width: root.compactLayout ? (root.compactPreview ? parent.width : 0) : parent.width * 0.32
                  visible: width > 0
                  height: parent.height
                  clip: true
                  property var activeRow: clipboardModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < clipboardModel.count ? clipboardModel.get(root.selectedIndex) : null

                  Rectangle {
                    visible: clipboardModel.count > 0
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Style.normalBorderWidth
                    color: Util.alpha(root.border, 0.28)
                  }

                  Column {
                    anchors.fill: parent
                    anchors.leftMargin: root.contentMargin
                    anchors.rightMargin: root.contentMargin
                    spacing: Style.space(4)
                    visible: parent.activeRow !== null

                    Text {
                      id: labelText
                      textFormat: Text.PlainText
                      width: parent.width
                      text: {
                        var r = parent.parent.activeRow
                        if (!r) return ""
                        var label = r.pinned ? "Pinned · " : ""
                        label += (r.entryType === "image" ? "Image" : (r.entryType === "file" ? "File" : "Text"))
                        return label
                      }
                      color: root.foreground
                      opacity: 0.7
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      visible: parent.parent.activeRow && !parent.parent.activeRow.previewImage
                      width: parent.width
                      height: Math.max(0, parent.height - labelText.height - parent.spacing)
                      text: parent.parent.activeRow ? parent.parent.activeRow.fullText : ""
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      wrapMode: Text.WrapAnywhere
                      elide: Text.ElideRight
                      verticalAlignment: Text.AlignTop
                    }

                    SizedImage {
                      id: previewImage
                      visible: parent.parent.activeRow && parent.parent.activeRow.previewImage
                      width: parent.width
                      height: Math.max(0, parent.height - labelText.height - parent.spacing)
                      url: parent.parent.activeRow ? parent.parent.activeRow.previewImage : ""
                      verticalAlignment: Image.AlignTop
                      asynchronous: true
                      smooth: true
                    }
                  }
                }
              }

              Column {
                anchors.centerIn: parent
                width: parent.width - 2 * root.contentMargin
                spacing: Style.space(8)
                visible: clipboardModel.count === 0

                Text {
                  text: "󰅌"
                  color: root.selectedText
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.history.length === 0 ? "Clipboard is empty" : "No matches"
                  color: root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                  elide: Text.ElideRight
                }
              }
            }

            // Emoji view
            Item {
              anchors.fill: parent
              visible: root.activeTab === "emoji"

              GridView {
                id: emojiGrid
                anchors.fill: parent
                model: emojiModel
                clip: true
                cellWidth: root.emojiCellWidth
                cellHeight: root.emojiCellHeight
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  required property int index
                  required property string emoji
                  readonly property bool hasCursor: root.emojiCursorActive && index === root.emojiSelectedIndex
                  width: root.emojiCellWidth
                  height: root.emojiCellHeight
                  radius: root.cornerRadius
                  color: hasCursor ? root.selectionBackground : "transparent"

                  Text {
                    textFormat: Text.PlainText
                    text: parent.emoji
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.displayLarge
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) { root.emojiCursorActive = true; root.emojiSelectedIndex = index }
                    onClicked: {
                      root.emojiCursorActive = true
                      root.emojiSelectedIndex = index
                      root.activateEmojiIndex(index)
                    }
                  }
                }
              }

              Column {
                anchors.centerIn: parent
                width: parent.width - 2 * root.contentMargin
                spacing: Style.space(8)
                visible: emojiModel.count === 0

                Text {
                  text: "󰞅"
                  color: root.selectedText
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.emojiFilterText ? "No emoji matches" : "No emoji available"
                  color: root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                  elide: Text.ElideRight
                }
              }
            }
          }
        }
      }
    }
  }
}
