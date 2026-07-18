(function (root) {
  "use strict";

  var state = {
    tutorId: "",
    valid: null,
    noticeTimer: null
  };

  function byId(id) {
    return typeof document === "undefined" ? null : document.getElementById(id);
  }

  function errorsOf(value) {
    var errors = value && (value.validation_errors || value.errors);
    return Array.isArray(errors) ? errors.map(String).filter(Boolean) : [];
  }

  function dispatchAssistantTab(tab) {
    document.dispatchEvent(new CustomEvent("ullme:assistant-tab", {
      detail: { tab: tab }
    }));
  }

  function renderErrors(errors) {
    var list = byId("ullme_tutor_validation_errors");
    if (!list) return;
    list.innerHTML = "";
    (errors.length ? errors : ["The Tutor definition did not pass validation."])
      .forEach(function (message) {
        var item = document.createElement("li");
        item.textContent = message;
        list.appendChild(item);
      });
  }

  function setWarningVisible(visible, errors, open) {
    var tab = byId("ullme_tutor_validation_tab");
    if (!tab) return;
    tab.hidden = !visible;
    if (visible) {
      renderErrors(errors || []);
      if (open) dispatchAssistantTab("validation");
    } else if (tab.classList.contains("ullme-assistant-tab-active")) {
      dispatchAssistantTab("help");
    }
  }

  function showNotice(message, valid) {
    var notice = byId("ullme_tutor_validation_notice");
    if (!notice) return;
    if (state.noticeTimer) root.clearTimeout(state.noticeTimer);
    notice.textContent = message;
    notice.classList.toggle("ullme-tutor-validation-notice-valid", Boolean(valid));
    notice.classList.toggle("ullme-tutor-validation-notice-invalid", !valid);
    notice.classList.add("ullme-tutor-validation-notice-active");
    state.noticeTimer = root.setTimeout(function () {
      notice.classList.remove("ullme-tutor-validation-notice-active");
    }, valid ? 4500 : 8000);
  }

  function update(tutor) {
    var tutorId = String(tutor && tutor.tutorid || "");
    if (!tutorId) {
      state.tutorId = "";
      state.valid = null;
      setWarningVisible(false);
      return;
    }
    var valid = tutor.is_valid !== false;
    var becameInvalid = !valid && (
      state.tutorId !== tutorId || state.valid !== false
    );
    state.tutorId = tutorId;
    state.valid = valid;
    setWarningVisible(!valid, errorsOf(tutor), becameInvalid);
  }

  function reportSave(validation) {
    if (!validation) return;
    var valid = validation.is_valid !== false;
    state.valid = valid;
    if (valid) {
      setWarningVisible(false);
      showNotice("Tutor saved. The definition is valid and available to students.", true);
      return;
    }
    var errors = errorsOf(validation);
    setWarningVisible(true, errors, true);
    showNotice(
      "Tutor saved, but its definition is invalid. Students cannot use it.",
      false
    );
  }

  root.ullmeTutorValidation = {
    update: update,
    reportSave: reportSave
  };
})(typeof window !== "undefined" ? window : globalThis);
