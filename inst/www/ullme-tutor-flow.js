(function (root) {
  "use strict";

  var SVG_NS = "http://www.w3.org/2000/svg";
  var END_ID = "__ullme_student_response__";

  function asObject(value) {
    return value && typeof value === "object" && !Array.isArray(value)
      ? value
      : {};
  }

  function nodeKind(node) {
    if (node.missing) return "Missing target";
    if (node.id === END_ID) return "Shown to student";
    if (node.skip) return "Skipped route";
    if (node.ask_for_input) return "Wait for student, then call model";
    if (node.hasSwitch && node.hasPrompt) return "Model call, then branch";
    if (node.hasSwitch) return "Branch on " + (node.switchInput || "value");
    if (node.hasPrompt && node.terminal) return "Model call, then return response";
    if (node.hasPrompt) return "Model call";
    return node.terminal ? "Return response" : "Workflow step";
  }

  function buildGraph(tutor) {
    tutor = tutor || {};
    var rawNodes = asObject(tutor.nodes);
    var ids = Object.keys(rawNodes);
    var start = String(tutor.start_node || "");
    if (!rawNodes[start]) start = ids[0] || "";
    var nodeMap = {};
    var edges = [];

    ids.forEach(function (id) {
      var raw = asObject(rawNodes[id]);
      var routes = asObject(raw.switch_to);
      var next = String(raw.next || "");
      var hasSwitch = Object.keys(routes).length > 0;
      var hasPrompt = Boolean(String(raw.prompt || "").trim());
      nodeMap[id] = {
        id: id,
        raw: raw,
        hasSwitch: hasSwitch,
        hasPrompt: hasPrompt,
        switchInput: String(raw.switch_input || ""),
        ask_for_input: raw.ask_for_input === true,
        skip: raw.skip === true,
        parallel: Number(raw.n_parallel || 1),
        aggregate: String(raw.aggregate || ""),
        terminal: !next && !hasSwitch
      };
      if (next) edges.push({ from: id, to: next, label: "next", kind: "next" });
      Object.keys(routes).forEach(function (label) {
        var target = String(routes[label] || "");
        if (target) edges.push({ from: id, to: target, label: label, kind: "branch" });
      });
    });

    edges.forEach(function (edge) {
      if (nodeMap[edge.to]) return;
      nodeMap[edge.to] = {
        id: edge.to,
        missing: true,
        terminal: true,
        hasSwitch: false,
        hasPrompt: false
      };
    });

    var terminals = Object.keys(nodeMap).filter(function (id) {
      return id !== END_ID && nodeMap[id].terminal && !nodeMap[id].missing;
    });
    if (terminals.length) {
      nodeMap[END_ID] = {
        id: END_ID,
        displayId: "Student response",
        response: true,
        terminal: true,
        hasSwitch: false,
        hasPrompt: false
      };
      terminals.forEach(function (id) {
        edges.push({ from: id, to: END_ID, label: "response", kind: "response" });
      });
    }

    Object.keys(nodeMap).forEach(function (id) {
      nodeMap[id].kind = nodeKind(nodeMap[id]);
    });
    return {
      start: start,
      nodes: Object.keys(nodeMap).map(function (id) { return nodeMap[id]; }),
      edges: edges
    };
  }

  function graphLayout(graph) {
    var nodeIds = graph.nodes.map(function (node) { return node.id; });
    var adjacency = {};
    var indegree = {};
    var depths = {};
    nodeIds.forEach(function (id) {
      adjacency[id] = [];
      indegree[id] = 0;
      depths[id] = 0;
    });
    graph.edges.forEach(function (edge) {
      if (!adjacency[edge.from] || !Object.prototype.hasOwnProperty.call(indegree, edge.to)) return;
      if (adjacency[edge.from].indexOf(edge.to) >= 0) return;
      adjacency[edge.from].push(edge.to);
      indegree[edge.to] += 1;
    });

    var reachable = {};
    var reachQueue = graph.start ? [graph.start] : [];
    while (reachQueue.length) {
      var reachableId = reachQueue.shift();
      if (reachable[reachableId]) continue;
      reachable[reachableId] = true;
      (adjacency[reachableId] || []).forEach(function (target) {
        if (!reachable[target]) reachQueue.push(target);
      });
    }
    graph.nodes.forEach(function (node) {
      node.unreachable = !reachable[node.id];
    });

    var queue = nodeIds.filter(function (id) { return indegree[id] === 0; });
    var ordered = [];
    while (queue.length) {
      var source = queue.shift();
      ordered.push(source);
      adjacency[source].forEach(function (target) {
        depths[target] = Math.max(depths[target], depths[source] + 1);
        indegree[target] -= 1;
        if (indegree[target] === 0) queue.push(target);
      });
    }
    var cyclic = nodeIds.filter(function (id) { return ordered.indexOf(id) < 0; });
    if (cyclic.length) {
      var cycleDepth = Math.max.apply(null, Object.keys(depths).map(function (id) {
        return depths[id];
      })) + 1;
      cyclic.forEach(function (id, index) { depths[id] = cycleDepth + index; });
    }

    var layers = {};
    graph.nodes.forEach(function (node) {
      var depth = depths[node.id];
      layers[depth] = layers[depth] || [];
      layers[depth].push(node);
    });
    var layerIds = Object.keys(layers).map(Number).sort(function (a, b) { return a - b; });
    var nodeWidth = 210;
    var nodeHeight = 88;
    var horizontalGap = 54;
    var verticalGap = 88;
    var padding = 34;
    var widest = layerIds.reduce(function (value, depth) {
      return Math.max(value, layers[depth].length);
    }, 1);
    var width = Math.max(600, padding * 2 + widest * nodeWidth + (widest - 1) * horizontalGap);
    var positions = {};
    layerIds.forEach(function (depth, rowIndex) {
      var row = layers[depth];
      var rowWidth = row.length * nodeWidth + (row.length - 1) * horizontalGap;
      var left = (width - rowWidth) / 2;
      row.forEach(function (node, column) {
        positions[node.id] = {
          x: left + column * (nodeWidth + horizontalGap),
          y: padding + rowIndex * (nodeHeight + verticalGap)
        };
      });
    });
    return {
      width: width,
      height: padding * 2 + layerIds.length * nodeHeight + Math.max(0, layerIds.length - 1) * verticalGap,
      nodeWidth: nodeWidth,
      nodeHeight: nodeHeight,
      positions: positions,
      cyclic: cyclic
    };
  }

  function svgElement(name, attributes) {
    var element = document.createElementNS(SVG_NS, name);
    Object.keys(attributes || {}).forEach(function (key) {
      element.setAttribute(key, attributes[key]);
    });
    return element;
  }

  function edgePath(from, to, layout) {
    var startX = from.x + layout.nodeWidth / 2;
    var startY = from.y + layout.nodeHeight;
    var endX = to.x + layout.nodeWidth / 2;
    var endY = to.y;
    if (endY > startY) {
      var middleY = startY + (endY - startY) / 2;
      return "M " + startX + " " + startY + " C " + startX + " " + middleY + ", " + endX + " " + middleY + ", " + endX + " " + endY;
    }
    var side = Math.max(from.x + layout.nodeWidth, to.x + layout.nodeWidth) + 34;
    return "M " + startX + " " + startY + " C " + side + " " + (startY + 24) + ", " + side + " " + (endY - 24) + ", " + endX + " " + endY;
  }

  function addTextLines(group, x, y, lines, className) {
    var text = svgElement("text", { x: x, y: y, class: className });
    lines.forEach(function (line, index) {
      var span = svgElement("tspan", { x: x, dy: index === 0 ? 0 : 16 });
      span.textContent = line;
      text.appendChild(span);
    });
    group.appendChild(text);
  }

  function wrapLabel(value, maximum, maxLines) {
    var words = String(value || "").replace(/[_-]+/g, " ").split(/\s+/);
    var lines = [];
    words.forEach(function (word) {
      var last = lines[lines.length - 1];
      if (!last || (last + " " + word).length > maximum) {
        lines.push(word);
      } else {
        lines[lines.length - 1] += " " + word;
      }
    });
    if (lines.length > maxLines) {
      lines = lines.slice(0, maxLines);
      lines[maxLines - 1] = lines[maxLines - 1].replace(/[.\s]+$/, "") + "…";
    }
    return lines;
  }

  function renderSvg(graph, layout, onSelect, modifiedNodes) {
    modifiedNodes = modifiedNodes || {};
    var svg = svgElement("svg", {
      class: "ullme-flow-svg",
      viewBox: "0 0 " + layout.width + " " + layout.height,
      width: layout.width,
      height: layout.height,
      role: "img",
      "aria-label": "AI Tutor workflow from " + (graph.start || "an unspecified start node")
    });
    var defs = svgElement("defs");
    var marker = svgElement("marker", {
      id: "ullme-flow-arrow",
      markerWidth: 8,
      markerHeight: 8,
      refX: 7,
      refY: 4,
      orient: "auto",
      markerUnits: "strokeWidth"
    });
    marker.appendChild(svgElement("path", { d: "M 0 0 L 8 4 L 0 8 z", class: "ullme-flow-arrow-head" }));
    defs.appendChild(marker);
    svg.appendChild(defs);

    var edgeLayer = svgElement("g", { class: "ullme-flow-edges" });
    graph.edges.forEach(function (edge, index) {
      var from = layout.positions[edge.from];
      var to = layout.positions[edge.to];
      if (!from || !to) return;
      var path = svgElement("path", {
        d: edgePath(from, to, layout),
        class: "ullme-flow-edge ullme-flow-edge-" + edge.kind,
        "marker-end": "url(#ullme-flow-arrow)"
      });
      edgeLayer.appendChild(path);
      var labelX = (from.x + to.x) / 2 + layout.nodeWidth / 2;
      var labelY = (from.y + to.y + layout.nodeHeight) / 2 - 5 + (index % 2) * 12;
      var label = svgElement("text", {
        x: labelX,
        y: labelY,
        class: "ullme-flow-edge-label",
        "text-anchor": "middle"
      });
      label.textContent = edge.label;
      edgeLayer.appendChild(label);
    });
    svg.appendChild(edgeLayer);

    var nodeLayer = svgElement("g", { class: "ullme-flow-nodes" });
    graph.nodes.forEach(function (node) {
      var position = layout.positions[node.id];
      if (!position) return;
      var classes = ["ullme-flow-node"];
      if (node.id === graph.start) classes.push("ullme-flow-node-start");
      if (node.response) classes.push("ullme-flow-node-response");
      if (node.hasSwitch) classes.push("ullme-flow-node-switch");
      if (node.ask_for_input) classes.push("ullme-flow-node-wait");
      if (node.unreachable) classes.push("ullme-flow-node-unreachable");
      if (node.missing) classes.push("ullme-flow-node-missing");
      if (!node.response && !node.missing) classes.push("ullme-flow-node-editable");
      if (modifiedNodes[node.id]) classes.push("ullme-flow-node-modified");
      var group = svgElement("g", {
        class: classes.join(" "),
        "data-flow-node-id": node.id,
        transform: "translate(" + position.x + " " + position.y + ")"
      });
      group.appendChild(svgElement("rect", {
        width: layout.nodeWidth,
        height: layout.nodeHeight,
        rx: 10,
        ry: 10
      }));
      addTextLines(
        group,
        14,
        24,
        wrapLabel(node.displayId || node.id, 25, 2),
        "ullme-flow-node-title"
      );
      var detail = node.kind;
      if (node.parallel > 1) {
        detail += " · " + node.parallel + " parallel";
      }
      addTextLines(group, 14, 62, wrapLabel(detail, 32, 2), "ullme-flow-node-detail");
      if (node.id === graph.start) {
        var startLabel = svgElement("text", {
          x: layout.nodeWidth - 12,
          y: 19,
          class: "ullme-flow-start-label",
          "text-anchor": "end"
        });
        startLabel.textContent = "START";
        group.appendChild(startLabel);
      }
      if (!node.response && !node.missing) {
        group.setAttribute("role", "button");
        group.setAttribute("tabindex", "0");
        group.setAttribute("aria-label", "Edit workflow node " + node.id);
        group.addEventListener("click", function () { onSelect(node.id); });
        group.addEventListener("keydown", function (event) {
          if (event.key !== "Enter" && event.key !== " ") return;
          event.preventDefault();
          onSelect(node.id);
        });
      }
      nodeLayer.appendChild(group);
    });
    svg.appendChild(nodeLayer);
    return svg;
  }

  function render(tutor, options) {
    options = options || {};
    var panel = document.createElement("section");
    panel.className = "ullme-tutor-tab-panel ullme-flow-panel";
    if (options.variant) panel.classList.add("ullme-flow-variant");
    if (options.compact) panel.classList.add("ullme-flow-compact");
    var graph = buildGraph(tutor);
    if (!graph.nodes.length) {
      var empty = document.createElement("div");
      empty.className = "ullme-feature-empty";
      empty.innerHTML = "<strong>No workflow nodes</strong><span>Add nodes to the Tutor definition YAML to create a flow diagram.</span>";
      panel.appendChild(empty);
      return panel;
    }

    var toolbar = document.createElement("div");
    var summary = document.createElement("div");
    var controls = document.createElement("div");
    var viewport = document.createElement("div");
    var layout = graphLayout(graph);
    var modifiedNodes = {};
    (options.modifiedNodes || []).forEach(function (id) { modifiedNodes[id] = true; });
    var svg = renderSvg(graph, layout, function (nodeId) {
      if (typeof options.onSelect === "function") options.onSelect(nodeId);
      else selectNode(tutor, nodeId);
    }, modifiedNodes);
    var scale = 1;
    toolbar.className = "ullme-flow-toolbar";
    summary.className = "ullme-flow-summary";
    summary.textContent = graph.nodes.filter(function (node) { return !node.response; }).length +
      " nodes · starts at " + (graph.start || "no configured node");
    if (layout.cyclic.length) {
      summary.textContent += " · cycle detected";
      summary.classList.add("ullme-flow-summary-error");
    }
    controls.className = "ullme-flow-controls";
    viewport.className = "ullme-flow-viewport";
    viewport.tabIndex = 0;
    viewport.setAttribute("aria-label", "Scrollable AI Tutor flow diagram");

    function setScale(value) {
      scale = Math.max(0.4, Math.min(1.6, value));
      svg.style.width = Math.round(layout.width * scale) + "px";
      svg.style.height = Math.round(layout.height * scale) + "px";
    }
    function control(label, title, action) {
      var button = document.createElement("button");
      button.type = "button";
      button.className = "ullme-secondary-action ullme-flow-control";
      button.textContent = label;
      button.title = title;
      button.setAttribute("aria-label", title);
      button.addEventListener("click", action);
      controls.appendChild(button);
    }
    control("−", "Zoom out", function () { setScale(scale - 0.15); });
    control("Fit", "Fit diagram to width", function () {
      setScale(Math.min(1, (viewport.clientWidth - 28) / layout.width));
      viewport.scrollLeft = 0;
      viewport.scrollTop = 0;
    });
    control("+", "Zoom in", function () { setScale(scale + 0.15); });
    toolbar.appendChild(summary);
    toolbar.appendChild(controls);
    viewport.appendChild(svg);
    panel.appendChild(toolbar);
    panel.appendChild(viewport);

    var legend = document.createElement("div");
    legend.className = "ullme-flow-legend";
    legend.innerHTML =
      '<span><i class="ullme-flow-key ullme-flow-key-start"></i>Start</span>' +
      '<span><i class="ullme-flow-key ullme-flow-key-switch"></i>Branch</span>' +
      '<span><i class="ullme-flow-key ullme-flow-key-wait"></i>Wait for student</span>' +
      '<span><i class="ullme-flow-key ullme-flow-key-unreachable"></i>Unreachable</span>';
    panel.appendChild(legend);
    root.requestAnimationFrame(function () {
      setScale(Math.min(1, (viewport.clientWidth - 28) / layout.width));
    });
    return panel;
  }

  var editorState = {
    active: false,
    tutor: null,
    selectedNodeId: "",
    originalNodeId: "",
    creating: false,
    busy: false
  };

  function editorElements() {
    if (typeof document === "undefined") return {};
    return {
      tab: document.getElementById("ullme_node_editor_tab"),
      panel: document.getElementById("ullme_node_editor_panel"),
      title: document.getElementById("ullme_node_editor_title"),
      nodeId: document.getElementById("ullme_node_editor_id"),
      yaml: document.getElementById("ullme_node_editor_yaml"),
      status: document.getElementById("ullme_node_editor_status"),
      create: document.getElementById("ullme_node_editor_new"),
      remove: document.getElementById("ullme_node_editor_delete"),
      save: document.getElementById("ullme_node_editor_save")
    };
  }

  function dispatchAssistantTab(tab) {
    document.dispatchEvent(new CustomEvent("ullme:assistant-tab", {
      detail: { tab: tab }
    }));
  }

  function setEditorStatus(message, error) {
    var elements = editorElements();
    if (!elements.status) return;
    elements.status.textContent = message || "";
    elements.status.classList.toggle("ullme-node-editor-status-error", Boolean(error));
  }

  function nodeYaml(tutor, nodeId) {
    var yaml = asObject(tutor && tutor.node_yaml);
    return String(yaml[nodeId] || "").trim();
  }

  function fillEditor(tutor, nodeId, creating) {
    var elements = editorElements();
    if (!elements.nodeId || !elements.yaml) return;
    editorState.tutor = tutor || editorState.tutor;
    editorState.selectedNodeId = creating ? "" : String(nodeId || "");
    editorState.originalNodeId = creating ? "" : editorState.selectedNodeId;
    editorState.creating = Boolean(creating);
    elements.nodeId.readOnly = false;
    elements.nodeId.value = creating ? "" : editorState.selectedNodeId;
    elements.yaml.value = creating
      ? "prompt: |\n  Describe what this workflow node should do."
      : nodeYaml(editorState.tutor, editorState.selectedNodeId);
    elements.title.textContent = creating ? "Create workflow node" : "Edit " + editorState.selectedNodeId;
    elements.remove.hidden = creating;
    elements.save.textContent = creating ? "Create node" : "Save node";
    setEditorStatus(
      creating
        ? "Enter a new node ID and edit its YAML. The complete Tutor will be checked before creation."
        : "Edit the Node ID or YAML. Renaming updates start_node, next, and switch_to references.",
      false
    );
  }

  function selectNode(tutor, nodeId) {
    if (!tutor || !nodeId) return;
    fillEditor(tutor, nodeId, false);
    dispatchAssistantTab("node");
  }

  function sendNodeMutation(action) {
    var elements = editorElements();
    var tutor = editorState.tutor || {};
    var nodeId = String(elements.nodeId && elements.nodeId.value || "").trim();
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(nodeId)) {
      setEditorStatus(
        "Node IDs must start with a letter and contain only letters, numbers, or underscores.",
        true
      );
      return;
    }
    if (action !== "delete" && !String(elements.yaml && elements.yaml.value || "").trim()) {
      setEditorStatus("Node YAML cannot be empty.", true);
      return;
    }
    editorState.busy = true;
    elements.save.disabled = true;
    elements.remove.disabled = true;
    elements.create.disabled = true;
    setEditorStatus("Checking the node and complete Tutor…", false);
    var payload = {
      tutorid: String(tutor.tutorid || ""),
      nodeid: nodeId,
      original_nodeid: editorState.creating ? "" : editorState.originalNodeId,
      action: action,
      yaml_content: action === "delete" ? "" : elements.yaml.value,
      nonce: Math.random()
    };
    if (root.Shiny && root.Shiny.setInputValue) {
      root.Shiny.setInputValue("ullme_ai_tutor_node_event", payload, { priority: "event" });
    } else if (root.Shiny && root.Shiny.onInputChange) {
      root.Shiny.onInputChange("ullme_ai_tutor_node_event", payload);
    }
  }

  function initEditor() {
    var elements = editorElements();
    if (!elements.create || elements.create.dataset.ullmeBound === "true") return;
    elements.create.dataset.ullmeBound = "true";
    elements.create.addEventListener("click", function () {
      fillEditor(editorState.tutor, "", true);
      dispatchAssistantTab("node");
      elements.nodeId.focus();
    });
    elements.save.addEventListener("click", function () {
      sendNodeMutation(editorState.creating ? "create" : "save");
    });
    elements.remove.addEventListener("click", function () {
      var nodeId = editorState.selectedNodeId;
      if (!nodeId || !root.confirm(
        'Delete workflow node "' + nodeId + '"? The Tutor may become unavailable to students until its definition is repaired.'
      )) return;
      sendNodeMutation("delete");
    });
  }

  function setActive(active, tutor) {
    initEditor();
    var elements = editorElements();
    var previousTutorId = String(editorState.tutor && editorState.tutor.tutorid || "");
    var nextTutorId = String(tutor && tutor.tutorid || "");
    editorState.active = Boolean(active);
    editorState.tutor = tutor || null;
    if (elements.tab) elements.tab.hidden = !editorState.active;
    if (!editorState.active) {
      if (elements.tab && elements.tab.classList.contains("ullme-assistant-tab-active")) {
        dispatchAssistantTab("help");
      }
      return;
    }
    if (previousTutorId && previousTutorId !== nextTutorId) {
      editorState.selectedNodeId = "";
      editorState.originalNodeId = "";
      editorState.creating = false;
    }
    if (editorState.selectedNodeId && !editorState.busy &&
        asObject(tutor.nodes)[editorState.selectedNodeId]) {
      fillEditor(tutor, editorState.selectedNodeId, false);
    }
  }

  function nodeMutationComplete(result) {
    initEditor();
    var elements = editorElements();
    editorState.busy = false;
    elements.save.disabled = false;
    elements.remove.disabled = false;
    elements.create.disabled = false;
    if (!result || result.ok === false) {
      setEditorStatus((result && result.message) || "The workflow node could not be saved.", true);
      return;
    }
    if (root.ullmeTutorValidation && root.ullmeTutorValidation.reportSave) {
      root.ullmeTutorValidation.reportSave(result.validation);
    }
    var action = String(result.action || "save");
    if (action === "delete") {
      editorState.selectedNodeId = "";
      editorState.originalNodeId = "";
      editorState.creating = false;
      if (!result.validation || result.validation.is_valid !== false) {
        dispatchAssistantTab("help");
      }
      setEditorStatus(result.message || "Workflow node deleted.", false);
      return;
    }
    editorState.selectedNodeId = String(result.nodeid || "");
    editorState.originalNodeId = editorState.selectedNodeId;
    editorState.creating = false;
    elements.nodeId.readOnly = false;
    elements.remove.hidden = false;
    elements.save.textContent = "Save node";
    setEditorStatus(result.message || "Workflow node saved.", false);
  }

  var api = {
    buildGraph: buildGraph,
    layoutGraph: graphLayout,
    render: render,
    setActive: setActive,
    nodeMutationComplete: nodeMutationComplete
  };
  root.ullmeTutorFlow = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof document !== "undefined") {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", initEditor);
    } else {
      initEditor();
    }
  }
})(typeof window !== "undefined" ? window : globalThis);
