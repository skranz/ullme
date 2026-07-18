(function () {
  var state = {
    tutors: [],
    templates: [],
    selectedTutorId: "",
    activeTab: "instances",
    yamlTab: "definition",
    courseFiles: [],
    tutorPaneActive: false,
    loading: false,
    instanceAutoSave: null,
    initialized: false
  };

  var tutorIcon = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"></circle><path d="M5 21a7 7 0 0 1 14 0"></path><path d="M18 4l2-2M19 8h3"></path></svg>';
  var robotIcon = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="7" width="16" height="12" rx="3"></rect><path d="M12 3v4M8 12h.01M16 12h.01M8 16h8"></path></svg>';
  var undoIcon = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="M9 8l-4 4 4 4"></path><path d="M5 12h8a4 4 0 0 1 4 4"></path></svg>';
  var redoIcon = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="M15 8l4 4-4 4"></path><path d="M19 12h-8a4 4 0 0 0-4 4"></path></svg>';

  function byId(id) {
    return document.getElementById(id);
  }

  function sendEvent(inputId, payload) {
    payload = payload || {};
    payload.nonce = Math.random();
    if (window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue(inputId, payload, { priority: "event" });
    } else if (window.Shiny && Shiny.onInputChange) {
      Shiny.onInputChange(inputId, payload);
    }
  }

  function init() {
    if (state.initialized) return;
    state.initialized = true;
    var nav = byId("ullme_studio_nav");
    var addButton = byId("ullme_add_menu_btn");
    var addMenu = byId("ullme_add_menu");

    if (nav) {
      nav.addEventListener("click", function (event) {
        var tutorButton = event.target.closest("[data-tutor-id]");
        if (tutorButton && nav.contains(tutorButton)) {
          state.tutorPaneActive = true;
          selectTutor(tutorButton.getAttribute("data-tutor-id"));
          return;
        }
        var viewButton = event.target.closest("[data-studio-view]");
        if (viewButton && nav.contains(viewButton)) {
          state.tutorPaneActive = false;
          if (window.ullmeTutorValidation && window.ullmeTutorValidation.update) {
            window.ullmeTutorValidation.update(null);
          }
          if (window.ullmeTutorFlow && window.ullmeTutorFlow.setActive) {
            window.ullmeTutorFlow.setActive(false, null);
          }
          renderTutorNavigation();
        }
      });
    }

    if (addButton && addMenu) {
      addButton.addEventListener("click", function (event) {
        event.stopPropagation();
        var open = addMenu.classList.toggle("ullme-add-menu-open");
        addButton.setAttribute("aria-expanded", open ? "true" : "false");
        if (open) positionAddMenu(addButton, addMenu);
      });
      addMenu.addEventListener("click", function (event) {
        var item = event.target.closest("[data-add-kind]");
        if (!item) return;
        closeAddMenu();
        if (window.ullme) {
          var kind = item.getAttribute("data-add-kind");
          if (kind === "course" && window.ullme.openAddCourseDialog) {
            window.ullme.openAddCourseDialog();
          } else if (kind === "tutors" && window.ullme.openCatalogDialog) {
            window.ullme.openCatalogDialog("tutors");
          } else if (kind === "test-suite" && window.ullmeTests && window.ullmeTests.openCreateDialog) {
            window.ullmeTests.openCreateDialog();
          }
        }
      });
      document.addEventListener("click", function (event) {
        if (!addMenu.contains(event.target) && event.target !== addButton) closeAddMenu();
      });
    }
    render();
  }

  function positionAddMenu(button, menu) {
    var bounds = button.getBoundingClientRect();
    menu.style.left = Math.round(bounds.right + 8) + "px";
    menu.style.bottom = Math.max(8, Math.round(window.innerHeight - bounds.bottom)) + "px";
  }

  function closeAddMenu() {
    var button = byId("ullme_add_menu_btn");
    var menu = byId("ullme_add_menu");
    if (menu) menu.classList.remove("ullme-add-menu-open");
    if (button) button.setAttribute("aria-expanded", "false");
  }

  function update(tutors, templates, courseFiles, loading) {
    state.tutors = Array.isArray(tutors) ? tutors : [];
    state.templates = Array.isArray(templates) ? templates : [];
    if (arguments.length > 2) {
      state.courseFiles = (Array.isArray(courseFiles) ? courseFiles : [])
        .filter(function (file) {
          return String(file.path || "").indexOf("materials/") === 0;
        });
    }
    state.loading = Boolean(loading);
    if (!state.tutors.some(function (tutor) {
      return tutor.tutorid === state.selectedTutorId;
    })) {
      state.selectedTutorId = state.tutors.length ? state.tutors[0].tutorid : "";
    }
    if (state.instanceAutoSave && state.instanceAutoSave.saving) {
      renderTutorNavigation();
      return;
    }
    render();
  }

  function selectedTutor() {
    return state.tutors.find(function (tutor) {
      return tutor.tutorid === state.selectedTutorId;
    }) || null;
  }

  function selectTutor(tutorid) {
    if (!state.tutors.some(function (tutor) { return tutor.tutorid === tutorid; })) return;
    state.selectedTutorId = tutorid;
    renderTutorNavigation();
    renderTutorDetail();
  }

  function render() {
    if (!state.initialized && document.readyState !== "loading") init();
    renderTutorNavigation();
    renderTutorDetail();
  }

  function renderTutorNavigation() {
    var container = byId("ullme_tutor_nav_items");
    if (!container) return;
    container.innerHTML = "";
    state.tutors.forEach(function (tutor) {
      var button = document.createElement("button");
      var label = document.createElement("span");
      button.type = "button";
      button.className = "ullme-studio-nav-item ullme-dynamic-nav-item";
      if (state.tutorPaneActive && tutor.tutorid === state.selectedTutorId) {
        button.classList.add("ullme-studio-nav-item-active");
      }
      button.setAttribute("data-studio-view", "ai-tutors");
      button.setAttribute("data-tutor-id", tutor.tutorid);
      button.title = tutor.label || tutor.tutorid;
      button.innerHTML = tutorIcon;
      label.textContent = tutor.label || tutor.tutorid;
      button.appendChild(label);
      container.appendChild(button);
    });
  }

  function renderTutorDetail() {
    var container = byId("ullme_ai_tutor_detail");
    if (!container) return;
    var previousAutoSave = state.instanceAutoSave;
    if (previousAutoSave && previousAutoSave.panel.isConnected &&
        !previousAutoSave.saving &&
        instanceAssignmentSnapshot(previousAutoSave) !== previousAutoSave.lastSubmitted) {
      submitInstanceAutosave(previousAutoSave);
    }
    if (previousAutoSave && !previousAutoSave.saving) {
      state.instanceAutoSave = null;
    }
    container.innerHTML = "";
    var tutor = selectedTutor();
    if (!tutor) {
      if (window.ullmeTutorValidation && window.ullmeTutorValidation.update) {
        window.ullmeTutorValidation.update(null);
      }
      if (window.ullmeTutorFlow && window.ullmeTutorFlow.setActive) {
        window.ullmeTutorFlow.setActive(false, null);
      }
      container.appendChild(emptyState(
        state.loading ? "Still computing AI Tutors" : "No AI Tutor selected",
        state.loading
          ? "The Tutor buttons and full editor will appear as soon as the course data is ready."
          : "Use Add to create an editable course copy."
      ));
      return;
    }
    if (tutor.loading) {
      if (window.ullmeTutorValidation && window.ullmeTutorValidation.update) {
        window.ullmeTutorValidation.update(null);
      }
      if (window.ullmeTutorFlow && window.ullmeTutorFlow.setActive) {
        window.ullmeTutorFlow.setActive(false, null);
      }
      container.appendChild(emptyState(
        "Still computing " + (tutor.label || tutor.tutorid),
        "The Tutor instances and flow data are being prepared. You can keep using the rest of the Teacher App."
      ));
      return;
    }
    if (tutor.multiple_instances === false && state.activeTab === "instances") {
      state.activeTab = "yaml";
    }
    if (tutor.multiple_instances === false && state.yamlTab === "instances") {
      state.yamlTab = "definition";
    }
    if (window.ullmeTutorFlow && window.ullmeTutorFlow.setActive) {
      window.ullmeTutorFlow.setActive(
        state.tutorPaneActive && state.activeTab === "flow",
        tutor
      );
    }
    if (window.ullmeTutorValidation && window.ullmeTutorValidation.update) {
      window.ullmeTutorValidation.update(state.tutorPaneActive ? tutor : null);
    }

    container.appendChild(tutorHeader(tutor));
    container.appendChild(tutorTabs(tutor));
    if (state.activeTab === "yaml") {
      container.appendChild(yamlEditor(tutor));
    } else if (state.activeTab === "flow") {
      container.appendChild(flowDiagram(tutor));
    } else {
      container.appendChild(instancePanel(tutor));
    }
    notifyTutorHelp();
  }

  function tutorHeader(tutor) {
    var header = document.createElement("header");
    var identity = document.createElement("div");
    var select = document.createElement("select");
    var tutorId = document.createElement("div");
    var description = document.createElement("div");
    var actions = document.createElement("div");
    var history = tutorHistoryControls(tutor);
    var remove = document.createElement("button");
    var toggleLabel = document.createElement("label");
    var toggle = document.createElement("input");
    var toggleText = document.createElement("span");

    header.className = "ullme-tutor-detail-header";
    identity.className = "ullme-tutor-detail-identity";
    select.className = "ullme-tutor-selector";
    select.setAttribute("aria-label", "AI Tutor");
    state.tutors.forEach(function (item) {
      var option = document.createElement("option");
      option.value = item.tutorid;
      option.textContent = item.label || item.tutorid;
      option.selected = item.tutorid === tutor.tutorid;
      select.appendChild(option);
    });
    select.addEventListener("change", function () {
      selectTutor(select.value);
    });
    tutorId.className = "ullme-tutor-detail-id";
    tutorId.textContent = "Tutor ID: " + tutor.tutorid;
    description.className = "ullme-tutor-detail-description";
    description.textContent = tutor.description || "No description";
    identity.appendChild(select);
    identity.appendChild(tutorId);
    identity.appendChild(description);

    actions.className = "ullme-tutor-detail-actions";
    remove.type = "button";
    remove.className = "ullme-danger-action ullme-tutor-delete-button";
    remove.textContent = "Delete Tutor";
    remove.addEventListener("click", function () {
      if (!window.confirm(
        'Delete Tutor "' + (tutor.label || tutor.tutorid) +
        '" (' + tutor.tutorid + ')?'
      )) return;
      remove.disabled = true;
      sendEvent("ullme_ai_tutor_delete_event", {
        tutorid: tutor.tutorid
      });
    });
    toggleLabel.className = "ullme-tutor-enabled";
    toggle.type = "checkbox";
    toggle.checked = Boolean(tutor.enabled);
    toggle.setAttribute("aria-label", "Enable AI Tutor");
    toggle.addEventListener("change", function () {
      sendEvent("ullme_ai_tutor_toggle_event", {
        tutorid: tutor.tutorid,
        enabled: toggle.checked
      });
    });
    toggleText.textContent = "Enabled";
    toggleLabel.appendChild(toggle);
    toggleLabel.appendChild(toggleText);
    actions.appendChild(history);
    actions.appendChild(remove);
    actions.appendChild(toggleLabel);
    header.appendChild(identity);
    header.appendChild(actions);
    return header;
  }

  function tutorHistoryControls(tutor) {
    var wrap = document.createElement("div");
    var editHistory = tutor.edit_history || {};
    var scope = "tutor_definition";
    var history = editHistory.definition || {};
    if (tutor.multiple_instances !== false && (
        state.activeTab === "instances" ||
        (state.activeTab === "yaml" && state.yamlTab === "instances"))) {
      scope = "tutor_instances";
      history = editHistory.instances || {};
    }
    wrap.className = "ullme-edit-history-controls";
    [
      { direction: "undo", icon: undoIcon, enabled: Boolean(history.can_undo) },
      { direction: "redo", icon: redoIcon, enabled: Boolean(history.can_redo) }
    ].forEach(function (spec) {
      var button = document.createElement("button");
      var label = spec.direction === "undo" ? "Undo" : "Redo";
      button.type = "button";
      button.className = "ullme-icon-button ullme-edit-history-button";
      button.innerHTML = spec.icon;
      button.disabled = !spec.enabled;
      button.title = label;
      button.setAttribute("aria-label", label + " changes in this Tutor pane");
      button.addEventListener("click", function () {
        button.disabled = true;
        sendEvent("ullme_edit_history_event", {
          scope: scope,
          tutorid: tutor.tutorid,
          direction: spec.direction
        });
      });
      wrap.appendChild(button);
    });
    return wrap;
  }

  function tutorTabs(tutor) {
    var tabs = document.createElement("nav");
    tabs.className = "ullme-tutor-tabs";
    var tabSpecs = [
      { id: "flow", label: "Flow" },
      { id: "yaml", label: "Tutor YAML" }
    ];
    if (tutor.multiple_instances !== false) {
      tabSpecs.unshift({
        id: "instances",
        label: "Instances (" + Number(tutor.instance_count || 0) + ")"
      });
    }
    tabSpecs.forEach(function (tab) {
      var button = document.createElement("button");
      button.type = "button";
      button.className = "ullme-tutor-tab";
      if (state.activeTab === tab.id) button.classList.add("ullme-tutor-tab-active");
      button.textContent = tab.label;
      button.addEventListener("click", function () {
        state.activeTab = tab.id;
        renderTutorDetail();
      });
      tabs.appendChild(button);
    });
    return tabs;
  }

  function flowDiagram(tutor) {
    if (window.ullmeTutorFlow && window.ullmeTutorFlow.render) {
      return window.ullmeTutorFlow.render(tutor);
    }
    return emptyState(
      "Flow diagram unavailable",
      "The Tutor workflow renderer could not be loaded."
    );
  }

  function notifyTutorHelp() {
    if (!state.tutorPaneActive) return;
    var view = "ai-tutors-instances";
    if (state.activeTab === "flow") {
      view = "ai-tutors-flow";
    } else if (state.activeTab === "yaml") {
      view = state.yamlTab === "instances"
        ? "ai-tutors-yaml-instances"
        : "ai-tutors-yaml-definition";
    }
    document.dispatchEvent(new CustomEvent("ullme:help-view", {
      detail: { view: view }
    }));
  }

  function instancePanel(tutor) {
    var panel = document.createElement("section");
    panel.className = "ullme-tutor-tab-panel";
    var instances = Array.isArray(tutor.instances) ? tutor.instances : [];
    var roles = Array.isArray(tutor.doc_ids_per_instance)
      ? tutor.doc_ids_per_instance.slice()
      : [];
    var courseRoles = Array.isArray(tutor.doc_ids_per_course)
      ? tutor.doc_ids_per_course.slice()
      : [];

    if (!tutor.instance_assignments_saved && instances.length) {
      var suggestion = document.createElement("div");
      suggestion.className = "ullme-suggestion-summary";
      suggestion.innerHTML = "<strong>Suggested from course files</strong>" +
        "<span>Review these document assignments. Changes save automatically.</span>";
      panel.appendChild(suggestion);
    }

    if (courseRoles.length) {
      panel.appendChild(documentAssignments(
        "Course documents",
        "ullme_course_docs",
        courseRoles,
        tutor.course_docs || {}
      ));
    }

    var wrap = document.createElement("div");
    var table = document.createElement("table");
    var head = document.createElement("thead");
    var headRow = document.createElement("tr");
    var body = document.createElement("tbody");
    body.id = "ullme_tutor_instance_rows";
    appendCell(headRow, "th", "Instance ID");
    appendCell(headRow, "th", "Label");
    roles.forEach(function (role) {
      appendCell(headRow, "th", humanize(role));
    });
    appendCell(headRow, "th", "");
    head.appendChild(headRow);
    instances.forEach(function (instance) {
      body.appendChild(instanceEditorRow(instance, roles, tutor));
    });
    table.appendChild(head);
    table.appendChild(body);
    wrap.className = "ullme-instance-table-wrap";
    wrap.appendChild(table);
    panel.appendChild(wrap);

    var actions = document.createElement("div");
    var suggest = document.createElement("button");
    var add = document.createElement("button");
    var status = document.createElement("span");
    actions.className = "ullme-tutor-form-actions ullme-instance-actions";
    suggest.type = "button";
    suggest.className = "ullme-secondary-action";
    suggest.classList.add("ullme-instance-builder-button");
    suggest.innerHTML = robotIcon + "<span>Make Instances</span>";
    suggest.addEventListener("click", function () {
      openInstanceBuilderDialog(tutor);
    });
    add.type = "button";
    add.className = "ullme-secondary-action";
    add.textContent = "Add instance";
    add.addEventListener("click", function () {
      body.appendChild(instanceEditorRow({ instanceid: "", label: "", docs: {} }, roles, tutor));
    });
    status.className = "ullme-instance-autosave-status";
    status.setAttribute("role", "status");
    status.setAttribute("aria-live", "polite");
    status.textContent = "Changes save automatically";
    actions.appendChild(suggest);
    actions.appendChild(add);
    actions.appendChild(status);
    panel.appendChild(actions);
    if (!instances.length) {
      panel.insertBefore(emptyState(
        "No instances found",
        "Add an instance manually. Document suggestions appear automatically when matching course files are found."
      ), wrap);
    }
    var coordinator = {
      tutor: tutor,
      roles: roles,
      courseRoles: courseRoles,
      panel: panel,
      status: status,
      timer: null,
      saving: false,
      pending: false,
      lastSubmitted: ""
    };
    coordinator.lastSubmitted = instanceAssignmentSnapshot(coordinator);
    state.instanceAutoSave = coordinator;
    panel.addEventListener("focusout", function (event) {
      if (event.target && event.target.matches("input, textarea")) {
        scheduleInstanceAutosave(coordinator);
      }
    });
    panel.addEventListener("change", function (event) {
      if (event.target && event.target.matches("select, input[type='checkbox']")) {
        scheduleInstanceAutosave(coordinator);
      }
    });
    panel.addEventListener("click", function (event) {
      if (event.target && event.target.classList.contains("ullme-text-action")) {
        scheduleInstanceAutosave(coordinator);
      }
    });
    return panel;
  }

  function instanceAssignmentPayload(coordinator) {
    return {
      tutorid: coordinator.tutor.tutorid,
      instances: collectInstanceRows(coordinator.roles),
      course_docs: collectCourseDocs(coordinator.courseRoles)
    };
  }

  function instanceAssignmentSnapshot(coordinator) {
    return JSON.stringify(instanceAssignmentPayload(coordinator));
  }

  function scheduleInstanceAutosave(coordinator) {
    if (!coordinator || !coordinator.panel.isConnected) return;
    if (coordinator.timer) window.clearTimeout(coordinator.timer);
    coordinator.timer = window.setTimeout(function () {
      coordinator.timer = null;
      submitInstanceAutosave(coordinator);
    }, 50);
  }

  function submitInstanceAutosave(coordinator) {
    if (!coordinator || !coordinator.panel.isConnected) return;
    var snapshot = instanceAssignmentSnapshot(coordinator);
    if (snapshot === coordinator.lastSubmitted) {
      if (!coordinator.saving) coordinator.status.textContent = "Saved";
      return;
    }
    if (coordinator.saving) {
      coordinator.pending = true;
      coordinator.status.textContent = "More changes waiting to save…";
      return;
    }
    coordinator.saving = true;
    coordinator.pending = false;
    coordinator.lastSubmitted = snapshot;
    coordinator.status.textContent = "Saving…";
    sendEvent("ullme_ai_tutor_instances_save_event", instanceAssignmentPayload(coordinator));
  }

  function openInstanceBuilderDialog(tutor) {
    var existing = byId("ullme_instance_builder_dialog");
    if (existing) existing.remove();
    var backdrop = document.createElement("div");
    var dialog = document.createElement("section");
    var title = document.createElement("h2");
    var description = document.createElement("p");
    var historyWrap = document.createElement("label");
    var historyLabel = document.createElement("span");
    var history = document.createElement("select");
    var modelWrap = document.createElement("label");
    var modelLabel = document.createElement("span");
    var model = document.createElement("select");
    var guidance = document.createElement("textarea");
    var actions = document.createElement("div");
    var cancel = document.createElement("button");
    var start = document.createElement("button");
    backdrop.id = "ullme_instance_builder_dialog";
    backdrop.className = "ullme-instance-builder-backdrop";
    dialog.className = "ullme-instance-builder-dialog";
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    dialog.setAttribute("aria-label", "Make AI Tutor instances");
    title.textContent = "Make AI Tutor instances";
    description.textContent =
      "Describe filename conventions or which files belong together. " +
      "The AI helper will use filenames in ps/ to write instances.yml. " +
      "Convert source files manually before running it.";
    var savedInputs = tutor.instance_builder_inputs || {};
    var recentInputs = Array.isArray(savedInputs.recent)
      ? savedInputs.recent.slice(0, 5)
      : [];
    var defaultInput = String(savedInputs.default || "").trim() ||
      String(tutor.instance_guidance || "").trim();
    historyWrap.className = "ullme-instance-builder-history";
    historyLabel.textContent = "Reuse a recent instruction";
    history.setAttribute("aria-label", "Recent instance-builder instructions");
    var historyPlaceholder = document.createElement("option");
    historyPlaceholder.value = "";
    historyPlaceholder.textContent = recentInputs.length
      ? "Choose one of the last saved instructions"
      : "No saved instructions yet";
    history.appendChild(historyPlaceholder);
    recentInputs.forEach(function (record, index) {
      var option = document.createElement("option");
      var text = String(record.text || "").trim();
      var scope = record.scope === "course" ? "This course" : "My prompts";
      var preview = text.replace(/\s+/g, " ");
      if (preview.length > 82) preview = preview.slice(0, 79) + "…";
      option.value = String(index);
      option.textContent = scope + " · " + preview;
      if (text === defaultInput) option.selected = true;
      history.appendChild(option);
    });
    history.disabled = recentInputs.length === 0;
    history.addEventListener("change", function () {
      if (!history.value) return;
      var record = recentInputs[Number(history.value)];
      if (record) guidance.value = String(record.text || "");
    });
    guidance.placeholder =
      'Example: Create one instance per problem set. Solution files end in "solution".';
    guidance.value = defaultInput;
    guidance.addEventListener("input", function () {
      var selected = recentInputs[Number(history.value)];
      if (!selected || String(selected.text || "") !== guidance.value) {
        history.value = "";
      }
    });
    modelWrap.className = "ullme-instance-builder-history";
    modelLabel.textContent = "AI model";
    model.setAttribute("aria-label", "AI model for instance builder");
    var chatModel = byId("ullme_model_select");
    if (chatModel) {
      Array.prototype.forEach.call(chatModel.options, function (source) {
        var option = document.createElement("option");
        option.value = source.value;
        option.textContent = source.textContent;
        option.title = source.title || source.value;
        option.selected = source.value === chatModel.value;
        model.appendChild(option);
      });
    }
    model.disabled = !model.options.length;
    actions.className = "ullme-dialog-actions";
    cancel.type = "button";
    cancel.className = "ullme-secondary-action";
    cancel.textContent = "Cancel";
    start.type = "button";
    start.className = "ullme-primary-action";
    start.innerHTML = robotIcon + "<span>Start AI helper</span>";
    cancel.addEventListener("click", function () { backdrop.remove(); });
    start.addEventListener("click", function () {
      if (!window.ullme || !window.ullme.startInstanceBuilder) {
        window.alert("The AI helper is not available.");
        return;
      }
      var submittedGuidance = guidance.value.trim();
      if (submittedGuidance) {
        var record = {
          text: submittedGuidance,
          scope: "course",
          saved_at: new Date().toISOString()
        };
        recentInputs = [record].concat(recentInputs.filter(function (item) {
          return String(item.text || "").trim() !== submittedGuidance;
        })).slice(0, 5);
        tutor.instance_builder_inputs = tutor.instance_builder_inputs || {};
        tutor.instance_builder_inputs.recent = recentInputs;
        tutor.instance_builder_inputs.default = submittedGuidance;
      }
      backdrop.remove();
      window.ullme.startInstanceBuilder({
        tutorid: tutor.tutorid,
        label: tutor.label || tutor.tutorid,
        guidance: submittedGuidance,
        model: model.value || null
      });
    });
    [cancel, start].forEach(function (button) { actions.appendChild(button); });
    dialog.appendChild(title);
    dialog.appendChild(description);
    historyWrap.appendChild(historyLabel);
    historyWrap.appendChild(history);
    dialog.appendChild(historyWrap);
    modelWrap.appendChild(modelLabel);
    modelWrap.appendChild(model);
    dialog.appendChild(modelWrap);
    dialog.appendChild(guidance);
    dialog.appendChild(actions);
    backdrop.appendChild(dialog);
    document.body.appendChild(backdrop);
    guidance.focus();
  }

  function instanceEditorRow(instance, roles, tutor) {
    var row = document.createElement("tr");
    var idCell = document.createElement("td");
    var idInput = document.createElement("input");
    var labelCell = document.createElement("td");
    var labelInput = document.createElement("input");
    var removeCell = document.createElement("td");
    var remove = document.createElement("button");
    row.className = "ullme-instance-editor-row";
    idInput.className = "ullme-instance-input ullme-instance-id";
    idInput.value = instance.instanceid || "";
    idInput.placeholder = "ps1";
    idCell.appendChild(idInput);
    row.appendChild(idCell);
    labelInput.className = "ullme-instance-input ullme-instance-label";
    labelInput.value = instance.label || instance.instanceid || "";
    labelInput.placeholder = "Problem Set 1";
    labelCell.appendChild(labelInput);
    row.appendChild(labelCell);
    roles.forEach(function (role) {
      var cell = document.createElement("td");
      var input = document.createElement("input");
      var paths = instance.docs && instance.docs[role];
      var spec = tutorDocSpec(tutor, role, "docs_per_instance");
      input.className = "ullme-instance-input ullme-instance-docs";
      input.setAttribute("data-docid", role);
      input.value = (Array.isArray(paths) ? paths : (paths ? [paths] : [])).join(", ");
      input.placeholder = materialFilterLabel(spec);
      cell.appendChild(input);
      attachMaterialSuggestions(input, spec, role);
      row.appendChild(cell);
    });
    remove.type = "button";
    remove.className = "ullme-text-action";
    remove.textContent = "Remove";
    remove.addEventListener("click", function () { row.remove(); });
    removeCell.appendChild(remove);
    row.appendChild(removeCell);
    return row;
  }

  function collectInstanceRows(roles) {
    var body = byId("ullme_tutor_instance_rows");
    if (!body) return [];
    return Array.prototype.map.call(body.querySelectorAll("tr"), function (row) {
      var docs = {};
      roles.forEach(function (role) {
        var input = row.querySelector('[data-docid="' + role + '"]');
        docs[role] = splitList(input ? input.value : "");
      });
      return {
        instanceid: (row.querySelector(".ullme-instance-id") || {}).value || "",
        label: (row.querySelector(".ullme-instance-label") || {}).value || "",
        docs: docs
      };
    }).filter(function (instance) { return instance.instanceid.trim(); });
  }

  function documentAssignments(titleText, id, roles, values) {
    var section = document.createElement("div");
    var title = document.createElement("h3");
    var grid = document.createElement("div");
    section.className = "ullme-tutor-form-section ullme-course-docs";
    title.textContent = titleText;
    grid.id = id;
    grid.className = "ullme-course-doc-grid";
    roles.forEach(function (role) {
      var paths = values && values[role];
      var assignment = field(
        humanize(role),
        id + "_" + role,
        "input",
        (Array.isArray(paths) ? paths : (paths ? [paths] : [])).join(", "),
        "Comma-separated relative material paths"
      );
      attachMaterialSuggestions(
        assignment.querySelector("input"),
        tutorDocSpec(selectedTutor(), role, "docs_per_course"),
        role
      );
      grid.appendChild(assignment);
    });
    section.appendChild(title);
    section.appendChild(grid);
    return section;
  }

  function tutorDocSpec(tutor, role, fieldName) {
    var specs = tutor && Array.isArray(tutor[fieldName]) ? tutor[fieldName] : [];
    return specs.find(function (spec) { return spec.docid === role; }) || {};
  }

  function materialChoices(spec) {
    spec = spec || {};
    var directory = String(spec.pref_doc_dir || "").replace(/^\/+|\/+$/g, "");
    var prefix = "materials/" + (directory ? directory + "/" : "");
    var extensions = (Array.isArray(spec.file_types) ? spec.file_types : [])
      .map(function (value) { return String(value).replace(/^\./, "").toLowerCase(); });
    return state.courseFiles.filter(function (file) {
      var path = String(file.path || "");
      return path.indexOf(prefix) === 0 &&
        (!extensions.length || extensions.indexOf(String(file.extension || "").toLowerCase()) >= 0);
    }).map(function (file) {
      return String(file.path).replace(/^materials\//, "");
    });
  }

  function materialFilterLabel(spec) {
    spec = spec || {};
    var directory = String(spec.pref_doc_dir || "materials");
    var extensions = Array.isArray(spec.file_types) ? spec.file_types : [];
    return "Choose " + directory + (extensions.length ? " · " + extensions.join(", ") : " file");
  }

  function attachMaterialSuggestions(input, spec, role) {
    if (!input) return;
    var choices = materialChoices(spec);
    var list = document.createElement("datalist");
    var id = "ullme_material_choices_" + String(role || "file").replace(/[^A-Za-z0-9_-]/g, "_") +
      "_" + Math.random().toString(36).slice(2);
    list.id = id;
    choices.forEach(function (path) {
      var option = document.createElement("option");
      option.value = path;
      list.appendChild(option);
    });
    input.setAttribute("list", id);
    input.title = choices.length
      ? "Choose a file below materials/" + String(spec.pref_doc_dir || "") +
        " matching: " + (spec.file_types || []).join(", ")
      : "No material files match this document role's directory and file-type filters.";
    input.parentNode.appendChild(list);
  }

  function collectCourseDocs(roles) {
    var result = {};
    roles.forEach(function (role) {
      result[role] = splitList(valueOf("ullme_course_docs_" + role));
    });
    return result;
  }

  function promptForm(tutor) {
    var form = document.createElement("section");
    var prompt = document.createElement("div");
    var actions = document.createElement("div");
    var save = document.createElement("button");

    form.className = "ullme-tutor-tab-panel ullme-tutor-prompt-form";
    prompt.className = "ullme-tutor-form-section ullme-tutor-prompt-section";
    prompt.appendChild(field(
      "System prompt",
      "ullme_tutor_system_prompt",
      "textarea",
      tutor.system_prompt || ""
    ));
    actions.className = "ullme-tutor-form-actions";
    save.type = "button";
    save.className = "ullme-primary-action ullme-tutor-save-button";
    save.textContent = "Save prompt";
    save.addEventListener("click", function () {
      save.disabled = true;
      sendEvent("ullme_ai_tutor_save_event", {
        tutorid: tutor.tutorid,
        mode: "ui",
        fields: {
          system_prompt: valueOf("ullme_tutor_system_prompt")
        }
      });
    });
    actions.appendChild(save);
    form.appendChild(prompt);
    form.appendChild(actions);
    return form;
  }

  function configForm(tutor) {
    var form = document.createElement("section");
    var basics = document.createElement("div");
    var customization = document.createElement("div");
    var actions = document.createElement("div");
    var save = document.createElement("button");

    form.className = "ullme-tutor-tab-panel ullme-tutor-definition-form";
    basics.className = "ullme-tutor-form-section";
    basics.appendChild(sectionTitle("Basics"));
    basics.appendChild(field("Language", "ullme_tutor_lang", "input", tutor.lang || ""));
    basics.appendChild(field("Label", "ullme_tutor_label", "input", tutor.label || ""));
    basics.appendChild(field(
      "Description",
      "ullme_tutor_description",
      "textarea",
      tutor.description || ""
    ));
    basics.appendChild(field(
      "Text shown to students at start",
      "ullme_tutor_shown_text",
      "textarea",
      tutor.shown_text || "",
      "Displayed as the Tutor's first chat message."
    ));
    basics.appendChild(checkboxField(
      "Use multiple Tutor instances",
      "ullme_tutor_multiple_instances",
      tutor.multiple_instances !== false,
      "Disable this for one course-wide Tutor."
    ));
    basics.appendChild(checkboxField(
      "Store and show student chat history",
      "ullme_tutor_chat_history",
      Boolean(tutor.chat_history),
      "Shows course- and Tutor-specific conversations in the student sidebar."
    ));
    basics.appendChild(checkboxField(
      "Show final node output",
      "ullme_tutor_show_final_output",
      tutor.show_final_output !== false,
      "Enabled by default. Disable it when show_before/show_after provide the complete student-facing response."
    ));
    if (tutor.multiple_instances !== false) {
      basics.appendChild(field(
        "Typical instances for the AI helper",
        "ullme_tutor_instance_guidance",
        "textarea",
        tutor.instance_guidance || "",
        "Explain filename conventions, solution matching, and what normally forms one instance."
      ));
    }
    customization.className = "ullme-tutor-form-section";
    customization.appendChild(sectionTitle("Customization and tools"));
    customization.appendChild(field(
      "Default personality",
      "ullme_tutor_default_personality",
      "textarea",
      tutor.default_personality || ""
    ));
    customization.appendChild(field(
      "Allowed tools",
      "ullme_tutor_tools",
      "input",
      (tutor.allowed_tools || []).join(", "),
      "Comma-separated tool IDs"
    ));
    customization.appendChild(field(
      "Student customization",
      "ullme_tutor_customization",
      "input",
      (tutor.allowed_student_customization || []).join(", "),
      "Comma-separated customization fields"
    ));
    form.appendChild(basics);
    form.appendChild(customization);
    if (tutor.multiple_instances !== false) {
      form.appendChild(documentSpecsEditor(
        "Documents per instance",
        "ullme_docs_per_instance",
        tutor.docs_per_instance || [],
        false
      ));
    }
    form.appendChild(placeholderDocumentsEditor(
      tutor.placeholder_documents || []
    ));
    form.appendChild(filePermissionsEditor(tutor.file_permissions || []));

    actions.className = "ullme-tutor-form-actions";
    save.type = "button";
    save.className = "ullme-primary-action ullme-tutor-save-button";
    save.textContent = "Save config";
    save.addEventListener("click", function () {
      save.disabled = true;
      sendEvent("ullme_ai_tutor_save_event", {
        tutorid: tutor.tutorid,
        mode: "ui",
        fields: {
          lang: valueOf("ullme_tutor_lang"),
          label: valueOf("ullme_tutor_label"),
          description: valueOf("ullme_tutor_description"),
          shown_text: valueOf("ullme_tutor_shown_text"),
          instance_guidance: tutor.multiple_instances === false
            ? (tutor.instance_guidance || "")
            : valueOf("ullme_tutor_instance_guidance"),
          multiple_instances: checkedOf("ullme_tutor_multiple_instances"),
          chat_history: checkedOf("ullme_tutor_chat_history"),
          show_final_output: checkedOf("ullme_tutor_show_final_output"),
          default_personality: valueOf("ullme_tutor_default_personality"),
          allowed_tools: splitList(valueOf("ullme_tutor_tools")),
          allowed_student_customization: splitList(valueOf("ullme_tutor_customization")),
          docs_per_instance: tutor.multiple_instances === false
            ? (tutor.docs_per_instance || [])
            : collectDocSpecs("ullme_docs_per_instance"),
          placeholder_documents: collectPlaceholderDocuments(),
          file_permissions: collectFilePermissions()
        }
      });
    });
    actions.appendChild(save);
    form.appendChild(actions);
    return form;
  }

  function documentSpecsEditor(titleText, id, specs, allowFixedPaths) {
    var section = document.createElement("div");
    var head = document.createElement("div");
    var title = sectionTitle(titleText);
    var add = document.createElement("button");
    var table = document.createElement("table");
    var tableHead = document.createElement("thead");
    var headRow = document.createElement("tr");
    var body = document.createElement("tbody");
    section.className = "ullme-tutor-form-section";
    section.classList.add("ullme-doc-spec-section");
    head.className = "ullme-doc-spec-head";
    add.type = "button";
    add.className = "ullme-secondary-action";
    add.textContent = "Add document";
    add.addEventListener("click", function () {
      body.appendChild(docSpecRow({}, allowFixedPaths));
    });
    head.appendChild(title);
    head.appendChild(add);
    var labels = ["ID"];
    if (allowFixedPaths) labels.push("Fixed material file");
    labels = labels.concat(["Description", "File types", "Directory", "Images", ""]);
    labels
      .forEach(function (label) { appendCell(headRow, "th", label); });
    tableHead.appendChild(headRow);
    body.id = id;
    (Array.isArray(specs) ? specs : []).forEach(function (spec) {
      body.appendChild(docSpecRow(spec, allowFixedPaths));
    });
    table.appendChild(tableHead);
    table.appendChild(body);
    section.appendChild(head);
    var wrap = document.createElement("div");
    wrap.className = "ullme-doc-spec-table-wrap";
    wrap.appendChild(table);
    section.appendChild(wrap);
    return section;
  }

  function docSpecRow(spec, allowFixedPaths) {
    var row = document.createElement("tr");
    var fields = [
      { name: "docid", value: spec.docid || "", placeholder: "ps" }
    ];
    if (allowFixedPaths) {
      fields.push({
        name: "fixed_path",
        value: spec.fixed_path || "",
        placeholder: "knowledge.md"
      });
    }
    fields = fields.concat([
      { name: "descr", value: spec.descr || "", placeholder: "Problem set" },
      { name: "file_types", value: (spec.file_types || []).join(", "), placeholder: "md, tex" },
      { name: "pref_doc_dir", value: spec.pref_doc_dir || "", placeholder: "ps" }
    ]);
    fields.forEach(function (fieldSpec) {
      var cell = document.createElement("td");
      var input = document.createElement("input");
      input.className = "ullme-doc-spec-input";
      input.setAttribute("data-field", fieldSpec.name);
      input.value = fieldSpec.value;
      input.placeholder = fieldSpec.placeholder;
      cell.appendChild(input);
      row.appendChild(cell);
    });
    var imageCell = document.createElement("td");
    var images = document.createElement("input");
    images.type = "checkbox";
    images.checked = Boolean(spec.add_images);
    images.setAttribute("data-field", "add_images");
    imageCell.appendChild(images);
    row.appendChild(imageCell);
    var removeCell = document.createElement("td");
    var remove = document.createElement("button");
    remove.type = "button";
    remove.className = "ullme-text-action";
    remove.textContent = "Remove";
    remove.addEventListener("click", function () { row.remove(); });
    removeCell.appendChild(remove);
    row.appendChild(removeCell);
    return row;
  }

  function collectDocSpecs(id) {
    var body = byId(id);
    if (!body) return [];
    return Array.prototype.map.call(body.querySelectorAll("tr"), function (row) {
      function fieldValue(name) {
        var input = row.querySelector('[data-field="' + name + '"]');
        return input ? input.value : "";
      }
      var images = row.querySelector('[data-field="add_images"]');
      return {
        docid: fieldValue("docid").trim(),
        fixed_path: fieldValue("fixed_path").trim(),
        descr: fieldValue("descr"),
        file_types: splitList(fieldValue("file_types")),
        pref_doc_dir: fieldValue("pref_doc_dir").trim(),
        add_images: Boolean(images && images.checked)
      };
    }).filter(function (spec) { return spec.docid; });
  }

  function placeholderDocumentsEditor(documents) {
    var section = document.createElement("div");
    var head = document.createElement("div");
    var add = document.createElement("button");
    var table = document.createElement("table");
    var tableHead = document.createElement("thead");
    var headRow = document.createElement("tr");
    var body = document.createElement("tbody");
    section.className = "ullme-tutor-form-section ullme-doc-spec-section";
    head.className = "ullme-doc-spec-head";
    head.appendChild(sectionTitle("Placeholder documents"));
    add.type = "button";
    add.className = "ullme-secondary-action";
    add.textContent = "Add document";
    add.addEventListener("click", function () {
      body.appendChild(placeholderDocumentRow({}));
    });
    head.appendChild(add);
    ["Placeholder", "Material file", ""].forEach(function (label) {
      appendCell(headRow, "th", label);
    });
    tableHead.appendChild(headRow);
    body.id = "ullme_placeholder_documents";
    (Array.isArray(documents) ? documents : []).forEach(function (document) {
      body.appendChild(placeholderDocumentRow(document));
    });
    table.appendChild(tableHead);
    table.appendChild(body);
    var wrap = document.createElement("div");
    wrap.className = "ullme-doc-spec-table-wrap";
    wrap.appendChild(table);
    section.appendChild(head);
    section.appendChild(wrap);
    return section;
  }

  function placeholderDocumentRow(placeholderDocument) {
    var row = document.createElement("tr");
    [
      {
        name: "placeholder",
        value: placeholderDocument.placeholder || "",
        placeholder: "knowledge_start"
      },
      {
        name: "path",
        value: placeholderDocument.path || "",
        placeholder: "knowledge.md"
      }
    ].forEach(function (spec) {
      var cell = document.createElement("td");
      var input = document.createElement("input");
      input.className = "ullme-doc-spec-input";
      input.setAttribute("data-field", spec.name);
      input.value = spec.value;
      input.placeholder = spec.placeholder;
      cell.appendChild(input);
      row.appendChild(cell);
    });
    var removeCell = document.createElement("td");
    var remove = document.createElement("button");
    remove.type = "button";
    remove.className = "ullme-text-action";
    remove.textContent = "Remove";
    remove.addEventListener("click", function () { row.remove(); });
    removeCell.appendChild(remove);
    row.appendChild(removeCell);
    return row;
  }

  function collectPlaceholderDocuments() {
    var body = byId("ullme_placeholder_documents");
    if (!body) return [];
    return Array.prototype.map.call(body.querySelectorAll("tr"), function (row) {
      var placeholder = row.querySelector('[data-field="placeholder"]');
      var path = row.querySelector('[data-field="path"]');
      return {
        placeholder: placeholder ? placeholder.value.trim() : "",
        path: path ? path.value.trim() : ""
      };
    }).filter(function (document) {
      return document.placeholder;
    });
  }

  function filePermissionsEditor(permissions) {
    var section = document.createElement("div");
    var head = document.createElement("div");
    var add = document.createElement("button");
    var table = document.createElement("table");
    var tableHead = document.createElement("thead");
    var headRow = document.createElement("tr");
    var body = document.createElement("tbody");
    section.className = "ullme-tutor-form-section ullme-doc-spec-section";
    head.className = "ullme-doc-spec-head";
    head.appendChild(sectionTitle("Tutor file permissions"));
    add.type = "button";
    add.className = "ullme-secondary-action";
    add.textContent = "Add permission";
    add.addEventListener("click", function () {
      body.appendChild(filePermissionRow({}));
    });
    head.appendChild(add);
    ["Access", "Main path", "Directories", "Recursive", "Extensions", ""]
      .forEach(function (label) { appendCell(headRow, "th", label); });
    tableHead.appendChild(headRow);
    body.id = "ullme_tutor_file_permissions";
    (Array.isArray(permissions) ? permissions : []).forEach(function (permission) {
      body.appendChild(filePermissionRow(permission));
    });
    table.appendChild(tableHead);
    table.appendChild(body);
    var wrap = document.createElement("div");
    wrap.className = "ullme-doc-spec-table-wrap";
    wrap.appendChild(table);
    section.appendChild(head);
    section.appendChild(wrap);
    return section;
  }

  function filePermissionRow(permission) {
    var row = document.createElement("tr");
    var typeCell = document.createElement("td");
    var type = document.createElement("select");
    type.setAttribute("data-field", "type");
    [
      { value: "read_only", label: "Read only" },
      { value: "write_and_read", label: "Write and read" }
    ].forEach(function (item) {
      var option = document.createElement("option");
      option.value = item.value;
      option.textContent = item.label;
      type.appendChild(option);
    });
    type.value = permission.type || "read_only";
    typeCell.appendChild(type);
    row.appendChild(typeCell);
    [
      {
        name: "main_path",
        value: permission.main_path || "materials",
        placeholder: "materials"
      },
      {
        name: "directories",
        value: (permission.directories || []).join(", "),
        placeholder: "scripts, slides"
      }
    ].forEach(function (spec) {
      var cell = document.createElement("td");
      var input = document.createElement("input");
      input.setAttribute("data-field", spec.name);
      input.className = "ullme-doc-spec-input";
      input.value = spec.value;
      input.placeholder = spec.placeholder;
      cell.appendChild(input);
      row.appendChild(cell);
    });
    var recursiveCell = document.createElement("td");
    var recursive = document.createElement("input");
    recursive.type = "checkbox";
    recursive.setAttribute("data-field", "recursive");
    recursive.checked = Boolean(permission.recursive);
    recursiveCell.appendChild(recursive);
    row.appendChild(recursiveCell);
    var extensionCell = document.createElement("td");
    var extensions = document.createElement("input");
    extensions.setAttribute("data-field", "extensions");
    extensions.className = "ullme-doc-spec-input";
    extensions.value = (permission.extensions || []).join(", ");
    extensions.placeholder = "md, tex, txt";
    extensionCell.appendChild(extensions);
    row.appendChild(extensionCell);
    var removeCell = document.createElement("td");
    var remove = document.createElement("button");
    remove.type = "button";
    remove.className = "ullme-text-action";
    remove.textContent = "Remove";
    remove.addEventListener("click", function () { row.remove(); });
    removeCell.appendChild(remove);
    row.appendChild(removeCell);
    return row;
  }

  function collectFilePermissions() {
    var body = byId("ullme_tutor_file_permissions");
    if (!body) return [];
    return Array.prototype.map.call(body.querySelectorAll("tr"), function (row) {
      function value(name) {
        var input = row.querySelector('[data-field="' + name + '"]');
        return input ? input.value : "";
      }
      var recursive = row.querySelector('[data-field="recursive"]');
      return {
        type: value("type"),
        main_path: value("main_path").trim(),
        directories: splitList(value("directories")),
        recursive: Boolean(recursive && recursive.checked),
        extensions: splitList(value("extensions"))
      };
    });
  }

  function yamlEditor(tutor) {
    var panel = document.createElement("section");
    var tabs = document.createElement("nav");
    var note = document.createElement("div");
    var editor = document.createElement("textarea");
    var actions = document.createElement("div");
    var save = document.createElement("button");
    panel.className = "ullme-tutor-tab-panel ullme-tutor-yaml-panel";
    tabs.className = "ullme-tutor-yaml-tabs";
    var yamlTabs = [{ id: "definition", label: "Definition" }];
    if (tutor.multiple_instances !== false) {
      yamlTabs.push({ id: "instances", label: "Instances" });
    }
    yamlTabs.forEach(function (tab) {
      var button = document.createElement("button");
      button.type = "button";
      button.className = "ullme-tutor-yaml-tab";
      if (state.yamlTab === tab.id) {
        button.classList.add("ullme-tutor-yaml-tab-active");
      }
      button.textContent = tab.label;
      button.addEventListener("click", function () {
        state.yamlTab = tab.id;
        renderTutorDetail();
      });
      tabs.appendChild(button);
    });
    note.className = "ullme-tutor-yaml-note";
    note.textContent = state.yamlTab === "definition"
      ? "This is the course-local definition used by the Tutor."
      : "These are the course-local document assignments for Tutor instances.";
    editor.id = state.yamlTab === "definition"
      ? "ullme_tutor_yaml"
      : "ullme_tutor_instances_yaml";
    editor.className = "ullme-tutor-yaml-editor";
    editor.spellcheck = false;
    editor.value = state.yamlTab === "definition"
      ? (tutor.yaml_content || "")
      : (tutor.instances_yaml_content || "course_docs: {}\ninstances: []");
    actions.className = "ullme-tutor-form-actions";
    save.type = "button";
    save.className = "ullme-primary-action ullme-tutor-save-button";
    save.textContent = state.yamlTab === "definition"
      ? "Save definition YAML"
      : "Save instance YAML";
    save.addEventListener("click", function () {
      save.disabled = true;
      if (state.yamlTab === "definition") {
        sendEvent("ullme_ai_tutor_save_event", {
          tutorid: tutor.tutorid,
          mode: "yaml",
          yaml_content: editor.value
        });
      } else {
        sendEvent("ullme_ai_tutor_instances_yaml_save_event", {
          tutorid: tutor.tutorid,
          yaml_content: editor.value
        });
      }
    });
    if (state.yamlTab === "instances") {
      actions.appendChild(conversionMenu(tutor));
    }
    actions.appendChild(save);
    panel.appendChild(tabs);
    panel.appendChild(note);
    panel.appendChild(editor);
    panel.appendChild(actions);
    return panel;
  }

  function conversionMenu(tutor) {
    var details = document.createElement("details");
    var summary = document.createElement("summary");
    var menu = document.createElement("div");
    var files = document.createElement("select");
    var from = document.createElement("select");
    var to = document.createElement("select");
    var overwrite = document.createElement("label");
    var overwriteInput = document.createElement("input");
    var convert = document.createElement("button");
    details.className = "ullme-conversion-menu";
    summary.textContent = "Convert file type";
    menu.className = "ullme-conversion-menu-body";
    files.multiple = true;
    files.className = "ullme-conversion-files";
    files.setAttribute("aria-label", "Documents to convert");
    (tutor.conversion_files || []).forEach(function (path) {
      var option = document.createElement("option");
      option.value = path;
      option.textContent = path;
      files.appendChild(option);
    });
    appendFormatOption(from, "", "From: automatic");
    (tutor.conversion_input_formats || []).forEach(function (format) {
      appendFormatOption(from, format, "From: " + format);
    });
    appendFormatOption(to, "preferred", "To: preferred by definition");
    (tutor.conversion_output_formats || []).forEach(function (format) {
      appendFormatOption(to, format, "To: " + format);
    });
    overwriteInput.type = "checkbox";
    overwrite.appendChild(overwriteInput);
    overwrite.appendChild(document.createTextNode(" Replace existing"));
    convert.type = "button";
    convert.className = "ullme-secondary-action ullme-tutor-convert-button";
    convert.textContent = "Convert selected";
    convert.addEventListener("click", function () {
      var paths = Array.prototype.map.call(
        files.selectedOptions || [],
        function (option) { return option.value; }
      );
      if (!paths.length) {
        window.alert("Select at least one document to convert.");
        return;
      }
      convert.disabled = true;
      sendEvent("ullme_ai_tutor_convert_event", {
        tutorid: tutor.tutorid,
        paths: paths,
        from: from.value,
        to: to.value,
        overwrite: overwriteInput.checked
      });
    });
    [files, from, to, overwrite, convert].forEach(function (item) {
      menu.appendChild(item);
    });
    details.appendChild(summary);
    details.appendChild(menu);
    return details;
  }

  function appendFormatOption(select, value, text) {
    var option = document.createElement("option");
    option.value = value;
    option.textContent = text;
    select.appendChild(option);
  }

  function splitList(value) {
    return String(value || "")
      .split(",")
      .map(function (item) { return item.trim(); })
      .filter(Boolean);
  }

  function field(labelText, id, type, value, helpText) {
    var label = document.createElement("label");
    var title = document.createElement("span");
    var input = type === "textarea"
      ? document.createElement("textarea")
      : document.createElement("input");
    label.className = "ullme-tutor-field";
    title.textContent = labelText;
    input.id = id;
    if (type !== "textarea") input.type = type;
    input.value = value || "";
    label.appendChild(title);
    label.appendChild(input);
    if (helpText) {
      var help = document.createElement("small");
      help.textContent = helpText;
      label.appendChild(help);
    }
    return label;
  }

  function checkboxField(labelText, id, checked, helpText) {
    var label = document.createElement("label");
    var line = document.createElement("span");
    var input = document.createElement("input");
    var text = document.createElement("span");
    label.className = "ullme-tutor-field";
    line.className = "ullme-tutor-checkbox-line";
    input.id = id;
    input.type = "checkbox";
    input.checked = Boolean(checked);
    text.textContent = labelText;
    line.appendChild(input);
    line.appendChild(text);
    label.appendChild(line);
    if (helpText) {
      var help = document.createElement("small");
      help.textContent = helpText;
      label.appendChild(help);
    }
    return label;
  }

  function sectionTitle(text) {
    var title = document.createElement("h3");
    title.textContent = text;
    return title;
  }

  function valueOf(id) {
    var element = byId(id);
    return element ? element.value : "";
  }

  function checkedOf(id) {
    var element = byId(id);
    return Boolean(element && element.checked);
  }

  function appendCell(row, kind, text) {
    var cell = document.createElement(kind);
    cell.textContent = text;
    row.appendChild(cell);
  }

  function humanize(value) {
    return String(value || "")
      .replace(/[_-]+/g, " ")
      .replace(/\b\w/g, function (letter) { return letter.toUpperCase(); });
  }

  function emptyState(titleText, descriptionText) {
    var empty = document.createElement("div");
    var title = document.createElement("strong");
    var description = document.createElement("span");
    empty.className = "ullme-feature-empty";
    title.textContent = titleText;
    description.textContent = descriptionText;
    empty.appendChild(title);
    empty.appendChild(description);
    return empty;
  }

  function saveComplete(result) {
    Array.prototype.forEach.call(
      document.querySelectorAll(
        ".ullme-tutor-save-button, .ullme-tutor-convert-button"
      ),
      function (button) { button.disabled = false; }
    );
    var coordinator = state.instanceAutoSave;
    if (result && result.kind === "instances" && coordinator) {
      coordinator.saving = false;
      if (result.ok === false) {
        coordinator.lastSubmitted = "";
        coordinator.status.textContent = "Could not save automatically";
        window.alert(result.message || "The Tutor instances could not be saved.");
        return;
      }
      coordinator.status.textContent = "Saved";
      if (!coordinator.panel.isConnected) {
        state.instanceAutoSave = null;
        renderTutorDetail();
        return;
      }
      if (coordinator.panel.contains(document.activeElement)) {
        coordinator.pending = false;
        return;
      }
      coordinator.pending = false;
      if (instanceAssignmentSnapshot(coordinator) !== coordinator.lastSubmitted) {
        submitInstanceAutosave(coordinator);
        return;
      }
      state.instanceAutoSave = null;
      renderTutorDetail();
      return;
    }
    if (!result || result.ok === false) {
      window.alert((result && result.message) || "The AI Tutor could not be saved.");
      return;
    }
    if (window.ullmeTutorValidation && window.ullmeTutorValidation.reportSave) {
      window.ullmeTutorValidation.reportSave(result.validation);
    }
  }

  function deleteComplete(result) {
    if (!result || result.ok === false) {
      renderTutorDetail();
      window.alert((result && result.message) || "The AI Tutor could not be deleted.");
    }
  }

  function historyComplete(result) {
    if (!result || result.ok === false) {
      renderTutorDetail();
      window.alert((result && result.message) || "The change could not be applied.");
    }
  }

  window.ullmeTutors = {
    update: update
  };
  window.ullme = window.ullme || {};
  window.ullme.aiTutorSaveComplete = saveComplete;
  window.ullme.aiTutorInstancesSaveComplete = saveComplete;
  window.ullme.aiTutorConversionComplete = saveComplete;
  window.ullme.aiTutorDeleteComplete = deleteComplete;
  window.ullme.editHistoryComplete = historyComplete;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
