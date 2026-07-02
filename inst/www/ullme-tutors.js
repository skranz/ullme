(function () {
  var state = {
    tutors: [],
    templates: [],
    courseSkills: [],
    activeSkill: null,
    selectedTutorId: "",
    activeTab: "instances",
    tutorPaneActive: false,
    initialized: false
  };

  var tutorIcon = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"></circle><path d="M5 21a7 7 0 0 1 14 0"></path><path d="M18 4l2-2M19 8h3"></path></svg>';
  var skillIcon = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3l1.4 4.1L17.5 8.5l-4.1 1.4L12 14l-1.4-4.1-4.1-1.4 4.1-1.4L12 3z"></path><path d="M18.5 14l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8.8-2.2z"></path></svg>';

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
        var skillButton = event.target.closest("[data-skill-id]");
        if (tutorButton && nav.contains(tutorButton)) {
          state.tutorPaneActive = true;
          selectTutor(tutorButton.getAttribute("data-tutor-id"));
          return;
        }
        if (skillButton && nav.contains(skillButton)) {
          sendEvent("ullme_skill_activate_event", {
            skillid: skillButton.getAttribute("data-skill-id")
          });
          return;
        }
        var viewButton = event.target.closest("[data-studio-view]");
        if (viewButton && nav.contains(viewButton)) {
          state.tutorPaneActive = false;
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
        if (window.ullme && window.ullme.openCatalogDialog) {
          window.ullme.openCatalogDialog(item.getAttribute("data-add-kind"));
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

  function update(tutors, templates, activeSkill, courseSkills) {
    state.tutors = Array.isArray(tutors) ? tutors : [];
    state.templates = Array.isArray(templates) ? templates : [];
    if (arguments.length > 2) state.activeSkill = activeSkill || null;
    if (arguments.length > 3) {
      state.courseSkills = Array.isArray(courseSkills) ? courseSkills : [];
    }
    if (!state.tutors.some(function (tutor) {
      return tutor.tutorid === state.selectedTutorId;
    })) {
      state.selectedTutorId = state.tutors.length ? state.tutors[0].tutorid : "";
    }
    render();
  }

  function updateSkill(skill) {
    state.activeSkill = skill || null;
    renderSkillNavigation();
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
    renderSkillNavigation();
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

  function renderSkillNavigation() {
    var container = byId("ullme_skill_nav_items");
    if (!container) return;
    container.innerHTML = "";
    state.courseSkills.forEach(function (skill) {
      var button = document.createElement("button");
      var label = document.createElement("span");
      var active = state.activeSkill &&
        state.activeSkill.skillid === skill.skillid;
      button.type = "button";
      button.className = "ullme-studio-nav-item ullme-dynamic-nav-item ullme-skill-nav-item";
      if (active) button.classList.add("ullme-skill-nav-item-active");
      button.setAttribute("data-skill-id", skill.skillid || "");
      button.title = skill.label || skill.skillid || "Skill";
      button.innerHTML = skillIcon;
      label.textContent = skill.label || skill.skillid || "Skill";
      button.appendChild(label);
      container.appendChild(button);
    });
  }

  function renderTutorDetail() {
    var container = byId("ullme_ai_tutor_detail");
    if (!container) return;
    container.innerHTML = "";
    var tutor = selectedTutor();
    if (!tutor) {
      container.appendChild(emptyState(
        "No AI Tutor selected",
        "Use Add to create an editable course copy."
      ));
      return;
    }

    container.appendChild(tutorHeader(tutor));
    container.appendChild(tutorTabs(tutor));
    if (state.activeTab === "prompt") {
      container.appendChild(promptForm(tutor));
    } else if (state.activeTab === "config") {
      container.appendChild(configForm(tutor));
    } else if (state.activeTab === "yaml") {
      container.appendChild(yamlEditor(tutor));
    } else {
      container.appendChild(instancePanel(tutor));
    }
  }

  function tutorHeader(tutor) {
    var header = document.createElement("header");
    var identity = document.createElement("div");
    var select = document.createElement("select");
    var description = document.createElement("div");
    var actions = document.createElement("div");
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
    description.className = "ullme-tutor-detail-description";
    description.textContent = tutor.description || "No description";
    identity.appendChild(select);
    identity.appendChild(description);

    actions.className = "ullme-tutor-detail-actions";
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
    actions.appendChild(toggleLabel);
    header.appendChild(identity);
    header.appendChild(actions);
    return header;
  }

  function tutorTabs(tutor) {
    var tabs = document.createElement("nav");
    tabs.className = "ullme-tutor-tabs";
    [
      { id: "instances", label: "Instances (" + Number(tutor.instance_count || 0) + ")" },
      { id: "prompt", label: "Prompt" },
      { id: "config", label: "Config" },
      { id: "yaml", label: "YAML" }
    ].forEach(function (tab) {
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
        "<span>Review these document assignments, then save them.</span>";
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
    appendCell(headRow, "th", "Instance");
    roles.forEach(function (role) {
      appendCell(headRow, "th", humanize(role));
    });
    appendCell(headRow, "th", "");
    head.appendChild(headRow);
    instances.forEach(function (instance) {
      body.appendChild(instanceEditorRow(instance, roles));
    });
    table.appendChild(head);
    table.appendChild(body);
    wrap.className = "ullme-instance-table-wrap";
    wrap.appendChild(table);
    panel.appendChild(wrap);

    var actions = document.createElement("div");
    var suggest = document.createElement("button");
    var add = document.createElement("button");
    var save = document.createElement("button");
    actions.className = "ullme-tutor-form-actions ullme-instance-actions";
    suggest.type = "button";
    suggest.className = "ullme-secondary-action";
    suggest.textContent = "Suggest from course files";
    suggest.addEventListener("click", function () {
      body.innerHTML = "";
      (Array.isArray(tutor.suggested_instances) ? tutor.suggested_instances : [])
        .forEach(function (instance) {
          body.appendChild(instanceEditorRow(instance, roles));
        });
    });
    add.type = "button";
    add.className = "ullme-secondary-action";
    add.textContent = "Add instance";
    add.addEventListener("click", function () {
      body.appendChild(instanceEditorRow({ instanceid: "", docs: {} }, roles));
    });
    save.type = "button";
    save.className = "ullme-primary-action ullme-tutor-save-button";
    save.textContent = "Save assignments";
    save.addEventListener("click", function () {
      save.disabled = true;
      sendEvent("ullme_ai_tutor_instances_save_event", {
        tutorid: tutor.tutorid,
        instances: collectInstanceRows(roles),
        course_docs: collectCourseDocs(courseRoles)
      });
    });
    actions.appendChild(suggest);
    actions.appendChild(add);
    actions.appendChild(save);
    panel.appendChild(actions);
    if (!instances.length) {
      panel.insertBefore(emptyState(
        "No instances found",
        "Add an instance manually. Document suggestions appear automatically when matching course files are found."
      ), wrap);
    }
    return panel;
  }

  function instanceEditorRow(instance, roles) {
    var row = document.createElement("tr");
    var idCell = document.createElement("td");
    var idInput = document.createElement("input");
    var removeCell = document.createElement("td");
    var remove = document.createElement("button");
    row.className = "ullme-instance-editor-row";
    idInput.className = "ullme-instance-input ullme-instance-id";
    idInput.value = instance.instanceid || "";
    idInput.placeholder = "ps1";
    idCell.appendChild(idInput);
    row.appendChild(idCell);
    roles.forEach(function (role) {
      var cell = document.createElement("td");
      var input = document.createElement("input");
      var paths = instance.docs && instance.docs[role];
      input.className = "ullme-instance-input ullme-instance-docs";
      input.setAttribute("data-docid", role);
      input.value = (Array.isArray(paths) ? paths : (paths ? [paths] : [])).join(", ");
      input.placeholder = "Relative material path";
      cell.appendChild(input);
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
      grid.appendChild(field(
        humanize(role),
        id + "_" + role,
        "input",
        (Array.isArray(paths) ? paths : (paths ? [paths] : [])).join(", "),
        "Comma-separated relative material paths"
      ));
    });
    section.appendChild(title);
    section.appendChild(grid);
    return section;
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
    form.appendChild(documentSpecsEditor(
      "Documents per instance",
      "ullme_docs_per_instance",
      tutor.docs_per_instance || []
    ));
    form.appendChild(documentSpecsEditor(
      "Documents per course",
      "ullme_docs_per_course",
      tutor.docs_per_course || []
    ));

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
          default_personality: valueOf("ullme_tutor_default_personality"),
          allowed_tools: splitList(valueOf("ullme_tutor_tools")),
          allowed_student_customization: splitList(valueOf("ullme_tutor_customization")),
          docs_per_instance: collectDocSpecs("ullme_docs_per_instance"),
          docs_per_course: collectDocSpecs("ullme_docs_per_course")
        }
      });
    });
    actions.appendChild(save);
    form.appendChild(actions);
    return form;
  }

  function documentSpecsEditor(titleText, id, specs) {
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
      body.appendChild(docSpecRow({}));
    });
    head.appendChild(title);
    head.appendChild(add);
    ["ID", "Description", "Preferred formats", "Convert", "Directory", "Images", ""]
      .forEach(function (label) { appendCell(headRow, "th", label); });
    tableHead.appendChild(headRow);
    body.id = id;
    (Array.isArray(specs) ? specs : []).forEach(function (spec) {
      body.appendChild(docSpecRow(spec));
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

  function docSpecRow(spec) {
    var row = document.createElement("tr");
    [
      { name: "docid", value: spec.docid || "", placeholder: "ps" },
      { name: "descr", value: spec.descr || "", placeholder: "Problem set" },
      { name: "pref_format", value: (spec.pref_format || []).join(", "), placeholder: "md, tex, pdf" },
      { name: "auto_convert", value: (spec.auto_convert || []).join(", "), placeholder: "pdf" },
      { name: "pref_doc_dir", value: spec.pref_doc_dir || "", placeholder: "ps" }
    ].forEach(function (fieldSpec) {
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
        descr: fieldValue("descr"),
        pref_format: splitList(fieldValue("pref_format")),
        auto_convert: splitList(fieldValue("auto_convert")),
        pref_doc_dir: fieldValue("pref_doc_dir").trim(),
        add_images: Boolean(images && images.checked)
      };
    }).filter(function (spec) { return spec.docid; });
  }

  function yamlEditor(tutor) {
    var panel = document.createElement("section");
    var note = document.createElement("div");
    var editor = document.createElement("textarea");
    var actions = document.createElement("div");
    var save = document.createElement("button");
    panel.className = "ullme-tutor-tab-panel ullme-tutor-yaml-panel";
    note.className = "ullme-tutor-yaml-note";
    note.textContent = "This is the course-local definition used by the Tutor.";
    editor.id = "ullme_tutor_yaml";
    editor.className = "ullme-tutor-yaml-editor";
    editor.spellcheck = false;
    editor.value = tutor.yaml_content || "";
    actions.className = "ullme-tutor-form-actions";
    save.type = "button";
    save.className = "ullme-primary-action ullme-tutor-save-button";
    save.textContent = "Save YAML";
    save.addEventListener("click", function () {
      save.disabled = true;
      sendEvent("ullme_ai_tutor_save_event", {
        tutorid: tutor.tutorid,
        mode: "yaml",
        yaml_content: editor.value
      });
    });
    actions.appendChild(save);
    panel.appendChild(note);
    panel.appendChild(editor);
    panel.appendChild(actions);
    return panel;
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

  function sectionTitle(text) {
    var title = document.createElement("h3");
    title.textContent = text;
    return title;
  }

  function valueOf(id) {
    var element = byId(id);
    return element ? element.value : "";
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
      document.querySelectorAll(".ullme-tutor-save-button"),
      function (button) { button.disabled = false; }
    );
    if (!result || result.ok === false) {
      window.alert((result && result.message) || "The AI Tutor could not be saved.");
    }
  }

  window.ullmeTutors = {
    update: update,
    updateSkill: updateSkill
  };
  window.ullme = window.ullme || {};
  window.ullme.aiTutorSaveComplete = saveComplete;
  window.ullme.aiTutorInstancesSaveComplete = saveComplete;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
