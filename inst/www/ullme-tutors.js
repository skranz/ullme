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
    if (state.activeTab === "definition") {
      container.appendChild(definitionForm(tutor));
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
      { id: "definition", label: "Definition" },
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
    var matcher = normalizeMatcher(tutor.file_matcher);
    panel.className = "ullme-tutor-tab-panel";
    if (matcher) panel.appendChild(matcherSummary(matcher));

    var instances = Array.isArray(tutor.instances) ? tutor.instances : [];
    if (!instances.length) {
      panel.appendChild(emptyState(
        "No instances found",
        matcher
          ? "No course files currently match this Tutor's file patterns."
          : "This Tutor has no file matcher or explicit instance files."
      ));
      return panel;
    }

    var roles = Array.isArray(tutor.required_material_roles)
      ? tutor.required_material_roles.slice()
      : [];
    instances.forEach(function (instance) {
      Object.keys(instance.materials || {}).forEach(function (role) {
        if (roles.indexOf(role) < 0) roles.push(role);
      });
    });
    var wrap = document.createElement("div");
    var table = document.createElement("table");
    var head = document.createElement("thead");
    var headRow = document.createElement("tr");
    var body = document.createElement("tbody");
    appendCell(headRow, "th", "Instance");
    roles.forEach(function (role) {
      appendCell(headRow, "th", humanize(role));
    });
    head.appendChild(headRow);

    instances.forEach(function (instance) {
      var row = document.createElement("tr");
      appendCell(row, "td", instance.instanceid || "Instance");
      roles.forEach(function (role) {
        var cell = document.createElement("td");
        var paths = instance.materials && instance.materials[role];
        paths = Array.isArray(paths) ? paths : (paths ? [paths] : []);
        if (!paths.length) {
          var missing = document.createElement("span");
          missing.className = "ullme-instance-missing";
          missing.textContent = "Missing";
          cell.appendChild(missing);
        } else {
          paths.forEach(function (path) {
            var file = document.createElement("code");
            file.textContent = path;
            cell.appendChild(file);
          });
        }
        row.appendChild(cell);
      });
      body.appendChild(row);
    });
    table.appendChild(head);
    table.appendChild(body);
    wrap.className = "ullme-instance-table-wrap";
    wrap.appendChild(table);
    panel.appendChild(wrap);
    return panel;
  }

  function matcherSummary(matcher) {
    var card = document.createElement("div");
    var title = document.createElement("strong");
    var text = document.createElement("span");
    card.className = "ullme-matcher-summary";
    title.textContent = "Instances generated from file patterns";
    text.textContent = "Scan " + (matcher.directory || "materials") +
      " with " + (matcher.primary_pattern || "the configured pattern") +
      ". Edit matching rules in Definition.";
    card.appendChild(title);
    card.appendChild(text);
    return card;
  }

  function definitionForm(tutor) {
    var form = document.createElement("section");
    var basics = document.createElement("div");
    var teaching = document.createElement("div");
    var matcher = normalizeMatcher(tutor.file_matcher);
    var actions = document.createElement("div");
    var save = document.createElement("button");

    form.className = "ullme-tutor-tab-panel ullme-tutor-definition-form";
    basics.className = "ullme-tutor-form-section";
    basics.appendChild(sectionTitle("Basics"));
    basics.appendChild(field("Label", "ullme_tutor_label", "input", tutor.label || ""));
    basics.appendChild(field(
      "Description",
      "ullme_tutor_description",
      "textarea",
      tutor.description || ""
    ));
    basics.appendChild(field(
      "Required material roles",
      "ullme_tutor_roles",
      "input",
      (tutor.required_material_roles || []).join(", "),
      "Comma-separated, for example problem_set, solution"
    ));
    teaching.className = "ullme-tutor-form-section";
    teaching.appendChild(sectionTitle("Teaching behavior"));
    teaching.appendChild(field(
      "Pedagogical instructions",
      "ullme_tutor_instructions",
      "textarea",
      tutor.pedagogical_instructions || ""
    ));
    teaching.appendChild(field(
      "Allowed tools",
      "ullme_tutor_tools",
      "input",
      (tutor.allowed_tools || []).join(", "),
      "Comma-separated tool IDs"
    ));
    teaching.appendChild(field(
      "Student customization",
      "ullme_tutor_customization",
      "input",
      (tutor.student_customization || []).join(", "),
      "Comma-separated customization fields"
    ));
    form.appendChild(basics);
    form.appendChild(teaching);
    if (matcher) form.appendChild(matcherForm(matcher));

    actions.className = "ullme-tutor-form-actions";
    save.type = "button";
    save.className = "ullme-primary-action ullme-tutor-save-button";
    save.textContent = "Save definition";
    save.addEventListener("click", function () {
      save.disabled = true;
      sendEvent("ullme_ai_tutor_save_event", {
        tutorid: tutor.tutorid,
        mode: "ui",
        fields: {
          label: valueOf("ullme_tutor_label"),
          description: valueOf("ullme_tutor_description"),
          pedagogical_instructions: valueOf("ullme_tutor_instructions"),
          required_material_roles: valueOf("ullme_tutor_roles")
            .split(",")
            .map(function (role) { return role.trim(); })
            .filter(Boolean),
          allowed_tools: valueOf("ullme_tutor_tools")
            .split(",")
            .map(function (tool) { return tool.trim(); })
            .filter(Boolean),
          student_customization: valueOf("ullme_tutor_customization")
            .split(",")
            .map(function (fieldName) { return fieldName.trim(); })
            .filter(Boolean)
        },
        matcher: matcher ? {
          directory: valueOf("ullme_matcher_directory"),
          primary_role: valueOf("ullme_matcher_primary_role"),
          primary_pattern: valueOf("ullme_matcher_primary_pattern"),
          exclude_pattern: valueOf("ullme_matcher_exclude_pattern"),
          id_group: Number(valueOf("ullme_matcher_id_group") || 1),
          solution_pattern: valueOf("ullme_matcher_solution_pattern")
        } : null
      });
    });
    actions.appendChild(save);
    form.appendChild(actions);
    return form;
  }

  function matcherForm(matcher) {
    var section = document.createElement("div");
    section.className = "ullme-tutor-form-section";
    section.appendChild(sectionTitle("Instance matching"));
    var intro = document.createElement("p");
    intro.className = "ullme-tutor-form-help";
    intro.textContent = "This section is shown because instance_generation.file_matcher is present in the Tutor YAML.";
    section.appendChild(intro);
    var grid = document.createElement("div");
    grid.className = "ullme-matcher-grid";
    grid.appendChild(field("Material directory", "ullme_matcher_directory", "input", matcher.directory || ""));
    grid.appendChild(field("Primary role", "ullme_matcher_primary_role", "input", matcher.primary_role || "primary"));
    grid.appendChild(field("Primary file pattern", "ullme_matcher_primary_pattern", "input", matcher.primary_pattern || ""));
    grid.appendChild(field("Exclude pattern", "ullme_matcher_exclude_pattern", "input", matcher.exclude_pattern || ""));
    grid.appendChild(field("ID capture group", "ullme_matcher_id_group", "number", String(matcher.id_group || 1)));
    grid.appendChild(field(
      "Solution pattern",
      "ullme_matcher_solution_pattern",
      "input",
      solutionPattern(matcher),
      "Use {{id}} where the captured instance ID belongs."
    ));
    section.appendChild(grid);
    return section;
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

  function normalizeMatcher(matcher) {
    return matcher && typeof matcher === "object" ? matcher : null;
  }

  function solutionPattern(matcher) {
    var associated = matcher.associated || {};
    var solution = associated.solution || {};
    return typeof solution === "string" ? solution : (solution.pattern || "");
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

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
