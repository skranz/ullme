(function () {
  var state = {
    uploads: [],
    messageIndex: 0,
    isRecording: false,
    chatBusy: false,
    activeAssistantMessageId: "",
    chatWatchdog: null,
    chatWatchdogPaused: false,
    submitButtonHtml: "",
    cancelledAssistantRequests: {},
    assistantRequests: {},
    pendingMaterialInputId: "",
    aiTutors: [],
    aiTutorCatalog: [],
    skills: [],
    courseSkills: [],
    activeSkill: null,
    definitionWorkspace: null,
    definitionOriginalContent: "",
    definitionAssistantOpen: false,
    definitionAssistantMessages: {},
    definitionAssistantRequestIndex: 0,
    courseFiles: [],
    materialView: "materials",
    materialTree: [],
    materialSelection: {},
    materialExpanded: {},
    materialSort: "name",
    materialSortDirection: "asc",
    materialConversionBusy: false,
    materialUploadDestination: "",
    pendingMaterialDrop: null,
    studioView: "usage",
    previousStudioView: "usage",
    courseFile: null,
    courseFileOriginalContent: "",
    selectedCourseid: ""
  };
  var chatCommon = window.ullmeChat;
  var typesetMath = chatCommon.typesetMath;
  var textBlock = chatCommon.textBlock;
  var renderAttachments = chatCommon.renderAttachments;

  var materialLabels = {
    root: "Materials root",
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
    close: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M18 6L6 18"></path><path d="M6 6l12 12"></path></svg>',
    stop: '<svg class="ullme-icon ullme-stop-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="7" y="7" width="10" height="10" rx="1"></rect></svg>'
  };

  function byId(id) {
    return chatCommon.byId(id);
  }

  function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
  }

  function initPaneResizers() {
    var app = byId("ullme_app");
    var workspace = app && app.querySelector(".ullme-workspace");
    var handles = workspace
      ? workspace.querySelectorAll(".ullme-pane-resizer")
      : [];
    if (!workspace || !handles.length) return;

    var saved = null;
    try {
      saved = JSON.parse(window.localStorage.getItem("ullme-teacher-pane-widths") || "null");
    } catch (error) {
      saved = null;
    }
    if (saved && Number.isFinite(saved.nav)) {
      workspace.style.setProperty("--ullme-nav-width", clamp(saved.nav, 52, 112) + "px");
    }
    if (saved && Number.isFinite(saved.ai)) {
      workspace.style.setProperty("--ullme-ai-width", clamp(saved.ai, 260, 560) + "px");
    }

    function currentWidth(name) {
      var styles = window.getComputedStyle(workspace);
      var property = name === "nav" ? "--ullme-nav-width" : "--ullme-ai-width";
      var fallback = name === "nav" ? 62 : 340;
      return parseFloat(styles.getPropertyValue(property)) || fallback;
    }

    function setWidth(name, value) {
      var minimum = name === "nav" ? 52 : 260;
      var maximum = name === "nav" ? 112 : 560;
      var property = name === "nav" ? "--ullme-nav-width" : "--ullme-ai-width";
      workspace.style.setProperty(property, clamp(value, minimum, maximum) + "px");
    }

    function saveWidths() {
      try {
        window.localStorage.setItem("ullme-teacher-pane-widths", JSON.stringify({
          nav: currentWidth("nav"),
          ai: currentWidth("ai")
        }));
      } catch (error) {
        return;
      }
    }

    Array.prototype.forEach.call(handles, function (handle) {
      var name = handle.getAttribute("data-pane-resizer");
      handle.addEventListener("pointerdown", function (event) {
        if (window.innerWidth <= 820) return;
        event.preventDefault();
        var bounds = workspace.getBoundingClientRect();
        document.body.classList.add("ullme-pane-resizing");

        function move(moveEvent) {
          var value = name === "nav"
            ? moveEvent.clientX - bounds.left
            : bounds.right - moveEvent.clientX;
          setWidth(name, value);
        }

        function finish() {
          document.body.classList.remove("ullme-pane-resizing");
          window.removeEventListener("pointermove", move);
          window.removeEventListener("pointerup", finish);
          window.removeEventListener("pointercancel", finish);
          saveWidths();
        }

        window.addEventListener("pointermove", move);
        window.addEventListener("pointerup", finish);
        window.addEventListener("pointercancel", finish);
      });
      handle.addEventListener("keydown", function (event) {
        if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return;
        event.preventDefault();
        var movement = event.key === "ArrowRight" ? 1 : -1;
        var delta = movement * (event.shiftKey ? 16 : 6);
        setWidth(name, currentWidth(name) + (name === "nav" ? delta : -delta));
        saveWidths();
      });
      handle.addEventListener("dblclick", function () {
        setWidth(name, name === "nav" ? 62 : 340);
        saveWidths();
      });
    });
  }

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function nextId(prefix) {
    return chatCommon.nextId(state, prefix);
  }

  function init() {
    var messages = byId("ullme_chat_messages");
    var input = byId("ullme_chat_input");
    var submitButton = byId("ullme_submit_btn");
    var uploadButton = byId("ullme_upload_btn");
    var fileInput = byId("ullme_image_upload");
    var voiceButton = byId("ullme_voice_btn");
    var semesterSelect = byId("ullme_semester_select");
    var courseSelect = byId("ullme_course_select");
    var addCourseButton = byId("ullme_add_course_btn");
    var courseTabs = byId("ullme_course_tabs");
    var settingsSave = byId("ullme_course_settings_save");
    var materialUploadButton = byId("ullme_material_upload_btn");
    var materialInlineUpload = byId("ullme_material_inline_upload");
    var materialSortName = byId("ullme_material_sort_name");
    var materialSortDate = byId("ullme_material_sort_date");
    var materialSelectAll = byId("ullme_material_select_all");
    var materialClearSelection = byId("ullme_material_clear_selection");
    var materialApplyOperation = byId("ullme_material_apply_operation");
    var materialConvert = byId("ullme_material_convert");
    var materialDeleteSelected = byId("ullme_material_delete_selected");
    var materialCreateDirectory = byId("ullme_material_create_directory");
    var userSettingsButton = byId("ullme_user_settings_btn");
    var userSettings = byId("ullme_user_settings");
    var skillsButton = byId("ullme_skills_btn");
    var manageSkillsButton = byId("ullme_manage_skills_btn");
    var studioNav = byId("ullme_studio_nav");
    var studioUploadButton = byId("ullme_studio_upload_btn");
    var aiPaneToggle = byId("ullme_ai_pane_toggle");
    var materialPanel = byId("ullme_material_panel");
    var courseFileBack = byId("ullme_course_file_back");
    var courseFileSave = byId("ullme_course_file_save");
    var courseFileEditor = byId("ullme_course_file_editor");
    var editHistoryControls = document.querySelectorAll(
      ".ullme-edit-history-controls[data-edit-history-scope]"
    );

    if (!messages || !input || !submitButton) return;
    state.submitButtonHtml = submitButton.innerHTML;

    mountIntro(messages);
    initPaneResizers();
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

    submitButton.addEventListener("click", function () {
      if (state.chatBusy) {
        stopActiveChat();
      } else {
        submitChat();
      }
    });

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
    document.addEventListener("shiny:disconnected", function () {
      if (!state.chatBusy || !state.activeAssistantMessageId) return;
      finishClientChatError(
        state.activeAssistantMessageId,
        "The connection to the uLLMe server was lost. Please reconnect and try again."
      );
    });

    if (voiceButton) {
      voiceButton.addEventListener("click", function () {
        if (window.ullmeAudio && window.ullmeAudio.startRecording) {
          window.ullmeAudio.startRecording();
        }
      });
    }

    if (semesterSelect) {
      semesterSelect.addEventListener("click", function (event) {
        event.stopPropagation();
        closeUserSettings();
        var previousSemester = semesterSelect.getAttribute("data-value") || "";
        toggleSidebarMenu(semesterSelect, function (semester) {
          if (teacherWorkspaceDirty() && !window.confirm("Discard your unsaved changes?")) {
            setSidebarValue(semesterSelect, previousSemester);
            return;
          }
          sendSidebarEvent("ullme_semester_select_event", { semester: semester });
        });
      });
    }

    if (courseSelect) {
      courseSelect.addEventListener("click", function (event) {
        event.stopPropagation();
        closeUserSettings();
        var previousCourse = courseSelect.getAttribute("data-value") || "";
        toggleSidebarMenu(courseSelect, function (courseid) {
          if (teacherWorkspaceDirty() && !window.confirm("Discard your unsaved changes?")) {
            setSidebarValue(courseSelect, previousCourse);
            return;
          }
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
      if (byId("ullme_change_approval_overlay")) {
        return;
      }
      if (byId("ullme_tutor_create_dialog")) {
        closeTutorCreateDialog();
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

    if (studioNav) {
      studioNav.addEventListener("click", function (event) {
        var item = event.target.closest(".ullme-studio-nav-item");
        if (!item || !studioNav.contains(item)) return;
        var view = item.getAttribute("data-studio-view");
        if (view) activateStudioView(view);
      });
    }

    if (studioUploadButton) {
      studioUploadButton.addEventListener("click", function () {
        openMaterialUpload(currentMaterialDestination());
      });
    }

    if (aiPaneToggle) {
      aiPaneToggle.addEventListener("click", function () {
        var appElement = byId("ullme_app");
        if (!appElement) return;
        var collapsed = appElement.classList.toggle("ullme-ai-pane-collapsed");
        aiPaneToggle.setAttribute(
          "aria-label",
          collapsed ? "Expand AI pane" : "Collapse AI pane"
        );
        aiPaneToggle.title = collapsed ? "Expand AI pane" : "Collapse AI pane";
      });
    }

    if (materialPanel) {
      materialPanel.addEventListener("click", function (event) {
        var toggle = event.target.closest(".ullme-material-view-button");
        if (!toggle) return;
        state.materialView = toggle.getAttribute("data-material-view") || "materials";
        materialPanel.classList.toggle("ullme-material-show-files", state.materialView === "files");
        Array.prototype.forEach.call(
          materialPanel.querySelectorAll(".ullme-material-view-button"),
          function (button) {
            button.classList.toggle("ullme-material-view-button-active", button === toggle);
          }
        );
      });
    }

    if (courseFileBack) {
      courseFileBack.addEventListener("click", function () {
        if (courseFileDirty() && !window.confirm("Discard your unsaved changes?")) return;
        activateStudioView(state.previousStudioView || "materials");
      });
    }
    if (courseFileSave) courseFileSave.addEventListener("click", saveCourseFile);
    if (courseFileEditor) {
      courseFileEditor.addEventListener("input", updateCourseFileDirtyState);
      courseFileEditor.addEventListener("keydown", function (event) {
        if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") {
          event.preventDefault();
          saveCourseFile();
        }
        if (event.key === "Tab") {
          event.preventDefault();
          var start = courseFileEditor.selectionStart;
          var end = courseFileEditor.selectionEnd;
          courseFileEditor.setRangeText("  ", start, end, "end");
          courseFileEditor.dispatchEvent(new Event("input", { bubbles: true }));
        }
      });
    }

    if (skillsButton) {
      skillsButton.addEventListener("click", function () {
        openCatalogDialog("skills");
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
    Array.prototype.forEach.call(editHistoryControls, function (controls) {
      controls.addEventListener("click", function (event) {
        var button = event.target.closest("[data-edit-history-direction]");
        if (!button || button.disabled) return;
        button.disabled = true;
        sendSidebarEvent("ullme_edit_history_event", {
          scope: controls.getAttribute("data-edit-history-scope"),
          direction: button.getAttribute("data-edit-history-direction")
        });
      });
    });

    if (materialUploadButton) {
      materialUploadButton.addEventListener("click", function () {
        openMaterialUpload(currentMaterialDestination());
      });
    }
    if (materialInlineUpload) {
      materialInlineUpload.addEventListener("click", function () {
        openMaterialUpload(currentMaterialDestination());
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
    if (window.ullmeMaterialInteractions) {
      state.materialInteractions = window.ullmeMaterialInteractions.create({
        surface: materialPanel && materialPanel.querySelector(".ullme-material-files"),
        rows: byId("ullme_material_files"),
        getSelectedPaths: selectedMaterialPaths,
        setSelectedPaths: function (paths, render) {
          state.materialSelection = {};
          (paths || []).forEach(function (path) {
            state.materialSelection[path] = true;
          });
          if (render) renderMaterialTree();
        },
        selectionComplete: renderMaterialTree,
        movePaths: moveMaterialPathsTo,
        uploadFiles: queueMaterialFiles,
        currentDestination: function () { return ""; }
      });
    }
    if (materialSortName) {
      materialSortName.addEventListener("click", function () {
        setMaterialSort("name");
      });
    }
    if (materialSortDate) {
      materialSortDate.addEventListener("click", function () {
        setMaterialSort("date");
      });
    }
    if (materialSelectAll) {
      materialSelectAll.addEventListener("click", function () {
        (state.materialTree || []).forEach(function (record) {
          if (record.type === "file") state.materialSelection[record.path] = true;
        });
        renderMaterialTree();
      });
    }
    if (materialClearSelection) {
      materialClearSelection.addEventListener("click", function () {
        state.materialSelection = {};
        renderMaterialTree();
      });
    }
    if (materialApplyOperation) {
      materialApplyOperation.addEventListener("click", applySelectedMaterialOperation);
    }
    if (materialConvert) {
      materialConvert.addEventListener("click", function (event) {
        event.stopPropagation();
        if (state.materialConversionBusy || materialConvert.disabled) return;
        toggleSidebarMenu(materialConvert, convertSelectedMaterials);
      });
    }
    if (materialDeleteSelected) {
      materialDeleteSelected.addEventListener("click", deleteSelectedMaterials);
    }
    if (materialCreateDirectory) {
      materialCreateDirectory.addEventListener("click", createMaterialDirectory);
    }
  }

  function teacherWorkspaceDirty() {
    return courseFileDirty() || definitionWorkspaceDirty();
  }

  function mountIntro(messages) {
    var text = messages.getAttribute("data-intro-text") || "";
    var meta = messages.getAttribute("data-intro-meta") || "";
    var html = messages.getAttribute("data-intro-html") || "";
    if (!text) return;
    appendAssistantMessage({
      id: "ullme_intro_message",
      text: text,
      html: html,
      meta: meta
    });
  }

  function resizeInput(input) {
    chatCommon.resizeInput(input, 38);
  }

  function updateSubmitState() {
    var input = byId("ullme_chat_input");
    var submitButton = byId("ullme_submit_btn");
    if (!input || !submitButton) return;
    var stopping = state.chatBusy && Boolean(state.activeAssistantMessageId);
    submitButton.disabled = stopping
      ? false
      : (input.value.trim().length === 0 && state.uploads.length === 0);
    submitButton.classList.toggle("ullme-submit-stop", stopping);
    submitButton.setAttribute(
      "aria-label",
      stopping ? "Stop response" : "Submit chat"
    );
    submitButton.title = stopping ? "Stop response" : "Send message";
    submitButton.innerHTML = stopping ? icons.stop : state.submitButtonHtml;
  }

  function submitChat() {
    var input = byId("ullme_chat_input");
    var modelSelect = byId("ullme_model_select");
    if (!input || state.chatBusy) return;

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
      context: {
        studio_view: state.studioView,
        course_file: state.courseFile && state.studioView === "file"
          ? state.courseFile.path
          : "",
        courseid: (byId("ullme_course_select") || {}).getAttribute
          ? byId("ullme_course_select").getAttribute("data-value")
          : ""
      },
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

    state.chatBusy = true;
    startChatWatchdog(assistantMessageId);
    appendUserMessage({
      id: clientMessageId,
      text: text,
      uploads: uploads
    });
    appendAssistantMessage({
      id: assistantMessageId,
      text: "Thinking...",
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

  function startInstanceBuilder(options) {
    options = options || {};
    if (state.chatBusy) {
      window.alert("Stop or wait for the current assistant response first.");
      return;
    }
    var tutorid = String(options.tutorid || "");
    if (!tutorid) return;
    var guidance = String(options.guidance || "").trim();
    var modelSelect = byId("ullme_model_select");
    var clientMessageId = nextId("user");
    var assistantMessageId = nextId("assistant");
    var displayText = "Preparing the complete instance-builder prompt for " +
      String(options.label || tutorid) +
      (guidance ? "\n\n" + guidance : "");
    var payload = {
      id: "ullme_submit_chat",
      clientMessageId: clientMessageId,
      assistantMessageId: assistantMessageId,
      text: guidance,
      model: modelSelect ? modelSelect.value : null,
      skillid: null,
      context: {
        studio_view: "ai-tutors",
        course_file: "",
        courseid: (byId("ullme_course_select") || {}).getAttribute
          ? byId("ullme_course_select").getAttribute("data-value")
          : ""
      },
      uploads: [],
      instance_builder: {
        tutorid: tutorid,
        guidance: guidance
      },
      nonce: Math.random()
    };
    state.chatBusy = true;
    startChatWatchdog(assistantMessageId);
    appendUserMessage({ id: clientMessageId, text: displayText, uploads: [] });
    appendAssistantMessage({
      id: assistantMessageId,
      text: "Preparing the instance-builder prompt…",
      thinking: true
    });
    state.assistantRequests[assistantMessageId] = payload;
    updateSubmitState();
    scrollMessagesToBottom();
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

  function clearChatWatchdog(messageId) {
    if (messageId && state.activeAssistantMessageId &&
        messageId !== state.activeAssistantMessageId) return;
    if (state.chatWatchdog) window.clearTimeout(state.chatWatchdog);
    state.chatWatchdog = null;
    state.chatWatchdogPaused = false;
    state.activeAssistantMessageId = "";
  }

  function startChatWatchdog(messageId) {
    if (state.chatWatchdog) window.clearTimeout(state.chatWatchdog);
    state.activeAssistantMessageId = messageId;
    state.chatWatchdogPaused = false;
    state.chatWatchdog = window.setTimeout(function () {
      finishClientChatError(
        messageId,
        "The model did not respond within three minutes. Please check the connection and try again."
      );
    }, 180000);
  }

  function pauseChatWatchdog(messageId) {
    if (state.chatWatchdog) window.clearTimeout(state.chatWatchdog);
    state.chatWatchdog = null;
    state.chatWatchdogPaused = true;
    state.activeAssistantMessageId = messageId;
  }

  function finishClientChatError(messageId, message) {
    receiveAssistantStream(messageId, "", "", "", "", true, message);
  }

  function stopActiveChat() {
    var messageId = state.activeAssistantMessageId;
    if (!messageId) return;
    state.cancelledAssistantRequests[messageId] = true;
    sendSidebarEvent("ullme_cancel_chat_event", {
      assistantMessageId: messageId
    });
    var article = byId(messageId);
    var bubble = article && article.querySelector(".ullme-bubble");
    var messageText = article && article.querySelector(".ullme-message-text");
    var current = messageText ? messageText.textContent : "";
    if (current === "Thinking...") current = "";
    if (article) article.classList.remove("ullme-thinking");
    if (bubble) updateAssistantThinking(bubble, "", "");
    if (messageText) {
      messageText.classList.remove("ullme-message-error");
      if (!current) setAssistantMessageContent(messageText, "Stopped.", "");
    }
    if (bubble && !bubble.querySelector(".ullme-message-actions")) {
      bubble.appendChild(renderAssistantActions(messageId, current || "Stopped."));
    }
    state.chatBusy = false;
    clearChatWatchdog(messageId);
    updateSubmitState();
  }

  function sendSidebarEvent(inputId, payload) {
    chatCommon.sendEvent(inputId, payload);
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

  function activateStudioView(view) {
    var definitionOverlay = byId("ullme_definition_overlay");
    if (definitionOverlay && definitionOverlay.classList.contains("ullme-definition-embedded")) {
      if (definitionWorkspaceDirty() && !window.confirm("Discard your unsaved changes?")) return;
      removeDefinitionWorkspace(true);
    }
    state.studioView = view;
    var titles = {
      usage: "Usage statistics",
      materials: "Materials",
      "ai-tutors": "AI Tutors",
      settings: "Course settings",
      file: "File editor"
    };
    setStudioNavigation(view, titles[view] || "Course studio");
    showCoursePanel(view);
    var upload = byId("ullme_studio_upload_btn");
    if (upload) upload.style.display = view === "materials" ? "" : "none";
    updateAIContext();
  }

  function setStudioNavigation(view, title) {
    var nav = byId("ullme_studio_nav");
    if (nav) {
      Array.prototype.forEach.call(nav.querySelectorAll(".ullme-studio-nav-item"), function (item) {
        item.classList.toggle(
          "ullme-studio-nav-item-active",
          item.getAttribute("data-studio-view") === view
        );
      });
    }
    var titleElement = byId("ullme_studio_title");
    if (titleElement) titleElement.textContent = title || "Course studio";
  }

  function updateAIContext() {
    var studioContext = byId("ullme_studio_context");
    var courseSelect = byId("ullme_course_select");
    var courseid = courseSelect ? courseSelect.getAttribute("data-value") : "";
    if (studioContext) studioContext.textContent = courseid || "Select a course";
  }

  function renderAITutors(tutors) {
    tutors = Array.isArray(tutors) ? tutors : [];
    if (window.ullmeTutors && window.ullmeTutors.update) {
      window.ullmeTutors.update(
        tutors,
        state.aiTutorCatalog,
        state.activeSkill,
        state.courseSkills
      );
    }
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
    title.textContent = isTutorCatalog ? "Add AI Tutor" : "Add Skill";
    subtitle.className = "ullme-catalog-subtitle";
    subtitle.textContent = isTutorCatalog
      ? "Choose a template. uLLMe creates a complete editable copy in this course."
      : "Activate a reusable workflow for your next task.";
    headActions.className = "ullme-catalog-head-actions";
    manage.type = "button";
    manage.className = "ullme-secondary-action";
    manage.textContent = "Manage Skills";
    manage.addEventListener("click", function () {
      closeCatalogDialog();
      requestDefinitionWorkspace("skill");
    });
    close.type = "button";
    close.className = "ullme-icon-button";
    close.setAttribute("aria-label", "Close");
    close.innerHTML = icons.close;
    close.addEventListener("click", closeCatalogDialog);
    list.className = "ullme-catalog-list";
    note.className = "ullme-catalog-note";
    note.textContent = isTutorCatalog
      ? "Templates are never used directly after adding; the course copy is authoritative."
      : "Skills resolve in this order: personal, general, package.";

    heading.appendChild(title);
    heading.appendChild(subtitle);
    head.appendChild(heading);
    if (!isTutorCatalog) headActions.appendChild(manage);
    headActions.appendChild(close);
    head.appendChild(headActions);
    dialog.appendChild(head);

    if (!items.length) {
      var empty = document.createElement("div");
      empty.className = "ullme-feature-empty";
      empty.innerHTML = "<strong>Nothing here yet</strong><span>No reusable templates are available.</span>";
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
    var courseSkill = !isTutor && state.courseSkills.some(function (skill) {
      return skill.skillid === id;
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
      requestDefinitionWorkspace("skill", item);
    });
    action.type = "button";
    action.className = courseSkill
      ? "ullme-secondary-action"
      : "ullme-primary-action";
    action.textContent = isTutor ? "Add" : (courseSkill ? "Activate" : "Add");
    action.addEventListener("click", function () {
      if (isTutor) {
        closeCatalogDialog();
        openTutorCreateDialog(item);
      } else {
        sendSidebarEvent("ullme_skill_activate_event", { skillid: id });
        closeCatalogDialog();
      }
    });

    titleRow.appendChild(title);
    if (!isTutor) titleRow.appendChild(badge);
    body.appendChild(titleRow);
    body.appendChild(description);
    card.appendChild(body);
    if (!isTutor) actions.appendChild(view);
    actions.appendChild(action);
    card.appendChild(actions);
    return card;
  }

  function closeCatalogDialog() {
    var overlay = byId("ullme_catalog_overlay");
    if (overlay) overlay.remove();
  }

  function openTutorCreateDialog(template) {
    closeTutorCreateDialog();
    template = template || {};
    var templateid = template.tutorid || "";
    var overlay = document.createElement("div");
    var dialog = document.createElement("section");
    var head = document.createElement("div");
    var title = document.createElement("div");
    var close = document.createElement("button");
    var description = document.createElement("p");
    var tutorIdField = courseDialogField("Tutor ID", "ullme_new_tutor_id");
    var hint = document.createElement("small");
    var actions = document.createElement("div");
    var cancel = document.createElement("button");
    var create = document.createElement("button");

    overlay.id = "ullme_tutor_create_dialog";
    overlay.className = "ullme-dialog-overlay";
    dialog.className = "ullme-dialog";
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    dialog.setAttribute("aria-label", "Create AI Tutor");
    head.className = "ullme-dialog-head";
    title.className = "ullme-dialog-title";
    title.textContent = "Add AI Tutor";
    close.type = "button";
    close.className = "ullme-icon-button";
    close.innerHTML = icons.close;
    close.setAttribute("aria-label", "Close");
    close.addEventListener("click", closeTutorCreateDialog);
    description.textContent =
      "Template: " + (template.label || templateid) +
      ". Choose the ID for this course copy.";
    tutorIdField.input.value = templateid;
    tutorIdField.input.autocomplete = "off";
    hint.textContent =
      "Start with a letter; use only letters, numbers, underscores, or hyphens.";
    tutorIdField.label.appendChild(hint);
    actions.className = "ullme-dialog-actions";
    cancel.type = "button";
    cancel.className = "ullme-secondary-action";
    cancel.textContent = "Cancel";
    cancel.addEventListener("click", closeTutorCreateDialog);
    create.type = "button";
    create.className = "ullme-primary-action";
    create.textContent = "Add Tutor";
    create.addEventListener("click", function () {
      var tutorid = tutorIdField.input.value.trim();
      if (!/^[A-Za-z][A-Za-z0-9_-]*$/.test(tutorid)) {
        tutorIdField.input.focus();
        return;
      }
      create.disabled = true;
      sendSidebarEvent("ullme_ai_tutor_add_event", {
        templateid: templateid,
        tutorid: tutorid
      });
    });
    overlay.addEventListener("click", function (event) {
      if (event.target === overlay) closeTutorCreateDialog();
    });

    head.appendChild(title);
    head.appendChild(close);
    actions.appendChild(cancel);
    actions.appendChild(create);
    dialog.appendChild(head);
    dialog.appendChild(description);
    dialog.appendChild(tutorIdField.label);
    dialog.appendChild(actions);
    overlay.appendChild(dialog);
    document.body.appendChild(overlay);
    tutorIdField.input.select();
  }

  function closeTutorCreateDialog() {
    var overlay = byId("ullme_tutor_create_dialog");
    if (overlay) overlay.remove();
  }

  function aiTutorAddComplete(result) {
    if (result && result.ok) {
      closeTutorCreateDialog();
      return;
    }
    var create = byId("ullme_tutor_create_dialog");
    create = create && create.querySelector(".ullme-primary-action");
    if (create) create.disabled = false;
    window.alert((result && result.message) || "The AI Tutor could not be added.");
  }

  function requestDefinitionWorkspace(kind, item) {
    if (definitionWorkspaceDirty() && !window.confirm("Discard your unsaved changes?")) return;
    item = item || {};
    sendSidebarEvent("ullme_definition_action_event", {
      action: "open",
      kind: kind,
      definitionid: item.id || item.skillid || "",
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
    var navigation = document.createElement("div");
    var kindTabs = document.createElement("div");
    var picker = document.createElement("select");
    var headerActions = document.createElement("div");
    var importButton = document.createElement("button");
    var create = document.createElement("button");
    var assistantToggle = document.createElement("button");
    var close = document.createElement("button");
    var body = document.createElement("div");
    var editor = document.createElement("main");
    var assistant = document.createElement("aside");
    var appElement = byId("ullme_app");
    var mount = byId("ullme_definition_mount");
    var embedded = Boolean(
      mount && appElement && appElement.classList.contains("ullme-role-teacher")
    );

    overlay.id = "ullme_definition_overlay";
    overlay.className = embedded
      ? "ullme-definition-overlay ullme-definition-embedded"
      : "ullme-definition-overlay";
    workspace.className = "ullme-definition-workspace";
    workspace.classList.toggle(
      "ullme-definition-assistant-open",
      state.definitionAssistantOpen
    );
    workspace.setAttribute("role", embedded ? "region" : "dialog");
    workspace.setAttribute("aria-modal", embedded ? "false" : "true");
    workspace.setAttribute("aria-label", "Definition Workspace");
    header.className = "ullme-definition-header";
    navigation.className = "ullme-definition-navigation";
    kindTabs.className = "ullme-definition-kind-tabs";
    picker.className = "ullme-definition-picker";
    picker.setAttribute("aria-label", "Selected definition");
    headerActions.className = "ullme-definition-header-actions";

    ["skill"].forEach(function (kind) {
      var tab = document.createElement("button");
      tab.type = "button";
      tab.className = "ullme-definition-kind-tab";
      tab.classList.toggle("ullme-definition-kind-tab-active", payload.kind === kind);
      tab.textContent = "Skills";
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
      var input = byId("ullme_definition_import_" + (payload.kind || "skill"));
      if (!input) return;
      input.value = "";
      input.click();
    });
    create.type = "button";
    create.className = "ullme-primary-action";
    create.textContent = "New Skill";
    create.disabled = !payload.can_create;
    create.addEventListener("click", function () {
      openCreateDefinitionDialog(payload.kind || "skill");
    });
    assistantToggle.type = "button";
    assistantToggle.className = "ullme-secondary-action ullme-definition-assistant-toggle";
    assistantToggle.textContent = state.definitionAssistantOpen ? "Close AI" : "AI draft";
    assistantToggle.disabled = !payload.selected;
    assistantToggle.addEventListener("click", function () {
      state.definitionAssistantOpen = !state.definitionAssistantOpen;
      workspace.classList.toggle(
        "ullme-definition-assistant-open",
        state.definitionAssistantOpen
      );
      assistantToggle.textContent = state.definitionAssistantOpen ? "Close AI" : "AI draft";
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

    navigation.appendChild(kindTabs);
    navigation.appendChild(picker);
    headerActions.appendChild(importButton);
    headerActions.appendChild(create);
    headerActions.appendChild(assistantToggle);
    headerActions.appendChild(close);
    header.appendChild(navigation);
    header.appendChild(headerActions);

    body.className = "ullme-definition-body";
    editor.className = "ullme-definition-editor";
    assistant.className = "ullme-definition-assistant";
    renderDefinitionEditor(editor, payload);
    renderDefinitionAssistant(assistant, payload);
    body.appendChild(editor);
    body.appendChild(assistant);
    workspace.appendChild(header);
    workspace.appendChild(body);
    overlay.appendChild(workspace);
    if (embedded) {
      if (state.studioView !== "definitions") state.previousStudioView = state.studioView || "materials";
      state.studioView = "definitions";
      setStudioNavigation("definitions", "Definitions");
      updateAIContext();
      var studioMain = mount.closest(".ullme-studio-main");
      if (studioMain) studioMain.classList.add("ullme-studio-definition-open");
      mount.appendChild(overlay);
    } else {
      document.body.appendChild(overlay);
      close.focus();
    }
  }

  function renderDefinitionSidebar(sidebar, payload) {
    var library = Array.isArray(payload.library) ? payload.library : [];
    var selected = payload.selected || {};
    var entries = library.filter(function (item) {
      return item.kind === payload.kind;
    });
    var sourceOrder = ["personal", "general", "package"];

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
        selected.personal_exists ? "Personal copy" : "Make personal copy",
        "copy-personal",
        selected
      ));
    }
    var download = document.createElement("button");
    download.type = "button";
    download.className = "ullme-secondary-action";
    download.textContent = "Download";
    download.title = "Download Skill ZIP";
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
      remove.textContent = "Delete";
      remove.title = "Delete this copy";
      remove.addEventListener("click", function () {
        var detail = "This removes the Personal copy and falls back to a General or Package definition when available.";
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
    var embedded = Boolean(overlay && overlay.classList.contains("ullme-definition-embedded"));
    if (overlay) overlay.remove();
    var studioMain = byId("ullme_definition_mount");
    studioMain = studioMain ? studioMain.closest(".ullme-studio-main") : null;
    if (studioMain) studioMain.classList.remove("ullme-studio-definition-open");
    closeCreateDefinitionDialog();
    closeDefinitionImportPreview();
    state.definitionWorkspace = null;
    state.definitionOriginalContent = "";
    if (!preserveAssistantState) state.definitionAssistantOpen = false;
    if (embedded && !preserveAssistantState) {
      state.studioView = state.previousStudioView || "materials";
      var titles = {
        usage: "Usage statistics",
        materials: "Materials",
        "ai-tutors": "AI Tutors",
        settings: "Course settings"
      };
      setStudioNavigation(state.studioView, titles[state.studioView] || "Course studio");
      showCoursePanel(state.studioView);
      updateAIContext();
    }
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
    dialog.setAttribute("aria-label", "Create Skill");
    title.className = "ullme-definition-create-title";
    title.textContent = "New Skill";
    idLabel.className = "ullme-definition-create-field";
    idText.textContent = "ID";
    idInput.type = "text";
    idInput.placeholder = "my_skill";
    idInput.autocomplete = "off";
    nameLabel.className = "ullme-definition-create-field";
    nameText.textContent = "Label";
    nameInput.type = "text";
    nameInput.placeholder = "My Skill";
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
        message: instruction,
        model: (byId("ullme_model_select") || {}).value || null
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
    title.textContent = "Import Skill ZIP";
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
    if (window.ullmeTutors && window.ullmeTutors.updateSkill) {
      window.ullmeTutors.updateSkill(state.activeSkill);
    }
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
        coursename: nameField.input.value.trim()
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

  function closeChangeApproval() {
    var overlay = byId("ullme_change_approval_overlay");
    if (overlay) overlay.remove();
  }

  function openChangeApproval(operation) {
    closeChangeApproval();
    operation = operation || {};
    var changes = Array.isArray(operation.changes) ? operation.changes : [];
    var overlay = document.createElement("div");
    var dialog = document.createElement("section");
    var title = document.createElement("div");
    var summary = document.createElement("p");
    var meta = document.createElement("div");
    var list = document.createElement("div");
    var actions = document.createElement("div");
    var reject = document.createElement("button");
    var approve = document.createElement("button");

    overlay.id = "ullme_change_approval_overlay";
    overlay.className = "ullme-dialog-overlay";
    dialog.className = "ullme-change-approval-dialog";
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    dialog.setAttribute("aria-label", "Approve agent change");
    title.className = "ullme-dialog-title";
    title.textContent = "Approve agent change?";
    summary.className = "ullme-change-approval-summary";
    summary.textContent = operation.summary || "The assistant proposes a file change.";
    meta.className = "ullme-change-approval-meta";
    meta.textContent = (operation.action || "change") + (operation.courseid ? " · " + operation.courseid : "");
    list.className = "ullme-change-approval-files";
    changes.forEach(function (change) {
      var row = document.createElement("div");
      var kind = document.createElement("strong");
      var path = document.createElement("code");
      kind.textContent = (change.type || "change").replace(/_/g, " ");
      path.textContent = change.target || "";
      row.appendChild(kind);
      row.appendChild(path);
      list.appendChild(row);
      if (change.preview) {
        var preview = document.createElement("details");
        var previewTitle = document.createElement("summary");
        var compare = document.createElement("div");
        var before = document.createElement("div");
        var after = document.createElement("div");
        var beforeLabel = document.createElement("span");
        var afterLabel = document.createElement("span");
        var beforeCode = document.createElement("pre");
        var afterCode = document.createElement("pre");
        preview.className = "ullme-change-preview";
        previewTitle.textContent = "Review YAML";
        compare.className = "ullme-change-preview-compare";
        beforeLabel.textContent = "Before";
        afterLabel.textContent = "After";
        beforeCode.textContent = change.preview.before || "(new file)";
        afterCode.textContent = change.preview.after || "";
        before.appendChild(beforeLabel);
        before.appendChild(beforeCode);
        after.appendChild(afterLabel);
        after.appendChild(afterCode);
        compare.appendChild(before);
        compare.appendChild(after);
        preview.appendChild(previewTitle);
        preview.appendChild(compare);
        list.appendChild(preview);
      }
      if (Array.isArray(change.warnings) && change.warnings.length) {
        var warning = document.createElement("div");
        warning.className = "ullme-change-warning";
        warning.textContent = change.warnings.join(" ");
        list.appendChild(warning);
      }
    });
    actions.className = "ullme-dialog-actions";
    reject.type = "button";
    reject.className = "ullme-secondary-action";
    reject.textContent = "Reject";
    approve.type = "button";
    approve.className = "ullme-primary-action";
    approve.textContent = "Approve once";
    function decide(approved) {
      reject.disabled = true;
      approve.disabled = true;
      sendSidebarEvent("ullme_change_approval_event", {
        operation_id: operation.id,
        approved: approved
      });
    }
    reject.addEventListener("click", function () { decide(false); });
    approve.addEventListener("click", function () { decide(true); });
    actions.appendChild(reject);
    actions.appendChild(approve);
    dialog.appendChild(title);
    dialog.appendChild(summary);
    dialog.appendChild(meta);
    dialog.appendChild(list);
    dialog.appendChild(actions);
    overlay.appendChild(dialog);
    document.body.appendChild(overlay);
    approve.focus();
  }

  function changeApprovalComplete(result) {
    closeChangeApproval();
    if (result && result.status === "error") {
      window.alert(result.message || "The change could not be completed.");
    }
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
      coursename: name ? name.value.trim() : ""
    };
  }

  function fillCourseSettings(course) {
    course = course || {};
    setInputValue("ullme_settings_courseid", course.courseid || "");
    setInputValue("ullme_settings_coursename", course.coursename || "");
  }

  function fillEditHistoryControls(scope, history) {
    history = history || {};
    var controls = document.querySelector(
      '.ullme-edit-history-controls[data-edit-history-scope="' + scope + '"]'
    );
    if (!controls) return;
    var undo = controls.querySelector('[data-edit-history-direction="undo"]');
    var redo = controls.querySelector('[data-edit-history-direction="redo"]');
    if (undo) undo.disabled = !history.can_undo;
    if (redo) redo.disabled = !history.can_redo;
  }

  function setInputValue(id, value) {
    var input = byId(id);
    if (input) input.value = value || "";
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
    return materialDestinationCategory(currentMaterialDestination());
  }

  function materialInputForCategory(category) {
    return byId("ullme_material_upload_" + category);
  }

  function materialDestinationCategory(destination) {
    destination = destination == null ? "" : String(destination);
    return destination ? destination.split("/")[0] : "root";
  }

  function currentMaterialDestination() {
    var destination = byId("ullme_material_destination");
    if (destination && destination.options && destination.options.length) {
      return destination.value || "";
    }
    return state.materialUploadDestination || "";
  }

  function prepareMaterialUpload(destination) {
    destination = destination == null ? "" : String(destination);
    var category = materialDestinationCategory(destination);
    var input = materialInputForCategory(category);
    if (!input) return null;
    state.materialUploadDestination = destination;
    sendSidebarEvent("ullme_material_upload_destination_event", {
      path: destination
    });
    return input;
  }

  function openMaterialUpload(destination) {
    var input = prepareMaterialUpload(destination);
    if (input) input.click();
  }

  function folderUploadFile(file, index) {
    var extension = "";
    var dot = file.name.lastIndexOf(".");
    if (dot > 0) extension = file.name.slice(dot).replace(/[^A-Za-z0-9.]/g, "");
    var name = "ullme_folder_" + Date.now() + "_" + index + extension;
    return new File([file], name, {
      type: file.type,
      lastModified: file.lastModified
    });
  }

  function queueMaterialFiles(files, destination, relativePaths, directories) {
    destination = destination == null ? "" : String(destination);
    var category = materialDestinationCategory(destination);
    var input = materialInputForCategory(category);
    directories = Array.isArray(directories) ? directories : [];
    var isFolderUpload = Array.isArray(relativePaths);
    if (!input || (!files.length && !directories.length) ||
        typeof DataTransfer === "undefined") return;

    var uploadFiles = files;
    var tree = null;
    if (isFolderUpload) {
      var filePaths = {};
      uploadFiles = files.map(function (file, index) {
        var wrapped = folderUploadFile(file, index);
        filePaths[wrapped.name] = relativePaths[index] || file.name;
        return wrapped;
      });
      tree = {
        files: filePaths,
        directories: directories
      };
    }

    state.materialUploadDestination = destination;
    state.pendingMaterialDrop = {
      destination: destination,
      inputId: input.id,
      files: uploadFiles
    };
    sendSidebarEvent("ullme_material_upload_destination_event", {
      path: destination,
      tree: tree
    });
  }

  function materialUploadDestinationReady(result) {
    result = result || {};
    var pending = state.pendingMaterialDrop;
    if (!pending || pending.destination !== result.path) return;
    state.pendingMaterialDrop = null;
    if (!result.ok) {
      window.alert(result.message || "The upload folder is no longer available.");
      return;
    }
    var input = byId(pending.inputId);
    if (!input) return;
    if (!pending.files.length) return;
    var transfer = new DataTransfer();
    pending.files.forEach(function (file) {
      transfer.items.add(file);
    });
    input.files = transfer.files;
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function courseFileRecord(path) {
    return (Array.isArray(state.courseFiles) ? state.courseFiles : []).find(function (record) {
      return record.path === path;
    });
  }

  function requestCourseFile(path) {
    var record = courseFileRecord(path);
    if (record && !record.text) return;
    sendSidebarEvent("ullme_course_file_open_event", { path: path });
  }

  function renderCourseFileTree(files) {
    var tree = byId("ullme_course_file_tree");
    if (!tree) return;
    tree.innerHTML = "";
    files = Array.isArray(files) ? files : [];
    if (!files.length) {
      tree.textContent = "No course files";
      return;
    }
    var groups = {};
    files.forEach(function (record) {
      var directory = record.directory && record.directory !== "." ? record.directory : "Course root";
      if (!groups[directory]) groups[directory] = [];
      groups[directory].push(record);
    });
    Object.keys(groups).sort().forEach(function (directory) {
      var group = document.createElement("section");
      var title = document.createElement("div");
      title.className = "ullme-file-directory-title";
      title.textContent = directory;
      group.className = "ullme-file-directory";
      group.appendChild(title);
      groups[directory].forEach(function (record) {
        var row = document.createElement("div");
        var open = document.createElement("button");
        var meta = document.createElement("span");
        row.className = "ullme-file-tree-row";
        open.type = "button";
        open.className = "ullme-file-tree-open";
        open.textContent = record.name || record.path;
        open.disabled = !record.text;
        open.title = record.text ? "Open " + record.path : "Binary file";
        open.addEventListener("click", function () { requestCourseFile(record.path); });
        meta.className = "ullme-file-tree-meta";
        meta.textContent = record.text
          ? (record.editable ? "Text" : "View only")
          : (record.extension || "Binary").toUpperCase();
        row.appendChild(open);
        row.appendChild(meta);
        group.appendChild(row);
      });
      tree.appendChild(group);
    });
  }

  function courseFileDirty() {
    var editor = byId("ullme_course_file_editor");
    return Boolean(
      state.courseFile &&
      editor &&
      editor.value !== state.courseFileOriginalContent
    );
  }

  function updateCourseFileDirtyState() {
    var status = byId("ullme_course_file_status");
    var save = byId("ullme_course_file_save");
    var dirty = courseFileDirty();
    if (save) save.disabled = !dirty || !state.courseFile || !state.courseFile.editable;
    if (status && state.courseFile) {
      status.className = "";
      status.textContent = dirty ? "Unsaved changes" : (state.courseFile.notice || "Saved");
    }
  }

  function openCourseFile(payload) {
    payload = payload || {};
    if (courseFileDirty() && state.courseFile && state.courseFile.path !== payload.path &&
        !window.confirm("Discard your unsaved changes?")) return;
    if (state.studioView !== "file") state.previousStudioView = state.studioView || "materials";
    state.courseFile = payload;
    state.courseFileOriginalContent = payload.content || "";
    var name = byId("ullme_course_file_name");
    var path = byId("ullme_course_file_path");
    var editor = byId("ullme_course_file_editor");
    var status = byId("ullme_course_file_status");
    if (name) name.textContent = payload.name || "File";
    if (path) path.textContent = payload.path || "";
    if (editor) {
      editor.value = payload.content || "";
      editor.readOnly = !payload.editable;
    }
    if (status) {
      status.className = payload.error
        ? "ullme-course-file-status-error"
        : (payload.notice ? "ullme-course-file-status-success" : "");
      status.textContent = payload.error || payload.notice ||
        (payload.editable ? "Ready to edit" : "View only");
    }
    activateStudioView("file");
    updateCourseFileDirtyState();
    if (editor) editor.focus();
  }

  function saveCourseFile() {
    var editor = byId("ullme_course_file_editor");
    var save = byId("ullme_course_file_save");
    var status = byId("ullme_course_file_status");
    if (!state.courseFile || !state.courseFile.editable || !editor || !courseFileDirty()) return;
    if (save) save.disabled = true;
    if (status) {
      status.className = "";
      status.textContent = "Validating and saving…";
    }
    sendSidebarEvent("ullme_course_file_save_event", {
      path: state.courseFile.path,
      content: editor.value,
      base_hash: state.courseFile.base_hash
    });
  }

  function courseFileSaveComplete(result) {
    result = result || {};
    var status = byId("ullme_course_file_status");
    var save = byId("ullme_course_file_save");
    if (status) {
      status.className = "ullme-course-file-status-error";
      status.textContent = result.message || "The file could not be saved.";
    }
    if (save) save.disabled = false;
  }

  function courseFileError(message) {
    window.alert(message || "The file could not be opened.");
  }

  function renderMaterialFiles(material, category) {
    renderMaterialTree();
  }

  function materialTimestamp(value) {
    if (!value) return 0;
    var normalized = String(value).replace(/([+-]\d\d)(\d\d)$/, "$1:$2");
    var timestamp = Date.parse(normalized);
    return Number.isFinite(timestamp) ? timestamp : 0;
  }

  function materialDateLabel(value) {
    var timestamp = materialTimestamp(value);
    if (!timestamp) return "";
    return new Date(timestamp).toLocaleString([], {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit"
    });
  }

  function setMaterialSort(field) {
    field = field === "date" ? "date" : "name";
    if (state.materialSort === field) {
      state.materialSortDirection =
        state.materialSortDirection === "asc" ? "desc" : "asc";
    } else {
      state.materialSort = field;
      state.materialSortDirection = field === "date" ? "desc" : "asc";
    }
    renderMaterialTree();
  }

  function updateMaterialSortHeadings() {
    ["name", "date"].forEach(function (field) {
      var button = byId("ullme_material_sort_" + field);
      if (!button) return;
      var active = state.materialSort === field;
      var arrow = button.querySelector(".ullme-material-sort-arrow");
      button.classList.toggle("ullme-material-sort-heading-active", active);
      button.setAttribute(
        "aria-sort",
        active
          ? (state.materialSortDirection === "asc" ? "ascending" : "descending")
          : "none"
      );
      if (arrow) {
        arrow.textContent = active
          ? (state.materialSortDirection === "asc" ? "\u2191" : "\u2193")
          : "";
      }
    });
  }

  function materialChildrenByParent(records) {
    var children = {};
    records.forEach(function (record) {
      var parent = record.parent || "";
      if (!children[parent]) children[parent] = [];
      children[parent].push(record);
    });
    Object.keys(children).forEach(function (parent) {
      children[parent].sort(function (left, right) {
        if (left.type !== right.type) return left.type === "directory" ? -1 : 1;
        var direction = state.materialSortDirection === "desc" ? -1 : 1;
        if (state.materialSort === "date") {
          var dateDifference =
            materialTimestamp(left.modified) - materialTimestamp(right.modified);
          if (dateDifference) return dateDifference * direction;
        }
        return String(left.name).localeCompare(String(right.name), undefined, {
          numeric: true,
          sensitivity: "base"
        }) * direction;
      });
    });
    return children;
  }

  function selectedMaterialPaths() {
    return Object.keys(state.materialSelection || {}).filter(function (path) {
      return Boolean(state.materialSelection[path]);
    });
  }

  function materialDescendantFiles(folderPath) {
    var prefix = folderPath + "/";
    return (state.materialTree || []).filter(function (record) {
      return record.type === "file" && record.path.indexOf(prefix) === 0;
    }).map(function (record) {
      return record.path;
    });
  }

  function materialEmptyDirectoryPaths(records, children) {
    var empty = {};
    records.forEach(function (record) {
      if (record.type === "directory" && !(children[record.path] || []).length) {
        empty[record.path] = true;
      }
    });
    return empty;
  }

  function selectedMaterialFilePaths() {
    var files = {};
    (state.materialTree || []).forEach(function (record) {
      if (record.type === "file") files[record.path] = true;
    });
    return selectedMaterialPaths().filter(function (path) {
      return Boolean(files[path]);
    });
  }

  function updateMaterialBatchControls() {
    var selected = selectedMaterialPaths();
    var selectedFiles = selectedMaterialFilePaths();
    var count = byId("ullme_material_selection_count");
    var apply = byId("ullme_material_apply_operation");
    var convert = byId("ullme_material_convert");
    var remove = byId("ullme_material_delete_selected");
    var batch = byId("ullme_material_batch_bar");
    if (count) count.textContent = selected.length + " selected";
    if (apply) apply.disabled = selectedFiles.length === 0;
    if (convert) convert.disabled = selectedFiles.length === 0 || state.materialConversionBusy;
    if (remove) remove.disabled = selected.length === 0;
    if (batch) {
      batch.classList.toggle("ullme-material-batch-bar-active", selected.length > 0);
    }
  }

  function updateMaterialDestinations(records) {
    var select = byId("ullme_material_destination");
    if (!select) return;
    var previous = select.options && select.options.length
      ? select.value
      : state.materialUploadDestination || "";
    var directories = records.filter(function (record) {
      return record.type === "directory";
    }).sort(function (left, right) {
      return left.path.localeCompare(right.path, undefined, {
        numeric: true,
        sensitivity: "base"
      });
    });
    select.innerHTML = "";
    var root = document.createElement("option");
    root.value = "";
    root.textContent = "Materials root";
    select.appendChild(root);
    directories.forEach(function (record) {
      var option = document.createElement("option");
      option.value = record.path;
      option.textContent = record.path;
      select.appendChild(option);
    });
    var available = previous === "" || directories.some(function (record) {
      return record.path === previous;
    });
    if (available) select.value = previous;
    state.materialUploadDestination = select.value || "";
  }

  function moveMaterialPathsTo(paths, destination) {
    paths = (paths || []).filter(function (path) {
      var separator = path.lastIndexOf("/");
      var parent = separator >= 0 ? path.slice(0, separator) : "";
      return parent !== destination;
    });
    if (!paths.length) return;
    sendSidebarEvent("ullme_material_operation_event", {
      action: "move",
      paths: paths,
      destination: destination
    });
  }

  function appendMaterialTreeRows(container, children, parent, depth) {
    (children[parent] || []).forEach(function (record) {
      var isDirectory = record.type === "directory";
      var descendants = isDirectory ? materialDescendantFiles(record.path) : [];
      var directChildren = isDirectory ? (children[record.path] || []) : [];
      var selectableEmptyDirectory = isDirectory && directChildren.length === 0;
      var affectedSelection = selectableEmptyDirectory ? [record.path] : descendants;
      var selectedDescendants = descendants.filter(function (path) {
        return Boolean(state.materialSelection[path]);
      });
      var row = document.createElement("div");
      var toggle = document.createElement("button");
      var checkbox = document.createElement("input");
      var icon = document.createElement("span");
      var name = document.createElement("button");
      var date = document.createElement("span");
      row.className = "ullme-material-tree-row ullme-material-tree-" + record.type;
      row.setAttribute("role", "treeitem");
      row.setAttribute("data-path", record.path);
      row.setAttribute("data-parent", record.parent || "");
      row.setAttribute("data-type", record.type);
      row.style.setProperty("--ullme-tree-depth", depth);
      if (isDirectory) {
        row.setAttribute("aria-label", "Folder " + record.path + ", drop files here");
      }

      toggle.type = "button";
      toggle.className = "ullme-material-tree-toggle";
      if (isDirectory) {
        var expanded = state.materialExpanded[record.path] !== false;
        toggle.textContent = expanded ? "\u25be" : "\u25b8";
        toggle.setAttribute("aria-label", (expanded ? "Collapse " : "Expand ") + record.path);
        toggle.addEventListener("click", function () {
          state.materialExpanded[record.path] = !expanded;
          renderMaterialTree();
        });
      } else {
        toggle.disabled = true;
        toggle.textContent = "";
      }

      checkbox.type = "checkbox";
      checkbox.className = "ullme-material-tree-check";
      checkbox.setAttribute("aria-label", "Select " + record.path);
      checkbox.checked = isDirectory
        ? (selectableEmptyDirectory
          ? Boolean(state.materialSelection[record.path])
          : descendants.length > 0 && selectedDescendants.length === descendants.length)
        : Boolean(state.materialSelection[record.path]);
      checkbox.indeterminate = isDirectory && !selectableEmptyDirectory &&
        selectedDescendants.length > 0 &&
        selectedDescendants.length < descendants.length;
      checkbox.disabled = isDirectory && affectedSelection.length === 0;
      checkbox.addEventListener("change", function () {
        var affected = isDirectory ? affectedSelection : [record.path];
        affected.forEach(function (path) {
          if (checkbox.checked) state.materialSelection[path] = true;
          else delete state.materialSelection[path];
        });
        renderMaterialTree();
      });

      icon.className = "ullme-material-tree-icon";
      icon.textContent = isDirectory ? "\u25a0" : "\u2022";
      name.type = "button";
      name.className = "ullme-material-tree-name";
      name.textContent = record.name;
      name.title = record.path;
      if (isDirectory) {
        name.addEventListener("click", function () {
          state.materialExpanded[record.path] =
            state.materialExpanded[record.path] === false;
          renderMaterialTree();
        });
      } else {
        name.draggable = true;
        var fullPath = "materials/" + record.path;
        var courseRecord = courseFileRecord(fullPath);
        var openable = Boolean(courseRecord && courseRecord.text);
        name.title = openable
          ? "Open " + record.path
          : record.path + " (binary file)";
        if (openable) {
          name.addEventListener("click", function () {
            requestCourseFile(fullPath);
          });
        } else {
          name.classList.add("ullme-material-tree-name-unavailable");
          name.setAttribute("aria-disabled", "true");
        }
      }

      date.className = "ullme-material-tree-date";
      date.textContent = materialDateLabel(record.modified);
      row.appendChild(toggle);
      row.appendChild(checkbox);
      row.appendChild(icon);
      row.appendChild(name);
      row.appendChild(date);
      container.appendChild(row);

      if (isDirectory && state.materialExpanded[record.path] !== false) {
        appendMaterialTreeRows(container, children, record.path, depth + 1);
      }
    });
  }

  function renderMaterialTree() {
    var list = byId("ullme_material_files");
    if (!list) return;
    var records = Array.isArray(state.materialTree) ? state.materialTree : [];
    var children = materialChildrenByParent(records);
    var emptyDirectories = materialEmptyDirectoryPaths(records, children);
    var validFiles = {};
    records.forEach(function (record) {
      if (record.type === "file") validFiles[record.path] = true;
    });
    Object.keys(state.materialSelection || {}).forEach(function (path) {
      if (!validFiles[path] && !emptyDirectories[path]) {
        delete state.materialSelection[path];
      }
    });
    list.innerHTML = "";
    updateMaterialDestinations(records);
    updateMaterialSortHeadings();

    if (!records.length) {
      var empty = document.createElement("div");
      empty.className = "ullme-material-empty";
      empty.textContent = "No material folders or files";
      list.appendChild(empty);
      updateMaterialBatchControls();
      return;
    }
    appendMaterialTreeRows(list, children, "", 0);
    updateMaterialBatchControls();
  }

  function applySelectedMaterialOperation() {
    var paths = selectedMaterialFilePaths();
    var operation = byId("ullme_material_operation");
    var destination = byId("ullme_material_destination");
    if (!paths.length || !operation || !destination) return;
    sendSidebarEvent("ullme_material_operation_event", {
      action: operation.value,
      paths: paths,
      destination: destination.value
    });
  }

  function deleteSelectedMaterials() {
    var paths = selectedMaterialPaths();
    if (!paths.length) return;
    if (!window.confirm(
      "Permanently delete " + paths.length + " selected material item" +
      (paths.length === 1 ? "?" : "s?")
    )) return;
    sendSidebarEvent("ullme_material_operation_event", {
      action: "delete",
      paths: paths
    });
  }

  function setMaterialConversionBusy(busy) {
    var button = byId("ullme_material_convert");
    state.materialConversionBusy = Boolean(busy);
    if (button) {
      button.innerHTML = busy
        ? "Converting\u2026"
        : 'Convert<span class="ullme-sidebar-value-arrow" aria-hidden="true">&#9662;</span>';
      button.setAttribute("aria-expanded", "false");
    }
    updateMaterialBatchControls();
  }

  function convertSelectedMaterials(mode) {
    var paths = selectedMaterialFilePaths();
    if (!paths.length || state.materialConversionBusy) return;
    setMaterialConversionBusy(true);
    sendSidebarEvent("ullme_material_convert_event", {
      mode: mode,
      paths: paths
    });
  }

  function createMaterialDirectory() {
    var destination = byId("ullme_material_destination");
    if (!destination) return;
    var parent = destination.value || "";
    var parentLabel = parent || "Materials root";
    var name = window.prompt("Name for the new folder inside " + parentLabel + ":");
    if (name == null || !String(name).trim()) return;
    name = String(name).trim();
    sendSidebarEvent("ullme_material_create_directory_event", {
      path: parent ? parent + "/" + name : name
    });
  }

  function materialOperationComplete(result) {
    result = result || {};
    if (!result.ok) {
      window.alert(result.message || "The material operation failed.");
      return;
    }
    state.materialSelection = {};
    renderMaterialTree();
  }

  function materialConversionComplete(result) {
    result = result || {};
    setMaterialConversionBusy(false);
    if (!result.ok) {
      window.alert(result.message || "The document conversion failed.");
      return;
    }
    state.materialSelection = {};
    renderMaterialTree();
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
        if (button.getAttribute("data-action-menu") !== "true") {
          setSidebarValue(button, value);
        }
        closeSidebarMenus();
        onSelect(value);
      });
      menu.appendChild(item);
    });

    button.parentNode.appendChild(menu);
    button.classList.add("ullme-sidebar-value-open");
    button.setAttribute("aria-expanded", "true");
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
      button.setAttribute("aria-expanded", "false");
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
    if (kind === "conversion") {
      return {
        "docx-md": "docx -> md",
        "tex-md": "tex -> md",
        "all-md": "all -> md",
        "pdf-txt": "pdf -> txt",
        "all-md-txt": "all -> md, txt",
        "all-overwrite": "all -> overwrite"
      }[value] || value;
    }
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

  function replaceUserMessage(messageId, text) {
    var article = byId(messageId);
    if (!article) return;
    var stack = article.querySelector(".ullme-user-stack");
    var bubble = stack && stack.querySelector(".ullme-bubble");
    if (!stack || !bubble) return;
    bubble.innerHTML = "";
    bubble.appendChild(textBlock(text || ""));
    var actions = stack.querySelector(".ullme-user-actions");
    if (actions) actions.remove();
    stack.appendChild(renderUserActions(text || ""));
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
    if (message.thinkingText) {
      updateAssistantThinking(
        bubble,
        message.thinkingText,
        message.thinkingHtml || ""
      );
    }
    setAssistantMessageContent(text, message.text || "", message.html || "");
    bubble.appendChild(text);

    if (!message.thinking) {
      bubble.appendChild(renderAssistantActions(message.id, message.text || ""));
    }

    article.appendChild(bubble);
    messages.appendChild(article);
    if (!message.thinking) {
      typesetMath(text);
      var completedThinking = bubble.querySelector(".ullme-message-thinking-text");
      if (completedThinking) typesetMath(completedThinking);
    }
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

  function setAssistantMessageContent(element, text, html) {
    chatCommon.setMessageContent(element, text, html);
  }

  function updateAssistantThinking(bubble, thinking, html) {
    var details = bubble.querySelector(".ullme-message-thinking");
    if (!thinking) {
      if (details) details.remove();
      return;
    }
    if (!details) {
      details = document.createElement("details");
      details.className = "ullme-message-thinking";
      var summary = document.createElement("summary");
      var content = document.createElement("div");
      summary.textContent = "Thinking";
      content.className = "ullme-message-thinking-text";
      details.appendChild(summary);
      details.appendChild(content);
      var response = bubble.querySelector(".ullme-message-text");
      bubble.insertBefore(details, response || null);
    }
    setAssistantMessageContent(
      details.querySelector(".ullme-message-thinking-text"),
      thinking,
      html
    );
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
    if (!payload || !article || state.chatBusy) return;

    var messageText = article.querySelector(".ullme-message-text");
    var actions = article.querySelector(".ullme-message-actions");
    var meta = article.querySelector(".ullme-message-meta");
    var bubble = article.querySelector(".ullme-bubble");

    article.classList.add("ullme-thinking");
    delete state.cancelledAssistantRequests[messageId];
    state.chatBusy = true;
    startChatWatchdog(messageId);
    updateSubmitState();
    if (meta) meta.remove();
    if (actions) actions.remove();
    if (bubble) updateAssistantThinking(bubble, "", "");
    if (messageText) setAssistantMessageContent(messageText, "Thinking...", "");

    payload.nonce = Math.random();
    sendChatEvent(payload);
  }

  function addLocalUploads(files) {
    chatCommon.addLocalUploads(
      files,
      state,
      nextId,
      renderUploadPreview,
      function () {
        updateComposerUploadClass();
      }
    );
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
    chatCommon.renderUploadPreview(
      state,
      icons.close,
      updateSubmitState,
      updateComposerUploadClass
    );
  }

  function clearUploads() {
    chatCommon.clearUploads(state, renderUploadPreview);
  }

  function updateComposerUploadClass() {
    var preview = byId("ullme_upload_preview");
    var composer = preview ? preview.closest(".ullme-composer") : null;
    if (composer) composer.classList.toggle("ullme-composer-has-uploads", state.uploads.length > 0);
  }

  function receiveStoredUploads(records) {
    chatCommon.receiveStoredUploads(state, records);
  }

  function receiveAssistantMessage(messageId, text, html) {
    if (state.cancelledAssistantRequests[messageId]) return;
    var article = byId(messageId);
    if (!article) {
      appendAssistantMessage({
        id: messageId || nextId("assistant"),
        text: text || "",
        html: html || "",
        meta: ""
      });
      state.chatBusy = false;
      clearChatWatchdog(messageId);
      updateSubmitState();
      return;
    }

    article.classList.remove("ullme-thinking");
    var meta = article.querySelector(".ullme-message-meta");
    var messageText = article.querySelector(".ullme-message-text");
    var bubble = article.querySelector(".ullme-bubble");

    if (meta) meta.remove();
    if (bubble) updateAssistantThinking(bubble, "", "");
    if (messageText) setAssistantMessageContent(messageText, text || "", html || "");
    typesetMath(messageText);
    if (bubble && !bubble.querySelector(".ullme-message-actions")) {
      bubble.appendChild(renderAssistantActions(messageId, text || ""));
    }
    state.chatBusy = false;
    clearChatWatchdog(messageId);
    updateSubmitState();
  }

  function receiveAssistantStream(messageId, text, html, thinking,
                                  thinkingHtml, done, error, activity,
                                  waitingForUser) {
    if (state.cancelledAssistantRequests[messageId]) return;
    var messages = byId("ullme_chat_messages");
    var previousScrollTop = messages ? messages.scrollTop : 0;
    var article = byId(messageId);
    if (!article) {
      appendAssistantMessage({
        id: messageId || nextId("assistant"),
        text: text || (error || ""),
        html: text ? (html || "") : "",
        thinkingText: thinking || "",
        thinkingHtml: thinkingHtml || "",
        meta: activity || ((error && (text || thinking)) ? error : ""),
        thinking: !done
      });
      if (done) {
        state.chatBusy = false;
        clearChatWatchdog(messageId);
        updateSubmitState();
      } else if (waitingForUser) {
        pauseChatWatchdog(messageId);
      } else {
        startChatWatchdog(messageId);
      }
      if (messages) messages.scrollTop = previousScrollTop;
      return;
    }

    var bubble = article.querySelector(".ullme-bubble");
    var messageText = article.querySelector(".ullme-message-text");
    var meta = article.querySelector(".ullme-message-meta");
    if (meta && meta.dataset && meta.dataset.toolActivity === "true" && !activity) {
      meta.remove();
      meta = null;
    }
    if ((text || thinking) && meta && meta.textContent === "Thinking") {
      meta.remove();
      meta = null;
    }
    if (bubble) updateAssistantThinking(bubble, thinking || "", thinkingHtml || "");
    var thinkingTextElement = bubble
      ? bubble.querySelector(".ullme-message-thinking-text")
      : null;
    if (messageText) {
      messageText.classList.toggle(
        "ullme-message-error",
        Boolean(error && !text && !thinking)
      );
      setAssistantMessageContent(
        messageText,
        text || ((!thinking && error) ? error : ""),
        text ? (html || "") : ""
      );
    }
    if (text || thinking || done) article.classList.remove("ullme-thinking");

    if (error && bubble && (text || thinking)) {
      if (!meta) {
        meta = document.createElement("div");
        meta.className = "ullme-message-meta ullme-message-error";
        bubble.insertBefore(meta, bubble.firstChild);
      }
      meta.textContent = error;
    } else if (error && meta) {
      meta.remove();
      meta = null;
    }
    if (activity && bubble) {
      if (!meta) {
        meta = document.createElement("div");
        meta.className = "ullme-message-meta";
        bubble.insertBefore(meta, bubble.firstChild);
      }
      meta.classList.remove("ullme-message-error");
      meta.dataset.toolActivity = "true";
      meta.textContent = activity;
    }
    if (done && bubble && !bubble.querySelector(".ullme-message-actions")) {
      bubble.appendChild(renderAssistantActions(messageId, text || ""));
    }
    if (done) {
      state.chatBusy = false;
      clearChatWatchdog(messageId);
      updateSubmitState();
      typesetMath(messageText);
      typesetMath(thinkingTextElement);
    } else if (waitingForUser) {
      pauseChatWatchdog(messageId);
    } else {
      startChatWatchdog(messageId);
    }
    if (messages) messages.scrollTop = previousScrollTop;
  }

  function updateCourseList(courseids, selectedCourseid, showCourses, summary, semester) {
    var courseSelect = byId("ullme_course_select");
    var courseTabs = byId("ullme_course_tabs");
    var addCourseButton = byId("ullme_add_course_btn");

    courseids = Array.isArray(courseids) ? courseids : [];
    selectedCourseid = selectedCourseid || "";
    if (semester) setSidebarValue(byId("ullme_semester_select"), semester);
    if (courseSelect) {
      courseSelect.classList.toggle("ullme-course-select-hidden", !showCourses);
      courseSelect.setAttribute("data-options", courseids.join("|"));
      setSidebarValue(courseSelect, selectedCourseid);
    }
    if (addCourseButton) {
      addCourseButton.classList.toggle(
        "ullme-add-course-button-hidden",
        !showCourses
      );
    }
    if (courseTabs) courseTabs.classList.toggle("ullme-course-tabs-hidden", !selectedCourseid);
    updateActiveCourse(summary, selectedCourseid);
  }

  function updateActiveCourse(summary, selectedCourseid) {
    if (state.selectedCourseid && state.selectedCourseid !== selectedCourseid) {
      state.courseFile = null;
      state.courseFileOriginalContent = "";
      if (state.studioView === "file") activateStudioView("materials");
      if (byId("ullme_definition_overlay")) removeDefinitionWorkspace(true);
    }
    state.selectedCourseid = selectedCourseid || "";
    var course = summary && summary.course ? summary.course : { courseid: selectedCourseid || "" };
    var material = summary && summary.material ? summary.material : {};
    var materialTree = summary && Array.isArray(summary.material_tree)
      ? summary.material_tree
      : [];
    var aiTutors = summary && Array.isArray(summary.ai_tutors) ? summary.ai_tutors : [];
    var aiTutorCatalog = summary && Array.isArray(summary.ai_tutor_catalog) ? summary.ai_tutor_catalog : [];
    var skills = summary && Array.isArray(summary.skills) ? summary.skills : [];
    var courseSkills = summary && Array.isArray(summary.course_skills)
      ? summary.course_skills
      : [];
    var activeSkill = summary ? summary.active_skill : null;
    var courseFiles = summary && Array.isArray(summary.course_files) ? summary.course_files : [];
    var editHistory = summary && summary.edit_history ? summary.edit_history : {};
    var courseWorkspace = byId("ullme_course_workspace");
    state.courseMaterial = material;
    state.materialTree = materialTree;
    state.aiTutors = aiTutors;
    state.aiTutorCatalog = aiTutorCatalog;
    state.skills = skills;
    state.courseSkills = courseSkills;
    state.courseFiles = courseFiles;
    if (courseWorkspace) {
      courseWorkspace.classList.toggle("ullme-course-workspace-empty", !selectedCourseid);
    }
    fillCourseSettings(course);
    fillEditHistoryControls("course_settings", editHistory.course_settings);
    renderMaterialTree();
    renderCourseFileTree(courseFiles);
    renderAITutors(aiTutors);
    renderActiveSkill(activeSkill);
    updateAIContext();
    if (!selectedCourseid && state.studioView !== "usage") {
      activateStudioView("usage");
    }
  }

  function completePendingMaterialUpload(inputId, result) {
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
    if (result && result.ok === false) {
      window.alert(result.message || "The material upload failed.");
    }
  }

  function scrollMessagesToBottom() {
    var messages = byId("ullme_chat_messages");
    if (!messages) return;
    messages.scrollTop = messages.scrollHeight;
  }

  function updateModelCatalog(payload) {
    chatCommon.updateModelCatalog(payload);
  }

  window.ullme = window.ullme || {};
  window.ullme.receiveAssistantMessage = receiveAssistantMessage;
  window.ullme.receiveAssistantStream = receiveAssistantStream;
  window.ullme.replaceUserMessage = replaceUserMessage;
  window.ullme.receiveStoredUploads = receiveStoredUploads;
  window.ullme.materialUploadComplete = completePendingMaterialUpload;
  window.ullme.materialUploadDestinationReady = materialUploadDestinationReady;
  window.ullme.materialOperationComplete = materialOperationComplete;
  window.ullme.materialConversionComplete = materialConversionComplete;
  window.ullme.updateCourseList = updateCourseList;
  window.ullme.openCatalogDialog = openCatalogDialog;
  window.ullme.aiTutorAddComplete = aiTutorAddComplete;
  window.ullme.openDefinitionWorkspace = openDefinitionWorkspace;
  window.ullme.openDefinitionImportPreview = openDefinitionImportPreview;
  window.ullme.definitionImportComplete = definitionImportComplete;
  window.ullme.downloadDefinition = downloadDefinition;
  window.ullme.receiveDefinitionAssistantMessage = receiveDefinitionAssistantMessage;
  window.ullme.openChangeApproval = openChangeApproval;
  window.ullme.changeApprovalComplete = changeApprovalComplete;
  window.ullme.openCourseFile = openCourseFile;
  window.ullme.courseFileSaveComplete = courseFileSaveComplete;
  window.ullme.courseFileError = courseFileError;
  window.ullme.updateModelCatalog = updateModelCatalog;
  window.ullme.startInstanceBuilder = startInstanceBuilder;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
