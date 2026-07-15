(function () {
  "use strict";

  var mathJaxQueue = Promise.resolve();

  function byId(id) {
    return document.getElementById(id);
  }

  function nextId(state, prefix) {
    state.messageIndex = Number(state.messageIndex || 0) + 1;
    return prefix + "_" + Date.now() + "_" + state.messageIndex;
  }

  function sendEvent(inputId, payload) {
    payload = payload || {};
    payload.nonce = Math.random();
    if (window.Shiny && window.Shiny.setInputValue) {
      window.Shiny.setInputValue(inputId, payload, { priority: "event" });
      return true;
    }
    if (window.Shiny && window.Shiny.onInputChange) {
      window.Shiny.onInputChange(inputId, payload);
      return true;
    }
    return false;
  }

  function resizeInput(input, fallbackHeight) {
    var composer = input.closest(".ullme-composer");
    if (composer) composer.classList.remove("ullme-composer-multiline");
    input.style.height = "auto";
    var minHeight = parseFloat(window.getComputedStyle(input).minHeight) ||
      fallbackHeight || 38;
    var multiline = input.value.indexOf("\n") !== -1 ||
      input.scrollHeight > minHeight + 2;
    if (composer) composer.classList.toggle("ullme-composer-multiline", multiline);
    input.style.height = Math.max(
      minHeight,
      Math.min(input.scrollHeight, 170)
    ) + "px";
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

  function setMessageContent(element, text, html) {
    var renderHtml = typeof html === "string" && html.length > 0;
    clearMath(element);
    element.classList.toggle("ullme-message-text-markdown", renderHtml);
    if (renderHtml) element.innerHTML = html;
    else element.textContent = text || "";
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

  function clipboardImageFiles(event) {
    var items = event.clipboardData && event.clipboardData.items;
    if (!items) return [];
    return Array.prototype.slice.call(items)
      .filter(function (item) {
        return item.kind === "file" && /^image\//.test(item.type || "");
      })
      .map(function (item) { return item.getAsFile(); })
      .filter(Boolean);
  }

  function addLocalUploads(files, state, makeId, render, afterAdd) {
    files
      .filter(function (file) {
        return /^image\//.test(file.type || "");
      })
      .forEach(function (file) {
        var upload = {
          localId: makeId("upload"),
          name: file.name,
          size: file.size,
          type: file.type,
          previewUrl: ""
        };
        state.uploads.push(upload);
        if (afterAdd) afterAdd(upload);
        var reader = new FileReader();
        reader.onload = function (event) {
          upload.previewUrl = event.target.result;
          render();
        };
        reader.readAsDataURL(file);
      });
    render();
  }

  function renderUploadPreview(state, closeIcon, onChanged, afterRender) {
    var preview = byId("ullme_upload_preview");
    if (!preview) return;
    preview.innerHTML = "";
    preview.classList.toggle("has-items", state.uploads.length > 0);
    if (afterRender) afterRender();
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
      remove.innerHTML = closeIcon;
      remove.addEventListener("click", function () {
        state.uploads = state.uploads.filter(function (candidate) {
          return candidate.localId !== upload.localId;
        });
        renderUploadPreview(state, closeIcon, onChanged, afterRender);
        if (onChanged) onChanged();
      });
      item.appendChild(image);
      item.appendChild(remove);
      preview.appendChild(item);
    });
  }

  function clearUploads(state, render) {
    var input = byId("ullme_image_upload");
    var cameraInput = byId("ullme_camera_upload");
    state.uploads = [];
    if (input) input.value = "";
    if (cameraInput) cameraInput.value = "";
    render();
  }

  function receiveStoredUploads(state, records) {
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

  function updateModelCatalog(payload) {
    var select = byId("ullme_model_select");
    if (!select || !payload) return;
    var previous = select.value;
    var models = Array.isArray(payload.models) ? payload.models : [];
    select.innerHTML = "";
    models.forEach(function (model) {
      var option = document.createElement("option");
      option.value = String(model.id || "");
      option.textContent = String(model.label || model.id || "");
      option.title = String(model.id || "");
      select.appendChild(option);
    });
    var wanted = models.some(function (model) {
      return model.id === previous;
    }) ? previous : payload.default;
    if (wanted) select.value = wanted;
    select.disabled = models.length === 0;
    var provider = String(payload.provider || "Model");
    select.title = payload.error
      ? provider + ": " + payload.error
      : "Model provider: " + provider;
  }

  window.ullmeChat = {
    byId: byId,
    nextId: nextId,
    sendEvent: sendEvent,
    resizeInput: resizeInput,
    clearMath: clearMath,
    typesetMath: typesetMath,
    setMessageContent: setMessageContent,
    textBlock: textBlock,
    renderAttachments: renderAttachments,
    clipboardImageFiles: clipboardImageFiles,
    addLocalUploads: addLocalUploads,
    renderUploadPreview: renderUploadPreview,
    clearUploads: clearUploads,
    receiveStoredUploads: receiveStoredUploads,
    updateModelCatalog: updateModelCatalog
  };
})();
