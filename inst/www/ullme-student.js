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
    context: null
  };
  var mathJaxQueue = Promise.resolve();

  var icons = {
    copy: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="8" y="8" width="11" height="11" rx="2"></rect><path d="M5 15V5h10"></path></svg>',
    check: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 6L9 17l-5-5"></path></svg>',
    retry: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 12a8 8 0 1 1-2.35-5.65"></path><path d="M20 4v6h-6"></path></svg>',
    close: '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M18 6L6 18"></path><path d="M6 6l12 12"></path></svg>',
    stop: '<svg class="ullme-icon ullme-stop-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="7" y="7" width="10" height="10" rx="1"></rect></svg>'
  };

  function byId(id) {
    return document.getElementById(id);
  }

  function nextId(prefix) {
    state.messageIndex += 1;
    return prefix + "_" + Date.now() + "_" + state.messageIndex;
  }

  function sendEvent(inputId, payload) {
    payload = payload || {};
    payload.nonce = Math.random();
    if (window.Shiny && window.Shiny.setInputValue) {
      window.Shiny.setInputValue(inputId, payload, { priority: "event" });
    } else if (window.Shiny && window.Shiny.onInputChange) {
      window.Shiny.onInputChange(inputId, payload);
    }
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

  function studentSidebarIsMobile() {
    return window.matchMedia("(max-width: 760px)").matches;
  }

  function initStudentSidebar() {
    var workspace = document.querySelector(".ullme-student-workspace");
    var sidebar = document.querySelector(".ullme-student-sidebar");
    var resizer = byId("ullme_student_pane_resizer");
    var toggle = byId("ullme_student_sidebar_toggle");
    if (!workspace || !sidebar || !resizer || !toggle) return;

    var widthKey = "ullme-student-sidebar-width";
    var collapsedKey = "ullme-student-sidebar-collapsed";
    var minimum = 220;
    var maximum = 520;

    function clamp(value) {
      return Math.max(minimum, Math.min(maximum, value));
    }

    function currentWidth() {
      var value = parseFloat(
        window.getComputedStyle(workspace).getPropertyValue(
          "--ullme-student-sidebar-width"
        )
      );
      return Number.isFinite(value) ? value : sidebar.getBoundingClientRect().width;
    }

    function setWidth(value, persist) {
      value = clamp(value);
      workspace.style.setProperty(
        "--ullme-student-sidebar-width",
        value + "px"
      );
      resizer.setAttribute("aria-valuenow", Math.round(value));
      if (persist) {
        try {
          window.localStorage.setItem(widthKey, String(value));
        } catch (error) {
          return;
        }
      }
    }

    function setCollapsed(collapsed, persist) {
      workspace.classList.toggle(
        "ullme-student-sidebar-collapsed",
        Boolean(collapsed)
      );
      toggle.setAttribute("aria-expanded", collapsed ? "false" : "true");
      toggle.setAttribute(
        "aria-label",
        collapsed ? "Expand tutor sidebar" : "Collapse tutor sidebar"
      );
      toggle.title = collapsed ? "Expand tutor sidebar" : "Collapse tutor sidebar";
      if (persist) {
        try {
          window.localStorage.setItem(collapsedKey, collapsed ? "true" : "false");
        } catch (error) {
          return;
        }
      }
    }

    try {
      var savedWidth = parseFloat(window.localStorage.getItem(widthKey) || "");
      setWidth(Number.isFinite(savedWidth) ? savedWidth : 280, false);
      setCollapsed(
        window.localStorage.getItem(collapsedKey) === "true",
        false
      );
    } catch (error) {
      setWidth(280, false);
      setCollapsed(false, false);
    }

    toggle.addEventListener("click", function (event) {
      event.stopPropagation();
      setCollapsed(
        !workspace.classList.contains("ullme-student-sidebar-collapsed"),
        true
      );
    });

    resizer.addEventListener("pointerdown", function (event) {
      if (event.target === toggle || toggle.contains(event.target) ||
          studentSidebarIsMobile() ||
          workspace.classList.contains("ullme-student-sidebar-collapsed")) {
        return;
      }
      event.preventDefault();
      var startX = event.clientX;
      var startWidth = currentWidth();
      document.body.classList.add("ullme-student-pane-resizing");

      function move(moveEvent) {
        setWidth(startWidth + moveEvent.clientX - startX, false);
      }

      function finish() {
        document.body.classList.remove("ullme-student-pane-resizing");
        window.removeEventListener("pointermove", move);
        window.removeEventListener("pointerup", finish);
        window.removeEventListener("pointercancel", finish);
        setWidth(currentWidth(), true);
      }

      window.addEventListener("pointermove", move);
      window.addEventListener("pointerup", finish);
      window.addEventListener("pointercancel", finish);
    });

    resizer.addEventListener("keydown", function (event) {
      if (event.target === toggle || studentSidebarIsMobile() ||
          workspace.classList.contains("ullme-student-sidebar-collapsed") ||
          !["ArrowLeft", "ArrowRight"].includes(event.key)) {
        return;
      }
      event.preventDefault();
      var direction = event.key === "ArrowRight" ? 1 : -1;
      setWidth(currentWidth() + direction * (event.shiftKey ? 24 : 8), true);
    });

    resizer.addEventListener("dblclick", function (event) {
      if (event.target === toggle || toggle.contains(event.target) ||
          studentSidebarIsMobile()) return;
      setWidth(280, true);
    });
  }

  function clearMath(element) {
    if (!element || !window.MathJax ||
        typeof window.MathJax.typesetClear !== "function") return;
    try {
      window.MathJax.typesetClear([element]);
    } catch (error) {
      return;
    }
  }

  function typesetMath(element) {
    if (!element || !window.MathJax ||
        typeof window.MathJax.typesetPromise !== "function") return;
    var startup = window.MathJax.startup && window.MathJax.startup.promise
      ? window.MathJax.startup.promise
      : Promise.resolve();
    mathJaxQueue = mathJaxQueue
      .then(function () { return startup; })
      .then(function () {
        return window.MathJax.typesetPromise([element]);
      })
      .catch(function (error) {
        if (window.console && console.warn) {
          console.warn("MathJax could not typeset a chat message.", error);
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
    var tutorSelect = byId("ullme_student_tutor_select");
    var instanceSelect = byId("ullme_student_instance_select");

    if (!messages || !input || !submitButton) return;
    state.submitButtonHtml = submitButton.innerHTML;
    initStudentSidebar();
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

    if (tutorSelect) {
      tutorSelect.addEventListener("change", function () {
        sendEvent("ullme_student_context_event", {
          tutorid: tutorSelect.value,
          instanceid: null
        });
      });
    }
    if (instanceSelect) {
      instanceSelect.addEventListener("change", function () {
        sendEvent("ullme_student_context_event", {
          tutorid: tutorSelect ? tutorSelect.value : null,
          instanceid: instanceSelect.value || null
        });
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
    var composer = input.closest(".ullme-composer");
    if (composer) composer.classList.remove("ullme-composer-multiline");
    input.style.height = "auto";
    var minHeight = parseFloat(window.getComputedStyle(input).minHeight) || 40;
    var multiline = input.value.indexOf("\n") !== -1 ||
      input.scrollHeight > minHeight + 2;
    if (composer) composer.classList.toggle("ullme-composer-multiline", multiline);
    input.style.height = Math.max(
      minHeight,
      Math.min(input.scrollHeight, 170)
    ) + "px";
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
          type: upload.type
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
    if (!message.thinking) typesetMath(text);
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
    scrollMessagesToBottom();
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
    var renderHtml = typeof html === "string" && html.length > 0;
    clearMath(element);
    element.classList.toggle("ullme-message-text-markdown", renderHtml);
    if (renderHtml) element.innerHTML = html;
    else element.textContent = text || "";
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
    scrollMessagesToBottom();
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
    files.filter(function (file) {
      return /^image\//.test(file.type || "");
    }).forEach(function (file) {
      var upload = {
        localId: nextId("upload"),
        name: file.name,
        size: file.size,
        type: file.type,
        previewUrl: ""
      };
      state.uploads.push(upload);
      var reader = new FileReader();
      reader.onload = function (event) {
        upload.previewUrl = event.target.result;
        renderUploadPreview();
      };
      reader.readAsDataURL(file);
    });
    renderUploadPreview();
  }

  function handlePaste(event) {
    var items = event.clipboardData && event.clipboardData.items;
    if (!items) return;
    var files = Array.prototype.slice.call(items).filter(function (item) {
      return item.kind === "file" && /^image\//.test(item.type || "");
    }).map(function (item) {
      return item.getAsFile();
    }).filter(Boolean);
    if (!files.length) return;
    event.preventDefault();
    addLocalUploads(files);
    updateSubmitState();
  }

  function renderUploadPreview() {
    var preview = byId("ullme_upload_preview");
    if (!preview) return;
    preview.innerHTML = "";
    preview.classList.toggle("has-items", state.uploads.length > 0);
    state.uploads.forEach(function (upload) {
      var item = document.createElement("div");
      var image = document.createElement("img");
      var remove = document.createElement("button");
      item.className = "ullme-preview-item";
      image.alt = upload.name || "Upload preview";
      image.src = upload.previewUrl || "";
      remove.className = "ullme-preview-remove";
      remove.type = "button";
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
    var input = byId("ullme_image_upload");
    state.uploads = [];
    if (input) input.value = "";
    renderUploadPreview();
  }

  function receiveStoredUploads(records) {
    (records || []).forEach(function (record) {
      var match = state.uploads.find(function (upload) {
        return !upload.serverId && upload.size === record.size;
      });
      if (match) {
        match.serverId = record.id;
        match.storedUrl = record.url;
      }
    });
  }

  function option(value, label) {
    var item = document.createElement("option");
    item.value = String(value || "");
    item.textContent = String(label || value || "");
    return item;
  }

  function updateStudentContext(payload) {
    payload = payload || {};
    state.context = payload;
    state.contextReady = !payload.error && Boolean(payload.tutorid);

    var courseSummary = byId("ullme_student_course_summary");
    var course = byId("ullme_student_sidebar_course");
    var teacher = byId("ullme_student_teacher");
    var semester = byId("ullme_student_semester");
    var tutorSelect = byId("ullme_student_tutor_select");
    var instanceSelect = byId("ullme_student_instance_select");
    var description = byId("ullme_student_tutor_description");
    var error = byId("ullme_student_context_error");
    var tutors = Array.isArray(payload.tutors) ? payload.tutors : [];

    if (courseSummary) courseSummary.textContent = payload.courseid || "Course";
    if (course) course.textContent = payload.courseid || "Course";
    if (teacher) teacher.textContent = payload.teacherid || "";
    if (semester) semester.textContent = payload.semester || "";
    if (error) error.textContent = payload.error || "";

    if (tutorSelect) {
      tutorSelect.innerHTML = "";
      tutors.forEach(function (tutor) {
        tutorSelect.appendChild(option(tutor.tutorid, tutor.label || tutor.tutorid));
      });
      if (payload.tutorid) tutorSelect.value = payload.tutorid;
      tutorSelect.disabled = Boolean(payload.error) ||
        !payload.allow_tutor_switch || tutors.length < 2;
    }

    var selectedTutor = tutors.find(function (tutor) {
      return tutor.tutorid === payload.tutorid;
    }) || null;
    updateStudentIntro(selectedTutor);
    if (description) {
      description.textContent = selectedTutor ? selectedTutor.description || "" : "";
    }
    if (instanceSelect) {
      var instances = selectedTutor && Array.isArray(selectedTutor.instances)
        ? selectedTutor.instances : [];
      instanceSelect.innerHTML = "";
      if (!instances.length) {
        instanceSelect.appendChild(option("", "No instances"));
      } else {
        instances.forEach(function (instance) {
          instanceSelect.appendChild(option(
            instance.instanceid,
            instance.label || instance.instanceid
          ));
        });
      }
      if (payload.instanceid) instanceSelect.value = payload.instanceid;
      instanceSelect.disabled = Boolean(payload.error) ||
        !payload.allow_instance_switch || instances.length < 2;
    }
    updateSubmitState();
  }

  function updateModelCatalog(payload) {
    var select = byId("ullme_model_select");
    if (!select || !payload) return;
    var previous = select.value;
    var models = Array.isArray(payload.models) ? payload.models : [];
    select.innerHTML = "";
    models.forEach(function (model) {
      select.appendChild(option(model.id, model.label || model.id));
    });
    var hasPrevious = models.some(function (model) {
      return model.id === previous;
    });
    if (hasPrevious) select.value = previous;
    else if (payload.default) select.value = payload.default;
    select.disabled = models.length === 0;
    select.title = payload.error
      ? String(payload.provider || "Model") + ": " + payload.error
      : "Model provider: " + String(payload.provider || "model");
  }

  window.ullme = window.ullme || {};
  window.ullme.receiveAssistantMessage = receiveAssistantMessage;
  window.ullme.receiveAssistantStream = receiveAssistantStream;
  window.ullme.replaceUserMessage = replaceUserMessage;
  window.ullme.receiveStoredUploads = receiveStoredUploads;
  window.ullme.updateStudentContext = updateStudentContext;
  window.ullme.updateModelCatalog = updateModelCatalog;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
