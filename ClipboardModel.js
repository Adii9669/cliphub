var displayTextLimit = 8192

// Stable, content-derived IDs let row actions target the exact item the user
// selected, even if the underlying history is reordered before the click.
function hashString(value) {
  var str = String(value || "")
  var h = 0x811c9dc5
  for (var i = 0; i < str.length; i++) {
    h = Math.imul(h ^ str.charCodeAt(i), 0x01000193) >>> 0
  }
  return ("00000000" + h.toString(16)).slice(-8)
}

function makeId(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image:" + String(entry.path || "")
  return "text:" + hashString(String(entry.text || ""))
}

function normalizeEntry(value) {
  if (typeof value === "string") {
    if (value.trim().length === 0) return null
    var s = { type: "text", text: value, pinned: false }
    s.id = makeId(s)
    return s
  }

  if (!value || typeof value !== "object") return null

  var type = String(value.type || value.kind || "")
  var pinned = !!value.pinned

  if (type === "text") {
    var text = String(value.text || "")
    if (text.trim().length === 0) return null
    var t = { type: "text", text: text, pinned: pinned }
    t.id = String(value.id || "") || makeId(t)
    if (value.updatedAt !== undefined && value.updatedAt !== null) t.updatedAt = String(value.updatedAt)
    return t
  }

  if (type === "image") {
    var path = String(value.path || "")
    if (!path) return null
    var img = {
      type: "image",
      path: path,
      mime: String(value.mime || "image/png"),
      pinned: pinned
    }
    img.id = String(value.id || "") || makeId(img)
    if (value.capturedAt !== undefined && value.capturedAt !== null)
      img.capturedAt = String(value.capturedAt)
    if (value.updatedAt !== undefined && value.updatedAt !== null)
      img.updatedAt = String(value.updatedAt)
    return img
  }

  return null
}

function entryKey(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image:" + String(entry.path || "")
  return "text:" + String(entry.text || "")
}

function parseHistory(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    var next = []
    if (!Array.isArray(parsed)) return next
    for (var i = 0; i < parsed.length; i++) {
      var entry = normalizeEntry(parsed[i])
      if (entry) next.push(entry)
    }
    return next
  } catch (e) {
    return []
  }
}

function pinnedCount(history) {
  var values = Array.isArray(history) ? history : []
  var n = 0
  for (var i = 0; i < values.length; i++) if (values[i] && values[i].pinned) n++
  return n
}

function unpinnedCount(history) {
  var values = Array.isArray(history) ? history : []
  var n = 0
  for (var i = 0; i < values.length; i++) if (values[i] && !values[i].pinned) n++
  return n
}

function addEntry(history, entry, unpinnedLimit) {
  var normalized = normalizeEntry(entry)
  var values = Array.isArray(history) ? history : []
  var limit = unpinnedLimit === undefined || unpinnedLimit === null ? 200 : Number(unpinnedLimit)
  if (isNaN(limit)) limit = 200
  limit = Math.max(0, limit)
  if (!normalized) return capUnpinned(values, limit)

  var key = entryKey(normalized)
  var wasPinned = false
  var existing = null

  for (var i = 0; i < values.length; i++) {
    var e = normalizeEntry(values[i])
    if (!e) continue
    if (entryKey(e) === key) {
      wasPinned = wasPinned || !!e.pinned
      if (!existing) existing = e
    }
  }

  normalized.pinned = wasPinned || !!normalized.pinned
  if (existing && existing.capturedAt && !normalized.capturedAt) normalized.capturedAt = existing.capturedAt

  var next = [normalized]
  for (var j = 0; j < values.length; j++) {
    var cur = normalizeEntry(values[j])
    if (!cur) continue
    if (entryKey(cur) === key) continue
    next.push(cur)
  }

  return capUnpinned(next, limit)
}

function capUnpinned(history, unpinnedLimit) {
  var values = Array.isArray(history) ? history : []
  var limit = unpinnedLimit === undefined || unpinnedLimit === null ? 200 : Number(unpinnedLimit)
  if (isNaN(limit)) limit = 200
  limit = Math.max(0, limit)
  var out = []
  var unpinnedSeen = 0
  for (var i = 0; i < values.length; i++) {
    var e = normalizeEntry(values[i])
    if (!e) continue
    if (e.pinned) {
      out.push(e)
    } else {
      if (unpinnedSeen < limit) {
        out.push(e)
        unpinnedSeen++
      }
    }
  }
  return out
}

function togglePinnedById(history, id) {
  var values = Array.isArray(history) ? history : []
  var wanted = String(id || "")
  if (!wanted) return values.slice()
  var out = []
  for (var i = 0; i < values.length; i++) {
    var e = normalizeEntry(values[i])
    if (!e) continue
    if (String(e.id || makeId(e)) === wanted) e.pinned = !e.pinned
    out.push(e)
  }
  return out
}

function removeById(history, id) {
  var values = Array.isArray(history) ? history : []
  var wanted = String(id || "")
  if (!wanted) return values.slice()
  var out = []
  for (var i = 0; i < values.length; i++) {
    var e = normalizeEntry(values[i])
    if (!e) continue
    if (String(e.id || makeId(e)) === wanted) continue
    out.push(e)
  }
  return out
}

function clearUnpinned(history) {
  var values = Array.isArray(history) ? history : []
  var out = []
  for (var i = 0; i < values.length; i++) {
    var e = normalizeEntry(values[i])
    if (e && e.pinned) out.push(e)
  }
  return out
}

function parseEntryJson(line) {
  var raw = String(line || "").trim()
  if (!raw) return null
  try { return normalizeEntry(JSON.parse(raw)) } catch (e) { return null }
}

