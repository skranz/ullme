(function (root) {
  "use strict";

  function indentation(line) {
    var match = String(line || "").match(/^[ \t]*/);
    return (match ? match[0] : "").replace(/\t/g, "  ").length;
  }

  function yamlKey(line) {
    var match = String(line || "").match(/^([ \t]*)(?:(['"])(.*?)\2|([A-Za-z_][A-Za-z0-9_-]*))\s*:\s*(.*)$/);
    if (!match) return null;
    return {
      indent: indentation(match[1]),
      key: String(match[3] || match[4] || ""),
      rest: String(match[5] || "")
    };
  }

  function scanPaths(text) {
    var lines = String(text || "").split(/\r?\n/);
    var stack = [];
    var paths = [];
    var blockIndent = null;
    lines.forEach(function (line, index) {
      var trimmed = line.trim();
      var indent = indentation(line);
      if (blockIndent != null) {
        if (!trimmed || indent > blockIndent) return;
        blockIndent = null;
      }
      if (!trimmed || trimmed.charAt(0) === "#") return;
      var key = yamlKey(line);
      if (!key) return;
      while (stack.length && stack[stack.length - 1].indent >= key.indent) stack.pop();
      var parts = stack.map(function (item) { return item.key; }).concat([key.key]);
      paths.push({ path: parts.join("."), line: index, indent: key.indent });
      stack.push({ key: key.key, indent: key.indent });
      if (/^[|>]/.test(key.rest)) blockIndent = key.indent;
    });
    return { lines: lines, paths: paths };
  }

  function hasPath(text, path) {
    return scanPaths(text).paths.some(function (item) { return item.path === path; });
  }

  function appendTemplate(text, template) {
    var current = String(text || "").replace(/\s+$/, "");
    return (current ? current + "\n" : "") + String(template || "").trim() + "\n";
  }

  function insertNested(text, parentPath, nestedTemplate) {
    var scanned = scanPaths(text);
    var parent = scanned.paths.find(function (item) { return item.path === parentPath; });
    if (!parent) return null;
    var insertAt = scanned.lines.length;
    for (var i = parent.line + 1; i < scanned.lines.length; i += 1) {
      var key = yamlKey(scanned.lines[i]);
      if (key && key.indent <= parent.indent) { insertAt = i; break; }
    }
    while (insertAt > parent.line + 1 && !scanned.lines[insertAt - 1].trim()) insertAt -= 1;
    var padding = new Array(parent.indent + 3).join(" ");
    var nestedLines = String(nestedTemplate || "").trim().split(/\r?\n/).map(function (line) {
      return padding + line;
    });
    scanned.lines.splice.apply(scanned.lines, [insertAt, 0].concat(nestedLines));
    return scanned.lines.join("\n").replace(/\s+$/, "") + "\n";
  }

  function insertField(text, option) {
    var path = String(option && option.value || "");
    if (!path) return { ok: false, message: "Choose a field first." };
    if (hasPath(text, path)) {
      return { ok: false, duplicate: true, message: path + " already exists in this node." };
    }
    var template = String(option.getAttribute("data-template") || "");
    var nestedTemplate = String(option.getAttribute("data-nested-template") || "");
    var parts = path.split(".");
    var updated = null;
    if (parts.length > 1 && nestedTemplate) {
      var parentPath = parts.slice(0, -1).join(".");
      if (hasPath(text, parentPath)) updated = insertNested(text, parentPath, nestedTemplate);
    }
    if (updated == null) updated = appendTemplate(text, template);
    return { ok: true, value: updated, message: "Added " + path + "." };
  }

  function insertPlaceholder(text, option, selectionStart, selectionEnd) {
    var token = String(option && option.getAttribute("data-insert") || "");
    if (!token) return { ok: false, message: "Choose a placeholder first." };
    text = String(text || "");
    var start = Number.isInteger(selectionStart) ? selectionStart : text.length;
    var end = Number.isInteger(selectionEnd) ? selectionEnd : start;
    start = Math.max(0, Math.min(text.length, start));
    end = Math.max(start, Math.min(text.length, end));
    return {
      ok: true,
      value: text.slice(0, start) + token + text.slice(end),
      cursor: start + token.length,
      message: "Inserted " + token + "."
    };
  }

  function bind(config) {
    config = config || {};
    var select = config.select;
    var textarea = config.textarea;
    var help = config.help;
    if (!select || !textarea || select.dataset.ullmeNodeFieldsBound === "true") return;
    select.dataset.ullmeNodeFieldsBound = "true";
    select.addEventListener("change", function () {
      var option = select.options[select.selectedIndex];
      if (!option || !option.value) return;
      var description = option.getAttribute("title") || "";
      select.title = description;
      if (help) help.title = description;
      var kind = option.getAttribute("data-kind") || "field";
      var result = kind === "placeholder"
        ? insertPlaceholder(textarea.value, option, textarea.selectionStart, textarea.selectionEnd)
        : insertField(textarea.value, option);
      if (result.ok) {
        textarea.value = result.value;
        textarea.focus();
        var cursor = Number.isInteger(result.cursor) ? result.cursor : textarea.value.length;
        textarea.setSelectionRange(cursor, cursor);
      }
      if (typeof config.onStatus === "function") {
        config.onStatus(result.message, Boolean(result.duplicate));
      }
      select.value = "";
    });
  }

  root.ullmeNodeFields = {
    bind: bind, insertField: insertField,
    insertPlaceholder: insertPlaceholder, hasPath: hasPath
  };
  if (typeof module !== "undefined" && module.exports) module.exports = root.ullmeNodeFields;
})(typeof window !== "undefined" ? window : globalThis);
