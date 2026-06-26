# uLLMe Chat Architecture

## UI Ownership

The chat screen is intentionally client-heavy. R builds a stable HTML shell and loads `inst/www/ullme-chat.css` and `inst/www/ullme-chat.js`; the browser owns transient UI state such as draft text, local image previews, message insertion, the thinking placeholder, composer resizing, model selection, and the voice button state.

This keeps the Shiny server focused on work that actually needs R: storing uploaded files, calling the AI backend, and sending the final assistant answer back to the browser.

## R / shinyEvents Boundary

The app uses `eventsApp()` and registers explicit shinyEvents handlers in `ullme_register_handlers()`.

- `ullme_submit_chat_event`: sent by JavaScript when the user submits a message. The payload includes the text, selected model, client message id, assistant placeholder id, and upload metadata.
- `ullme_image_upload`: handled through Shiny's file input binding when the hidden file input changes. The server copies uploaded image files into the active user's current session image folder.

The fake AI answer still comes from `ullme_ask_ai()`. When a real AI backend is added, `ullme_handle_chat_submit()` is the main integration point.

## Message Flow

1. JavaScript appends the user message immediately.
2. JavaScript appends an assistant placeholder with the matching `assistantMessageId`.
3. JavaScript sends `ullme_submit_chat_event` to Shiny.
4. R calls `ullme_ask_ai()`.
5. R calls `window.ullme.receiveAssistantMessage(assistantMessageId, answer)`.
6. JavaScript replaces the placeholder text and adds assistant action buttons.

The first assistant message is created through `ullme_intro_msg()`. It is currently simple on purpose so it can later become course-, user-, or context-specific.

## Users And Roles

`ullmeApp()` accepts `username` and `role`, where role is either `teacher` or `student`. For every username the app creates a role-independent user folder and both role-specific folders:

```text
main_dir/users/<username>
main_dir/teachers/<username>
main_dir/students/<username>
```

The active role is still available in `app$glob$role_user_dir`. Shared server-side data that should follow the person across teacher/student contexts belongs under `main_dir/users/<username>`.

## Upload Storage

Uploaded images are copied under:

```text
main_dir/users/<username>/cur_session/images/<session-token>/<upload-id>_<clean-file-name>
```

The app exposes `main_dir/users/<username>/cur_session/images` as the Shiny resource path `ullme-uploads`, so stored files can later be referenced from the browser if needed. The current UI uses local `FileReader` previews immediately and then records the server-side upload id once R confirms storage.

Images can arrive either through the upload button or by pasting from the clipboard. The browser normalizes pasted clipboard images into named `File` objects, assigns them to the hidden Shiny file input, and shows thumbnail previews inside the composer.

## Current Placeholders

The model selector is UI-ready but intentionally light. The selected model is included in the submit payload and can be connected to backend model routing without changing the chat layout.

Assistant messages keep enough client-side metadata to support local action buttons. Copy reads the rendered answer text, while redo resends the saved submit payload and replaces the existing assistant answer when the server returns.

The sidebar is also client-owned. Its hide/show state toggles a class on the app shell, letting CSS move the main chat window and composer into the freed space without a server round-trip.

## Audio Recording

Audio recording is implemented in `inst/www/ullme-audio.js` with the browser `MediaRecorder` API, avoiding an extra JavaScript dependency. Pressing the microphone button switches the composer into a recording state with cancel, timer/status, and done controls.

The recording UI offers format and quality choices. `Auto` prefers efficient Opus-based WebM when the browser supports it, then falls back through Ogg and MP4. Quality maps to `audioBitsPerSecond`: Small is 32 kbps, Standard is 64 kbps, and High is 128 kbps. Browsers may ignore or adjust these hints, so the client uses feature detection and falls back to the browser default if a selected MIME type is unavailable.

While recording, a lightweight waveform is drawn on a canvas using the Web Audio `AnalyserNode`. This stays entirely client-side and is only a visual indication of current microphone level. The `Mic sensitivity` setting changes the waveform scaling, not guaranteed hardware microphone gain.

Audio format, quality, and mic sensitivity are stored in browser `localStorage` under an app-specific key. This is intentionally not a cookie and not server-side JSON: the preference is device/browser-specific, should not be sent with every request, and may sensibly differ between a laptop, office PC, or phone.

When the user presses Done, the browser creates an audio `File` from the recorded blob and assigns it to the hidden Shiny file input `ullme_audio_upload`. The R handler in `R/audio.R` receives the normal Shiny upload metadata and copies the file into:

```text
main_dir/users/<username>/cur_session/audio/<session-token>/<audio-id>_<clean-file-name>
```

The handler then calls `window.ullmeAudio.receiveStoredAudio(...)` with the stored file record, including the server-side path. The most recent record is also kept in `app$glob$last_audio_recording`.
