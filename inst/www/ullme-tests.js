(function () {
  "use strict";

  var state = {
    suites: [], tutors: [], selectedSuiteId: "", tab: "inputs",
    pollTimer: null, pendingUpload: false, pendingImageFiles: [],
    pendingImageTarget: null, results: null, courseid: "",
    selectedVariantId: "", variantMode: "nodes", variantNode: null,
    hasRendered: false
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

  function beginBusy(message) {
    endBusy();
    if (document.body && document.body.classList) {
      document.body.classList.add("ullme-tests-is-busy");
    }
    var overlay = element("div", "ullme-tests-busy");
    overlay.id = "ullme_tests_busy";
    overlay.setAttribute("role", "status");
    overlay.setAttribute("aria-live", "assertive");
    var card = element("div", "ullme-tests-busy-card");
    card.appendChild(element("span", "ullme-tests-spinner"));
    card.appendChild(element("strong", "", message));
    card.appendChild(element("span", "", "Please wait…"));
    overlay.appendChild(card);
    document.body.appendChild(overlay);
  }

  function endBusy() {
    var overlay = byId("ullme_tests_busy");
    if (overlay) overlay.remove();
    if (document.body && document.body.classList) {
      document.body.classList.remove("ullme-tests-is-busy");
    }
  }

  function listValue(value) {
    if (Array.isArray(value)) return value.map(String);
    if (value == null || value === "") return [];
    return [String(value)];
  }

  function renderSignature(suites) {
    var suite = (suites || []).find(function (item) {
      return item.id === state.selectedSuiteId;
    }) || null;
    var view = null;
    if (suite && state.tab === "inputs") {
      view = { instances: suite.instances, inputs: suite.inputs };
    } else if (suite && state.tab === "variants") {
      view = { tutor: suite.tutor, variants: suite.variants };
    } else if (suite && state.tab === "settings") {
      view = { source_tutor: suite.source_tutor, config: suite.config };
    } else if (suite) {
      view = suite;
    }
    return JSON.stringify({
      ids: (suites || []).map(function (item) { return item.id; }),
      selected: state.selectedSuiteId, tab: state.tab, view: view
    });
  }

  function update(suites, tutors) {
    suites = Array.isArray(suites) ? suites : [];
    var previousSignature = renderSignature(state.suites);
    var courseid = suites.length ? (suites[0].courseid || "") : "";
    if (state.courseid && courseid !== state.courseid) {
      state.selectedSuiteId = "";
      state.results = null;
      state.selectedVariantId = "";
    }
    state.courseid = courseid;
    state.suites = suites;
    if (arguments.length > 1) state.tutors = Array.isArray(tutors) ? tutors : [];
    if (!state.suites.some(function (suite) { return suite.id === state.selectedSuiteId; })) {
      state.selectedSuiteId = state.suites.length ? state.suites[0].id : "";
      state.results = null;
      state.selectedVariantId = "";
    }
    var nextSignature = renderSignature(state.suites);
    if (!state.hasRendered || previousSignature !== nextSignature) render();
    updatePolling();
  }

  function render() {
    var root = byId("ullme_tests_workspace");
    if (!root) return;
    state.hasRendered = true;
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
    toolbar.appendChild(element("span", "ullme-tests-toolbar-label", "Test Suite:"));
    var select = document.createElement("select");
    select.setAttribute("aria-label", "Test Suite");
    state.suites.forEach(function (suite) {
      var option = document.createElement("option");
      option.value = suite.id;
      option.textContent = suite.id;
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
    toolbar.appendChild(button("Delete", "ullme-secondary-action ullme-tests-delete-suite", function () {
      var suite = selectedSuite();
      if (!suite || !window.confirm("Delete Test Suite '" + suite.id + "' and all of its inputs, variants, runs, and results?")) return;
      beginBusy("Deleting Test Suite " + suite.id);
      sendEvent("ullme_test_suite_delete_event", { suiteid: suite.id });
    }));
    root.appendChild(toolbar);

    var tabs = element("div", "ullme-tests-tabs");
    [
      ["inputs", "Inputs"], ["variants", "Variants"],
      ["settings", "Settings"], ["runs", "Runs & results"]
    ].forEach(function (item) {
      var tab = button(item[1], "ullme-tests-tab" + (state.tab === item[0] ? " ullme-tests-tab-active" : ""), function () {
        state.tab = item[0];
        if (state.tab !== "variants") hideVariantNodeEditor();
        render();
      });
      tabs.appendChild(tab);
    });
    root.appendChild(tabs);

    var suite = selectedSuite();
    if (suite && state.selectedVariantId !== "__new__" && !(suite.variants || []).some(function (variant) {
      return variant.id === state.selectedVariantId;
    })) {
      state.selectedVariantId = (suite.variants || []).length ? suite.variants[0].id : "";
    }
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
    var uploadTarget = function () {
      return {
        suiteid: suite.id, instanceid: instance.value,
        inputid: id.input.value.trim()
      };
    };
    actions.appendChild(button("Choose images", "ullme-secondary-action", function () {
      chooseImageFiles(uploadTarget());
    }));
    editor.appendChild(actions);
    var drop = element("div", "ullme-tests-image-drop");
    drop.tabIndex = 0;
    drop.appendChild(element("strong", "", "Drop or paste images here"));
    drop.appendChild(element("span", "", "Multiple images can stay together or become separate inputs."));
    ["dragenter", "dragover"].forEach(function (name) {
      drop.addEventListener(name, function (event) {
        event.preventDefault(); drop.classList.add("ullme-tests-image-drop-active");
      });
    });
    ["dragleave", "drop"].forEach(function (name) {
      drop.addEventListener(name, function () { drop.classList.remove("ullme-tests-image-drop-active"); });
    });
    drop.addEventListener("drop", function (event) {
      event.preventDefault();
      queueImageFiles(event.dataTransfer && event.dataTransfer.files, uploadTarget());
    });
    editor.addEventListener("paste", function (event) {
      var files = clipboardImageFiles(event.clipboardData);
      if (!files.length) return;
      event.preventDefault(); queueImageFiles(files, uploadTarget());
    });
    editor.appendChild(drop);
  }

  function imageFileList(files) {
    return Array.prototype.filter.call(files || [], function (file) {
      return /^image\/(png|jpeg|gif|webp)$/i.test(String(file.type || ""));
    });
  }

  function clipboardImageFiles(clipboard) {
    if (!clipboard) return [];
    var files = imageFileList(clipboard.files || []);
    if (files.length) return files;
    return Array.prototype.map.call(clipboard.items || [], function (item) {
      return item.kind === "file" ? item.getAsFile() : null;
    }).filter(function (file) { return file && /^image\//i.test(file.type || ""); });
  }

  function chooseImageFiles(target) {
    var picker = document.createElement("input");
    picker.type = "file"; picker.accept = "image/png,image/jpeg,image/gif,image/webp";
    picker.multiple = true;
    picker.addEventListener("change", function () { queueImageFiles(picker.files, target); });
    picker.click();
  }

  function queueImageFiles(files, target) {
    files = imageFileList(files);
    if (!files.length) {
      window.alert("Choose or drop a supported PNG, JPEG, GIF, or WebP image.");
      return;
    }
    if (!target.inputid) {
      window.alert("Enter an Input ID first.");
      return;
    }
    var split = files.length > 1 && window.confirm(
      "Create one separate test input for each of the " + files.length +
      " images?\n\nOK: separate inputs with no text\nCancel: keep all images in this input"
    );
    state.pendingUpload = true;
    state.pendingImageFiles = files;
    state.pendingImageTarget = target;
    sendEvent("ullme_test_suite_upload_prepare_event", {
      suiteid: target.suiteid, instanceid: target.instanceid,
      inputid: target.inputid, split: split
    });
  }

  function renderVariants(root, suite) {
    var layout = element("div", "ullme-tests-split ullme-tests-variant-layout");
    var list = element("div", "ullme-tests-list");
    var editor = element("div", "ullme-tests-editor");
    var listHead = element("div", "ullme-tests-compact-head");
    listHead.appendChild(element("h3", "", "Variants"));
    listHead.appendChild(button("+", "ullme-secondary-action", function () {
      state.selectedVariantId = "__new__"; state.variantMode = "yaml"; render();
    }));
    list.appendChild(listHead);
    (suite.variants || []).forEach(function (variant) {
      var card = element("button", "ullme-tests-list-item");
      card.type = "button";
      if (variant.id === state.selectedVariantId) card.classList.add("ullme-tests-list-item-active");
      card.appendChild(element("strong", "", variant.label || variant.id));
      card.appendChild(element("code", "", variant.base
        ? "base · always tested"
        : variant.id + " · " + (variant.modified_nodes || []).length + " changed node(s)"));
      card.addEventListener("click", function () {
        state.selectedVariantId = variant.id; state.variantMode = "nodes"; render();
      });
      list.appendChild(card);
    });
    var selected = (suite.variants || []).find(function (variant) {
      return variant.id === state.selectedVariantId;
    }) || null;
    fillVariantEditor(editor, suite, selected);
    layout.appendChild(list); layout.appendChild(editor); root.appendChild(layout);
  }

  function fillVariantEditor(editor, suite, variant) {
    editor.innerHTML = "";
    var head = element("div", "ullme-tests-variant-head");
    head.appendChild(element("h3", "", variant ? (variant.label || variant.id) : "New variant"));
    if (variant && !variant.base) {
      var modes = element("div", "ullme-tests-mode-tabs");
      [["nodes", "Nodes"], ["yaml", "YAML"]].forEach(function (item) {
        modes.appendChild(button(item[1], "ullme-tests-mode-tab" +
          (state.variantMode === item[0] ? " ullme-tests-mode-tab-active" : ""), function () {
          state.variantMode = item[0]; render();
        }));
      });
      modes.appendChild(button("Delete variant", "ullme-secondary-action ullme-tests-delete-variant", function () {
        if (!window.confirm("Delete variant '" + variant.id + "'? Existing results remain unchanged.")) return;
        hideVariantNodeEditor();
        beginBusy("Deleting variant " + variant.id);
        sendEvent("ullme_test_suite_variant_delete_event", {
          suiteid: suite.id, variantid: variant.id
        });
      }));
      head.appendChild(modes);
    }
    editor.appendChild(head);
    if (variant && variant.base) {
      editor.appendChild(element("p", "ullme-tests-hint",
        "This is the exact tutor.yml snapshot. It is read-only and always included in every test run."));
      return;
    }
    if (variant && state.variantMode === "nodes") {
      editor.appendChild(element("p", "ullme-tests-hint ullme-tests-variant-hint",
        "Grey nodes use the base Tutor. Colored nodes contain variant overrides. Click a node to edit it on the right."));
      if (window.ullmeTutorFlow && window.ullmeTutorFlow.render && suite.tutor) {
        editor.appendChild(window.ullmeTutorFlow.render(suite.tutor, {
          variant: true, compact: true,
          modifiedNodes: variant.modified_nodes || [],
          onSelect: function (nodeid) { openVariantNodeEditor(suite, variant, nodeid); }
        }));
      } else {
        editor.appendChild(element("p", "ullme-muted", "The Tutor has no workflow diagram."));
      }
      return;
    }
    var id = field("Variant ID", variant ? variant.id : "variant1");
    id.input.readOnly = Boolean(variant);
    var label = field("Label", variant ? variant.label : "New variant");
    var yaml = field("Tutor YAML overrides", variant ? variant.yaml_content : "# Fields here override tutor.yml\n", "textarea");
    yaml.input.rows = 14;
    var identity = element("div", "ullme-tests-variant-identity");
    identity.appendChild(id.wrap); identity.appendChild(label.wrap);
    editor.appendChild(identity); editor.appendChild(yaml.wrap);
    editor.appendChild(element("p", "ullme-tests-hint", "The server merges these fields into the suite Tutor snapshot and validates the complete Tutor before saving."));
    editor.appendChild(button("Save variant", "ullme-primary-action", function () {
      sendEvent("ullme_test_suite_variant_save_event", {
        suiteid: suite.id, variantid: id.input.value.trim(),
        label: label.input.value.trim(), yaml_content: yaml.input.value
      });
    }));
  }

  function dispatchAssistantTab(tab) {
    document.dispatchEvent(new CustomEvent("ullme:assistant-tab", { detail: { tab: tab } }));
  }

  function variantNodeElements() {
    return {
      tab: byId("ullme_test_variant_node_tab"),
      title: byId("ullme_test_variant_node_title"),
      nodeid: byId("ullme_test_variant_node_id"),
      yaml: byId("ullme_test_variant_node_yaml"),
      field: byId("ullme_test_variant_node_field"),
      fieldHelp: byId("ullme_test_variant_node_field_help"),
      status: byId("ullme_test_variant_node_status"),
      save: byId("ullme_test_variant_node_save"),
      revert: byId("ullme_test_variant_node_revert")
    };
  }

  function bindVariantNodeEditor() {
    var elements = variantNodeElements();
    if (window.ullmeNodeFields && window.ullmeNodeFields.bind) {
      window.ullmeNodeFields.bind({
        select: elements.field, textarea: elements.yaml, help: elements.fieldHelp,
        onStatus: function (message, duplicate) {
          if (!elements.status) return;
          elements.status.textContent = message;
          elements.status.classList.toggle("ullme-node-editor-status-error", Boolean(duplicate));
        }
      });
    }
    if (!elements.save || elements.save.dataset.ullmeBound === "true") return;
    elements.save.dataset.ullmeBound = "true";
    elements.save.addEventListener("click", function () { submitVariantNode("save"); });
    elements.revert.addEventListener("click", function () {
      if (!state.variantNode || !window.confirm("Remove this node override and use the base Tutor node?")) return;
      submitVariantNode("revert");
    });
  }

  function openVariantNodeEditor(suite, variant, nodeid) {
    bindVariantNodeEditor();
    var elements = variantNodeElements();
    var baseYaml = String(suite.tutor && suite.tutor.node_yaml && suite.tutor.node_yaml[nodeid] || "").trim();
    var overrideYaml = String(variant.node_yaml && variant.node_yaml[nodeid] || "").trim();
    state.variantNode = { suiteid: suite.id, variantid: variant.id, nodeid: nodeid };
    if (elements.tab) elements.tab.hidden = false;
    if (elements.title) elements.title.textContent = "Variant: " + nodeid;
    if (elements.nodeid) elements.nodeid.value = nodeid;
    if (elements.yaml) elements.yaml.value = overrideYaml || baseYaml;
    if (elements.revert) elements.revert.disabled = !overrideYaml;
    if (elements.status) {
      elements.status.textContent = overrideYaml
        ? "This node is modified by the variant."
        : "This is the base node. Saving creates a variant override.";
      elements.status.classList.remove("ullme-node-editor-status-error");
    }
    dispatchAssistantTab("variant-node");
    if (elements.yaml) elements.yaml.focus();
  }

  function submitVariantNode(action) {
    var elements = variantNodeElements();
    if (!state.variantNode) return;
    if (action === "save" && !String(elements.yaml.value || "").trim()) {
      elements.status.textContent = "Node YAML cannot be empty.";
      elements.status.classList.add("ullme-node-editor-status-error");
      return;
    }
    elements.save.disabled = true; elements.revert.disabled = true;
    elements.status.textContent = "Checking the variant and complete Tutor…";
    sendEvent("ullme_test_suite_variant_node_save_event", {
      suiteid: state.variantNode.suiteid, variantid: state.variantNode.variantid,
      nodeid: state.variantNode.nodeid, action: action,
      yaml_content: action === "save" ? elements.yaml.value : ""
    });
  }

  function hideVariantNodeEditor() {
    var elements = variantNodeElements();
    if (elements.tab) elements.tab.hidden = true;
    state.variantNode = null;
    if (elements.tab && elements.tab.classList.contains("ullme-assistant-tab-active")) {
      dispatchAssistantTab("help");
    }
  }

  function renderSettings(root, suite) {
    var config = suite.config || {};
    var form = element("div", "ullme-tests-settings");
    var models = field("Models (one per line)", listValue(config.models).join("\n"), "textarea");
    models.input.rows = 4;
    var api = field("API provider", config.api || "nvidia");
    var batch = field("Batch size", config.batch_size || 1, "number");
    var timeout = field("Timeout per wave (seconds)", config.timeout_seconds || 600, "number");
    var prompts = checkbox("Store full prompts in results", config.add_full_prompts_in_results);
    var nodes = checkbox("Store results by workflow node", config.results_by_node !== false);
    form.appendChild(element("p", "ullme-tests-source", "Based on AI Tutor: " + (suite.source_tutor || "unknown")));
    [models.wrap, api.wrap, batch.wrap, timeout.wrap,
      prompts.wrap, nodes.wrap].forEach(function (item) { form.appendChild(item); });
    form.appendChild(button("Save settings", "ullme-primary-action", function () {
      sendEvent("ullme_test_suite_config_save_event", {
        suiteid: suite.id,
        fields: {
          models: models.input.value.split(/[\n,]+/).map(function (x) { return x.trim(); }).filter(Boolean),
          api: api.input.value.trim(), batch_size: Number(batch.input.value),
          timeout_seconds: Number(timeout.input.value),
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
      if (variant.base) {
        item.input.disabled = true;
        item.wrap.title = "The base Tutor is always tested.";
      }
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
    run.disabled = running || !(suite.inputs || []).length;
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
    var id = field("Suite ID", "tests1");
    var tutorWrap = element("label", "ullme-tests-field");
    tutorWrap.appendChild(element("span", "ullme-tests-field-label", "AI Tutor"));
    var tutor = document.createElement("select");
    state.tutors.forEach(function (item) {
      var option = document.createElement("option"); option.value = item.tutorid;
      option.textContent = item.label || item.tutorid; tutor.appendChild(option);
    });
    tutorWrap.appendChild(tutor);
    dialog.appendChild(id.wrap); dialog.appendChild(tutorWrap);
    var actions = element("div", "ullme-dialog-actions");
    actions.appendChild(button("Cancel", "ullme-secondary-action", closeDialog));
    actions.appendChild(button("Create suite", "ullme-primary-action", function () {
      beginBusy("Creating Test Suite " + (id.input.value.trim() || "…"));
      sendEvent("ullme_test_suite_create_event", {
        suiteid: id.input.value.trim(), tutorid: tutor.value
      });
    }));
    dialog.appendChild(actions); overlay.appendChild(dialog); document.body.appendChild(overlay); id.input.focus();
  }

  function closeDialog() { var dialog = byId("ullme_test_suite_dialog"); if (dialog) dialog.remove(); }

  function actionComplete(result) {
    endBusy();
    var variantElements = variantNodeElements();
    if (variantElements.save) variantElements.save.disabled = false;
    if (variantElements.revert && state.variantNode) {
      var activeSuite = selectedSuite();
      var activeVariant = activeSuite && (activeSuite.variants || []).find(function (item) {
        return item.id === state.variantNode.variantid;
      });
      variantElements.revert.disabled = !(activeVariant && activeVariant.node_yaml &&
        activeVariant.node_yaml[state.variantNode.nodeid]);
    }
    if (!result || result.ok === false) {
      if (result && result.kind === "variant_node" && variantElements.status) {
        variantElements.status.textContent = result.message || "The node override could not be saved.";
        variantElements.status.classList.add("ullme-node-editor-status-error");
        return;
      }
      window.alert((result && result.message) || "The Test Suite action failed.");
      return;
    }
    if (result.suiteid && result.kind !== "suite_delete") {
      state.selectedSuiteId = result.suiteid; closeDialog();
    }
    if (result.kind === "suite_delete") {
      state.results = null;
      state.selectedVariantId = "";
      hideVariantNodeEditor();
    }
    if (result.kind === "variant_delete") {
      state.selectedVariantId = "base";
      hideVariantNodeEditor();
      render();
    }
    if (result.kind === "variant" && result.variantid) {
      state.selectedVariantId = result.variantid;
      state.variantMode = "nodes";
      render();
    }
    if (result.kind === "variant_node" && state.variantNode) {
      var suite = selectedSuite();
      var variant = suite && (suite.variants || []).find(function (item) {
        return item.id === state.variantNode.variantid;
      });
      if (suite && variant) openVariantNodeEditor(suite, variant, state.variantNode.nodeid);
    }
  }

  function uploadReady(result) {
    if (!result || result.ok === false) {
      state.pendingUpload = false;
      state.pendingImageFiles = [];
      state.pendingImageTarget = null;
      window.alert((result && result.message) || "The upload could not be prepared."); return;
    }
    var input = byId("ullme_test_input_upload");
    if (!input || !state.pendingImageFiles.length) return;
    var transfer = new DataTransfer();
    state.pendingImageFiles.forEach(function (file) { transfer.items.add(file); });
    input.files = transfer.files;
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function uploadComplete(result) {
    state.pendingUpload = false;
    state.pendingImageFiles = [];
    state.pendingImageTarget = null;
    var input = byId("ullme_test_input_upload"); if (input) input.value = "";
    if (window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue("ullme_test_input_upload", null, { priority: "event" });
    }
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

  if (typeof document !== "undefined" && typeof document.addEventListener === "function") {
    document.addEventListener("ullme:studio-view", function (event) {
      var view = event.detail && event.detail.view;
      if (view && view !== "tests") hideVariantNodeEditor();
    });
  }

  function observeTestSuiteVisibility() {
    var panel = byId("ullme_test_suites_panel");
    if (!panel || !window.MutationObserver || panel.dataset.ullmeVisibilityObserved === "true") return;
    panel.dataset.ullmeVisibilityObserved = "true";
    var observer = new window.MutationObserver(function () {
      if (!panel.classList.contains("ullme-course-content-panel-active")) hideVariantNodeEditor();
    });
    observer.observe(panel, { attributes: true, attributeFilter: ["class"] });
  }

  if (typeof document !== "undefined" && typeof document.addEventListener === "function" &&
      document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", observeTestSuiteVisibility);
  } else if (typeof document !== "undefined") {
    observeTestSuiteVisibility();
  }

  window.ullmeTests = {
    update: update, openCreateDialog: openCreateDialog,
    actionComplete: actionComplete, uploadReady: uploadReady,
    uploadComplete: uploadComplete, receiveResults: receiveResults
  };
})();
