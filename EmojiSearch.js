function parseEmojis(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    if (!Array.isArray(parsed)) return []
    var out = []
    for (var i = 0; i < parsed.length; i++) {
      var e = parsed[i]
      if (e && e.e) out.push(e)
    }
    return out
  } catch (e) {
    return []
  }
}

function filterEmojis(emojis, query, limit) {
  var values = Array.isArray(emojis) ? emojis : []
  var needle = String(query || "").trim().toLowerCase()
  var max = limit === undefined || limit === null ? 1000 : Number(limit)
  if (isNaN(max)) max = 1000
  max = Math.max(0, max)
  if (max === 0) return []

  var out = []
  for (var i = 0; i < values.length; i++) {
    var item = values[i]
    if (!item || !item.e) continue
    if (needle) {
      var hay = String(item.e) + " " + String(item.name || "") + " " + String(item.k || "")
      if (hay.toLowerCase().indexOf(needle) < 0) continue
    }
    out.push(item)
    if (out.length >= max) break
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    parseEmojis: parseEmojis,
    filterEmojis: filterEmojis
  }
}
