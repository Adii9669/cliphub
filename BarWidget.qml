import QtQuick
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "adii9669.clipboard-hub"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function openMenu() {
    if (!root.bar) return
    root.bar.run("omarchy-shell shell toggle adii9669.clipboard-hub '{\"tab\":\"clipboard\"}'")
  }

  BarIconButton {
    id: button
    width: Math.max(implicitWidth, Style.space(22))
    height: parent.height > 0 ? parent.height : implicitHeight
    bar: root.bar
    text: "󰅌"
    fontFamily: "JetBrainsMono Nerd Font"
    fontSize: Style.font.iconLarge
    onPressed: function() { root.openMenu() }
  }
}
