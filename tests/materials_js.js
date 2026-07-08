const assert = require("assert");

function eventTarget() {
  return {
    listeners: {},
    classList: { add() {}, remove() {} },
    addEventListener(name, listener) {
      this.listeners[name] = listener;
    },
    contains() {
      return false;
    },
    querySelectorAll() {
      return [];
    }
  };
}

global.window = {};
global.document = {
  body: {
    appendChild() {},
    classList: { add() {}, remove() {} }
  },
  createElement() {
    return { className: "", style: {}, remove() {} };
  }
};

require("../inst/www/ullme-materials.js");

const surface = eventTarget();
const rows = eventTarget();
let uploaded = null;
window.ullmeMaterialInteractions.create({
  surface,
  rows,
  uploadFiles(files, destination, paths, directories) {
    uploaded = { files, destination, paths, directories };
  },
  movePaths() {},
  currentDestination() {
    return "general";
  },
  getSelectedPaths() {
    return [];
  },
  setSelectedPaths() {},
  selectionComplete() {}
});

function fileEntry(name) {
  return {
    name,
    isFile: true,
    isDirectory: false,
    file(resolve) {
      resolve({ name });
    }
  };
}

function directoryEntry(name, batches) {
  return {
    name,
    isFile: false,
    isDirectory: true,
    createReader() {
      let index = 0;
      return {
        readEntries(resolve) {
          resolve(batches[index++] || []);
        }
      };
    }
  };
}

const empty = directoryEntry("leer", [[]]);
const nested = directoryEntry("Woche 1", [[fileEntry("Übung1.pdf")], []]);
const folder = directoryEntry("Übungen", [[nested], [empty], []]);
const dataTransfer = {
  files: [],
  types: ["Files"],
  items: [{
    kind: "file",
    webkitGetAsEntry() {
      return folder;
    }
  }]
};

surface.listeners.drop({
  dataTransfer,
  target: null,
  preventDefault() {},
  relatedTarget: null
});

setTimeout(() => {
  assert(uploaded);
  assert.strictEqual(uploaded.destination, "");
  assert.deepStrictEqual(uploaded.paths, ["Übungen/Woche 1/Übung1.pdf"]);
  assert.deepStrictEqual(uploaded.directories, [
    "Übungen",
    "Übungen/Woche 1",
    "Übungen/leer"
  ]);
}, 0);