function searchableText(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image screenshot pinned " + String(entry.mime || "") + " " + String(entry.capturedAt || "")
  return String(entry.text || "") + " " + fileEntryText(entry)
}

function decodeFileUri(uri) {
  var value = String(uri || "").trim()
  if (value.indexOf("file://") !== 0) return ""
  var path = value.substring(7)
  if (path.indexOf("localhost/") === 0) path = path.substring(9)
  if (path.charAt(0) !== "/") return ""
  try { return decodeURIComponent(path) } catch (e) { return path }
}

function filePaths(entry) {
  if (!entry || entry.type !== "text") return []
  var lines = String(entry.text || "").split(/\r?\n/)
  var paths = []
  for (var i = 0; i < lines.length; i++) {
    var path = decodeFileUri(lines[i])
    if (path) paths.push(path)
  }
  return paths
}

function fileName(path) {
  var parts = String(path || "").split("/")
  return parts.length > 0 ? parts[parts.length - 1] : String(path || "")
}

function isImagePath(path) {
  return /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(String(path || ""))
}

function fileEntryText(entry) {
  var paths = filePaths(entry)
  if (paths.length === 0) return ""
  if (paths.length === 1) return fileName(paths[0])
  return paths.length + " files"
}

function imagePreviewText(entry) {
  var timestamp = String(entry && entry.capturedAt || "")
  var screenshot = String(entry && entry.mime || "") === "image/png"
  if (!timestamp) return screenshot ? "Screenshot" : "Image"
  return (screenshot ? "Screenshot from " : "Image from ") + timestamp
}

function previewText(entry) {
  if (!entry) return ""
  if (entry.type === "image") return imagePreviewText(entry)
  var fileText = fileEntryText(entry)
  if (fileText) return fileText
  return String(entry.text || "").replace(/\s+/g, " ")
}

function fullText(entry) {
  if (!entry) return ""
  var paths = filePaths(entry)
  if (paths.length > 0) return paths.join("\n")
  return String(entry.text || "")
}

function cappedEntry(entry) {
  if (!entry || entry.type !== "text" || entry.text.length <= displayTextLimit) return entry
  var cut = entry.text.lastIndexOf("\n", displayTextLimit)
  return {
    type: "text",
    text: entry.text.slice(0, cut > 0 ? cut : displayTextLimit),
    pinned: !!entry.pinned,
    id: entry.id
  }
}

function buildRow(entry, tr, fullEntry) {
  var t = typeof tr === "function" ? tr : function(key, fallback) { return fallback || key }
  var paths = filePaths(entry)
  var isFile = paths.length > 0
  var isImage = entry.type === "image"
  var source = fullEntry || entry
  var previewPath = isImage ? String(entry.path || "") : (isFile && paths.length === 1 && isImagePath(paths[0]) ? paths[0] : "")
  return {
    entryType: isFile ? "file" : entry.type,
    entryId: String(source.id || makeId(source)),
    fullText: isImage ? "" : fullText(entry),
    // Paste/copy use the uncapped source text, never the shortened preview.
    pasteText: isImage ? "" : String(source.text || ""),
    previewText: previewText(entry),
    previewImage: previewPath,
    path: isImage ? String(entry.path || "") : (isFile && paths.length === 1 ? paths[0] : ""),
    mime: isImage ? String(entry.mime || "image/png") : "text/plain",
    pinned: !!entry.pinned
  }
}

function displaySections(history, query, limitPerSection) {
  var values = Array.isArray(history) ? history : []
  var needle = String(query || "").trim().toLowerCase()
  var max = limitPerSection === undefined || limitPerSection === null ? 100 : Number(limitPerSection)
  if (isNaN(max)) max = 100
  max = Math.max(0, max)

  var pinned = []
  var recent = []

  for (var i = 0; i < values.length; i++) {
    var fullEntry = normalizeEntry(values[i])
    var entry = cappedEntry(fullEntry)
    if (!entry) continue
    if (needle && searchableText(fullEntry).toLowerCase().indexOf(needle) < 0) continue
    var row = buildRow(entry, undefined, fullEntry)
    if (entry.pinned) {
      if (pinned.length < max) pinned.push(row)
    } else {
      if (recent.length < max) recent.push(row)
    }
  }

  return { pinned: pinned, recent: recent }
}

function flatDisplayRows(history, query, limitPerSection) {
  var sections = displaySections(history, query, limitPerSection)
  var rows = []
  for (var i = 0; i < sections.pinned.length; i++) {
    var p = sections.pinned[i]
    p.section = "pinned"
    rows.push(p)
  }
  for (var j = 0; j < sections.recent.length; j++) {
    var r = sections.recent[j]
    r.section = "recent"
    rows.push(r)
  }
  return rows
}

function referencedImagePaths(history) {
  var values = Array.isArray(history) ? history : []
  var set = {}
  for (var i = 0; i < values.length; i++) {
    var e = normalizeEntry(values[i])
    if (e && e.type === "image" && e.path) set[String(e.path)] = true
  }
  return set
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeEntry: normalizeEntry,
    entryKey: entryKey,
    parseHistory: parseHistory,
    addEntry: addEntry,
    capUnpinned: capUnpinned,
    togglePinnedById: togglePinnedById,
    removeById: removeById,
    clearUnpinned: clearUnpinned,
    parseEntryJson: parseEntryJson,
    searchableText: searchableText,
    previewText: previewText,
    imagePreviewText: imagePreviewText,
    filePaths: filePaths,
    fileEntryText: fileEntryText,
    fullText: fullText,
    displaySections: displaySections,
    flatDisplayRows: flatDisplayRows,
    referencedImagePaths: referencedImagePaths,
    pinnedCount: pinnedCount,
    unpinnedCount: unpinnedCount
  }
}
