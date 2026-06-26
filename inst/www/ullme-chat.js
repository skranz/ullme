(function () {
  var state = {
    uploads: [],
    messageIndex: 0,
    isRecording: false,
    assistantRequests: {}
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
    var sidebarClose = byId("ullme_sidebar_close");
    var sidebarToggle = byId("ullme_sidebar_toggle");

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

    if (sidebarClose) {
      sidebarClose.addEventListener("click", function () {
        setSidebarHidden(true);
      });
    }

    if (sidebarToggle) {
      sidebarToggle.addEventListener("click", function () {
        setSidebarHidden(false);
      });
    }
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

  function setSidebarHidden(hidden) {
    var app = byId("ullme_app");
    if (!app) return;
    app.classList.toggle("ullme-sidebar-hidden", Boolean(hidden));
  }

  function scrollMessagesToBottom() {
    var messages = byId("ullme_chat_messages");
    if (!messages) return;
    messages.scrollTop = messages.scrollHeight;
  }

  window.ullme = window.ullme || {};
  window.ullme.receiveAssistantMessage = receiveAssistantMessage;
  window.ullme.receiveStoredUploads = receiveStoredUploads;
  window.ullme.setSidebarHidden = setSidebarHidden;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
