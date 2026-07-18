const assert = require("assert");
const fs = require("fs");
const flow = require("../inst/www/ullme-tutor-flow.js");

const graph = flow.buildGraph({
  start_node: "choose",
  nodes: {
    choose: {
      switch_input: "image_uploaded",
      switch_to: { TRUE: "inspect", FALSE: "answer" }
    },
    inspect: {
      prompt: "Inspect the image",
      next: "wait"
    },
    wait: {
      ask_for_input: true,
      show_text: "Which exercise?",
      prompt: "Classify the reply",
      switch_input: "output",
      switch_to: { ok: "answer", DEFAULT: "answer" }
    },
    answer: {
      prompt: "Answer the student"
    }
  }
});

assert.strictEqual(graph.start, "choose");
assert.ok(graph.nodes.some(node => node.id === "Student response") === false);
assert.ok(graph.nodes.some(node => node.response));
assert.ok(graph.edges.some(edge =>
  edge.from === "choose" && edge.to === "inspect" && edge.label === "TRUE"
));
assert.ok(graph.edges.some(edge =>
  edge.from === "inspect" && edge.to === "wait" && edge.kind === "next"
));
assert.ok(graph.edges.some(edge =>
  edge.from === "answer" && edge.kind === "response"
));
assert.strictEqual(
  graph.nodes.find(node => node.id === "wait").kind,
  "Wait for student, then call model"
);

const layout = flow.layoutGraph(graph);
graph.edges.forEach(edge => {
  assert.ok(
    layout.positions[edge.to].y > layout.positions[edge.from].y,
    `${edge.from} -> ${edge.to} must point downward`
  );
});
assert.deepStrictEqual(layout.cyclic, []);

const flowCss = fs.readFileSync("inst/www/ullme-tutor-flow.css", "utf8");
assert.match(
  flowCss,
  /\.ullme-flow-node\.ullme-flow-node-modified:not\(\.ullme-flow-node-response\):not\(\.ullme-flow-node-missing\)/
);

console.log("Tutor flow graph tests passed.");
