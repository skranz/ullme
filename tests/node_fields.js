const assert = require("assert");
const fields = require("../inst/www/ullme-node-fields.js");

function option(path, template, nestedTemplate = "") {
  return {
    value: path,
    getAttribute(name) {
      if (name === "data-template") return template;
      if (name === "data-nested-template") return nestedTemplate;
      return "";
    }
  };
}

const promptYaml = "prompt: |\n  A line that looks like a key:\n  next: not_a_real_node\n";
assert.strictEqual(fields.hasPath(promptYaml, "prompt"), true);
assert.strictEqual(fields.hasPath(promptYaml, "next"), false);

let result = fields.insertField("prompt: Answer.\n", option("next", "next: review"));
assert.strictEqual(result.ok, true);
assert.match(result.value, /next: review/);
result = fields.insertField(result.value, option("next", "next: review"));
assert.strictEqual(result.duplicate, true);

result = fields.insertField(
  "switch_input: output\nswitch_to:\n  ok: answer\n",
  option("switch_to.DEFAULT", "switch_to:\n  DEFAULT: next_node", "DEFAULT: next_node")
);
assert.strictEqual(result.ok, true);
assert.match(result.value, /switch_to:\n  ok: answer\n  DEFAULT: next_node/);
assert.strictEqual((result.value.match(/^switch_to:/gm) || []).length, 1);

console.log("Node field insertion checks passed.");
