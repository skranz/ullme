const assert = require("assert");

function node(tag) {
  return {
    tagName: tag, children: [], attributes: {}, className: "", textContent: "",
    value: "", checked: false, style: {}, classList: { add() {}, remove() {} },
    appendChild(child) { this.children.push(child); return child; },
    addEventListener() {}, setAttribute(key, value) { this.attributes[key] = value; },
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
  instances: [{ instanceid: "week1", label: "Week 1" }],
  inputs: [], variants: [{ id: "baseline", label: "Baseline", yaml_content: "" }],
  runs: [], status: { state: "idle", messages: [] }
}], [{ tutorid: "demo", label: "Demo" }]);
assert(workspace.children.length >= 3);

console.log("Test Suite client checks passed.");
