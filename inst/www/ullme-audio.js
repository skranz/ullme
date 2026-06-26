(function () {
  var state = {
    mediaRecorder: null,
    stream: null,
    chunks: [],
    startedAt: null,
    timerId: null,
    shouldSave: false,
    audioContext: null,
    audioSource: null,
    analyser: null,
    waveFrameId: null,
    waveData: null,
    waveLevels: [],
    waveLevel: 0,
    waveLastDraw: 0,
    settings: {
      format: "auto",
      quality: "standard",
      sensitivity: 3
    }
  };

  function byId(id) {
    return document.getElementById(id);
  }

  function init() {
    var cancelButton = byId("ullme_recording_cancel");
    var finishButton = byId("ullme_recording_finish");
    var settingsInputs = [
      byId("ullme_audio_format"),
      byId("ullme_audio_quality"),
      byId("ullme_mic_sensitivity")
    ].filter(Boolean);

    if (cancelButton) {
      cancelButton.addEventListener("click", cancelRecording);
    }
    if (finishButton) {
      finishButton.addEventListener("click", finishRecording);
    }
    settingsInputs.forEach(function (input) {
      input.addEventListener("change", function () {
        readSettingsFromUi();
        saveSettingsToBrowser();
      });
    });
    applySettings(loadSettingsFromBrowser());
  }

  async function startRecording() {
    if (state.mediaRecorder && state.mediaRecorder.state === "recording") return;

    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || !window.MediaRecorder) {
      showRecordingNotice("Recording is not supported in this browser.");
      return;
    }

    try {
      state.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      state.chunks = [];
      state.shouldSave = false;
      state.mediaRecorder = new MediaRecorder(state.stream, mediaRecorderOptions());
      state.mediaRecorder.addEventListener("dataavailable", function (event) {
        if (event.data && event.data.size > 0) {
          state.chunks.push(event.data);
        }
      });
      state.mediaRecorder.addEventListener("stop", handleRecordingStopped);
      state.mediaRecorder.start();
      showRecordingUi();
      startWaveform();
      startTimer();
    } catch (error) {
      showRecordingNotice("Microphone access was denied.");
    }
  }

  function mediaRecorderOptions() {
    var format = selectedValue("ullme_audio_format", "auto");
    var types = candidateMimeTypes(format);
    var match = types.find(function (type) {
      return MediaRecorder.isTypeSupported(type);
    });
    var options = audioQualityOptions();
    if (match) {
      options.mimeType = match;
      return options;
    }
    if (format !== "auto") {
      setAudioStatus("Format unavailable, using browser default.");
    }
    return options;
  }

  function candidateMimeTypes(format) {
    var byFormat = {
      webm: ["audio/webm;codecs=opus", "audio/webm"],
      ogg: ["audio/ogg;codecs=opus", "audio/ogg"],
      mp4: ["audio/mp4;codecs=mp4a.40.2", "audio/mp4"]
    };
    if (format !== "auto" && byFormat[format]) return byFormat[format];
    return byFormat.webm.concat(byFormat.ogg, byFormat.mp4);
  }

  function audioQualityOptions() {
    var quality = state.settings.quality || selectedValue("ullme_audio_quality", "standard");
    var bits = {
      small: 32000,
      standard: 64000,
      high: 128000
    };
    return { audioBitsPerSecond: bits[quality] || bits.standard };
  }

  function selectedValue(id, fallback) {
    var input = byId(id);
    return input && input.value ? input.value : fallback;
  }

  function finishRecording() {
    if (!state.mediaRecorder || state.mediaRecorder.state !== "recording") return;
    state.shouldSave = true;
    setAudioStatus("Saving...");
    state.mediaRecorder.stop();
  }

  function cancelRecording() {
    if (!state.mediaRecorder || state.mediaRecorder.state !== "recording") {
      resetRecordingUi();
      return;
    }
    state.shouldSave = false;
    state.mediaRecorder.stop();
  }

  function handleRecordingStopped() {
    stopTimer();
    stopWaveform();
    stopStream();

    if (!state.shouldSave) {
      state.chunks = [];
      resetRecordingUi();
      return;
    }

    var blob = new Blob(state.chunks, { type: recordingType() });
    state.chunks = [];
    uploadRecording(blob);
  }

  function uploadRecording(blob) {
    var input = byId("ullme_audio_upload");
    if (!input) {
      setAudioStatus("Audio upload input is missing.");
      resetRecordingUiSoon();
      return;
    }

    var file = new File(
      [blob],
      "recording-" + timestampForFileName() + recordingExtension(blob.type),
      { type: blob.type || "audio/webm" }
    );

    if (typeof DataTransfer === "undefined") {
      setAudioStatus("Audio upload is not supported in this browser.");
      resetRecordingUiSoon();
      return;
    }

    var transfer = new DataTransfer();
    transfer.items.add(file);
    input.files = transfer.files;
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function recordingType() {
    if (state.mediaRecorder && state.mediaRecorder.mimeType) {
      return state.mediaRecorder.mimeType;
    }
    return "audio/webm";
  }

  function recordingExtension(type) {
    if (/mp4/.test(type)) return ".m4a";
    if (/ogg/.test(type)) return ".ogg";
    return ".webm";
  }

  function timestampForFileName() {
    return new Date().toISOString().replace(/[-:]/g, "").replace(/\..+$/, "").replace("T", "-");
  }

  function showRecordingUi() {
    var composer = document.querySelector(".ullme-composer");
    var voiceButton = byId("ullme_voice_btn");
    var label = document.querySelector(".ullme-recording-label");
    if (composer) composer.classList.add("ullme-composer-recording");
    if (voiceButton) {
      voiceButton.classList.add("ullme-voice-active");
      voiceButton.setAttribute("aria-pressed", "true");
    }
    if (!label || label.textContent !== "Format unavailable, using browser default.") {
      setAudioStatus("Recording");
    }
  }

  function showRecordingNotice(text) {
    showRecordingUi();
    stopTimer();
    setTimerText("0:00");
    setAudioStatus(text);
    resetRecordingUiSoon();
  }

  function resetRecordingUi() {
    var composer = document.querySelector(".ullme-composer");
    var voiceButton = byId("ullme_voice_btn");
    if (composer) composer.classList.remove("ullme-composer-recording");
    if (voiceButton) {
      voiceButton.classList.remove("ullme-voice-active");
      voiceButton.setAttribute("aria-pressed", "false");
    }
    state.mediaRecorder = null;
    state.shouldSave = false;
    setTimerText("0:00");
    setAudioStatus("Recording");
    clearWaveform();
  }

  function resetRecordingUiSoon() {
    window.setTimeout(resetRecordingUi, 1400);
  }

  function startTimer() {
    state.startedAt = Date.now();
    setTimerText("0:00");
    stopTimer();
    state.timerId = window.setInterval(function () {
      var elapsed = Math.floor((Date.now() - state.startedAt) / 1000);
      var minutes = Math.floor(elapsed / 60);
      var seconds = String(elapsed % 60).padStart(2, "0");
      setTimerText(minutes + ":" + seconds);
    }, 250);
  }

  function stopTimer() {
    if (state.timerId) {
      window.clearInterval(state.timerId);
      state.timerId = null;
    }
  }

  function setTimerText(text) {
    var timer = byId("ullme_recording_timer");
    if (timer) timer.textContent = text;
  }

  function setAudioStatus(text) {
    var label = document.querySelector(".ullme-recording-label");
    if (label) label.textContent = text;
  }

  function startWaveform() {
    var canvas = byId("ullme_recording_wave");
    var AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!canvas || !state.stream || !AudioContextClass) {
      clearWaveform();
      return;
    }

    state.audioContext = new AudioContextClass();
    state.analyser = state.audioContext.createAnalyser();
    state.analyser.fftSize = 1024;
    state.analyser.smoothingTimeConstant = 0.82;
    state.waveData = new Uint8Array(state.analyser.frequencyBinCount);
    state.waveLevels = new Array(28).fill(0.08);
    state.waveLevel = 0;
    state.waveLastDraw = 0;
    state.audioSource = state.audioContext.createMediaStreamSource(state.stream);
    state.audioSource.connect(state.analyser);
    drawWaveform();
  }

  function drawWaveform(timestamp) {
    var canvas = byId("ullme_recording_wave");
    if (!canvas || !state.analyser || !state.waveData) return;

    if (timestamp - state.waveLastDraw < 80) {
      state.waveFrameId = window.requestAnimationFrame(drawWaveform);
      return;
    }
    state.waveLastDraw = timestamp;

    var context = canvas.getContext("2d");
    var width = canvas.width;
    var height = canvas.height;
    var bars = state.waveLevels.length;
    var barGap = 3;
    var barWidth = Math.max(2, Math.floor((width - (bars - 1) * barGap) / bars));
    var level = currentAudioLevel();

    state.waveLevel = state.waveLevel * 0.7 + level * 0.3;
    state.waveLevels.shift();
    state.waveLevels.push(Math.max(0.08, state.waveLevel));

    context.clearRect(0, 0, width, height);
    context.fillStyle = "#bdbdbd";

    for (var i = 0; i < bars; i += 1) {
      var distanceFromCenter = Math.abs(i - (bars - 1) / 2) / ((bars - 1) / 2);
      var centerWeight = 1 - distanceFromCenter * 0.22;
      var barHeight = Math.max(4, Math.round(state.waveLevels[i] * centerWeight * height * 0.92));
      var x = i * (barWidth + barGap);
      var y = Math.round((height - barHeight) / 2);
      roundedRect(context, x, y, barWidth, barHeight, Math.min(barWidth / 2, 3));
    }

    state.waveFrameId = window.requestAnimationFrame(drawWaveform);
  }

  function currentAudioLevel() {
    state.analyser.getByteTimeDomainData(state.waveData);
    var sumSquares = 0;
    for (var i = 0; i < state.waveData.length; i += 1) {
      var centered = (state.waveData[i] - 128) / 128;
      sumSquares += centered * centered;
    }
    var rms = Math.sqrt(sumSquares / state.waveData.length);
    var gated = Math.max(0, rms - 0.015);
    return Math.min(1, Math.pow(gated * 3.2 * state.settings.sensitivity, 0.72));
  }

  function readSettingsFromUi() {
    state.settings.format = selectedValue("ullme_audio_format", state.settings.format);
    state.settings.quality = selectedValue("ullme_audio_quality", state.settings.quality);
    state.settings.sensitivity = clampSensitivity(selectedValue("ullme_mic_sensitivity", state.settings.sensitivity));
  }

  function applySettings(settings) {
    settings = settings || {};
    state.settings.format = validFormat(settings.format || state.settings.format);
    state.settings.quality = validQuality(settings.quality || state.settings.quality);
    state.settings.sensitivity = clampSensitivity(settings.sensitivity || state.settings.sensitivity);
    setSelectValue("ullme_audio_format", state.settings.format);
    setSelectValue("ullme_audio_quality", state.settings.quality);
    setSelectValue("ullme_mic_sensitivity", String(state.settings.sensitivity));
  }

  function loadSettingsFromBrowser() {
    var storage = browserStorage();
    if (!storage) return state.settings;
    try {
      var raw = storage.getItem(audioSettingsStorageKey());
      if (!raw) return state.settings;
      return JSON.parse(raw);
    } catch (error) {
      return state.settings;
    }
  }

  function saveSettingsToBrowser() {
    var storage = browserStorage();
    if (!storage) return;
    try {
      storage.setItem(audioSettingsStorageKey(), JSON.stringify(state.settings));
    } catch (error) {
      // A blocked or full browser store should not break recording.
    }
  }

  function audioSettingsStorageKey() {
    return "ullme.audioSettings.v1:" + window.location.pathname;
  }

  function browserStorage() {
    try {
      return window.localStorage || null;
    } catch (error) {
      return null;
    }
  }

  function validFormat(format) {
    return ["auto", "webm", "ogg", "mp4"].indexOf(format) >= 0 ? format : "auto";
  }

  function validQuality(quality) {
    return ["small", "standard", "high"].indexOf(quality) >= 0 ? quality : "standard";
  }

  function clampSensitivity(sensitivity) {
    sensitivity = Number(sensitivity);
    if (!Number.isFinite(sensitivity)) sensitivity = 3;
    return Math.min(8, Math.max(1, sensitivity));
  }

  function setSelectValue(id, value) {
    var input = byId(id);
    if (input) input.value = value;
  }

  function roundedRect(context, x, y, width, height, radius) {
    context.beginPath();
    context.moveTo(x + radius, y);
    context.lineTo(x + width - radius, y);
    context.quadraticCurveTo(x + width, y, x + width, y + radius);
    context.lineTo(x + width, y + height - radius);
    context.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
    context.lineTo(x + radius, y + height);
    context.quadraticCurveTo(x, y + height, x, y + height - radius);
    context.lineTo(x, y + radius);
    context.quadraticCurveTo(x, y, x + radius, y);
    context.fill();
  }

  function stopWaveform() {
    if (state.waveFrameId) {
      window.cancelAnimationFrame(state.waveFrameId);
      state.waveFrameId = null;
    }
    if (state.audioContext) {
      state.audioContext.close();
      state.audioContext = null;
    }
    state.audioSource = null;
    state.analyser = null;
    state.waveData = null;
    state.waveLevels = [];
    state.waveLevel = 0;
    state.waveLastDraw = 0;
  }

  function clearWaveform() {
    var canvas = byId("ullme_recording_wave");
    if (!canvas) return;
    canvas.getContext("2d").clearRect(0, 0, canvas.width, canvas.height);
  }

  function stopStream() {
    if (!state.stream) return;
    state.stream.getTracks().forEach(function (track) {
      track.stop();
    });
    state.stream = null;
  }

  function receiveStoredAudio(records) {
    var record = records && records.length ? records[records.length - 1] : null;
    if (record) {
      setAudioStatus("Saved");
      window.ullme = window.ullme || {};
      window.ullme.lastAudioRecording = record;
    }
    resetRecordingUiSoon();
  }

  window.ullmeAudio = window.ullmeAudio || {};
  window.ullmeAudio.startRecording = startRecording;
  window.ullmeAudio.cancelRecording = cancelRecording;
  window.ullmeAudio.finishRecording = finishRecording;
  window.ullmeAudio.receiveStoredAudio = receiveStoredAudio;
  window.ullmeAudio.applySettings = applySettings;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
