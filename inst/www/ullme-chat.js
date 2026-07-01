(function () {
  var state = {
    uploads: [],
    messageIndex: 0,
    isRecording: false,
    assistantRequests: {},
    pendingMaterialInputId: "",
    aiTutors: [],
    aiTutorCatalog: [],
    skills: [],
    activeSkill: null,
    definitionWorkspace: null,
    definitionOriginalContent: "",
    definitionAssistantOpen: false,
    definitionAssistantMessages: {},
    definitionAssistantRequestIndex: 0
  };

  var materialLabels = {
    general: "General",
    slides: "Slides",
    ps: "Problem Sets",
    quiz: "Quiz",
    background: "Background"
  };

  var icons = {
    copy: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="8" y="8" width="11" height="11" rx="2"></rect><path d="M5 15V5h10"></path></svg>',
    check: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 6L9 17l-5-5"></path></svg>',
    retry: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 12a8 8 0 1 1-2.35-5.65"></path><path d="M20 4v6h-6"></path></svg>',
    more: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 12h.01"></path><path d="M12 12h.01"></path><path d="M18 12h.01"></path></svg>',
    close: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M18 6L6 18"></path><path d="M6 6l12 12"></path></svg>'
  };

  function byId(id) {
    return document.getElementById(id);
  }

  function nextId(prefix) {
    state.messageIndex = state.messageIndex + 1;
    return prefix + "_" + Date.now() + "_" + state.messageIndex;
  }

  function init() {
    var messages = byId("ullme_chat_messages");
    var input = byId("ullme_chat_input");
    var submitButton = byId("ullme_submit_btn");
    var uploadButton = byId("ullme_upload_btn");
    var fileInput = byId("ullme_image_upload");
    var voiceButton = byId("ullme_voice_btn");
    var roleSelect = byId("ullme_role_select");
    var semesterSelect = byId("ullme_semester_select");
    var courseSelect = byId("ullme_course_select");
    var addCourseButton = byId("ullme_add_course_btn");
    var courseTabs = byId("ullme_course_tabs");
    var settingsSave = byId("ullme_course_settings_save");
    var materialCategories = byId("ullme_material_categories");
    var materialUploadButton = byId("ullme_material_upload_btn");
    var materialDropzone = byId("ullme_material_dropzone");
    var userSettingsButton = byId("ullme_user_settings_btn");
    var userSettings = byId("ullme_user_settings");
    var addTutorButton = byId("ullme_ai_tutor_add_btn");
    var skillsButton = byId("ullme_skills_btn");
    var manageTutorsButton = byId("ullme_manage_tutors_btn");
    var manageSkillsButton = byId("ullme_manage_skills_btn");

    if (!messages || !input || !submitButton) return;

    mountIntro(messages);
    resizeInput(input);
    updateSubmitState();

    input.addEventListener("input", function () {
      resizeInput(input);
      updateSubmitState();
    });

    input.addEventListener("keydown", function (event) {
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        submitChat();
      }
    });

    submitButton.addEventListener("click", submitChat);

    if (uploadButton && fileInput) {
      uploadButton.addEventListener("click", function () {
        fileInput.click();
      });
      fileInput.addEventListener("change", function () {
        addLocalUploads(Array.prototype.slice.call(fileInput.files || []));
        updateSubmitState();
      });
    }

    document.addEventListener("paste", handlePaste);

    if (voiceButton) {
      voiceButton.addEventListener("click", function () {
        if (window.ullmeAudio && window.ullmeAudio.startRecording) {
          window.ullmeAudio.startRecording();
        }
      });
    }

    if (roleSelect) {
      roleSelect.addEventListener("click", function (event) {
        event.stopPropagation();
        closeUserSettings();
        toggleSidebarMenu(roleSelect, function (role) {
          setRoleLayout(role);
          sendSidebarEvent("ullme_role_select_event", { role: role });
        });
      });
    }

    if (semesterSelect) {
      semesterSelect.addEventListener("click", function (event) {
        event.stopPropagation();
        closeUserSettings();
        toggleSidebarMenu(semesterSelect, function (semester) {
          sendSidebarEvent("ullme_semester_select_event", { semester: semester });
        });
      });
    }

    if (courseSelect) {
      courseSelect.addEventListener("click", function (event) {
        event.stopPropagation();
        closeUserSettings();
        toggleSidebarMenu(courseSelect, function (courseid) {
          sendSidebarEvent("ullme_course_select_event", { courseid: courseid });
        });
      });
    }

    if (userSettingsButton && userSettings) {
      userSettingsButton.addEventListener("click", function (event) {
        event.stopPropagation();
        closeSidebarMenus();
        userSettings.classList.toggle("ullme-user-settings-open");
      });
      userSettings.addEventListener("click", function (event) {
        event.stopPropagation();
      });
    }

    document.addEventListener("click", function () {
      closeSidebarMenus();
      closeUserSettings();
    });
    document.addEventListener("keydown", function (event) {
      if (event.key !== "Escape") return;
      closeSidebarMenus();
      closeUserSettings();
      if (byId("ullme_definition_import_preview")) {
        closeDefinitionImportPreview();
        return;
      }
      if (byId("ullme_definition_create_dialog")) {
        closeCreateDefinitionDialog();
        return;
      }
      if (byId("ullme_definition_overlay")) {
        closeDefinitionWorkspace();
        return;
      }
      closeCatalogDialog();
    });

    if (addCourseButton) {
      addCourseButton.addEventListener("click", function () {
        openAddCourseDialog();
      });
    }

    if (courseTabs) {
      courseTabs.addEventListener("click", function (event) {
        var tab = event.target.closest(".ullme-course-tab");
        if (!tab || !courseTabs.contains(tab)) return;
        showCoursePanel(tab.getAttribute("data-course-panel") || "ai-tutors");
      });
    }

    if (addTutorButton) {
      addTutorButton.addEventListener("click", function () {
        openCatalogDialog("tutors");
      });
    }

    if (skillsButton) {
      skillsButton.addEventListener("click", function () {
        openCatalogDialog("skills");
      });
    }

    if (manageTutorsButton) {
      manageTutorsButton.addEventListener("click", function () {
        closeUserSettings();
        requestDefinitionWorkspace("tutor");
      });
    }

    if (manageSkillsButton) {
      manageSkillsButton.addEventListener("click", function () {
        closeUserSettings();
        requestDefinitionWorkspace("skill");
      });
    }

    if (settingsSave) {
      settingsSave.addEventListener("click", function () {
        sendSidebarEvent("ullme_course_settings_save_event", gatherCourseSettings());
      });
    }

    if (materialCategories) {
      materialCategories.addEventListener("click", function (event) {
        var item = event.target.closest(".ullme-material-category");
        if (!item || !materialCategories.contains(item)) return;
        selectMaterialCategory(item.getAttribute("data-category") || "general");
      });
    }

    if (materialUploadButton) {
      materialUploadButton.addEventListener("click", function () {
        var materialInput = materialInputForCategory(currentMaterialCategory());
        if (materialInput) materialInput.click();
      });
    }

    Array.prototype.forEach.call(document.querySelectorAll(".ullme-material-file-input"), function (inputElement) {
      inputElement.addEventListener("click", function () {
        inputElement.value = "";
      });
      inputElement.addEventListener("change", function () {
        if (inputElement.files && inputElement.files.length) {
          state.pendingMaterialInputId = inputElement.id;
        }
      });
    });
    bindMaterialDropzone(materialDropzone);
  }

  function mountIntro(messages) {
    var text = messages.getAttribute("data-intro-text") || "";
    var meta = messages.getAttribute("data-intro-meta") || "";
    if (!text) return;
    appendAssistantMessage({
      id: "ullme_intro_message",
      text: text,
      meta: meta
    });
  }

  function resizeInput(input) {
    var composer = input.closest(".ullme-composer");
    var minHeight = parseFloat(window.getComputedStyle(input).minHeight) || 38;
    if (composer) composer.classList.remove("ullme-composer-multiline");

    input.style.height = "auto";
    var multiline = input.value.indexOf("\n") !== -1 || input.scrollHeight > minHeight + 2;
    if (composer) composer.classList.toggle("ullme-composer-multiline", multiline);

    input.style.height = "auto";
    var nextHeight = Math.max(minHeight, Math.min(input.scrollHeight, 170));
    input.style.height = nextHeight + "px";
  }

  function updateSubmitState() {
    var input = byId("ullme_chat_input");
    var submitButton = byId("ullme_submit_btn");
    if (!input || !submitButton) return;
    submitButton.disabled = input.value.trim().length === 0 && state.uploads.length === 0;
  }

  function submitChat() {
    var input = byId("ullme_chat_input");
    var modelSelect = byId("ullme_model_select");
    if (!input) return;

    var text = input.value.trim();
    var uploads = state.uploads.slice();
    if (!text && uploads.length === 0) return;

    var clientMessageId = nextId("user");
    var assistantMessageId = nextId("assistant");
    var payload = {
      id: "ullme_submit_chat",
      clientMessageId: clientMessageId,
      assistantMessageId: assistantMessageId,
      text: text,
      model: modelSelect ? modelSelect.value : null,
      skillid: state.activeSkill ? state.activeSkill.skillid : null,
      uploads: uploads.map(function (upload) {
        return {
          id: upload.serverId || upload.localId,
          name: upload.name,
          size: upload.size,
          type: upload.type
        };
      }),
      nonce: Math.random()
    };

    appendUserMessage({
      id: clientMessageId,
      text: text,
      uploads: uploads
    });
    appendAssistantMessage({
      id: assistantMessageId,
      text: "Thinking...",
      meta: "Thinking",
      thinking: true
    });

    input.value = "";
    resizeInput(input);
    clearUploads();
    updateSubmitState();
    scrollMessagesToBottom();

    state.assistantRequests[assistantMessageId] = payload;
    sendChatEvent(payload);
  }

  function sendChatEvent(payload) {
    if (window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue("ullme_submit_chat_event", payload, { priority: "event" });
      return;
    }
    if (window.Shiny && Shiny.onInputChange) {
      Shiny.onInputChange("ullme_submit_chat_event", payload);
      return;
    }
    window.setTimeout(function () {
      receiveAssistantMessage(payload.assistantMessageId, "Fake AI answer to:\n" + payload.text);
    }, 450);
  }

  function sendSidebarEvent(inputId, payload) {
    payload = payload || {};
    payload.nonce = Math.random();
    if (window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue(inputId, payload, { priority: "event" });
      return;
    }
    if (window.Shiny && Shiny.onInputChange) {
      Shiny.onInputChange(inputId, payload);
    }
  }

  function showCoursePanel(panelName) {
    var tabs = byId("ullme_course_tabs");
    var uploadButton = byId("ullme_material_upload_btn");
    if (tabs) {
      Array.prototype.forEach.call(tabs.querySelectorAll(".ullme-course-tab"), function (tab) {
        tab.classList.toggle(
          "ullme-course-tab-active",
          tab.getAttribute("data-course-panel") === panelName
        );
      });
    }
    Array.prototype.forEach.call(document.querySelectorAll(".ullme-course-content-panel"), function (panel) {
      panel.classList.toggle(
        "ullme-course-content-panel-active",
        panel.getAttribute("data-course-panel") === panelName
      );
    });
    if (uploadButton) {
      uploadButton.classList.toggle("ullme-material-tab-upload-visible", panelName === "materials");
    }
  }

  function renderAITutors(tutors) {
    var list = byId("ullme_ai_tutor_list");
    if (!list) return;
    tutors = Array.isArray(tutors) ? tutors : [];
    list.innerHTML = "";

    if (!tutors.length) {
      var empty = document.createElement("div");
      empty.className = "ullme-feature-empty";
      empty.innerHTML = "<strong>No AI Tutors yet</strong><span>Add a tutor definition to make it available in this course.</span>";
      list.appendChild(empty);
      return;
    }

    tutors.forEach(function (tutor) {
      var card = document.createElement("article");
      var head = document.createElement("div");
      var titleWrap = document.createElement("div");
      var title = document.createElement("div");
      var badge = document.createElement("span");
      var description = document.createElement("div");
      var footer = document.createElement("div");
      var instances = document.createElement("span");
      var viewDefinition = document.createElement("button");
      var toggleLabel = document.createElement("label");
      var toggle = document.createElement("input");
      var toggleTrack = document.createElement("span");

      card.className = "ullme-feature-card";
      head.className = "ullme-feature-card-head";
      titleWrap.className = "ullme-feature-card-title-wrap";
      title.className = "ullme-feature-card-title";
      title.textContent = tutor.label || tutor.tutorid;
      badge.className = "ullme-source-badge";
      badge.textContent = sourceLabel(tutor.source);
      description.className = "ullme-feature-card-description";
      description.textContent = tutor.description || "No description";
      footer.className = "ullme-feature-card-footer";
      instances.className = "ullme-feature-card-meta";
      instances.textContent = Number(tutor.instance_count || 0) + " instances";
      viewDefinition.type = "button";
      viewDefinition.className = "ullme-text-action ullme-feature-card-view";
      viewDefinition.textContent = "View definition";
      viewDefinition.disabled = tutor.source === "missing";
      viewDefinition.addEventListener("click", function () {
        requestDefinitionWorkspace("tutor", tutor);
      });
      toggleLabel.className = "ullme-toggle";
      toggleLabel.title = tutor.enabled ? "Disable tutor" : "Enable tutor";
      toggle.type = "checkbox";
      toggle.checked = Boolean(tutor.enabled);
      toggle.setAttribute("aria-label", "Enable " + (tutor.label || tutor.tutorid));
      toggle.addEventListener("change", function () {
        sendSidebarEvent("ullme_ai_tutor_toggle_event", {
          tutorid: tutor.tutorid,
          enabled: toggle.checked
        });
      });
      toggleTrack.className = "ullme-toggle-track";

      titleWrap.appendChild(title);
      titleWrap.appendChild(badge);
      head.appendChild(titleWrap);
      toggleLabel.appendChild(toggle);
      toggleLabel.appendChild(toggleTrack);
      head.appendChild(toggleLabel);
      footer.appendChild(instances);
      appendMaterialRoles(footer, tutor.required_material_roles);
      footer.appendChild(viewDefinition);
      card.appendChild(head);
      card.appendChild(description);
      card.appendChild(footer);
      list.appendChild(card);
    });
  }

  function appendMaterialRoles(parent, roles) {
    roles = Array.isArray(roles) ? roles.filter(Boolean) : [];
    if (!roles.length) return;
    var text = document.createElement("span");
    text.className = "ullme-feature-card-meta";
    text.textContent = "Uses " + roles.join(", ");
    parent.appendChild(text);
  }

  function sourceLabel(source) {
    var labels = {
      course: "Course",
      personal: "Personal",
      general: "General",
      package: "Package",
      missing: "Missing"
    };
    return labels[source] || source || "Definition";
  }

  function openCatalogDialog(kind) {
    closeCatalogDialog();
    var isTutorCatalog = kind === "tutors";
    var items = isTutorCatalog ? state.aiTutorCatalog : state.skills;
    var overlay = document.createElement("div");
    var dialog = document.createElement("section");
    var head = document.createElement("div");
    var heading = document.createElement("div");
    var title = document.createElement("div");
    var subtitle = document.createElement("div");
    var headActions = document.createElement("div");
    var manage = document.createElement("button");
    var close = document.createElement("button");
    var list = document.createElement("div");
    var note = document.createElement("div");

    overlay.id = "ullme_catalog_overlay";
    overlay.className = "ullme-dialog-overlay";
    dialog.className = "ullme-catalog-dialog";
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    dialog.setAttribute("aria-label", isTutorCatalog ? "AI Tutor library" : "Skills");
    head.className = "ullme-catalog-head";
    heading.className = "ullme-catalog-heading";
    title.className = "ullme-catalog-title";
    title.textContent = isTutorCatalog ? "AI Tutor Library" : "Skills";
    subtitle.className = "ullme-catalog-subtitle";
    subtitle.textContent = isTutorCatalog
      ? "Add a resolved tutor definition to this course."
      : "Activate a reusable workflow for your next task.";
    headActions.className = "ullme-catalog-head-actions";
    manage.type = "button";
    manage.className = "ullme-secondary-action";
    manage.textContent = "Manage definitions";
    manage.addEventListener("click", function () {
      closeCatalogDialog();
      requestDefinitionWorkspace(isTutorCatalog ? "tutor" : "skill");
    });
    close.type = "button";
    close.className = "ullme-icon-button";
    close.setAttribute("aria-label", "Close");
    close.innerHTML = icons.close;
    close.addEventListener("click", closeCatalogDialog);
    list.className = "ullme-catalog-list";
    note.className = "ullme-catalog-note";
    note.textContent = isTutorCatalog
      ? "Definitions resolve in this order: course, personal, general, package."
      : "Skills resolve in this order: personal, general, package.";

    heading.appendChild(title);
    heading.appendChild(subtitle);
    head.appendChild(heading);
    headActions.appendChild(manage);
    headActions.appendChild(close);
    head.appendChild(headActions);
    dialog.appendChild(head);

    if (!items.length) {
      var empty = document.createElement("div");
      empty.className = "ullme-feature-empty";
      empty.innerHTML = "<strong>Nothing here yet</strong><span>Add definitions in the corresponding package, general, or personal directory.</span>";
      list.appendChild(empty);
    } else {
      items.forEach(function (item) {
        list.appendChild(catalogCard(item, kind));
      });
    }

    dialog.appendChild(list);
    dialog.appendChild(note);
    overlay.appendChild(dialog);
    overlay.addEventListener("click", function (event) {
      if (event.target === overlay) closeCatalogDialog();
    });
    document.body.appendChild(overlay);
    close.focus();
  }

  function catalogCard(item, kind) {
    var isTutor = kind === "tutors";
    var card = document.createElement("article");
    var body = document.createElement("div");
    var titleRow = document.createElement("div");
    var title = document.createElement("div");
    var badge = document.createElement("span");
    var description = document.createElement("div");
    var actions = document.createElement("div");
    var view = document.createElement("button");
    var action = document.createElement("button");
    var id = isTutor ? item.tutorid : item.skillid;
    var installed = isTutor && state.aiTutors.some(function (tutor) {
      return tutor.tutorid === id;
    });

    card.className = "ullme-catalog-card";
    body.className = "ullme-catalog-card-body";
    titleRow.className = "ullme-feature-card-title-wrap";
    title.className = "ullme-feature-card-title";
    title.textContent = item.label || id;
    badge.className = "ullme-source-badge";
    badge.textContent = sourceLabel(item.source);
    description.className = "ullme-feature-card-description";
    description.textContent = item.description || "No description";
    actions.className = "ullme-catalog-card-actions";
    view.type = "button";
    view.className = "ullme-secondary-action";
    view.textContent = "View";
    view.addEventListener("click", function () {
      closeCatalogDialog();
      requestDefinitionWorkspace(isTutor ? "tutor" : "skill", item);
    });
    action.type = "button";
    action.className = installed ? "ullme-secondary-action" : "ullme-primary-action";
    action.textContent = installed ? "Added" : (isTutor ? "Add" : "Use skill");
    action.disabled = installed;
    action.addEventListener("click", function () {
      if (isTutor) {
        sendSidebarEvent("ullme_ai_tutor_add_event", { tutorid: id });
      } else {
        sendSidebarEvent("ullme_skill_activate_event", { skillid: id });
      }
      closeCatalogDialog();
    });

    titleRow.appendChild(title);
    titleRow.appendChild(badge);
    body.appendChild(titleRow);
    body.appendChild(description);
    card.appendChild(body);
    actions.appendChild(view);
    actions.appendChild(action);
    card.appendChild(actions);
    return card;
  }

  function closeCatalogDialog() {
    var overlay = byId("ullme_catalog_overlay");
    if (overlay) overlay.remove();
  }

  function requestDefinitionWorkspace(kind, item) {
    if (definitionWorkspaceDirty() && !window.confirm("Discard your unsaved changes?")) return;
    item = item || {};
    sendSidebarEvent("ullme_definition_action_event", {
      action: "open",
      kind: kind,
      definitionid: item.id || item.tutorid || item.skillid || "",
      source: item.source || ""
    });
  }

  function openDefinitionWorkspace(payload) {
    closeCatalogDialog();
    removeDefinitionWorkspace(true);
    payload = payload || {};
    state.definitionWorkspace = payload;

    var overlay = document.createElement("div");
    var workspace = document.createElement("section");
    var header = document.createElement("header");
    var identity = document.createElement("div");
    var title = document.createElement("div");
    var subtitle = document.createElement("div");
    var navigation = document.createElement("div");
    var kindTabs = document.createElement("div");
    var picker = document.createElement("select");
    var headerActions = document.createElement("div");
    var importButton = document.createElement("button");
    var create = document.createElement("button");
    var assistantToggle = document.createElement("button");
    var close = document.createElement("button");
    var body = document.createElement("div");
    var sidebar = document.createElement("aside");
    var editor = document.createElement("main");
    var assistant = document.createElement("aside");

    overlay.id = "ullme_definition_overlay";
    overlay.className = "ullme-definition-overlay";
    workspace.className = "ullme-definition-workspace";
    workspace.classList.toggle(
      "ullme-definition-assistant-open",
      state.definitionAssistantOpen
    );
    workspace.setAttribute("role", "dialog");
    workspace.setAttribute("aria-modal", "true");
    workspace.setAttribute("aria-label", "Definition Workspace");
    header.className = "ullme-definition-header";
    identity.className = "ullme-definition-identity";
    title.className = "ullme-definition-title";
    title.textContent = "Definition Workspace";
    subtitle.className = "ullme-definition-subtitle";
    subtitle.textContent = "View and edit the Markdown and YAML behind uLLMe.";
    navigation.className = "ullme-definition-navigation";
    kindTabs.className = "ullme-definition-kind-tabs";
    picker.className = "ullme-definition-picker";
    picker.setAttribute("aria-label", "Selected definition");
    headerActions.className = "ullme-definition-header-actions";

    ["tutor", "skill"].forEach(function (kind) {
      var tab = document.createElement("button");
      tab.type = "button";
      tab.className = "ullme-definition-kind-tab";
      tab.classList.toggle("ullme-definition-kind-tab-active", payload.kind === kind);
      tab.textContent = kind === "tutor" ? "AI Tutors" : "Skills";
      tab.addEventListener("click", function () {
        if (payload.kind === kind) return;
        requestDefinitionWorkspace(kind);
      });
      kindTabs.appendChild(tab);
    });

    var pickerEntries = (Array.isArray(payload.library) ? payload.library : []).filter(function (item) {
      return item.kind === payload.kind;
    });
    pickerEntries.forEach(function (item, index) {
      var option = document.createElement("option");
      option.value = String(index);
      option.textContent = sourceLabel(item.source) + " · " + (item.label || item.id);
      option.selected = Boolean(payload.selected) &&
        payload.selected.id === item.id &&
        payload.selected.source === item.source;
      picker.appendChild(option);
    });
    picker.disabled = !pickerEntries.length;
    picker.addEventListener("change", function () {
      var item = pickerEntries[Number(picker.value)];
      if (item) requestDefinitionWorkspace(item.kind, item);
    });

    importButton.type = "button";
    importButton.className = "ullme-secondary-action";
    importButton.textContent = "Import";
    importButton.addEventListener("click", function () {
      var input = byId("ullme_definition_import_" + (payload.kind || "tutor"));
      if (!input) return;
      input.value = "";
      input.click();
    });
    create.type = "button";
    create.className = "ullme-primary-action";
    create.textContent = payload.kind === "skill" ? "New Skill" : "New AI Tutor";
    create.disabled = !payload.can_create;
    create.addEventListener("click", function () {
      openCreateDefinitionDialog(payload.kind || "tutor");
    });
    assistantToggle.type = "button";
    assistantToggle.className = "ullme-secondary-action ullme-definition-assistant-toggle";
    assistantToggle.textContent = state.definitionAssistantOpen ? "Close AI" : "AI assistant";
    assistantToggle.disabled = !payload.selected;
    assistantToggle.addEventListener("click", function () {
      state.definitionAssistantOpen = !state.definitionAssistantOpen;
      workspace.classList.toggle(
        "ullme-definition-assistant-open",
        state.definitionAssistantOpen
      );
      assistantToggle.textContent = state.definitionAssistantOpen ? "Close AI" : "AI assistant";
      if (state.definitionAssistantOpen) {
        var composer = byId("ullme_definition_assistant_input");
        if (composer) composer.focus();
      }
    });
    close.type = "button";
    close.className = "ullme-icon-button";
    close.setAttribute("aria-label", "Close Definition Workspace");
    close.innerHTML = icons.close;
    close.addEventListener("click", closeDefinitionWorkspace);

    identity.appendChild(title);
    identity.appendChild(subtitle);
    navigation.appendChild(kindTabs);
    navigation.appendChild(picker);
    headerActions.appendChild(importButton);
    headerActions.appendChild(create);
    headerActions.appendChild(assistantToggle);
    headerActions.appendChild(close);
    header.appendChild(identity);
    header.appendChild(navigation);
    header.appendChild(headerActions);

    body.className = "ullme-definition-body";
    sidebar.className = "ullme-definition-sidebar";
    editor.className = "ullme-definition-editor";
    assistant.className = "ullme-definition-assistant";
    renderDefinitionSidebar(sidebar, payload);
    renderDefinitionEditor(editor, payload);
    renderDefinitionAssistant(assistant, payload);
    body.appendChild(sidebar);
    body.appendChild(editor);
    body.appendChild(assistant);
    workspace.appendChild(header);
    workspace.appendChild(body);
    overlay.appendChild(workspace);
    document.body.appendChild(overlay);
    close.focus();
  }

  function renderDefinitionSidebar(sidebar, payload) {
    var library = Array.isArray(payload.library) ? payload.library : [];
    var selected = payload.selected || {};
    var entries = library.filter(function (item) {
      return item.kind === payload.kind;
    });
    var sourceOrder = ["course", "personal", "general", "package"];

    if (!entries.length) {
      var empty = document.createElement("div");
      empty.className = "ullme-definition-sidebar-empty";
      empty.textContent = "No definitions yet";
      sidebar.appendChild(empty);
      return;
    }

    sourceOrder.forEach(function (source) {
      var groupEntries = entries.filter(function (item) {
        return item.source === source;
      });
      if (!groupEntries.length) return;

      var group = document.createElement("section");
      var heading = document.createElement("div");
      heading.className = "ullme-definition-source-heading";
      heading.textContent = sourceLabel(source);
      group.className = "ullme-definition-source-group";
      group.appendChild(heading);

      groupEntries.forEach(function (item) {
        var button = document.createElement("button");
        var label = document.createElement("span");
        var id = document.createElement("span");
        var isSelected = selected.id === item.id &&
          selected.source === item.source &&
          selected.kind === item.kind;
        button.type = "button";
        button.className = "ullme-definition-list-item";
        button.classList.toggle("ullme-definition-list-item-active", isSelected);
        if (isSelected) button.setAttribute("aria-current", "true");
        label.className = "ullme-definition-list-label";
        label.textContent = item.label || item.id;
        id.className = "ullme-definition-list-id";
        id.textContent = item.id;
        button.appendChild(label);
        button.appendChild(id);
        button.addEventListener("click", function () {
          if (isSelected) return;
          requestDefinitionWorkspace(item.kind, item);
        });
        group.appendChild(button);
      });
      sidebar.appendChild(group);
    });
  }

  function renderDefinitionEditor(editor, payload) {
    var selected = payload.selected;
    if (!selected) {
      var empty = document.createElement("div");
      empty.className = "ullme-definition-editor-empty";
      empty.innerHTML = "<strong>No definition selected</strong><span>Create a personal definition or select one from the library.</span>";
      editor.appendChild(empty);
      return;
    }

    var head = document.createElement("div");
    var heading = document.createElement("div");
    var titleRow = document.createElement("div");
    var title = document.createElement("div");
    var badge = document.createElement("span");
    var description = document.createElement("div");
    var definitionActions = document.createElement("div");
    var files = document.createElement("div");
    var fileTabs = document.createElement("div");
    var toolbar = document.createElement("div");
    var filePath = document.createElement("code");
    var mode = document.createElement("span");
    var textarea = document.createElement("textarea");
    var footer = document.createElement("div");
    var status = document.createElement("div");
    var save = document.createElement("button");
    var records = Array.isArray(selected.files) ? selected.files : [];

    head.className = "ullme-definition-editor-head";
    heading.className = "ullme-definition-editor-heading";
    titleRow.className = "ullme-definition-editor-title-row";
    title.className = "ullme-definition-editor-title";
    title.textContent = selected.label || selected.id;
    badge.className = "ullme-source-badge";
    badge.textContent = sourceLabel(selected.source);
    description.className = "ullme-definition-editor-description";
    description.textContent = selected.description || "No description";
    definitionActions.className = "ullme-definition-copy-actions";

    if (selected.can_make_personal) {
      definitionActions.appendChild(definitionCopyButton(
        selected.personal_exists ? "Open personal copy" : "Make personal copy",
        "copy-personal",
        selected
      ));
    }
    if (selected.can_customize_course) {
      definitionActions.appendChild(definitionCopyButton(
        selected.course_exists ? "Open course copy" : "Customize for course",
        "copy-course",
        selected
      ));
    }
    var download = document.createElement("button");
    download.type = "button";
    download.className = "ullme-secondary-action";
    download.textContent = selected.kind === "skill" ? "Download ZIP" : "Download YAML";
    download.addEventListener("click", function () {
      sendSidebarEvent("ullme_definition_action_event", {
        action: "download",
        kind: selected.kind,
        definitionid: selected.id,
        source: selected.source
      });
    });
    definitionActions.appendChild(download);
    if (selected.can_delete) {
      var remove = document.createElement("button");
      remove.type = "button";
      remove.className = "ullme-danger-action";
      remove.textContent = "Delete copy";
      remove.addEventListener("click", function () {
        var detail = selected.source === "course"
          ? "This removes only the course-local definition copy; the Tutor remains installed and falls back to the next available definition."
          : "This removes the Personal copy and falls back to a General or Package definition when available.";
        if (!window.confirm("Delete " + (selected.label || selected.id) + "?\n\n" + detail)) return;
        sendSidebarEvent("ullme_definition_action_event", {
          action: "delete",
          kind: selected.kind,
          definitionid: selected.id,
          source: selected.source
        });
      });
      definitionActions.appendChild(remove);
    }

    titleRow.appendChild(title);
    titleRow.appendChild(badge);
    heading.appendChild(titleRow);
    heading.appendChild(description);
    head.appendChild(heading);
    head.appendChild(definitionActions);

    files.className = "ullme-definition-files";
    fileTabs.className = "ullme-definition-file-tabs";
    toolbar.className = "ullme-definition-file-toolbar";
    filePath.className = "ullme-definition-file-path";
    mode.className = "ullme-definition-file-mode";
    textarea.id = "ullme_definition_file_editor";
    textarea.className = "ullme-definition-file-editor";
    textarea.spellcheck = false;
    footer.className = "ullme-definition-editor-footer";
    status.className = "ullme-definition-status";
    save.type = "button";
    save.className = "ullme-primary-action";
    save.textContent = "Save";
    save.disabled = true;

    records.forEach(function (record) {
      var tab = document.createElement("button");
      tab.type = "button";
      tab.className = "ullme-definition-file-tab";
      tab.textContent = record.path;
      tab.setAttribute("data-definition-file", record.path);
      tab.addEventListener("click", function () {
        var current = currentDefinitionFile();
        if (current && current.path === record.path) return;
        if (definitionWorkspaceDirty() && !window.confirm("Discard your unsaved changes?")) return;
        selectDefinitionFile(record, selected, payload, fileTabs, filePath, mode, textarea, status, save);
      });
      fileTabs.appendChild(tab);
    });

    toolbar.appendChild(filePath);
    toolbar.appendChild(mode);
    footer.appendChild(status);
    footer.appendChild(save);
    files.appendChild(fileTabs);
    files.appendChild(toolbar);
    files.appendChild(textarea);
    files.appendChild(footer);
    editor.appendChild(head);
    editor.appendChild(files);

    textarea.addEventListener("input", function () {
      var dirty = definitionWorkspaceDirty();
      save.disabled = textarea.readOnly || !dirty;
      status.classList.remove("ullme-definition-status-error", "ullme-definition-status-success");
      status.textContent = dirty ? "Unsaved changes" : definitionDefaultStatus(selected, payload);
    });
    save.addEventListener("click", function () {
      var record = currentDefinitionFile();
      if (!record || textarea.readOnly || !definitionWorkspaceDirty()) return;
      save.disabled = true;
      status.classList.remove("ullme-definition-status-error", "ullme-definition-status-success");
      status.textContent = "Saving...";
      sendSidebarEvent("ullme_definition_action_event", {
        action: "save",
        kind: selected.kind,
        definitionid: selected.id,
        source: selected.source,
        file: record.path,
        content: textarea.value
      });
    });

    if (!records.length) {
      textarea.readOnly = true;
      textarea.value = "No Markdown or YAML files were found in this definition.";
      mode.textContent = "No editable files";
      status.textContent = definitionDefaultStatus(selected, payload);
      return;
    }

    var initial = records[0];
    if (payload.draft && payload.draft.file) {
      records.forEach(function (record) {
        if (record.path === payload.draft.file) initial = record;
      });
    }
    selectDefinitionFile(initial, selected, payload, fileTabs, filePath, mode, textarea, status, save);
  }

  function definitionCopyButton(label, action, selected) {
    var button = document.createElement("button");
    button.type = "button";
    button.className = "ullme-secondary-action";
    button.textContent = label;
    button.addEventListener("click", function () {
      if (definitionWorkspaceDirty() && !window.confirm("Discard your unsaved changes?")) return;
      sendSidebarEvent("ullme_definition_action_event", {
        action: action,
        kind: selected.kind,
        definitionid: selected.id,
        source: selected.source
      });
    });
    return button;
  }

  function selectDefinitionFile(record, selected, payload, fileTabs, filePath,
                                mode, textarea, status, save) {
    Array.prototype.forEach.call(fileTabs.querySelectorAll(".ullme-definition-file-tab"), function (tab) {
      tab.classList.toggle(
        "ullme-definition-file-tab-active",
        tab.getAttribute("data-definition-file") === record.path
      );
    });
    var content = record.content || "";
    if (payload.draft && payload.draft.file === record.path) {
      content = payload.draft.content || "";
    }
    filePath.textContent = record.path;
    mode.textContent = record.editable ? "Editable" : "Read-only";
    textarea.readOnly = !record.editable;
    textarea.value = content;
    textarea.setAttribute("data-definition-file", record.path);
    state.definitionOriginalContent = content;
    save.disabled = true;
    status.classList.toggle("ullme-definition-status-error", Boolean(payload.error));
    status.classList.toggle("ullme-definition-status-success", Boolean(payload.notice) && !payload.error);
    status.textContent = definitionDefaultStatus(selected, payload);
  }

  function definitionDefaultStatus(selected, payload) {
    if (payload.error) return payload.error;
    if (payload.notice) return payload.notice;
    return selected.editable
      ? "Changes are validated before saving."
      : sourceLabel(selected.source) + " definitions are read-only in teacher mode.";
  }

  function currentDefinitionFile() {
    var textarea = byId("ullme_definition_file_editor");
    if (!textarea) return null;
    return {
      path: textarea.getAttribute("data-definition-file") || "",
      content: textarea.value
    };
  }

  function definitionWorkspaceDirty() {
    var textarea = byId("ullme_definition_file_editor");
    if (!textarea || textarea.readOnly) return false;
    return textarea.value !== state.definitionOriginalContent;
  }

  function closeDefinitionWorkspace() {
    if (definitionWorkspaceDirty() && !window.confirm("Discard your unsaved changes?")) return;
    removeDefinitionWorkspace(false);
  }

  function removeDefinitionWorkspace(preserveAssistantState) {
    var overlay = byId("ullme_definition_overlay");
    if (overlay) overlay.remove();
    closeCreateDefinitionDialog();
    closeDefinitionImportPreview();
    state.definitionWorkspace = null;
    state.definitionOriginalContent = "";
    if (!preserveAssistantState) state.definitionAssistantOpen = false;
  }

  function openCreateDefinitionDialog(kind) {
    closeCreateDefinitionDialog();
    var overlay = byId("ullme_definition_overlay");
    if (!overlay) return;
    var backdrop = document.createElement("div");
    var dialog = document.createElement("section");
    var title = document.createElement("div");
    var idLabel = document.createElement("label");
    var idText = document.createElement("span");
    var idInput = document.createElement("input");
    var nameLabel = document.createElement("label");
    var nameText = document.createElement("span");
    var nameInput = document.createElement("input");
    var error = document.createElement("div");
    var actions = document.createElement("div");
    var cancel = document.createElement("button");
    var create = document.createElement("button");

    backdrop.id = "ullme_definition_create_dialog";
    backdrop.className = "ullme-definition-create-backdrop";
    dialog.className = "ullme-definition-create-dialog";
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    dialog.setAttribute("aria-label", kind === "skill" ? "Create Skill" : "Create AI Tutor");
    title.className = "ullme-definition-create-title";
    title.textContent = kind === "skill" ? "New Skill" : "New AI Tutor";
    idLabel.className = "ullme-definition-create-field";
    idText.textContent = "ID";
    idInput.type = "text";
    idInput.placeholder = kind === "skill" ? "my_skill" : "my_tutor";
    idInput.autocomplete = "off";
    nameLabel.className = "ullme-definition-create-field";
    nameText.textContent = "Label";
    nameInput.type = "text";
    nameInput.placeholder = kind === "skill" ? "My Skill" : "My AI Tutor";
    error.className = "ullme-definition-create-error";
    actions.className = "ullme-dialog-actions";
    cancel.type = "button";
    cancel.className = "ullme-secondary-action";
    cancel.textContent = "Cancel";
    cancel.addEventListener("click", closeCreateDefinitionDialog);
    create.type = "button";
    create.className = "ullme-primary-action";
    create.textContent = "Create";
    create.addEventListener("click", function () {
      var id = idInput.value.trim();
      if (!/^[A-Za-z][A-Za-z0-9_-]*$/.test(id)) {
        error.textContent = "Use letters, numbers, underscores, or hyphens, starting with a letter.";
        return;
      }
      sendSidebarEvent("ullme_definition_action_event", {
        action: "create",
        kind: kind,
        definitionid: id,
        label: nameInput.value.trim()
      });
      closeCreateDefinitionDialog();
    });

    idLabel.appendChild(idText);
    idLabel.appendChild(idInput);
    nameLabel.appendChild(nameText);
    nameLabel.appendChild(nameInput);
    actions.appendChild(cancel);
    actions.appendChild(create);
    dialog.appendChild(title);
    dialog.appendChild(idLabel);
    dialog.appendChild(nameLabel);
    dialog.appendChild(error);
    dialog.appendChild(actions);
    backdrop.appendChild(dialog);
    backdrop.addEventListener("click", function (event) {
      if (event.target === backdrop) closeCreateDefinitionDialog();
    });
    overlay.appendChild(backdrop);
    idInput.focus();
  }

  function closeCreateDefinitionDialog() {
    var dialog = byId("ullme_definition_create_dialog");
    if (dialog) dialog.remove();
  }

  function definitionAssistantKey(selected) {
    if (!selected) return "";
    return [selected.kind, selected.source, selected.id].join(":");
  }

  function definitionAssistantMessages(selected) {
    var key = definitionAssistantKey(selected);
    if (!key) return [];
    if (!Array.isArray(state.definitionAssistantMessages[key])) {
      state.definitionAssistantMessages[key] = [];
    }
    return state.definitionAssistantMessages[key];
  }

  function renderDefinitionAssistant(panel, payload) {
    panel.innerHTML = "";
    var selected = payload.selected;
    var head = document.createElement("div");
    var title = document.createElement("div");
    var context = document.createElement("div");
    var messages = document.createElement("div");
    var composer = document.createElement("div");
    var input = document.createElement("textarea");
    var send = document.createElement("button");

    head.className = "ullme-definition-assistant-head";
    title.className = "ullme-definition-assistant-title";
    title.textContent = "Definition Assistant";
    context.className = "ullme-definition-assistant-context";
    context.textContent = selected
      ? (selected.label || selected.id) + " · " + sourceLabel(selected.source)
      : "No definition selected";
    messages.className = "ullme-definition-assistant-messages";
    composer.className = "ullme-definition-assistant-composer";
    input.id = "ullme_definition_assistant_input";
    input.rows = 3;
    input.placeholder = selected && selected.editable
      ? "Ask AI to rewrite the current file"
      : "Make an editable copy before applying AI rewrites";
    input.disabled = !selected || !selected.editable;
    send.type = "button";
    send.className = "ullme-primary-action";
    send.textContent = "Send";
    send.disabled = input.disabled;

    head.appendChild(title);
    head.appendChild(context);
    panel.appendChild(head);

    var records = definitionAssistantMessages(selected);
    if (!records.length) {
      var intro = document.createElement("div");
      intro.className = "ullme-definition-assistant-intro";
      intro.textContent = selected && selected.editable
        ? "The assistant sees this definition. Its rewrites become unsaved editor drafts; only Save writes them to disk."
        : "Package and General definitions are read-only. Make a Personal or course-local copy to let AI rewrite them.";
      messages.appendChild(intro);
      if (selected && selected.editable) {
        var starters = document.createElement("div");
        starters.className = "ullme-definition-assistant-starters";
        [
          "Make the instructions clearer and more concise",
          "Use a more Socratic teaching style",
          "Check this file for inconsistencies"
        ].forEach(function (prompt) {
          var starter = document.createElement("button");
          starter.type = "button";
          starter.textContent = prompt;
          starter.addEventListener("click", function () {
            input.value = prompt;
            input.focus();
          });
          starters.appendChild(starter);
        });
        messages.appendChild(starters);
      }
    }

    records.forEach(function (record) {
      var message = document.createElement("article");
      var text = document.createElement("div");
      message.className = "ullme-definition-assistant-message ullme-definition-assistant-message-" + record.role;
      if (record.pending) message.classList.add("ullme-definition-assistant-message-pending");
      if (record.requestid) message.setAttribute("data-request-id", record.requestid);
      text.textContent = record.text;
      message.appendChild(text);
      if (record.undo) {
        var undo = document.createElement("button");
        undo.type = "button";
        undo.className = "ullme-text-action";
        undo.textContent = "Undo AI draft";
        undo.addEventListener("click", function () {
          var current = currentDefinitionFile();
          var editor = byId("ullme_definition_file_editor");
          if (!current || !editor || current.path !== record.undo.file) return;
          editor.value = record.undo.content;
          editor.dispatchEvent(new Event("input", { bubbles: true }));
          record.undo = null;
          renderDefinitionAssistant(panel, payload);
        });
        message.appendChild(undo);
      }
      messages.appendChild(message);
    });

    function submitDefinitionAssistant() {
      var instruction = input.value.trim();
      var current = currentDefinitionFile();
      if (!instruction || !selected || !selected.editable || !current) return;
      state.definitionAssistantRequestIndex += 1;
      var requestid = "definition_ai_" + Date.now() + "_" + state.definitionAssistantRequestIndex;
      records.push({ role: "user", text: instruction });
      records.push({
        role: "assistant",
        text: "Working on a draft...",
        requestid: requestid,
        pending: true
      });
      renderDefinitionAssistant(panel, payload);
      sendSidebarEvent("ullme_definition_chat_event", {
        requestid: requestid,
        kind: selected.kind,
        definitionid: selected.id,
        source: selected.source,
        file: current.path,
        content: current.content,
        message: instruction
      });
    }

    send.addEventListener("click", submitDefinitionAssistant);
    input.addEventListener("keydown", function (event) {
      if (event.key !== "Enter" || event.shiftKey) return;
      event.preventDefault();
      submitDefinitionAssistant();
    });
    composer.appendChild(input);
    composer.appendChild(send);
    panel.appendChild(messages);
    panel.appendChild(composer);
    messages.scrollTop = messages.scrollHeight;
  }

  function receiveDefinitionAssistantMessage(response) {
    response = response || {};
    var matchedMessages = null;
    Object.keys(state.definitionAssistantMessages).some(function (key) {
      var messages = state.definitionAssistantMessages[key];
      var found = messages.some(function (message) {
        return message.requestid === response.requestid && message.pending;
      });
      if (found) matchedMessages = messages;
      return found;
    });
    if (!matchedMessages) return;

    var pendingIndex = -1;
    matchedMessages.forEach(function (message, index) {
      if (message.requestid === response.requestid && message.pending) pendingIndex = index;
    });
    var assistantRecord = {
      role: "assistant",
      text: response.message || (response.ok ? "Draft ready." : "The rewrite failed.")
    };

    var editor = byId("ullme_definition_file_editor");
    var current = currentDefinitionFile();
    var selected = state.definitionWorkspace && state.definitionWorkspace.selected;
    var matchesSelection = selected && response.ok &&
      response.definitionid === selected.id &&
      response.source === selected.source;
    if (matchesSelection && response.draft && editor && current &&
        response.draft.file === current.path) {
      assistantRecord.undo = { file: current.path, content: editor.value };
      editor.value = response.draft.content || "";
      editor.dispatchEvent(new Event("input", { bubbles: true }));
      var changedTab = document.querySelector(
        '.ullme-definition-file-tab[data-definition-file="' +
        cssAttributeValue(current.path) +
        '"]'
      );
      if (changedTab) changedTab.classList.add("ullme-definition-file-tab-ai");
    }
    if (pendingIndex >= 0) matchedMessages.splice(pendingIndex, 1, assistantRecord);

    var panel = document.querySelector(".ullme-definition-assistant");
    if (panel && state.definitionWorkspace) {
      renderDefinitionAssistant(panel, state.definitionWorkspace);
    }
  }

  function cssAttributeValue(value) {
    return String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  }

  function openDefinitionImportPreview(preview) {
    closeDefinitionImportPreview();
    preview = preview || {};
    var host = byId("ullme_definition_overlay") || document.body;
    var backdrop = document.createElement("div");
    var dialog = document.createElement("section");
    var title = document.createElement("div");
    var summary = document.createElement("div");
    var files = document.createElement("div");
    var targetLabel = document.createElement("label");
    var targetText = document.createElement("span");
    var target = document.createElement("select");
    var warning = document.createElement("div");
    var actions = document.createElement("div");
    var cancel = document.createElement("button");
    var confirm = document.createElement("button");

    backdrop.id = "ullme_definition_import_preview";
    backdrop.className = "ullme-definition-create-backdrop";
    dialog.className = "ullme-definition-import-dialog";
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    dialog.setAttribute("aria-label", "Import definition");
    title.className = "ullme-definition-create-title";
    title.textContent = preview.kind === "skill" ? "Import Skill ZIP" : "Import AI Tutor YAML";
    summary.className = "ullme-definition-import-summary";
    files.className = "ullme-definition-import-files";
    targetLabel.className = "ullme-definition-create-field";
    targetText.textContent = "Destination";
    warning.className = "ullme-definition-import-warning";
    actions.className = "ullme-dialog-actions";
    cancel.type = "button";
    cancel.className = "ullme-secondary-action";
    cancel.textContent = "Cancel";
    cancel.addEventListener("click", closeDefinitionImportPreview);
    confirm.type = "button";
    confirm.className = "ullme-primary-action";

    if (preview.error) {
      summary.classList.add("ullme-definition-status-error");
      summary.textContent = preview.error;
      confirm.textContent = "Close";
      confirm.addEventListener("click", closeDefinitionImportPreview);
    } else {
      summary.innerHTML = "<strong></strong><span></span>";
      summary.querySelector("strong").textContent = preview.label || preview.id;
      summary.querySelector("span").textContent = preview.id;
      (Array.isArray(preview.files) ? preview.files : []).forEach(function (file) {
        var item = document.createElement("code");
        item.textContent = file;
        files.appendChild(item);
      });
      (Array.isArray(preview.targets) ? preview.targets : ["personal"]).forEach(function (source) {
        var option = document.createElement("option");
        option.value = source;
        option.textContent = source === "course"
          ? "Selected course"
          : "Personal library";
        target.appendChild(option);
      });
      function updateImportConflict() {
        var conflict = Boolean(preview.conflicts && preview.conflicts[target.value]);
        warning.textContent = conflict
          ? "A complete definition already exists here. Importing will replace that copy; files are not merged."
          : "The imported definition will be created as a complete copy.";
        warning.classList.toggle("ullme-definition-import-warning-danger", conflict);
        confirm.className = conflict ? "ullme-danger-action" : "ullme-primary-action";
        confirm.textContent = conflict ? "Replace complete copy" : "Import";
      }
      target.addEventListener("change", updateImportConflict);
      updateImportConflict();
      confirm.addEventListener("click", function () {
        var conflict = Boolean(preview.conflicts && preview.conflicts[target.value]);
        sendSidebarEvent("ullme_definition_action_event", {
          action: "import",
          kind: preview.kind,
          import_token: preview.token,
          target_source: target.value,
          replace: conflict
        });
        closeDefinitionImportPreview();
      });
    }

    targetLabel.appendChild(targetText);
    targetLabel.appendChild(target);
    actions.appendChild(cancel);
    actions.appendChild(confirm);
    dialog.appendChild(title);
    dialog.appendChild(summary);
    if (!preview.error) {
      dialog.appendChild(files);
      dialog.appendChild(targetLabel);
      dialog.appendChild(warning);
    }
    dialog.appendChild(actions);
    backdrop.appendChild(dialog);
    backdrop.addEventListener("click", function (event) {
      if (event.target === backdrop) closeDefinitionImportPreview();
    });
    host.appendChild(backdrop);
    confirm.focus();
  }

  function closeDefinitionImportPreview() {
    var preview = byId("ullme_definition_import_preview");
    if (preview) preview.remove();
  }

  function definitionImportComplete(inputId) {
    var input = byId(inputId);
    if (input) input.value = "";
    if (window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue(inputId, null, { priority: "event" });
    } else if (window.Shiny && Shiny.onInputChange) {
      Shiny.onInputChange(inputId, null);
    }
  }

  function downloadDefinition(url, filename) {
    var anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = filename || "";
    anchor.style.display = "none";
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
  }

  function renderActiveSkill(skill) {
    var container = byId("ullme_active_skill");
    var input = byId("ullme_chat_input");
    state.activeSkill = skill || null;
    if (!container) return;
    container.innerHTML = "";
    container.classList.toggle("ullme-active-skill-visible", Boolean(skill));
    if (input) input.placeholder = skill && skill.composer_placeholder
      ? skill.composer_placeholder
      : "Ask anything";
    if (!skill) return;

    var head = document.createElement("div");
    var identity = document.createElement("div");
    var icon = document.createElement("span");
    var title = document.createElement("strong");
    var clear = document.createElement("button");
    var intro = document.createElement("div");
    var starters = document.createElement("div");

    head.className = "ullme-active-skill-head";
    identity.className = "ullme-active-skill-identity";
    icon.className = "ullme-active-skill-icon";
    icon.innerHTML = ullmeSparklesIcon();
    title.textContent = skill.label || skill.skillid;
    clear.type = "button";
    clear.className = "ullme-active-skill-clear";
    clear.textContent = "Clear";
    clear.addEventListener("click", function () {
      sendSidebarEvent("ullme_skill_clear_event", {});
    });
    identity.appendChild(icon);
    identity.appendChild(title);
    head.appendChild(identity);
    head.appendChild(clear);
    container.appendChild(head);

    if (skill.intro) {
      intro.className = "ullme-active-skill-intro";
      intro.textContent = skill.intro;
      container.appendChild(intro);
    }

    var prompts = Array.isArray(skill.starter_prompts) ? skill.starter_prompts : [];
    if (prompts.length) {
      starters.className = "ullme-skill-starters";
      prompts.forEach(function (prompt) {
        var button = document.createElement("button");
        button.type = "button";
        button.textContent = prompt;
        button.addEventListener("click", function () {
          if (!input) return;
          input.value = prompt;
          input.dispatchEvent(new Event("input", { bubbles: true }));
          input.focus();
        });
        starters.appendChild(button);
      });
      container.appendChild(starters);
    }
  }

  function ullmeSparklesIcon() {
    return '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3l1.4 4.1L17.5 8.5l-4.1 1.4L12 14l-1.4-4.1-4.1-1.4 4.1-1.4L12 3z"></path><path d="M18.5 14l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8.8-2.2z"></path></svg>';
  }

  function openAddCourseDialog() {
    closeAddCourseDialog();
    var overlay = document.createElement("div");
    var dialog = document.createElement("div");
    var title = document.createElement("div");
    var idField = courseDialogField("Course ID", "ullme_new_courseid");
    var nameField = courseDialogField("Course name", "ullme_new_coursename");
    var actions = document.createElement("div");
    var cancel = document.createElement("button");
    var create = document.createElement("button");

    overlay.id = "ullme_add_course_overlay";
    overlay.className = "ullme-dialog-overlay";
    dialog.className = "ullme-dialog";
    title.className = "ullme-dialog-title";
    title.textContent = "Add Course";
    actions.className = "ullme-dialog-actions";
    cancel.type = "button";
    cancel.className = "ullme-secondary-action";
    cancel.textContent = "Cancel";
    create.type = "button";
    create.className = "ullme-primary-action";
    create.textContent = "Create";

    cancel.addEventListener("click", closeAddCourseDialog);
    overlay.addEventListener("click", function (event) {
      if (event.target === overlay) closeAddCourseDialog();
    });
    create.addEventListener("click", function () {
      var courseid = idField.input.value.trim();
      if (!courseid) {
        idField.input.focus();
        return;
      }
      sendSidebarEvent("ullme_add_course_event", {
        courseid: courseid,
        coursename: nameField.input.value.trim(),
        times: []
      });
      closeAddCourseDialog();
      showCoursePanel("settings");
    });

    actions.appendChild(cancel);
    actions.appendChild(create);
    dialog.appendChild(title);
    dialog.appendChild(idField.label);
    dialog.appendChild(nameField.label);
    dialog.appendChild(actions);
    overlay.appendChild(dialog);
    document.body.appendChild(overlay);
    idField.input.focus();
  }

  function closeAddCourseDialog() {
    var overlay = byId("ullme_add_course_overlay");
    if (overlay) overlay.remove();
  }

  function courseDialogField(labelText, id) {
    var label = document.createElement("label");
    var span = document.createElement("span");
    var input = document.createElement("input");
    label.className = "ullme-field";
    span.textContent = labelText;
    input.id = id;
    input.type = "text";
    label.appendChild(span);
    label.appendChild(input);
    return { label: label, input: input };
  }

  function gatherCourseSettings() {
    var name = byId("ullme_settings_coursename");
    return {
      coursename: name ? name.value.trim() : "",
      times: gatherCourseTimes()
    };
  }

  function gatherCourseTimes() {
    var rows = document.querySelectorAll(".ullme-time-slot");
    return Array.prototype.map.call(rows, function (row) {
      return {
        weekday: valueOf(row.querySelector(".ullme-time-weekday")),
        start: valueOf(row.querySelector(".ullme-time-start")),
        end: valueOf(row.querySelector(".ullme-time-end"))
      };
    }).filter(function (time) {
      return time.weekday || time.start || time.end;
    }).slice(0, 3);
  }

  function valueOf(input) {
    return input ? input.value : "";
  }

  function fillCourseSettings(course) {
    course = course || {};
    setInputValue("ullme_settings_courseid", course.courseid || "");
    setInputValue("ullme_settings_coursename", course.coursename || "");
    fillCourseTimes(course.times || []);
  }

  function setInputValue(id, value) {
    var input = byId(id);
    if (input) input.value = value || "";
  }

  function fillCourseTimes(times) {
    var rows = document.querySelectorAll(".ullme-time-slot");
    Array.prototype.forEach.call(rows, function (row, index) {
      var time = times[index] || {};
      setElementValue(row.querySelector(".ullme-time-weekday"), time.weekday || "");
      setElementValue(row.querySelector(".ullme-time-start"), time.start || "");
      setElementValue(row.querySelector(".ullme-time-end"), time.end || "");
    });
  }

  function setElementValue(element, value) {
    if (element) element.value = value || "";
  }

  function selectMaterialCategory(category) {
    var categories = byId("ullme_material_categories");
    if (!categories) return;
    Array.prototype.forEach.call(categories.querySelectorAll(".ullme-material-category"), function (item) {
      item.classList.toggle("ullme-material-category-active", item.getAttribute("data-category") === category);
    });
    var dropLabel = byId("ullme_material_drop_label");
    if (dropLabel) dropLabel.textContent = materialLabels[category] || category;
    sendSidebarEvent("ullme_material_category_event", { category: category });
    renderMaterialFiles(state.courseMaterial || {}, category);
  }

  function currentMaterialCategory() {
    var active = document.querySelector(".ullme-material-category-active");
    return active ? active.getAttribute("data-category") || "general" : "general";
  }

  function materialInputForCategory(category) {
    return byId("ullme_material_upload_" + category);
  }

  function bindMaterialDropzone(dropzone) {
    if (!dropzone) return;

    ["dragenter", "dragover"].forEach(function (eventName) {
      dropzone.addEventListener(eventName, function (event) {
        event.preventDefault();
        dropzone.classList.add("ullme-material-dropzone-active");
      });
    });

    ["dragleave", "dragend"].forEach(function (eventName) {
      dropzone.addEventListener(eventName, function () {
        dropzone.classList.remove("ullme-material-dropzone-active");
      });
    });

    dropzone.addEventListener("drop", function (event) {
      event.preventDefault();
      dropzone.classList.remove("ullme-material-dropzone-active");
      queueMaterialFiles(Array.prototype.slice.call(event.dataTransfer.files || []));
    });

    dropzone.addEventListener("click", function () {
      var input = materialInputForCategory(currentMaterialCategory());
      if (input) input.click();
    });

    dropzone.addEventListener("keydown", function (event) {
      if (event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
      dropzone.click();
    });
  }

  function queueMaterialFiles(files) {
    var input = materialInputForCategory(currentMaterialCategory());
    if (!input || !files.length || typeof DataTransfer === "undefined") return;
    var transfer = new DataTransfer();
    files.forEach(function (file) {
      transfer.items.add(file);
    });
    input.files = transfer.files;
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function renderMaterialFiles(material, category) {
    var list = byId("ullme_material_files");
    if (!list) return;
    category = category || currentMaterialCategory();
    var files = material && material[category] ? material[category] : [];
    list.innerHTML = "";

    if (!files.length) {
      var empty = document.createElement("div");
      empty.className = "ullme-material-empty";
      empty.textContent = "No files";
      list.appendChild(empty);
      return;
    }

    files.forEach(function (path) {
      var row = document.createElement("div");
      var name = document.createElement("div");
      var remove = document.createElement("button");
      row.className = "ullme-material-file";
      name.className = "ullme-material-file-name";
      name.textContent = path;
      remove.type = "button";
      remove.className = "ullme-danger-action";
      remove.textContent = "Delete";
      remove.addEventListener("click", function () {
        sendSidebarEvent("ullme_material_delete_event", {
          category: category,
          path: path
        });
      });
      row.appendChild(name);
      row.appendChild(remove);
      list.appendChild(row);
    });
  }

  function toggleSidebarMenu(button, onSelect) {
    var existing = button.parentNode.querySelector(".ullme-sidebar-menu");
    var wasOpen = Boolean(existing);
    closeSidebarMenus();
    if (wasOpen) return;

    var options = sidebarOptions(button);
    var current = button.getAttribute("data-value") || "";
    if (!options.length) return;

    var menu = document.createElement("div");
    menu.className = "ullme-sidebar-menu";
    menu.setAttribute("role", "menu");
    menu.style.left = button.offsetLeft + "px";
    menu.style.top = (button.offsetTop + button.offsetHeight + 3) + "px";
    menu.addEventListener("click", function (event) {
      event.stopPropagation();
    });

    options.forEach(function (value) {
      var item = document.createElement("button");
      item.className = "ullme-sidebar-menu-item";
      if (value === current) item.classList.add("ullme-sidebar-menu-item-active");
      item.type = "button";
      item.setAttribute("role", "menuitem");
      item.textContent = sidebarLabel(value, button.getAttribute("data-kind"));
      item.addEventListener("click", function () {
        setSidebarValue(button, value);
        closeSidebarMenus();
        onSelect(value);
      });
      menu.appendChild(item);
    });

    button.parentNode.appendChild(menu);
    button.classList.add("ullme-sidebar-value-open");
  }

  function sidebarOptions(button) {
    return (button.getAttribute("data-options") || "")
      .split("|")
      .map(function (value) { return value.trim(); })
      .filter(Boolean);
  }

  function setSidebarValue(button, value) {
    if (!button) return;
    var arrow = button.querySelector(".ullme-sidebar-value-arrow");
    button.setAttribute("data-value", value);
    button.textContent = sidebarLabel(value, button.getAttribute("data-kind"));
    if (arrow) button.appendChild(arrow);
  }

  function closeSidebarMenus() {
    Array.prototype.forEach.call(document.querySelectorAll(".ullme-sidebar-menu"), function (menu) {
      menu.remove();
    });
    Array.prototype.forEach.call(document.querySelectorAll(".ullme-sidebar-value-open"), function (button) {
      button.classList.remove("ullme-sidebar-value-open");
    });
  }

  function closeUserSettings() {
    var settings = byId("ullme_user_settings");
    if (settings) settings.classList.remove("ullme-user-settings-open");
  }

  function sidebarLabel(value, kind) {
    if (kind === "role") {
      return value.charAt(0).toUpperCase() + value.slice(1);
    }
    if (kind === "course") return value || "Course";
    return value;
  }

  function appendUserMessage(message) {
    var messages = byId("ullme_chat_messages");
    var article = document.createElement("article");
    var stack = document.createElement("div");
    var bubble = document.createElement("div");

    article.id = message.id;
    article.className = "ullme-message ullme-message-user";
    stack.className = "ullme-user-stack";
    bubble.className = "ullme-bubble";

    if (message.uploads && message.uploads.length) {
      bubble.appendChild(renderAttachments(message.uploads));
    }
    if (message.text) {
      bubble.appendChild(textBlock(message.text));
    }

    stack.appendChild(bubble);
    if (message.text) {
      stack.appendChild(renderUserActions(message.text));
    }
    article.appendChild(stack);
    messages.appendChild(article);
    scrollMessagesToBottom();
  }

  function appendAssistantMessage(message) {
    var messages = byId("ullme_chat_messages");
    var article = document.createElement("article");
    var bubble = document.createElement("div");
    var text = document.createElement("div");

    article.id = message.id;
    article.className = "ullme-message ullme-message-assistant";
    if (message.thinking) article.classList.add("ullme-thinking");

    bubble.className = "ullme-bubble";

    if (message.meta) {
      var meta = document.createElement("div");
      meta.className = "ullme-message-meta";
      meta.textContent = message.meta;
      bubble.appendChild(meta);
    }

    text.className = "ullme-message-text";
    text.textContent = message.text || "";
    bubble.appendChild(text);

    if (!message.thinking) {
      bubble.appendChild(renderAssistantActions(message.id, message.text || ""));
    }

    article.appendChild(bubble);
    messages.appendChild(article);
    scrollMessagesToBottom();
  }

  function renderAssistantActions(messageId, text) {
    var actions = document.createElement("div");
    var canRetry = Boolean(state.assistantRequests[messageId]);
    actions.className = "ullme-message-actions";
    actions.appendChild(miniAction("Copy", icons.copy, function () {
      copyText(text, this);
    }));
    actions.appendChild(miniAction("Redo", icons.retry, function () {
      retryAssistantMessage(messageId);
    }, !canRetry));
    actions.appendChild(miniAction("More", icons.more, function () {}));
    return actions;
  }

  function miniAction(label, icon, onClick, disabled) {
    var button = document.createElement("button");
    button.className = "ullme-mini-action";
    button.type = "button";
    button.setAttribute("aria-label", label);
    button.title = label;
    button.innerHTML = icon;
    button.disabled = Boolean(disabled);
    if (!disabled) button.addEventListener("click", onClick);
    return button;
  }

  function renderUserActions(text) {
    var actions = document.createElement("div");
    actions.className = "ullme-user-actions";
    actions.appendChild(miniAction("Copy prompt", icons.copy, function () {
      copyText(text, this);
    }));
    return actions;
  }

  function copyText(text, button) {
    if (navigator.clipboard) {
      navigator.clipboard.writeText(text);
      showCopied(button);
      return;
    }

    var textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "absolute";
    textarea.style.left = "-9999px";
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand("copy");
    document.body.removeChild(textarea);
    showCopied(button);
  }

  function showCopied(button) {
    if (!button) return;
    var oldLabel = button.getAttribute("aria-label") || "Copy";
    var oldTitle = button.title || oldLabel;
    var oldIcon = button.innerHTML;

    if (button.copyResetTimer) {
      window.clearTimeout(button.copyResetTimer);
    }

    button.setAttribute("aria-label", "Copied");
    button.title = "Copied";
    button.innerHTML = icons.check;

    button.copyResetTimer = window.setTimeout(function () {
      button.setAttribute("aria-label", oldLabel);
      button.title = oldTitle;
      button.innerHTML = oldIcon;
      button.copyResetTimer = null;
    }, 1200);
  }

  function retryAssistantMessage(messageId) {
    var payload = state.assistantRequests[messageId];
    var article = byId(messageId);
    if (!payload || !article) return;

    var messageText = article.querySelector(".ullme-message-text");
    var actions = article.querySelector(".ullme-message-actions");
    var meta = article.querySelector(".ullme-message-meta");

    article.classList.add("ullme-thinking");
    if (meta) meta.remove();
    if (actions) actions.remove();
    if (messageText) messageText.textContent = "Thinking...";

    payload.nonce = Math.random();
    sendChatEvent(payload);
  }

  function textBlock(text) {
    var block = document.createElement("div");
    block.textContent = text;
    return block;
  }

  function renderAttachments(uploads) {
    var wrap = document.createElement("div");
    wrap.className = "ullme-attachments";
    uploads.forEach(function (upload) {
      if (!upload.previewUrl) return;
      var image = document.createElement("img");
      image.className = "ullme-attachment-thumb";
      image.alt = upload.name || "Uploaded image";
      image.src = upload.previewUrl;
      wrap.appendChild(image);
    });
    return wrap;
  }

  function addLocalUploads(files) {
    files
      .filter(function (file) {
        return /^image\//.test(file.type || "");
      })
      .forEach(function (file) {
        var localId = nextId("upload");
        var reader = new FileReader();
        var upload = {
          localId: localId,
          name: file.name,
          size: file.size,
          type: file.type,
          previewUrl: ""
        };
        state.uploads.push(upload);
        updateComposerUploadClass();
        reader.onload = function (event) {
          upload.previewUrl = event.target.result;
          renderUploadPreview();
        };
        reader.readAsDataURL(file);
      });
    renderUploadPreview();
  }

  function handlePaste(event) {
    var files = clipboardImageFiles(event);
    if (!files.length) return;

    event.preventDefault();
    queueImageFiles(files);
  }

  function clipboardImageFiles(event) {
    var items = event.clipboardData && event.clipboardData.items;
    if (!items) return [];

    return Array.prototype.slice.call(items)
      .filter(function (item) {
        return item.kind === "file" && /^image\//.test(item.type || "");
      })
      .map(function (item, index) {
        return clipboardImageFile(item.getAsFile(), index);
      })
      .filter(Boolean);
  }

  function clipboardImageFile(file, index) {
    if (!file) return null;
    var type = file.type || "image/png";
    var name = "pasted-image-" + timestampForFileName() + "-" + (index + 1) + imageExtension(type);
    if (typeof File === "undefined") return file;
    return new File([file], name, { type: type });
  }

  function queueImageFiles(files) {
    files = files.filter(function (file) {
      return /^image\//.test(file.type || "");
    });
    if (!files.length) return;

    var fileInput = byId("ullme_image_upload");
    if (!fileInput || typeof DataTransfer === "undefined") {
      addLocalUploads(files);
      updateSubmitState();
      return;
    }

    var transfer = new DataTransfer();
    files.forEach(function (file) {
      transfer.items.add(file);
    });
    fileInput.files = transfer.files;
    fileInput.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function timestampForFileName() {
    return new Date().toISOString().replace(/[-:]/g, "").replace(/\..+$/, "").replace("T", "-");
  }

  function imageExtension(type) {
    if (/jpe?g/.test(type)) return ".jpg";
    if (/webp/.test(type)) return ".webp";
    if (/gif/.test(type)) return ".gif";
    return ".png";
  }

  function renderUploadPreview() {
    var preview = byId("ullme_upload_preview");
    if (!preview) return;

    preview.innerHTML = "";
    preview.classList.toggle("has-items", state.uploads.length > 0);
    updateComposerUploadClass();

    state.uploads.forEach(function (upload) {
      var item = document.createElement("div");
      var image = document.createElement("img");
      var remove = document.createElement("button");

      item.className = "ullme-preview-item";
      image.alt = upload.name || "Upload preview";
      image.src = upload.previewUrl || "";
      remove.className = "ullme-preview-remove";
      remove.type = "button";
      remove.setAttribute("aria-label", "Remove upload");
      remove.title = "Remove image";
      remove.innerHTML = icons.close;
      remove.addEventListener("click", function () {
        state.uploads = state.uploads.filter(function (candidate) {
          return candidate.localId !== upload.localId;
        });
        renderUploadPreview();
        updateSubmitState();
      });

      item.appendChild(image);
      item.appendChild(remove);
      preview.appendChild(item);
    });
  }

  function clearUploads() {
    var fileInput = byId("ullme_image_upload");
    state.uploads = [];
    if (fileInput) fileInput.value = "";
    renderUploadPreview();
  }

  function updateComposerUploadClass() {
    var preview = byId("ullme_upload_preview");
    var composer = preview ? preview.closest(".ullme-composer") : null;
    if (composer) composer.classList.toggle("ullme-composer-has-uploads", state.uploads.length > 0);
  }

  function receiveStoredUploads(records) {
    if (!records || !records.length) return;
    records.forEach(function (record) {
      var match = state.uploads.find(function (upload) {
        return !upload.serverId && upload.size === record.size;
      });
      if (match) {
        match.serverId = record.id;
        match.storedUrl = record.url;
      }
    });
  }

  function receiveAssistantMessage(messageId, text) {
    var article = byId(messageId);
    if (!article) {
      appendAssistantMessage({
        id: messageId || nextId("assistant"),
        text: text || "",
        meta: ""
      });
      return;
    }

    article.classList.remove("ullme-thinking");
    var meta = article.querySelector(".ullme-message-meta");
    var messageText = article.querySelector(".ullme-message-text");
    var bubble = article.querySelector(".ullme-bubble");

    if (meta) meta.remove();
    if (messageText) messageText.textContent = text || "";
    if (bubble && !bubble.querySelector(".ullme-message-actions")) {
      bubble.appendChild(renderAssistantActions(messageId, text || ""));
    }
    scrollMessagesToBottom();
  }

  function updateCourseList(courseids, selectedCourseid, showCourses, summary, role, semester) {
    var courseSelect = byId("ullme_course_select");
    var courseTabs = byId("ullme_course_tabs");
    var addCourseButton = byId("ullme_add_course_btn");

    courseids = Array.isArray(courseids) ? courseids : [];
    selectedCourseid = selectedCourseid || "";
    if (role) {
      setRoleLayout(role);
      setSidebarValue(byId("ullme_role_select"), role);
    }
    if (semester) setSidebarValue(byId("ullme_semester_select"), semester);
    if (courseSelect) {
      courseSelect.classList.toggle("ullme-course-select-hidden", !showCourses);
      courseSelect.setAttribute("data-options", courseids.join("|"));
      setSidebarValue(courseSelect, selectedCourseid);
    }
    if (addCourseButton) {
      addCourseButton.classList.toggle("ullme-add-course-button-hidden", !showCourses);
    }
    if (courseTabs) courseTabs.classList.toggle("ullme-course-tabs-hidden", !selectedCourseid);
    updateActiveCourse(summary, selectedCourseid);
  }

  function updateActiveCourse(summary, selectedCourseid) {
    var course = summary && summary.course ? summary.course : { courseid: selectedCourseid || "" };
    var material = summary && summary.material ? summary.material : {};
    var aiTutors = summary && Array.isArray(summary.ai_tutors) ? summary.ai_tutors : [];
    var aiTutorCatalog = summary && Array.isArray(summary.ai_tutor_catalog) ? summary.ai_tutor_catalog : [];
    var skills = summary && Array.isArray(summary.skills) ? summary.skills : [];
    var activeSkill = summary ? summary.active_skill : null;
    var courseWorkspace = byId("ullme_course_workspace");
    state.courseMaterial = material;
    state.aiTutors = aiTutors;
    state.aiTutorCatalog = aiTutorCatalog;
    state.skills = skills;
    if (courseWorkspace) {
      courseWorkspace.classList.toggle("ullme-course-workspace-empty", !selectedCourseid);
    }
    fillCourseSettings(course);
    renderMaterialFiles(material, currentMaterialCategory());
    renderAITutors(aiTutors);
    renderActiveSkill(activeSkill);
    if (!selectedCourseid) showCoursePanel("ai-tutors");
  }

  function setRoleLayout(role) {
    var app = byId("ullme_app");
    if (!app) return;
    ["teacher", "student", "admin"].forEach(function (candidate) {
      app.classList.toggle("ullme-role-" + candidate, role === candidate);
    });
  }

  function completePendingMaterialUpload(inputId) {
    inputId = inputId || state.pendingMaterialInputId;
    if (!inputId) return;
    if (state.pendingMaterialInputId && inputId !== state.pendingMaterialInputId) return;
    var input = byId(inputId);
    if (input) input.value = "";
    state.pendingMaterialInputId = "";

    if (window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue(inputId, null, { priority: "event" });
    } else if (window.Shiny && Shiny.onInputChange) {
      Shiny.onInputChange(inputId, null);
    }
  }

  function scrollMessagesToBottom() {
    var messages = byId("ullme_chat_messages");
    if (!messages) return;
    messages.scrollTop = messages.scrollHeight;
  }

  window.ullme = window.ullme || {};
  window.ullme.receiveAssistantMessage = receiveAssistantMessage;
  window.ullme.receiveStoredUploads = receiveStoredUploads;
  window.ullme.materialUploadComplete = completePendingMaterialUpload;
  window.ullme.updateCourseList = updateCourseList;
  window.ullme.openDefinitionWorkspace = openDefinitionWorkspace;
  window.ullme.openDefinitionImportPreview = openDefinitionImportPreview;
  window.ullme.definitionImportComplete = definitionImportComplete;
  window.ullme.downloadDefinition = downloadDefinition;
  window.ullme.receiveDefinitionAssistantMessage = receiveDefinitionAssistantMessage;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
