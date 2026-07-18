const assert = require("assert");
let createdNodes = 0;

function node(tag) {
  createdNodes += 1;
  const item = {
    tagName: tag, children: [], attributes: {}, className: "", textContent: "",
    value: "", checked: false, style: {}, listeners: {},
    classList: { add() {}, remove() {}, contains() { return false; } },
    appendChild(child) { child.parentNode = this; this.children.push(child); return child; },
    addEventListener(type, handler) { this.listeners[type] = handler; },
    click() { if (this.listeners.click) this.listeners.click(); },
    focus() {},
    setAttribute(key, value) { this.attributes[key] = value; },
    querySelectorAll() { return []; },
    remove() {
      if (this.parentNode) this.parentNode.children = this.parentNode.children.filter(child => child !== this);
    }
  };
  Object.defineProperty(item, "innerHTML", {
    get() { return this._innerHTML || ""; },
    set(value) { this._innerHTML = value; if (value === "") this.children = []; }
  });
  return item;
}

const workspace = node("div");
function findById(root, id) {
  if (!root) return null;
  if (root.id === id) return root;
  for (const child of root.children || []) {
    const found = findById(child, id);
    if (found) return found;
  }
  return null;
}
global.document = {
  body: node("body"),
  createElement: node,
  createTextNode(text) { const item = node("text"); item.textContent = text; return item; },
  getElementById(id) {
    if (id === "ullme_tests_workspace") return workspace;
    return findById(this.body, id);
  }
};
let lastShinyEvent = null;
global.window = {
  setInterval() { return 1; }, clearInterval() {}, alert() {}, confirm() { return true; },
  Shiny: { setInputValue(id, value) { lastShinyEvent = { id, value }; } }
};
global.Shiny = global.window.Shiny;

require("../inst/www/ullme-tests.js");

assert(window.ullmeTests);
assert.strictEqual(typeof window.ullmeTests.update, "function");
assert.strictEqual(typeof window.ullmeTests.openCreateDialog, "function");
assert.strictEqual(typeof window.ullmeTests.receiveResults, "function");

window.ullmeTests.update([], []);
assert(workspace.children.length > 0);

window.ullmeTests.update([{
  id: "suite1", label: "Demo suite", source_tutor: "demo",
  config: { models: ["fake"], api: "fake" },
  tutor: { start_node: "answer", nodes: { answer: { prompt: "Answer" } } },
  instances: [{ instanceid: "week1", label: "Week 1" }],
  inputs: [], variants: [{ id: "baseline", label: "Baseline", yaml_content: "" }],
  runs: [], status: { state: "idle", messages: [] }
}], [{ tutorid: "demo", label: "Demo" }]);
assert(workspace.children.length >= 3);

const stableChildCount = workspace.children.length;
window.ullmeTests.update([{
  id: "suite1", label: "A legacy label that must not be shown", source_tutor: "demo",
  config: { models: ["fake"], api: "fake" },
  tutor: { start_node: "answer", nodes: { answer: { prompt: "Answer" } } },
  instances: [{ instanceid: "week1", label: "Week 1" }],
  inputs: [], variants: [{ id: "baseline", label: "Baseline", yaml_content: "" }],
  runs: [], status: { state: "idle", messages: [] }
}], [{ tutorid: "demo", label: "Demo" }]);
assert.strictEqual(workspace.children.length, stableChildCount);

workspace.children[1].children[1].click();
const variantRenderNodeCount = createdNodes;
window.ullmeTests.update([{
  id: "suite1", source_tutor: "demo",
  config: { models: ["fake"], api: "fake" },
  tutor: { start_node: "answer", nodes: { answer: { prompt: "Answer" } } },
  instances: [{ instanceid: "week1", label: "Week 1" }], inputs: [],
  variants: [{ id: "baseline", label: "Baseline", yaml_content: "" }],
  runs: [], status: { state: "running", messages: ["Polling update"] }
}], [{ tutorid: "demo", label: "Demo" }]);
assert.strictEqual(createdNodes, variantRenderNodeCount, "status polling must not redraw the variant diagram");

workspace.children[0].children[3].click();
assert.strictEqual(lastShinyEvent.id, "ullme_test_suite_delete_event");
assert.strictEqual(document.body.children.at(-1).id, "ullme_tests_busy");
window.ullmeTests.actionComplete({ ok: false, message: "Expected test error" });
assert.ok(!document.body.children.some(child => child.id === "ullme_tests_busy"));

window.ullmeTests.openCreateDialog();
const createDialog = findById(document.body, "ullme_test_suite_dialog").children[0];
createDialog.children[4].children[1].click();
assert.strictEqual(lastShinyEvent.id, "ullme_test_suite_create_event");
assert.strictEqual(findById(document.body, "ullme_tests_busy").attributes.role, "status");
window.ullmeTests.actionComplete({ ok: false, message: "Expected test error" });
assert.strictEqual(findById(document.body, "ullme_tests_busy"), null);

console.log("Test Suite client checks passed.");
