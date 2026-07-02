(function () {
  function elementClosest(target, selector) {
    if (!target) return null;
    if (target.nodeType !== 1) target = target.parentElement;
    return target && target.closest ? target.closest(selector) : null;
  }

  function localFiles(dataTransfer) {
    if (!dataTransfer) return false;
    if (dataTransfer.files && dataTransfer.files.length) return true;
    return Array.prototype.indexOf.call(dataTransfer.types || [], "Files") >= 0;
  }

  function readDirectoryEntries(reader) {
    var entries = [];
    return new Promise(function (resolve, reject) {
      function readBatch() {
        reader.readEntries(function (batch) {
          if (!batch.length) {
            resolve(entries);
            return;
          }
          entries = entries.concat(Array.prototype.slice.call(batch));
          readBatch();
        }, reject);
      }
      readBatch();
    });
  }

  function readDroppedEntry(entry, parent, result) {
    var relativePath = parent ? parent + "/" + entry.name : entry.name;
    if (entry.isFile) {
      return new Promise(function (resolve, reject) {
        entry.file(function (file) {
          result.files.push(file);
          result.paths.push(relativePath);
          resolve();
        }, reject);
      });
    }
    if (!entry.isDirectory) return Promise.resolve();
    result.directories.push(relativePath);
    return readDirectoryEntries(entry.createReader()).then(function (children) {
      return Promise.all(children.map(function (child) {
        return readDroppedEntry(child, relativePath, result);
      }));
    });
  }

  function droppedFiles(dataTransfer) {
    var result = { files: [], paths: [], directories: [] };
    var items = Array.prototype.slice.call(dataTransfer && dataTransfer.items || []);
    var entries = items.map(function (item) {
      return item.kind === "file" && item.webkitGetAsEntry
        ? item.webkitGetAsEntry()
        : null;
    }).filter(Boolean);

    if (entries.length) {
      return Promise.all(entries.map(function (entry) {
        return readDroppedEntry(entry, "", result);
      })).then(function () {
        return result;
      });
    }

    result.files = Array.prototype.slice.call(
      dataTransfer && dataTransfer.files || []
    );
    result.paths = result.files.map(function (file) { return file.name; });
    return Promise.resolve(result);
  }

  function rowDestination(row, fallback) {
    if (!row) return fallback();
    return row.getAttribute("data-type") === "directory"
      ? row.getAttribute("data-path")
      : row.getAttribute("data-parent");
  }

  function createSelectionBox() {
    var box = document.createElement("div");
    box.className = "ullme-material-selection-box";
    document.body.appendChild(box);
    return box;
  }

  function rectanglesIntersect(left, right) {
    return !(
      left.right < right.left ||
      left.left > right.right ||
      left.bottom < right.top ||
      left.top > right.bottom
    );
  }

  function create(options) {
    var surface = options.surface;
    var rows = options.rows;
    if (!surface || !rows) return null;

    var dragPaths = [];
    var activeDropRow = null;
    var pointer = null;

    function clearDropTarget() {
      if (activeDropRow) {
        activeDropRow.classList.remove("ullme-material-folder-drop-active");
        activeDropRow = null;
      }
      surface.classList.remove("ullme-material-tree-drop-active");
    }

    function showDropTarget(row) {
      if (row === activeDropRow) return;
      clearDropTarget();
      if (row) {
        activeDropRow = row;
        row.classList.add("ullme-material-folder-drop-active");
      } else {
        surface.classList.add("ullme-material-tree-drop-active");
      }
    }

    function dropPayload(event, destination) {
      if (localFiles(event.dataTransfer)) {
        droppedFiles(event.dataTransfer).then(function (drop) {
          if (!drop.files.length && !drop.directories.length) return;
          options.uploadFiles(
            drop.files,
            destination,
            drop.paths,
            drop.directories
          );
        }).catch(function (error) {
          window.alert(
            "The dropped folder could not be read: " +
            (error && error.message ? error.message : String(error))
          );
        });
        return;
      }
      var paths = dragPaths;
      if (!paths.length && event.dataTransfer) {
        try {
          paths = JSON.parse(
            event.dataTransfer.getData("application/x-ullme-material-paths") || "[]"
          );
        } catch (error) {
          paths = [];
        }
      }
      options.movePaths(paths, destination);
    }

    rows.addEventListener("dragstart", function (event) {
      var handle = elementClosest(
        event.target,
        ".ullme-material-tree-file .ullme-material-tree-name"
      );
      if (!handle) return;
      var row = handle.closest(".ullme-material-tree-file");
      var path = row && row.getAttribute("data-path");
      if (!path) return;
      var selected = options.getSelectedPaths();
      if (selected.indexOf(path) < 0) {
        selected = [path];
        options.setSelectedPaths(selected, false);
        var checkbox = row.querySelector(".ullme-material-tree-check");
        if (checkbox) checkbox.checked = true;
      }
      dragPaths = selected;
      row.classList.add("ullme-material-tree-dragging");
      if (event.dataTransfer) {
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData(
          "application/x-ullme-material-paths",
          JSON.stringify(dragPaths)
        );
        event.dataTransfer.setData("text/plain", dragPaths.join("\n"));
      }
    });

    rows.addEventListener("dragend", function () {
      dragPaths = [];
      clearDropTarget();
      options.selectionComplete();
    });

    surface.addEventListener("dragover", function (event) {
      if (!localFiles(event.dataTransfer) && !dragPaths.length) return;
      event.preventDefault();
      var row = elementClosest(event.target, ".ullme-material-tree-row");
      showDropTarget(row && rows.contains(row) ? row : null);
      if (event.dataTransfer) {
        event.dataTransfer.dropEffect =
          localFiles(event.dataTransfer) ? "copy" : "move";
      }
    });

    surface.addEventListener("dragleave", function (event) {
      if (event.relatedTarget && surface.contains(event.relatedTarget)) return;
      clearDropTarget();
    });

    surface.addEventListener("drop", function (event) {
      if (!localFiles(event.dataTransfer) && !dragPaths.length) return;
      event.preventDefault();
      var row = elementClosest(event.target, ".ullme-material-tree-row");
      var destination = rowDestination(
        row && rows.contains(row) ? row : null,
        options.currentDestination
      );
      clearDropTarget();
      dropPayload(event, destination);
    });

    rows.addEventListener("pointerdown", function (event) {
      if (event.button !== 0) return;
      if (elementClosest(event.target, "button, input, select, a")) return;
      var preserve = event.ctrlKey || event.metaKey;
      pointer = {
        id: event.pointerId,
        startX: event.clientX,
        startY: event.clientY,
        preserve: preserve,
        base: preserve ? options.getSelectedPaths() : [],
        moved: false,
        box: null
      };
      rows.setPointerCapture(event.pointerId);
    });

    rows.addEventListener("pointermove", function (event) {
      if (!pointer || pointer.id !== event.pointerId) return;
      var distance = Math.max(
        Math.abs(event.clientX - pointer.startX),
        Math.abs(event.clientY - pointer.startY)
      );
      if (!pointer.moved && distance < 4) return;
      if (!pointer.moved) {
        pointer.moved = true;
        pointer.box = createSelectionBox();
        document.body.classList.add("ullme-material-rectangle-selecting");
      }
      event.preventDefault();

      var selectionRect = {
        left: Math.min(pointer.startX, event.clientX),
        right: Math.max(pointer.startX, event.clientX),
        top: Math.min(pointer.startY, event.clientY),
        bottom: Math.max(pointer.startY, event.clientY)
      };
      pointer.box.style.left = selectionRect.left + "px";
      pointer.box.style.top = selectionRect.top + "px";
      pointer.box.style.width = (selectionRect.right - selectionRect.left) + "px";
      pointer.box.style.height = (selectionRect.bottom - selectionRect.top) + "px";

      var selected = pointer.base.slice();
      Array.prototype.forEach.call(
        rows.querySelectorAll(".ullme-material-tree-file"),
        function (row) {
          var path = row.getAttribute("data-path");
          var hit = rectanglesIntersect(selectionRect, row.getBoundingClientRect());
          if (hit && selected.indexOf(path) < 0) selected.push(path);
          var checkbox = row.querySelector(".ullme-material-tree-check");
          if (checkbox) checkbox.checked = selected.indexOf(path) >= 0;
        }
      );
      options.setSelectedPaths(selected, false);
    });

    function finishPointer(event) {
      if (!pointer || pointer.id !== event.pointerId) return;
      var moved = pointer.moved;
      if (pointer.box) pointer.box.remove();
      document.body.classList.remove("ullme-material-rectangle-selecting");
      if (rows.hasPointerCapture(event.pointerId)) {
        rows.releasePointerCapture(event.pointerId);
      }
      pointer = null;
      if (moved) {
        options.selectionComplete();
      } else if (!event.ctrlKey && !event.metaKey) {
        options.setSelectedPaths([], true);
      }
    }

    rows.addEventListener("pointerup", finishPointer);
    rows.addEventListener("pointercancel", finishPointer);

    return {
      clear: function () {
        dragPaths = [];
        clearDropTarget();
      }
    };
  }

  window.ullmeMaterialInteractions = {
    create: create
  };
})();
