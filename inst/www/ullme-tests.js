(function () {
  "use strict";

  var state = {
    suites: [], tutors: [], selectedSuiteId: "", tab: "inputs",
    pollTimer: null, pendingUpload: false, results: null, courseid: ""
  };

  function byId(id) { return document.getElementById(id); }

  function sendEvent(id, payload) {
    payload = payload || {};
    payload.nonce = Math.random();
    if (window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue(id, payload, { priority: "event" });
    } else if (window.Shiny && Shiny.onInputChange) {
      Shiny.onInputChange(id, payload);
    }
  }

  function element(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function button(label, className, action) {
    var node = element("button", className || "ullme-secondary-action", label);
    node.type = "button";
    if (action) node.addEventListener("click", action);
    return node;
  }

  function field(label, value, type) {
    var wrap = element("label", "ullme-tests-field");
    var title = element("span", "ullme-tests-field-label", label);
    var input = document.createElement(type === "textarea" ? "textarea" : "input");
    if (type && type !== "textarea") input.type = type;
    input.value = value == null ? "" : value;
    wrap.appendChild(title);
    wrap.appendChild(input);
    return { wrap: wrap, input: input };
  }

  function checkbox(label, checked) {
    var wrap = element("label", "ullme-tests-check");
    var input = document.createElement("input");
    input.type = "checkbox";
    input.checked = Boolean(checked);
    wrap.appendChild(input);
    wrap.appendChild(document.createTextNode(label));
    return { wrap: wrap, input: input };
  }

  function selectedSuite() {
    return state.suites.find(function (suite) { return suite.id === state.selectedSuiteId; }) || null;
  }

  function listValue(value) {
    if (Array.isArray(value)) return value.map(String);
    if (value == null || value === "") return [];
    return [String(value)];
  }

  function update(suites, tutors) {
    suites = Array.isArray(suites) ? suites : [];
    var courseid = suites.length ? (suites[0].courseid || "") : "";
    if (state.courseid && courseid !== state.courseid) {
      state.selectedSuiteId = "";
      state.results = null;
    }
    state.courseid = courseid;
    state.suites = suites;
    if (arguments.length > 1) state.tutors = Array.isArray(tutors) ? tutors : [];
    if (!state.suites.some(function (suite) { return suite.id === state.selectedSuiteId; })) {
      state.selectedSuiteId = state.suites.length ? state.suites[0].id : "";
      state.results = null;
    }
    render();
    updatePolling();
  }

  function render() {
    var root = byId("ullme_tests_workspace");
    if (!root) return;
    root.innerHTML = "";
    if (!state.suites.length) {
      var empty = element("div", "ullme-tests-empty");
      empty.appendChild(element("h3", "", "No Test Suites yet"));
      empty.appendChild(element("p", "", "Create a suite from a course AI Tutor, then add inputs and variants."));
      empty.appendChild(button("New Test Suite", "ullme-primary-action", openCreateDialog));
      root.appendChild(empty);
      return;
    }

    var toolbar = element("div", "ullme-tests-toolbar");
    var select = document.createElement("select");
    select.setAttribute("aria-label", "Test Suite");
    state.suites.forEach(function (suite) {
      var option = document.createElement("option");
      option.value = suite.id;
      option.textContent = suite.label || suite.id;
      option.selected = suite.id === state.selectedSuiteId;
      select.appendChild(option);
    });
    select.addEventListener("change", function () {
      state.selectedSuiteId = select.value;
      state.results = null;
      render();
    });
    toolbar.appendChild(select);
    toolbar.appendChild(button("New suite", "ullme-secondary-action", openCreateDialog));
    root.appendChild(toolbar);

    var tabs = element("div", "ullme-tests-tabs");
    [
      ["inputs", "Inputs"], ["variants", "Variants"],
      ["settings", "Settings"], ["runs", "Runs & results"]
    ].forEach(function (item) {
      var tab = button(item[1], "ullme-tests-tab" + (state.tab === item[0] ? " ullme-tests-tab-active" : ""), function () {
        state.tab = item[0]; render();
      });
      tabs.appendChild(tab);
    });
    root.appendChild(tabs);

    var suite = selectedSuite();
    var body = element("div", "ullme-tests-body");
    if (state.tab === "inputs") renderInputs(body, suite);
    if (state.tab === "variants") renderVariants(body, suite);
    if (state.tab === "settings") renderSettings(body, suite);
    if (state.tab === "runs") renderRuns(body, suite);
    root.appendChild(body);
  }

  function renderInputs(root, suite) {
    var layout = element("div", "ullme-tests-split");
    var list = element("div", "ullme-tests-list");
    var editor = element("div", "ullme-tests-editor");
    list.appendChild(element("h3", "", "Saved inputs"));
    (suite.inputs || []).forEach(function (input) {
      var card = element("button", "ullme-tests-list-item");
      card.type = "button";
      card.appendChild(element("strong", "", input.instanceid + " / " + input.inputid));
      card.appendChild(element("span", "", (input.images || []).length + " image(s)"));
      card.addEventListener("click", function () { fillInputEditor(editor, suite, input); });
      list.appendChild(card);
    });
    if (!(suite.inputs || []).length) list.appendChild(element("p", "ullme-muted", "No inputs saved."));
    fillInputEditor(editor, suite, null);
    layout.appendChild(list); layout.appendChild(editor); root.appendChild(layout);
  }

  function fillInputEditor(editor, suite, input) {
    editor.innerHTML = "";
    editor.appendChild(element("h3", "", input ? "Edit input" : "New input"));
    var instanceWrap = element("label", "ullme-tests-field");
    instanceWrap.appendChild(element("span", "ullme-tests-field-label", "Tutor instance"));
    var availableInstances = suite.instances || [];
    var instance = document.createElement(availableInstances.length ? "select" : "input");
    if (availableInstances.length) {
      availableInstances.forEach(function (item) {
        var option = document.createElement("option");
        option.value = item.instanceid;
        option.textContent = item.label || item.instanceid;
        option.selected = Boolean(input && input.instanceid === item.instanceid);
        instance.appendChild(option);
      });
    } else {
      instance.value = input ? input.instanceid : "course";
      instance.placeholder = "course";
    }
    instanceWrap.appendChild(instance);
    var id = field("Input ID", input ? input.inputid : "input1");
    id.input.readOnly = Boolean(input);
    var text = field("Student message", input ? input.text : "", "textarea");
    text.input.rows = 7;
    editor.appendChild(instanceWrap); editor.appendChild(id.wrap); editor.appendChild(text.wrap);
    if (input && (input.images || []).length) {
      editor.appendChild(element("div", "ullme-tests-file-list", "Images: " + input.images.join(", ")));
    }
    var actions = element("div", "ullme-tests-actions");
    actions.appendChild(button("Save input", "ullme-primary-action", function () {
      sendEvent("ullme_test_suite_input_save_event", {
        suiteid: suite.id, instanceid: instance.value,
        inputid: id.input.value.trim(), text: text.input.value
      });
    }));
    actions.appendChild(button("Upload images", "ullme-secondary-action", function () {
      state.pendingUpload = true;
      sendEvent("ullme_test_suite_upload_prepare_event", {
        suiteid: suite.id, instanceid: instance.value, inputid: id.input.value.trim()
      });
    }));
    editor.appendChild(actions);
  }

  function renderVariants(root, suite) {
    var layout = element("div", "ullme-tests-split");
    var list = element("div", "ullme-tests-list");
    var editor = element("div", "ullme-tests-editor");
    list.appendChild(element("h3", "", "Tutor variants"));
    (suite.variants || []).forEach(function (variant) {
      var card = element("button", "ullme-tests-list-item");
      card.type = "button";
      card.appendChild(element("strong", "", variant.label || variant.id));
      card.appendChild(element("code", "", variant.id));
      card.addEventListener("click", function () { fillVariantEditor(editor, suite, variant); });
      list.appendChild(card);
    });
    fillVariantEditor(editor, suite, null);
    layout.appendChild(list); layout.appendChild(editor); root.appendChild(layout);
  }

  function fillVariantEditor(editor, suite, variant) {
    editor.innerHTML = "";
    editor.appendChild(element("h3", "", variant ? "Edit variant" : "New variant"));
    var id = field("Variant ID", variant ? variant.id : "variant1");
    id.input.readOnly = Boolean(variant);
    var label = field("Label", variant ? variant.label : "New variant");
    var yaml = field("Tutor YAML overrides", variant ? variant.yaml_content : "# Fields here override tutor.yml\n", "textarea");
    yaml.input.rows = 18;
    editor.appendChild(id.wrap); editor.appendChild(label.wrap); editor.appendChild(yaml.wrap);
    editor.appendChild(element("p", "ullme-tests-hint", "The server merges these fields into the suite Tutor snapshot and validates the complete Tutor before saving."));
    editor.appendChild(button("Save variant", "ullme-primary-action", function () {
      sendEvent("ullme_test_suite_variant_save_event", {
        suiteid: suite.id, variantid: id.input.value.trim(),
        label: label.input.value.trim(), yaml_content: yaml.input.value
      });
    }));
  }

  function renderSettings(root, suite) {
    var config = suite.config || {};
    var form = element("div", "ullme-tests-settings");
    var label = field("Suite label", suite.label || suite.id);
    var models = field("Models (one per line)", listValue(config.models).join("\n"), "textarea");
    models.input.rows = 4;
    var api = field("API provider", config.api || "nvidia");
    var batch = field("Batch size", config.batch_size || 1, "number");
    var timeout = field("Timeout per wave (seconds)", config.timeout_seconds || 600, "number");
    var runBase = checkbox("Run the unmodified Tutor snapshot", config.run_base);
    var prompts = checkbox("Store full prompts in results", config.add_full_prompts_in_results);
    var nodes = checkbox("Store results by workflow node", config.results_by_node !== false);
    form.appendChild(element("p", "ullme-tests-source", "Based on AI Tutor: " + (suite.source_tutor || "unknown")));
    [label.wrap, models.wrap, api.wrap, batch.wrap, timeout.wrap,
      runBase.wrap, prompts.wrap, nodes.wrap].forEach(function (item) { form.appendChild(item); });
    form.appendChild(button("Save settings", "ullme-primary-action", function () {
      sendEvent("ullme_test_suite_config_save_event", {
        suiteid: suite.id,
        fields: {
          label: label.input.value.trim(),
          models: models.input.value.split(/[\n,]+/).map(function (x) { return x.trim(); }).filter(Boolean),
          api: api.input.value.trim(), batch_size: Number(batch.input.value),
          timeout_seconds: Number(timeout.input.value), run_base: runBase.input.checked,
          add_full_prompts_in_results: prompts.input.checked,
          results_by_node: nodes.input.checked
        }
      });
    }));
    form.appendChild(button("Refresh Tutor snapshot", "ullme-secondary-action", function () {
      if (!window.confirm("Replace tutor.yml and instances.yml with the current course AI Tutor? Existing results remain unchanged.")) return;
      sendEvent("ullme_test_suite_refresh_event", { suiteid: suite.id });
    }));
    root.appendChild(form);
  }

  function renderRuns(root, suite) {
    var status = suite.status || { state: "idle", messages: [] };
    var top = element("div", "ullme-tests-run-card");
    top.appendChild(element("h3", "", "Run suite"));
    var badge = element("span", "ullme-tests-status ullme-tests-status-" + (status.state || "idle"), status.state || "idle");
    top.appendChild(badge);
    var variantBox = element("div", "ullme-tests-variant-checks");
    (suite.variants || []).forEach(function (variant) {
      var item = checkbox(variant.label || variant.id, true);
      item.input.value = variant.id;
      variantBox.appendChild(item.wrap);
    });
    top.appendChild(variantBox);
    var running = ["starting", "running"].indexOf(status.state) >= 0;
    var run = button(running ? "Running…" : "Start test run", "ullme-primary-action", function () {
      var variants = Array.prototype.map.call(
        variantBox.querySelectorAll('input[type="checkbox"]:checked'),
        function (input) { return input.value; }
      );
      sendEvent("ullme_test_suite_run_event", { suiteid: suite.id, variants: variants });
    });
    run.disabled = running || !(suite.inputs || []).length || !(suite.variants || []).length;
    top.appendChild(run);
    if (status.error) top.appendChild(element("div", "ullme-tests-error", status.error));
    if ((status.messages || []).length) {
      var log = element("pre", "ullme-tests-log", status.messages.slice(-12).join("\n"));
      top.appendChild(log);
    }
    root.appendChild(top);

    var results = element("div", "ullme-tests-results-layout");
    var runs = element("div", "ullme-tests-list");
    runs.appendChild(element("h3", "", "Result runs"));
    (suite.runs || []).forEach(function (item) {
      var card = element("button", "ullme-tests-list-item");
      card.type = "button";
      card.appendChild(element("strong", "", item.id.replace(/^results_/, "")));
      card.appendChild(element("span", "", item.completed + " completed · " + item.errors + " errors"));
      card.addEventListener("click", function () {
        sendEvent("ullme_test_suite_results_event", { suiteid: suite.id, runid: item.id });
      });
      runs.appendChild(card);
    });
    var detail = element("div", "ullme-tests-result-surface");
    renderResultPayload(detail, suite);
    results.appendChild(runs); results.appendChild(detail); root.appendChild(results);
  }

  function renderResultPayload(root, suite) {
    var payload = state.results;
    if (!payload || payload.suiteid !== suite.id) {
      root.appendChild(element("p", "ullme-muted", "Select a result run to inspect its cases."));
      return;
    }
    root.appendChild(element("h3", "", payload.runid.replace(/^results_/, "")));
    var table = element("table", "ullme-tests-result-table");
    var head = document.createElement("thead");
    head.innerHTML = "<tr><th>Variant</th><th>Model</th><th>Input</th><th>Status</th><th>Seconds</th></tr>";
    table.appendChild(head);
    var body = document.createElement("tbody");
    (payload.cases || []).forEach(function (item) {
      var row = document.createElement("tr");
      var test = item.test || {}; var execution = item.execution || {};
      [test.variant_label || test.variant_id, test.model,
       (test.instance_id || "") + "/" + (test.input_id || ""),
       test.status, execution.duration_seconds == null ? "" : Number(execution.duration_seconds).toFixed(1)
      ].forEach(function (value) { var cell = document.createElement("td"); cell.textContent = value || ""; row.appendChild(cell); });
      row.tabIndex = 0;
      row.addEventListener("click", function () {
        sendEvent("ullme_test_suite_results_event", {
          suiteid: suite.id, runid: payload.runid, filename: item.file
        });
      });
      body.appendChild(row);
    });
    table.appendChild(body); root.appendChild(table);
    if (payload.detail) renderCaseDetail(root, payload.detail);
  }

  function renderCaseDetail(root, item) {
    var panel = element("div", "ullme-tests-case-detail");
    var response = item.response || {}; var input = item.input || {};
    panel.appendChild(element("h4", "", "Case detail"));
    panel.appendChild(element("h5", "", "Student input"));
    panel.appendChild(element("pre", "", input.text || "(image upload)"));
    panel.appendChild(element("h5", "", "Final output"));
    panel.appendChild(element("pre", "ullme-tests-final-output", response.final_output || ""));
    if (response.error_message) panel.appendChild(element("div", "ullme-tests-error", response.error_message));
    (response.nodes || []).forEach(function (node) {
      var details = document.createElement("details");
      var summary = document.createElement("summary");
      summary.textContent = (node.node_id || "node") + " · " + Number(node.duration_seconds || 0).toFixed(1) + "s";
      details.appendChild(summary);
      details.appendChild(element("pre", "", node.output || ""));
      if (node.system_prompt) details.appendChild(element("pre", "ullme-tests-prompt", node.system_prompt));
      if (node.prompt) details.appendChild(element("pre", "ullme-tests-prompt", node.prompt));
      panel.appendChild(details);
    });
    if (item.raw_yaml) {
      var raw = document.createElement("details");
      var rawSummary = document.createElement("summary");
      rawSummary.textContent = "Raw result YAML";
      raw.appendChild(rawSummary);
      raw.appendChild(element("pre", "ullme-tests-prompt", item.raw_yaml));
      panel.appendChild(raw);
    }
    root.appendChild(panel);
  }

  function openCreateDialog() {
    if (!state.tutors.length) {
      window.alert("Add a course AI Tutor before creating a Test Suite.");
      return;
    }
    closeDialog();
    var overlay = element("div", "ullme-dialog-overlay");
    overlay.id = "ullme_test_suite_dialog";
    var dialog = element("section", "ullme-dialog");
    dialog.setAttribute("role", "dialog"); dialog.setAttribute("aria-modal", "true");
    dialog.appendChild(element("div", "ullme-dialog-title", "New Test Suite"));
    dialog.appendChild(element("p", "", "The suite starts as a reproducible snapshot of a course AI Tutor."));
    var id = field("Suite ID", "tests1"); var label = field("Label", "Tutor tests");
    var tutorWrap = element("label", "ullme-tests-field");
    tutorWrap.appendChild(element("span", "ullme-tests-field-label", "AI Tutor"));
    var tutor = document.createElement("select");
    state.tutors.forEach(function (item) {
      var option = document.createElement("option"); option.value = item.tutorid;
      option.textContent = item.label || item.tutorid; tutor.appendChild(option);
    });
    tutorWrap.appendChild(tutor);
    dialog.appendChild(id.wrap); dialog.appendChild(label.wrap); dialog.appendChild(tutorWrap);
    var actions = element("div", "ullme-dialog-actions");
    actions.appendChild(button("Cancel", "ullme-secondary-action", closeDialog));
    actions.appendChild(button("Create suite", "ullme-primary-action", function () {
      sendEvent("ullme_test_suite_create_event", {
        suiteid: id.input.value.trim(), label: label.input.value.trim(), tutorid: tutor.value
      });
    }));
    dialog.appendChild(actions); overlay.appendChild(dialog); document.body.appendChild(overlay); id.input.focus();
  }

  function closeDialog() { var dialog = byId("ullme_test_suite_dialog"); if (dialog) dialog.remove(); }

  function actionComplete(result) {
    if (!result || result.ok === false) {
      window.alert((result && result.message) || "The Test Suite action failed.");
      return;
    }
    if (result.suiteid) { state.selectedSuiteId = result.suiteid; closeDialog(); }
  }

  function uploadReady(result) {
    if (!result || result.ok === false) {
      state.pendingUpload = false;
      window.alert((result && result.message) || "The upload could not be prepared."); return;
    }
    var input = byId("ullme_test_input_upload"); if (input) input.click();
  }

  function uploadComplete(result) {
    state.pendingUpload = false;
    var input = byId("ullme_test_input_upload"); if (input) input.value = "";
    if (!result || result.ok === false) window.alert((result && result.message) || "The upload failed.");
  }

  function receiveResults(result) {
    if (!result || result.ok === false) {
      window.alert((result && result.message) || "Results could not be loaded."); return;
    }
    state.results = result; render();
  }

  function updatePolling() {
    var running = state.suites.some(function (suite) {
      return suite.status && ["starting", "running"].indexOf(suite.status.state) >= 0;
    });
    if (running && !state.pollTimer) {
      state.pollTimer = window.setInterval(function () {
        sendEvent("ullme_test_suite_poll_event", {});
      }, 1500);
    } else if (!running && state.pollTimer) {
      window.clearInterval(state.pollTimer); state.pollTimer = null;
    }
  }

  window.ullmeTests = {
    update: update, openCreateDialog: openCreateDialog,
    actionComplete: actionComplete, uploadReady: uploadReady,
    uploadComplete: uploadComplete, receiveResults: receiveResults
  };
})();
