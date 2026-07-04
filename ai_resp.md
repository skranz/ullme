This is an excellent UI improvement. Moving the context selectors to the header will give the student a distraction-free, full-width chat interface, which is perfect for complex math rendering and reading.

Here are the changes to completely eliminate the student sidebar and integrate the selectors into the top app bar.

### 1. Update the R UI Functions
We will modify the R functions in `studentApp.R` to remove the sidebar and place the Course, AI Tutor, and Instance selectors into the header context controls.

!MODIFICATION ullme_student_sidebar_ui in studentApp.R
scope = "function"
file = "C:/libraries/ullme/ullme/R/studentApp.R"
function_name = "ullme_student_sidebar_ui"
description = "Deprecate the sidebar UI entirely."
---
```r
ullme_student_sidebar_ui = function(app=getApp()) {
  restore.point("ullme_student_sidebar_ui")
  # Deprecated: The student app no longer uses a sidebar.
  NULL
}
```
!END_MODIFICATION ullme_student_sidebar_ui in studentApp.R

!MODIFICATION ullme_student_workspace_ui in studentApp.R
scope = "function"
file = "C:/libraries/ullme/ullme/R/studentApp.R"
function_name = "ullme_student_workspace_ui"
description = "Remove the sidebar from the student workspace layout."
---
```r
ullme_student_workspace_ui = function(app=getApp()) {
  restore.point("ullme_student_workspace_ui")
  tags$div(
    class="ullme-workspace ullme-student-workspace",
    ullme_chat_pane_ui(app=app, show_header=FALSE)
  )
}
```
!END_MODIFICATION ullme_student_workspace_ui in studentApp.R

!MODIFICATION ullme_student_context_controls_ui in studentApp.R
scope = "function"
file = "C:/libraries/ullme/ullme/R/studentApp.R"
function_name = "ullme_student_context_controls_ui"
description = "Move AI Tutor and Instance selection into the top app bar context controls."
---
```r
ullme_student_context_controls_ui = function(app=getApp()) {
  restore.point("ullme_student_context_controls_ui")
  tags$div(
    class="ullme-context-controls ullme-student-context-summary",
    tags$span(class="ullme-fixed-role", "Student"),
    tags$span(
      id="ullme_student_course_summary",
      class="ullme-student-course-summary",
      app$courseid %||% "Course"
    ),
    tags$div(
      class="ullme-student-header-select-wrap",
      tags$span(id="ullme_student_tutor_text", class="ullme-student-header-text", "Loading..."),
      tags$select(
        id="ullme_student_tutor_select",
        class="ullme-student-header-select",
        style="display: none;"
      )
    ),
    tags$div(
      class="ullme-student-header-select-wrap",
      tags$span(id="ullme_student_instance_text", class="ullme-student-header-text", "Loading..."),
      tags$select(
        id="ullme_student_instance_select",
        class="ullme-student-header-select",
        style="display: none;"
      )
    ),
    tags$span(
      id="ullme_student_context_error",
      class="ullme-student-context-error",
      role="alert"
    )
  )
}
```
!END_MODIFICATION ullme_student_context_controls_ui in studentApp.R

### 2. Rewrite `ullme-student.js`
We will rewrite the JavaScript file to remove all of the complex sidebar resizing logic. We will also update `updateStudentContext` to toggle the visibility of the new header dropdowns versus plain text spans based on the number of available options.

!MODIFICATION ullme-student.js
scope = "file"
file = "C:/libraries/ullme/ullme/inst/www/ullme-student.js"
description = "Rewrite student JS to remove sidebar logic and manage header-based context selectors."
---
```javascript
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

      var showInstanceSelect = instances.length > 1 && payload.allow_instance_switch && !payload.error;
      instanceSelect.style.display = showInstanceSelect ? "" : "none";
      instanceText.style.display = showInstanceSelect ? "none" : "";

      var selectedInstance = instances.find(function(i) { return i.instanceid === payload.instanceid; });
      instanceText.textContent = selectedInstance ? (selectedInstance.label || selectedInstance.instanceid) : (payload.instanceid || "No instances");
    }

    updateStudentIntro(selectedTutor);
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
```
!END_MODIFICATION ullme-student.js

### 3. Rewrite `ullme-student.css`
We will rewrite the CSS file to remove all sidebar layout rules. We will convert `.ullme-student-workspace` to a single-column layout, and we will style the new header selectors.

