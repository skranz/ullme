const assert = require("assert");
let createdNodes = 0;

function node(tag) {
  createdNodes += 1;
  return {
    tagName: tag, children: [], attributes: {}, className: "", textContent: "",
    value: "", checked: false, style: {}, listeners: {},
    classList: { add() {}, remove() {}, contains() { return false; } },
    appendChild(child) { this.children.push(child); return child; },
    addEventListener(type, handler) { this.listeners[type] = handler; },
    click() { if (this.listeners.click) this.listeners.click(); },
    setAttribute(key, value) { this.attributes[key] = value; },
    querySelectorAll() { return []; }, remove() {}
  };
}

const workspace = node("div");
global.document = {
  body: node("body"),
  createElement: node,
  createTextNode(text) { const item = node("text"); item.textContent = text; return item; },
  getElementById(id) { return id === "ullme_tests_workspace" ? workspace : null; }
};
global.window = { setInterval() { return 1; }, clearInterval() {}, alert() {} };

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

console.log("Test Suite client checks passed.");
