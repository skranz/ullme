(function () {
  "use strict";

  var state = {
    uploads: [],
    messageIndex: 0,
    chatBusy: false,
    activeAssistantMessageId: "",
    chatWatchdog: null,
    submitButtonHtml: "",
    assistantRequests: {},
    cancelledAssistantRequests: {},
    contextReady: false,
    context: null,
    historyCurrentId: null,
    historyEnabled: false,
    historyPaneClosed: false,
    historyPanePreferenceSet: false
  };
  var chatCommon = window.ullmeChat;
  var typesetMath = chatCommon.typesetMath;
  var textBlock = chatCommon.textBlock;
  var renderAttachments = chatCommon.renderAttachments;

  var icons = {
    copy: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="8" y="8" width="11" height="11" rx="2"></rect><path d="M5 15V5h10"></path></svg>',
    check: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 6L9 17l-5-5"></path></svg>',
    retry: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 12a8 8 0 1 1-2.35-5.65"></path><path d="M20 4v6h-6"></path></svg>',
    close: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M18 6L6 18"></path><path d="M6 6l12 12"></path></svg>',
    stop: '<svg class="ullme-icon ullme-stop-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="7" y="7" width="10" height="10" rx="1"></rect></svg>'
  };

  function byId(id) {
    return chatCommon.byId(id);
  }

  function nextId(prefix) {
    return chatCommon.nextId(state, prefix);
  }

  function sendEvent(inputId, payload) {
    chatCommon.sendEvent(inputId, payload);
  }

  function sendChatEvent(payload) {
    payload.nonce = Math.random();
    if (window.Shiny && window.Shiny.setInputValue) {
      window.Shiny.setInputValue(
        "ullme_submit_chat_event",
        payload,
        { priority: "event" }
      );
      return;
    }
    if (window.Shiny && window.Shiny.onInputChange) {
      window.Shiny.onInputChange("ullme_submit_chat_event", payload);
      return;
    }
    receiveAssistantStream(
      payload.assistantMessageId,
      "",
      "",
      "",
      "",
      true,
      "The app is not connected to the uLLMe server."
    );
  }

  function clearChatUI() {
    var messages = byId("ullme_chat_messages");
    if (!messages) return;
    var children = Array.prototype.slice.call(messages.children);
    children.forEach(function (child) {
      if (child.id !== "ullme_intro_message") {
        child.remove();
      }
    });
  }

  function init() {
    var messages = byId("ullme_chat_messages");
    var input = byId("ullme_chat_input");
    var submitButton = byId("ullme_submit_btn");
    var uploadButton = byId("ullme_upload_btn");
    var fileInput = byId("ullme_image_upload");
    var voiceButton = byId("ullme_voice_btn");
    var settingsButton = byId("ullme_user_settings_btn");
    var settings = byId("ullme_user_settings");
    var semesterSelect = byId("ullme_student_semester_select");
    var tutorSelect = byId("ullme_student_tutor_select");
    var instanceSelect = byId("ullme_student_instance_select");
    var newChatBtn = byId("ullme_student_new_chat_btn");
    var historyNewBtn = byId("ullme_student_history_new_btn");
    var historyCloseBtn = byId("ullme_student_history_close_btn");
    var historyOpenBtn = byId("ullme_student_history_open_btn");
    var themeSelect = byId("ullme_student_theme_select");

    if (!messages || !input || !submitButton) return;
    state.submitButtonHtml = submitButton.innerHTML;

    initViewportHeight();
    initTheme(themeSelect);

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
    submitButton.addEventListener("click", function () {
      if (state.chatBusy) stopActiveChat();
      else submitChat();
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

    if (voiceButton) {
      voiceButton.addEventListener("click", function () {
        if (window.ullmeAudio && window.ullmeAudio.startRecording) {
          window.ullmeAudio.startRecording();
        }
      });
    }

    if (settingsButton && settings) {
      settingsButton.addEventListener("click", function (event) {
        event.stopPropagation();
        settings.classList.toggle("ullme-user-settings-open");
      });
      settings.addEventListener("click", function (event) {
        event.stopPropagation();
      });
      document.addEventListener("click", function () {
        settings.classList.remove("ullme-user-settings-open");
      });
    }

    if (semesterSelect) {
      semesterSelect.addEventListener("change", function () {
        sendEvent("ullme_student_context_event", {
          semester: semesterSelect.value,
          tutorid: null,
          instanceid: null
        });
      });
    }
    if (tutorSelect) {
      tutorSelect.addEventListener("change", function () {
        sendEvent("ullme_student_context_event", {
          semester: semesterSelect ? semesterSelect.value : null,
          tutorid: tutorSelect.value,
          instanceid: null
        });
      });
    }
    if (instanceSelect) {
      instanceSelect.addEventListener("change", function () {
        sendEvent("ullme_student_context_event", {
          semester: semesterSelect ? semesterSelect.value : null,
          tutorid: tutorSelect ? tutorSelect.value : null,
          instanceid: instanceSelect.value || null
        });
      });
    }
    if (newChatBtn) {
      newChatBtn.addEventListener("click", function() {
        if (!window.confirm("Start a new chat and clear the current history?")) return;
        clearChatUI();
        sendEvent("ullme_student_chat_clear_event", {});
      });
    }
    if (historyNewBtn) {
      historyNewBtn.addEventListener("click", function () {
        sendEvent("ullme_student_chat_history_event", { new_chat: true });
      });
    }
    if (historyCloseBtn) {
      historyCloseBtn.addEventListener("click", function () {
        setHistoryPaneClosed(true);
      });
    }
    if (historyOpenBtn) {
      historyOpenBtn.addEventListener("click", function () {
        setHistoryPaneClosed(false);
      });
    }

    document.addEventListener("shiny:disconnected", function () {
      if (!state.chatBusy || !state.activeAssistantMessageId) return;
      receiveAssistantStream(
        state.activeAssistantMessageId, "", "", "", "", true,
        "The connection to the uLLMe server was lost. Please reconnect and try again."
      );
    });
  }

  function mountIntro(messages) {
    var text = messages.getAttribute("data-intro-text") || "";
    if (!text || byId("ullme_intro_message")) return;
    appendAssistantMessage({
      id: "ullme_intro_message",
      text: text,
      html: messages.getAttribute("data-intro-html") || "",
      meta: messages.getAttribute("data-intro-meta") || ""
    });
  }

  function resizeInput(input) {
    chatCommon.resizeInput(input, 40);
  }

  function updateSubmitState() {
    var input = byId("ullme_chat_input");
    var submitButton = byId("ullme_submit_btn");
    if (!input || !submitButton) return;
    var stopping = state.chatBusy && Boolean(state.activeAssistantMessageId);
    submitButton.disabled = stopping ? false : (
      !state.contextReady ||
      (input.value.trim().length === 0 && state.uploads.length === 0)
    );
    submitButton.classList.toggle("ullme-submit-stop", stopping);
    submitButton.setAttribute("aria-label", stopping ? "Stop response" : "Submit chat");
    submitButton.title = stopping ? "Stop response" : "Send message";
    submitButton.innerHTML = stopping ? icons.stop : state.submitButtonHtml;
  }

  function submitChat() {
    var input = byId("ullme_chat_input");
    var modelSelect = byId("ullme_model_select");
    if (!input || state.chatBusy || !state.contextReady) return;
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
      uploads: uploads.map(function (upload) {
        return {
          id: upload.serverId || upload.localId,
          name: upload.name,
          size: upload.size,
          type: upload.type,
          data_url: upload.previewUrl || ""
        };
      }),
      nonce: Math.random()
    };

    state.chatBusy = true;
    state.assistantRequests[assistantMessageId] = payload;
    startChatWatchdog(assistantMessageId);
    appendUserMessage({ id: clientMessageId, text: text, uploads: uploads });
    appendAssistantMessage({
      id: assistantMessageId,
      text: "Thinking...",
      thinking: true
    });
    input.value = "";
    resizeInput(input);
    clearUploads();
    updateSubmitState();
    sendChatEvent(payload);
  }

  function stopActiveChat() {
    var messageId = state.activeAssistantMessageId;
    if (!messageId) return;
    state.cancelledAssistantRequests[messageId] = true;
    sendEvent("ullme_cancel_chat_event", { assistantMessageId: messageId });
    receiveAssistantStream(messageId, "Stopped.", "", "", "", true, "");
  }

  function startChatWatchdog(messageId) {
    if (state.chatWatchdog) window.clearTimeout(state.chatWatchdog);
    state.activeAssistantMessageId = messageId;
    state.chatWatchdog = window.setTimeout(function () {
      receiveAssistantStream(
        messageId, "", "", "", "", true,
        "The model did not respond within three minutes."
      );
    }, 180000);
  }

  function clearChatWatchdog(messageId) {
    if (messageId && state.activeAssistantMessageId &&
        messageId !== state.activeAssistantMessageId) return;
    if (state.chatWatchdog) window.clearTimeout(state.chatWatchdog);
    state.chatWatchdog = null;
    state.activeAssistantMessageId = "";
  }

  function scrollMessagesToBottom() {
    var messages = byId("ullme_chat_messages");
    if (messages) messages.scrollTop = messages.scrollHeight;
  }

  function appendUserMessage(message) {
    var messages = byId("ullme_chat_messages");
    var article = document.createElement("article");
    var bubble = document.createElement("div");
    article.id = message.id;
    article.className = "ullme-message ullme-message-user";
    bubble.className = "ullme-bubble";
    if (message.uploads && message.uploads.length) {
      bubble.appendChild(renderAttachments(message.uploads));
    }
    if (message.text) bubble.appendChild(textBlock(message.text));
    article.appendChild(bubble);
    messages.appendChild(article);
    if (!message.thinking) typesetMath(bubble);
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
    setAssistantMessageContent(text, message.text || "", message.html || "");
    bubble.appendChild(text);
    if (!message.thinking) bubble.appendChild(renderAssistantActions(message.id, message.text || ""));
    article.appendChild(bubble);
    messages.appendChild(article);
    if (!message.thinking) typesetMath(text);
  }

  function initViewportHeight() {
    var viewport = window.visualViewport;
    function update() {
      var height = viewport ? viewport.height : window.innerHeight;
      document.documentElement.style.setProperty(
        "--ullme-viewport-height", Math.round(height) + "px"
      );
    }
    update();
    window.addEventListener("resize", update);
    window.addEventListener("orientationchange", update);
    if (viewport) viewport.addEventListener("resize", update);
  }

  function initTheme(select) {
    var storageKey = "ullme-color-theme";
    var media = window.matchMedia("(prefers-color-scheme: dark)");
    function storedTheme() {
      try {
        return window.localStorage.getItem(storageKey) || "system";
      } catch (error) {
        return "system";
      }
    }
    function apply(theme) {
      var dark = theme === "dark" || (theme === "system" && media.matches);
      document.documentElement.dataset.ullmeTheme = dark ? "dark" : "light";
      document.documentElement.style.colorScheme = dark ? "dark" : "light";
    }
    var theme = storedTheme();
    if (["system", "light", "dark"].indexOf(theme) < 0) theme = "system";
    if (select) {
      select.value = theme;
      select.addEventListener("change", function () {
        theme = select.value;
        try {
          window.localStorage.setItem(storageKey, theme);
        } catch (error) {}
        apply(theme);
      });
    }
    var onSystemThemeChange = function () {
      if (theme === "system") apply(theme);
    };
    if (media.addEventListener) media.addEventListener("change", onSystemThemeChange);
    else if (media.addListener) media.addListener(onSystemThemeChange);
    apply(theme);
  }

  function updateStudentIntro(tutor) {
    var messages = byId("ullme_chat_messages");
    if (!messages) return;
    tutor = tutor || {};
    var text = String(
      tutor.shown_text ||
      messages.getAttribute("data-intro-text") ||
      ""
    );
    var html = tutor.shown_text
      ? String(tutor.shown_html || "")
      : String(messages.getAttribute("data-intro-html") || "");
    var article = byId("ullme_intro_message");
    if (!article) {
      appendAssistantMessage({
        id: "ullme_intro_message",
        text: text,
        html: html,
        meta: ""
      });
      return;
    }
    var bubble = article.querySelector(".ullme-bubble");
    var messageText = article.querySelector(".ullme-message-text");
    if (!bubble || !messageText) return;
    setAssistantMessageContent(messageText, text, html);
    var actions = bubble.querySelector(".ullme-message-actions");
    if (actions) actions.remove();
    bubble.appendChild(renderAssistantActions("ullme_intro_message", text));
    typesetMath(messageText);
  }

  function replaceUserMessage(messageId, text) {
    var article = byId(messageId);
    var bubble = article && article.querySelector(".ullme-bubble");
    if (!bubble) return;
    bubble.innerHTML = "";
    bubble.appendChild(textBlock(text || ""));
  }

  function setAssistantMessageContent(element, text, html) {
    chatCommon.setMessageContent(element, text, html);
  }

  function renderAssistantActions(messageId, text) {
    var actions = document.createElement("div");
    actions.className = "ullme-message-actions";
    actions.appendChild(miniAction("Copy", icons.copy, function () {
      copyText(text, this);
    }));
    actions.appendChild(miniAction("Redo", icons.retry, function () {
      retryAssistantMessage(messageId);
    }, !state.assistantRequests[messageId]));
    return actions;
  }

  function miniAction(label, icon, onClick, disabled) {
    var button = document.createElement("button");
    button.className = "ullme-mini-action";
    button.type = "button";
    button.title = label;
    button.setAttribute("aria-label", label);
    button.innerHTML = icon;
    button.disabled = Boolean(disabled);
    if (!disabled) button.addEventListener("click", onClick);
    return button;
  }

  function copyText(text, button) {
    var complete = function () {
      var old = button.innerHTML;
      button.innerHTML = icons.check;
      window.setTimeout(function () { button.innerHTML = old; }, 1200);
    };
    if (navigator.clipboard) {
      navigator.clipboard.writeText(text).then(complete);
      return;
    }
    var area = document.createElement("textarea");
    area.value = text;
    area.style.position = "fixed";
    area.style.left = "-9999px";
    document.body.appendChild(area);
    area.select();
    document.execCommand("copy");
    area.remove();
    complete();
  }

  function retryAssistantMessage(messageId) {
    var payload = state.assistantRequests[messageId];
    var article = byId(messageId);
    if (!payload || !article || state.chatBusy) return;
    var messageText = article.querySelector(".ullme-message-text");
    var actions = article.querySelector(".ullme-message-actions");
    if (actions) actions.remove();
    if (messageText) setAssistantMessageContent(messageText, "Thinking...", "");
    article.classList.add("ullme-thinking");
    delete state.cancelledAssistantRequests[messageId];
    state.chatBusy = true;
    startChatWatchdog(messageId);
    updateSubmitState();
    payload.nonce = Math.random();
    sendChatEvent(payload);
  }

  function receiveAssistantMessage(messageId, text, html) {
    receiveAssistantStream(messageId, text, html, "", "", true, "");
  }

  function receiveAssistantStream(messageId, text, html, thinking,
                                  thinkingHtml, done, error, activity,
                                  waitingForUser) {
    if (state.cancelledAssistantRequests[messageId] && text !== "Stopped.") return;
    var article = byId(messageId);
    if (!article) {
      appendAssistantMessage({
        id: messageId || nextId("assistant"),
        text: text || error || "",
        html: text ? html || "" : "",
        meta: activity || "",
        thinking: !done
      });
      article = byId(messageId);
    }
    var bubble = article && article.querySelector(".ullme-bubble");
    var messageText = article && article.querySelector(".ullme-message-text");
    var meta = article && article.querySelector(".ullme-message-meta");
    if (messageText) {
      messageText.classList.toggle("ullme-message-error", Boolean(error && !text));
      setAssistantMessageContent(
        messageText,
        text || error || (thinking ? "Thinking..." : ""),
        text ? html || "" : ""
      );
    }
    if (activity && bubble) {
      if (!meta) {
        meta = document.createElement("div");
        meta.className = "ullme-message-meta";
        bubble.insertBefore(meta, bubble.firstChild);
      }
      meta.textContent = activity;
    } else if (meta && !error) {
      meta.remove();
    }
    if (done) {
      article.classList.remove("ullme-thinking");
      typesetMath(messageText);
      if (bubble && !bubble.querySelector(".ullme-message-actions")) {
        bubble.appendChild(renderAssistantActions(messageId, text || ""));
      }
      state.chatBusy = false;
      clearChatWatchdog(messageId);
      updateSubmitState();
    } else if (!waitingForUser) {
      startChatWatchdog(messageId);
    }
  }

  function addLocalUploads(files) {
    chatCommon.addLocalUploads(
      files, state, nextId, renderUploadPreview
    );
  }

  function handlePaste(event) {
    var files = chatCommon.clipboardImageFiles(event);
    if (!files.length) return;
    event.preventDefault();
    addLocalUploads(files);
    updateSubmitState();
  }

  function renderUploadPreview() {
    chatCommon.renderUploadPreview(
      state, icons.close, updateSubmitState
    );
  }

  function clearUploads() {
    chatCommon.clearUploads(state, renderUploadPreview);
  }

  function receiveStoredUploads(records) {
    chatCommon.receiveStoredUploads(state, records);
  }

  function option(value, label) {
    var item = document.createElement("option");
    item.value = String(value || "");
    item.textContent = String(label || value || "");
    return item;
  }

  function setHistoryPaneClosed(closed) {
    state.historyPaneClosed = Boolean(closed);
    state.historyPanePreferenceSet = true;
    updateHistoryPaneLayout();
  }

  function updateHistoryPaneLayout() {
    var workspace = document.querySelector(".ullme-student-workspace");
    var sidebar = byId("ullme_student_chat_history");
    var openButton = byId("ullme_student_history_open_btn");
    var open = state.historyEnabled && !state.historyPaneClosed;
    if (workspace) {
      workspace.classList.toggle("ullme-student-workspace-with-history", open);
    }
    if (sidebar) sidebar.setAttribute("aria-hidden", open ? "false" : "true");
    if (openButton) {
      openButton.style.display =
        state.historyEnabled && state.historyPaneClosed ? "" : "none";
    }
  }

  function historyButton(item, currentId) {
    var row = document.createElement("div");
    var button = document.createElement("button");
    var remove = document.createElement("button");
    row.className = "ullme-student-chat-history-row";
    button.type = "button";
    button.className = "ullme-student-chat-history-item";
    if (item.id === currentId) {
      button.classList.add("ullme-student-chat-history-item-active");
    }
    button.textContent = item.label || item.id || "Chat";
    button.title = item.label || item.id || "Chat";
    button.addEventListener("click", function () {
      if (item.id === state.historyCurrentId) return;
      sendEvent("ullme_student_chat_history_event", { chat_id: item.id });
    });
    remove.type = "button";
    remove.className = "ullme-student-chat-history-delete";
    remove.setAttribute("aria-label", "Delete " + (item.label || "chat"));
    remove.title = "Delete chat";
    remove.innerHTML = icons.close;
    remove.addEventListener("click", function (event) {
      event.stopPropagation();
      if (item.id === state.historyCurrentId && state.chatBusy) {
        window.alert("Wait for the current response to finish before deleting this chat.");
        return;
      }
      if (!window.confirm("Delete this chat permanently?")) return;
      sendEvent("ullme_student_chat_history_event", {
        delete_chat_id: item.id
      });
    });
    row.appendChild(button);
    row.appendChild(remove);
    return row;
  }

  function renderStoredChat(messages) {
    clearChatUI();
    (messages || []).forEach(function (message) {
      if (message.role === "user") {
        appendUserMessage({
          id: message.id || nextId("history_user"),
          text: message.text || ""
        });
      } else if (message.role === "assistant") {
        appendAssistantMessage({
          id: message.id || nextId("history_assistant"),
          text: message.text || "",
          html: message.html || ""
        });
      }
    });
  }

  function updateStudentChatHistory(payload) {
    payload = payload || {};
    var recent = byId("ullme_student_chat_history_recent");
    var older = byId("ullme_student_chat_history_older");
    var more = byId("ullme_student_chat_history_more");
    var enabled = Boolean(payload.enabled);
    state.historyEnabled = enabled;
    if (enabled && !state.historyPanePreferenceSet) {
      state.historyPaneClosed = Boolean(
        window.matchMedia && window.matchMedia("(max-width: 560px)").matches
      );
    }
    updateHistoryPaneLayout();
    if (!enabled) {
      state.historyCurrentId = null;
      if (recent) recent.innerHTML = "";
      if (older) older.innerHTML = "";
      if (more) more.style.display = "none";
      return;
    }
    if (recent) {
      recent.innerHTML = "";
      (payload.recent || []).forEach(function (item) {
        recent.appendChild(historyButton(item, payload.current_id));
      });
    }
    if (older) {
      older.innerHTML = "";
      (payload.older || []).forEach(function (item) {
        older.appendChild(historyButton(item, payload.current_id));
      });
    }
    if (more) {
      more.style.display = (payload.older || []).length ? "" : "none";
    }
    if (state.historyCurrentId !== payload.current_id) {
      state.historyCurrentId = payload.current_id || "";
      renderStoredChat(payload.messages || []);
    }
  }

  function updateStudentContext(payload) {
    payload = payload || {};
    var previousTutor = state.context ? state.context.tutorid : null;
    var previousInstance = state.context ? state.context.instanceid : null;
    state.context = payload;
    state.contextReady = !payload.error && Boolean(payload.tutorid);

    // Clear chat when instance or tutor changes from an established state
    if (previousTutor !== null && (previousTutor !== payload.tutorid || previousInstance !== payload.instanceid)) {
      clearChatUI();
      state.historyCurrentId = null;
    }

    var courseSummary = byId("ullme_student_course_summary");
    var semesterSelect = byId("ullme_student_semester_select");
    var semesterText = byId("ullme_student_semester_text");
    var tutorSelect = byId("ullme_student_tutor_select");
    var tutorText = byId("ullme_student_tutor_text");
    var instanceSelect = byId("ullme_student_instance_select");
    var instanceText = byId("ullme_student_instance_text");
    var errorLabel = byId("ullme_student_context_error");
    var tutors = Array.isArray(payload.tutors) ? payload.tutors : [];

    if (courseSummary) courseSummary.textContent = payload.courseid || "Course";
    if (errorLabel) {
      errorLabel.textContent = payload.error || "";
      errorLabel.style.display = payload.error ? "inline-block" : "none";
    }

    if (semesterSelect && semesterText) {
      var semesters = Array.isArray(payload.semesters) ? payload.semesters : [];
      semesterSelect.innerHTML = "";
      if (!semesters.length && payload.semester) semesters = [payload.semester];
      semesters.forEach(function (semester) {
        semesterSelect.appendChild(option(semester, semester));
      });
      if (payload.semester) semesterSelect.value = payload.semester;
      var showSemesterSelect = semesters.length > 1 &&
        payload.allow_semester_switch;
      semesterSelect.style.display = showSemesterSelect ? "" : "none";
      semesterText.style.display = showSemesterSelect ? "none" : "";
      semesterText.textContent = payload.semester || "Semester";
    }

    var selectedTutor = tutors.find(function (tutor) {
      return tutor.tutorid === payload.tutorid;
    }) || null;

    if (tutorSelect && tutorText) {
      tutorSelect.innerHTML = "";
      tutors.forEach(function (tutor) {
        tutorSelect.appendChild(option(tutor.tutorid, tutor.label || tutor.tutorid));
      });
      if (payload.tutorid) tutorSelect.value = payload.tutorid;

      var showTutorSelect = tutors.length > 1 && payload.allow_tutor_switch && !payload.error;
      tutorSelect.style.display = showTutorSelect ? "" : "none";
      tutorText.style.display = showTutorSelect ? "none" : "";

      var description = selectedTutor ? (selectedTutor.description || "") : "";
      tutorText.textContent = selectedTutor ? (selectedTutor.label || selectedTutor.tutorid) : (payload.tutorid || "No Tutor");
      tutorText.title = description;
      tutorSelect.title = description;
    }

    if (instanceSelect && instanceText) {
      var instances = selectedTutor && Array.isArray(selectedTutor.instances) ? selectedTutor.instances : [];

      instanceSelect.innerHTML = "";
      if (!instances.length) {
        instanceSelect.appendChild(option("", "No instances"));
      } else {
        instances.forEach(function (instance) {
          instanceSelect.appendChild(option(instance.instanceid, instance.label || instance.instanceid));
        });
      }
      if (payload.instanceid) instanceSelect.value = payload.instanceid;

      var usesInstances = !selectedTutor || selectedTutor.multiple_instances !== false;
      var instanceWrap = instanceSelect.closest(".ullme-student-header-select-wrap");
      if (instanceWrap) instanceWrap.style.display = usesInstances ? "" : "none";
      var showInstanceSelect = usesInstances && instances.length > 1 &&
        payload.allow_instance_switch && !payload.error;
      instanceSelect.style.display = showInstanceSelect ? "" : "none";
      instanceText.style.display = showInstanceSelect ? "none" : "";

      var selectedInstance = instances.find(function(i) { return i.instanceid === payload.instanceid; });
      instanceText.textContent = selectedInstance ? (selectedInstance.label || selectedInstance.instanceid) : (payload.instanceid || "No instances");
    }

    updateStudentIntro(selectedTutor);
    updateStudentChatHistory(payload.chat_history || { enabled: false });
    updateSubmitState();
  }

  function updateModelCatalog(payload) {
    chatCommon.updateModelCatalog(payload);
  }

  window.ullme = window.ullme || {};
  window.ullme.receiveAssistantMessage = receiveAssistantMessage;
  window.ullme.receiveAssistantStream = receiveAssistantStream;
  window.ullme.replaceUserMessage = replaceUserMessage;
  window.ullme.receiveStoredUploads = receiveStoredUploads;
  window.ullme.updateStudentContext = updateStudentContext;
  window.ullme.updateStudentChatHistory = updateStudentChatHistory;
  window.ullme.updateModelCatalog = updateModelCatalog;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