!MODIFICATION ullme-student.css
scope = "file"
file = "C:/libraries/ullme/ullme/inst/www/ullme-student.css"
description = "Remove sidebar layout styles and style the new top-bar context selectors."
---
```css
:root {
  color-scheme: light;
  --ullme-accent: #235bdb;
  --ullme-accent-dark: #1746b0;
  --ullme-border: #dfe3ea;
  --ullme-muted: #667085;
  --ullme-panel: #f7f8fb;
  --ullme-text: #172033;
}

* {
  box-sizing: border-box;
}

html,
body {
  height: 100%;
  margin: 0;
}

body {
  color: var(--ullme-text);
  background: #fff;
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

button,
select,
textarea,
input {
  font: inherit;
}

.ullme-fluid,
.ullme-app {
  min-height: 100vh;
}

.ullme-app {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr);
}

.ullme-appbar {
  position: relative;
  z-index: 20;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 16px;
  min-width: 0;
  min-height: 58px;
  padding: 8px 22px;
  border-bottom: 1px solid var(--ullme-border);
  background: rgba(255, 255, 255, 0.96);
}

.ullme-appbar-brand {
  color: #13244a;
  font-size: 20px;
  font-weight: 750;
  letter-spacing: -0.03em;
}

.ullme-context-controls {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  min-width: 0;
  gap: 10px;
}

.ullme-fixed-role {
  color: var(--ullme-muted);
  font-size: 13px;
  font-weight: 650;
}

.ullme-student-course-summary {
  overflow: hidden;
  max-width: 320px;
  padding-left: 10px;
  border-left: 1px solid var(--ullme-border);
  font-size: 14px;
  font-weight: 650;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ullme-student-header-select-wrap {
  display: inline-flex;
  align-items: center;
}

.ullme-student-header-text {
  font-size: 13px;
  font-weight: 600;
  color: #344054;
  padding: 5px 9px;
  border-radius: 6px;
  background: #f0f2f5;
  cursor: help;
}

.ullme-student-header-select {
  font-size: 13px;
  font-weight: 600;
  color: #344054;
  padding: 5px 28px 5px 9px;
  border: 1px solid #ccd2dc;
  border-radius: 6px;
  background: #fff;
  cursor: pointer;
}

.ullme-student-header-select:focus {
  outline: 0;
  border-color: #98a2b3;
}

.ullme-student-context-error {
  display: none;
  color: #b42318;
  font-size: 12px;
  font-weight: 600;
  margin-left: 6px;
}

.ullme-appbar-spacer {
  flex: 1;
  min-width: 12px;
}

.ullme-icon-button,
.ullme-submit-button,
.ullme-mini-action,
.ullme-preview-remove {
  display: inline-grid;
  place-items: center;
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  cursor: pointer;
}

.ullme-icon-button {
  width: 36px;
  height: 36px;
  border-radius: 10px;
}

.ullme-icon-button:hover,
.ullme-mini-action:hover {
  background: #eef1f6;
}

.ullme-icon {
  width: 20px;
  height: 20px;
  fill: none;
  stroke: currentColor;
  stroke-linecap: round;
  stroke-linejoin: round;
  stroke-width: 1.8;
}

.ullme-user-settings {
  position: absolute;
  top: 56px;
  right: 18px;
  display: none;
  width: min(300px, calc(100vw - 36px));
  padding: 18px;
  border: 1px solid var(--ullme-border);
  border-radius: 14px;
  background: #fff;
  box-shadow: 0 18px 45px rgba(20, 30, 55, 0.16);
}

.ullme-user-settings-open {
  display: block;
}

.ullme-user-settings-title {
  margin-bottom: 14px;
  font-weight: 700;
}

.ullme-user-settings-field {
  display: grid;
  gap: 6px;
  color: var(--ullme-muted);
  font-size: 12px;
}

.ullme-user-settings-field input {
  width: 100%;
  padding: 9px 10px;
  border: 1px solid var(--ullme-border);
  border-radius: 8px;
  color: var(--ullme-text);
  background: var(--ullme-panel);
}

.ullme-main {
  min-height: 0;
}

.ullme-student-workspace {
  display: block;
  height: calc(100vh - 58px);
  min-height: 0;
}

.ullme-chat-pane {
  display: grid;
  grid-template-rows: minmax(0, 1fr) auto;
  height: 100%;
  min-width: 0;
  min-height: 0;
  background: #fff;
}

.ullme-chat-messages {
  overflow-y: auto;
  min-height: 0;
  padding: 34px max(24px, calc((100% - 780px) / 2)) 24px;
}

.ullme-message {
  display: flex;
  width: 100%;
  margin: 0 auto 24px;
}

.ullme-message-user {
  justify-content: flex-end;
}

.ullme-bubble {
  max-width: min(82%, 720px);
  color: var(--ullme-text);
  font-size: 15px;
  line-height: 1.6;
  white-space: pre-wrap;
}

.ullme-message-user .ullme-bubble {
  padding: 11px 15px;
  border-radius: 18px 18px 4px 18px;
  background: #eef2f8;
}

.ullme-message-assistant .ullme-bubble {
  width: 100%;
}

.ullme-message-text-markdown {
  white-space: normal;
}

.ullme-message-text-markdown > :first-child {
  margin-top: 0;
}

.ullme-message-text-markdown > :last-child {
  margin-bottom: 0;
}

.ullme-message-text-markdown pre {
  overflow-x: auto;
  padding: 13px;
  border-radius: 10px;
  background: #f3f5f8;
}

.ullme-message-text-markdown code {
  font-family: ui-monospace, SFMono-Regular, Consolas, monospace;
}

.ullme-message-meta {
  margin-bottom: 7px;
  color: var(--ullme-muted);
  font-size: 12px;
}

.ullme-message-error {
  color: #b42318;
}

.ullme-thinking .ullme-message-text {
  color: var(--ullme-muted);
}

.ullme-message-actions {
  display: flex;
  gap: 4px;
  margin-top: 7px;
}

.ullme-mini-action {
  width: 30px;
  height: 30px;
  border-radius: 7px;
  color: var(--ullme-muted);
}

.ullme-mini-action .ullme-icon {
  width: 17px;
  height: 17px;
}

.ullme-composer-wrap {
  padding: 10px max(20px, calc((100% - 800px) / 2)) 20px;
  background: linear-gradient(to bottom, rgba(255,255,255,0), #fff 18px);
}

.ullme-composer {
  position: relative;
  display: flex;
  align-items: flex-end;
  gap: 6px;
  padding: 8px;
  border: 1px solid #cfd5df;
  border-radius: 17px;
  background: #fff;
  box-shadow: 0 8px 28px rgba(32, 48, 80, 0.08);
}

.ullme-chat-input {
  flex: 1;
  min-width: 80px;
  min-height: 38px;
  max-height: 170px;
  resize: none;
  padding: 8px 5px;
  border: 0;
  outline: 0;
  color: var(--ullme-text);
  line-height: 1.45;
}

.ullme-chat-input::placeholder {
  color: #98a2b3;
}

.ullme-model-select {
  align-self: center;
  max-width: 145px;
  padding: 7px 5px;
  border: 0;
  color: var(--ullme-muted);
  background: transparent;
  font-size: 11px;
}

.ullme-submit-button {
  flex: 0 0 auto;
  width: 38px;
  height: 38px;
  border-radius: 11px;
  color: #fff;
  background: var(--ullme-accent);
}

.ullme-submit-button:hover:not(:disabled) {
  background: var(--ullme-accent-dark);
}

.ullme-submit-button:disabled {
  cursor: default;
  opacity: 0.35;
}

.ullme-submit-stop {
  background: #344054;
}

.ullme-upload-preview {
  position: absolute;
  right: 10px;
  bottom: calc(100% + 8px);
  display: none;
  gap: 8px;
  padding: 8px;
  border: 1px solid var(--ullme-border);
  border-radius: 12px;
  background: #fff;
  box-shadow: 0 8px 24px rgba(32, 48, 80, 0.12);
}

.ullme-upload-preview.has-items {
  display: flex;
}

.ullme-preview-item {
  position: relative;
}

.ullme-preview-item img,
.ullme-attachment-thumb {
  width: 74px;
  height: 74px;
  border-radius: 9px;
  object-fit: cover;
}

.ullme-preview-remove {
  position: absolute;
  top: -6px;
  right: -6px;
  width: 22px;
  height: 22px;
  border-radius: 50%;
  color: #fff;
  background: #344054;
}

.ullme-preview-remove .ullme-icon {
  width: 13px;
  height: 13px;
}

.ullme-attachments {
  display: flex;
  gap: 8px;
  margin-bottom: 8px;
}

.ullme-file-input,
.ullme-recording-panel,
.ullme-active-skill {
  display: none;
}

.ullme-composer.ullme-composer-recording .ullme-recording-panel {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
}

.ullme-composer.ullme-composer-recording > :not(.ullme-recording-panel) {
  display: none;
}

.ullme-recording-cancel,
.ullme-recording-finish {
  min-width: 68px;
  height: 38px;
  padding: 0 14px;
  border: 0;
  border-radius: 19px;
}

.ullme-recording-cancel {
  background: #eef0f4;
}

.ullme-recording-finish {
  color: #fff;
  background: #172033;
}

.ullme-recording-status {
  display: flex;
  flex: 1;
  align-items: center;
  justify-content: center;
  min-width: 0;
  gap: 8px;
  font-size: 13px;
}

.ullme-recording-dot {
  width: 9px;
  height: 9px;
  border-radius: 50%;
  background: #d92d20;
}

.ullme-recording-wave {
  width: 110px;
  height: 28px;
}

.ullme-recording-options {
  display: flex;
  gap: 4px;
}

.ullme-audio-select {
  max-width: 90px;
  height: 34px;
  border: 0;
  border-radius: 17px;
  background: #f2f4f7;
  font-size: 12px;
}

@media (max-width: 760px) {
  .ullme-appbar {
    padding: 8px 14px;
  }
  
  .ullme-student-course-summary {
    max-width: 140px;
  }

  .ullme-chat-messages {
    padding: 22px 16px;
  }

  .ullme-composer-wrap {
    padding: 8px 10px 12px;
  }

  .ullme-model-select {
    display: none;
  }
}
```
!END_MODIFICATION ullme-student.css
