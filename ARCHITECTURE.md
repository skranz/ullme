# uLLMe Architecture

## Scratch Files

`my_prompt.Rmd` and `ai_resp.md` are temporary files used to interact with
other AI tools. Ignore them during repository changes; they never need to be
read, updated, or kept in sync with source files.

## Runtime And State Ownership

uLLMe is an R package built on Shiny and shinyEvents. `teacherApp()` and
`studentApp()` create fixed-role `eventsApp()` instances and register explicit
event and change handlers instead of using reactive expressions throughout the
application. Shared construction and handlers live in `R/ullme.R`; the
role-specific constructors and workspace markup live in `R/teacherApp.R` and
`R/studentApp.R`.

Each Shiny app instance has its own `app` object. User- and session-specific
state therefore lives directly on `app`, including:

- `app$userid`
- `app$teacherid` for active teacher workspaces
- `app$studentid` for student-role storage
- the fixed `app$role` and `app$app_kind`
- `app$semester`
- `app$courseids` and `app$courseid`
- user, session, image, and audio paths
- the current material category and transient folder-upload path map

`app$glob` is shared across app instances. It is reserved for genuinely shared
configuration, currently `app$glob$main_dir`. Per-user state must not be stored
there.

## Browser And Server Ownership

R builds a stable HTML shell and loads:

```text
inst/www/ullme-teacher.css or inst/www/ullme-student.css
inst/www/ullme-materials.js
inst/www/ullme-chat.js
inst/www/ullme-teacher.js or inst/www/ullme-student.js
inst/www/ullme-tutors.js
inst/www/ullme-audio.js
```

The browser owns transient interaction state: draft text, local image previews,
message insertion, assistant placeholders, composer sizing, dropdown menus,
course-tab selection, tutor- and skill-catalog rendering, material-list
rendering, and audio recording controls.

The R server owns persistent or trusted work: filesystem discovery, file
storage and deletion, YAML reads and writes, role/semester/course state, and AI
calls. R sends updated course state and final assistant answers back through
explicit JavaScript calls.

## Application Layout

Both apps use one compact application bar containing:

- the `uLLMe` brand
- a fixed Teacher or Student label
- semester selector
- course selector
- add-course button in the teacher app
- personal-settings button

The personal-settings popover displays the instance userid and gives teachers
access to Skill and agent settings. AI Tutors are added from the rail's Add
menu.

Teacher mode divides the workspace into a compact navigation rail, the main
work surface, and a resizable AI assistant pane. The global Usage dashboard is
the initial view; Materials and Settings are fixed course rail entries. Each
installed AI Tutor and each course Skill receive a dynamic rail entry. The
active Skill is highlighted. The Add menu opens the Tutor-template or Skill
catalog. A bottom settings group currently contains the Users view, where
authorized teachers edit `allowed_users.yaml` through a table rather than a raw
YAML editor. The main teacher listed in `general/teachers.yaml` is shown as a
protected row and cannot be removed.

Selecting a Tutor opens one course-local Tutor with Instances, Definition, and
YAML tabs. `course/ai_tutors/<tutorid>/tutor.yml` is always a complete,
editable definition copied from a flat package template in
`inst/ai_tutors/<tutorid>.yml`. `docs_per_instance` and `docs_per_course`
define the required document roles. Each role's ordered `file_types` list
defines its allowed extensions and preference order. Reviewed assignments are stored in
`course/ai_tutors/<tutorid>/instances.yml`.

The YAML pane exposes the complete course-local `tutor.yml` and `instances.yml`
as Definition and Instances subtabs. Instance discovery scans preferred material
directories recursively and considers only the role's ordered `file_types`.
`R/convert.R` performs manual Pandoc
conversions beside the source document and extracts media into a sibling
`figures--<converted-filename>` directory, replacing dots in the filename with
underscores (for example, `ps1.md` uses `figures--ps1_md`). The Instances YAML
subtab can invoke these conversions. The Materials batch bar
also exposes format-specific actions plus `all -> md, txt` and
`all -> overwrite`. The mixed actions consider only selected DOCX and PDF
files, routing DOCX to `.md` and PDF to `.txt`; only the explicit overwrite
action replaces existing destinations. The material tree refreshes after
conversion completes.
`R/convert_pdf.R` implements the PDF path by invoking the system `pdftotext`
executable.

The Instances tab's **Make Instances** action opens a guidance dialog and sends
an instance-builder request through the normal assistant pane. The rendered
`inst/prompts/instance_builder.txt` prompt includes a definition-derived
example YAML, every recursive filename beneath `materials/ps`, and the
teacher's guidance. The specialized assistant receives only
`write_rtutor_instances_yaml`; it does not inspect or convert files. That tool
validates YAML structure, document roles, unique instance IDs, and assigned
file paths before atomically replacing `instances.yml`, and returns an
assignment summary. It commits without an approval dialog while still using
the shared transaction backup and history mechanism. Committed changes refresh
the Tutor UI.
`ullme_test_instance_builder()` exposes the same prompt and tool workflow
outside Shiny for prompt development.

All ULLME-managed Tutor YAML, instance YAML, course settings, Skill assignment,
and course-file edits use the same transaction history. The **Edits & undo**
navigation item opens recent changes and restores an earlier version only when
the target has not changed since that edit. Tutor panes expose the same history
through their header shortcut.

Skills belong to the teacher assistant rather than the course tab row. A
composer button opens the resolved Skill catalog. Selecting a Skill displays
its introduction, starter prompts, and composer placeholder above the composer
until the teacher clears it or selects another Skill.

The legacy Definitions work surface is not part of Teacher Studio. Tutor
editing belongs to the selected Tutor pane. Skill definitions may still use
their dedicated library tooling.

The Definition Assistant is an optional adaptive panel. Opening it collapses
the source library into a definition picker and divides the workspace between
the editor and chat. Assistant rewrites modify only the browser's unsaved
editor draft and provide Undo; the existing Save action remains the only path
to disk. The fake-AI implementation exercises this protocol; real models
return a validated structured draft.

The student app builds a chat-first workspace without the Teacher Studio,
teacher navigation, or pane resizers. It reuses the common chat implementation
while keeping its constructor and workspace markup separate.

## shinyEvents Boundary

With `login_check="sel"`, the initial UI contains only the
shinyEventsLogin output container. Course state, user directories, dynamic
resource paths, and the full teacher/student UI are initialized only after the
login callback succeeds. Authenticated emails are converted to normalized
userids through the constructor's `email2userid` function, defaulting to
`ullme_email2userid()` for `@uni-ulm.de` addresses. The original email is
stored as `main_dir/users/<userid>/email.txt`. Teacher workspaces are declared
in `main_dir/general/teachers.yaml`, while per-teacher access is read from
`main_dir/teachers/<teacherid>/config/allowed_users.yaml`. If a userid has
access to multiple teacher IDs, the teacher app shows a workspace chooser
before initializing course state. Students receive a stable random
`studentid` stored in `main_dir/users/<userid>/studentid.txt`. Upload, audio,
and download resource prefixes are random per authenticated Shiny session and
are removed when that session ends.

`ullme_register_handlers()` registers the main application boundary:

- `ullme_submit_chat_event`: submits text, model, message IDs, and image
  metadata.
- `ullme_image_upload`: stores images selected or pasted into the chat.
- `ullme_semester_select_event`: updates `app$semester` and refreshes courses.
- `ullme_course_select_event`: updates `app$courseid`.
- `ullme_add_course_event`: creates and selects a course.
- `ullme_course_settings_save_event`: writes course settings to `course.yaml`.
- `ullme_allowed_users_save_event`: validates and writes the active teacher's
  `config/allowed_users.yaml`.
- `ullme_usage_statistics_refresh_event`: starts an incremental deferred usage
  aggregation.
- `ullme_material_category_event`: records the active material category.
- `ullme_material_delete_event`: validates and deletes one material file.
- `ullme_material_operation_event`: copies, moves, or deletes selected material
  files through the containment-checked helpers in `R/ullme_io.R`.
- `ullme_material_create_directory_event`: creates a subdirectory below the
  active course's material root.
- `ullme_material_upload_<category>`: stores files for one material category.
- `ullme_ai_tutor_add_event`: copies a Tutor template into the selected course.
- `ullme_ai_tutor_toggle_event`: enables or disables an installed course tutor.
- `ullme_ai_tutor_save_event`: validates and saves the selected course Tutor's
  form or YAML definition.
- `ullme_skill_activate_event`: activates one resolved Skill for the teacher
  assistant.
- `ullme_skill_clear_event`: clears the active Skill.
- `ullme_definition_action_event`: supports the remaining Skill-library
  definition actions.
- `ullme_definition_import_tutor` and `ullme_definition_import_skill`: upload
  Tutor YAML and Skill ZIP files for validation and import preview.
- `ullme_definition_chat_event`: constructs definition-scoped context and
  returns an in-memory rewrite draft.

Audio handlers are registered separately by `ullme_register_audio_handlers()`.

After semester, course, settings, material, Tutor, or Skill changes, R
calls `window.ullme.updateCourseList(...)`. The browser updates selectors,
  fixed-role layout classes, settings fields, Tutor panes, Skill state, and
material lists without rebuilding the UI.

## Users, Roles, And Semesters

`teacherApp()` accepts a human `userid` and a teacher workspace `teacherid`;
when `teacherid` is omitted in no-login mode it defaults to `userid`.
`teacherApp(base_url_student=...)` records the base Shiny Server URL where
student course apps are mounted. For teacher `skranz` and course `Umwelt`, the
course app base URL is:

```text
<base_url_student>/skranz/Umwelt
```

Course Settings show that base URL and a plain newline-separated list of
Tutor/instance URLs using `sem=<semester>`, `tutor=<tutorid>`, and
`inst=<instanceid>`.
`studentApp()` accepts a student `userid` plus `teacherid`, `courseid`, and
optional `semester`, `tutorid`, and `instanceid`. These student-context identifiers can also come from URL query
parameters when the matching constructor argument is `NULL`; constructor
arguments always win. An app's role cannot be changed after construction.
For student apps, `sem`, `tutor`, and `inst` are accepted as aliases for
`semester`, `tutorid`, and `instanceid`. URL-selected values are initial
defaults, not permanent locks; the student header can switch semester, Tutor,
and instance when alternatives exist.

The student app's default semester for a teacher/course is selected only among
semesters where the course exists, preferring semesters that contain at least
one enabled Tutor. The calendar target is the winter semester from October 15
through April 30 and the summer semester otherwise. If the target semester does
not have a course with an enabled Tutor, the closest available semester is
chosen.

The role-independent user directory is:

```text
main_dir/users/<userid>
```

User mapping files are:

```text
main_dir/users/<userid>/email.txt
main_dir/users/<userid>/studentid.txt
main_dir/users/<userid>/teacherids.txt
```

Teacher workspace directories are:

```text
main_dir/teachers/<teacherid>
main_dir/teachers/<teacherid>/config/allowed_users.yaml
```

Student role storage uses the random student ID:

```text
main_dir/students/<studentid>
```

Course storage is available for teacher and student apps. Teacher courses are
owned by `teacherid`, not by the human `userid`.

Semesters use these abbreviations:

```text
SS25
WS2526
SS26
WS2627
```

The current semester is derived from the date. The browser selector receives a
sequence around that semester, while R validates every selected abbreviation.

## Course Discovery And Storage

Courses are discovered directly from directory names:

```text
main_dir/teachers/<teacherid>/courses/<semester>/<courseid>
main_dir/students/<studentid>/courses/<semester>/<courseid>
```

For example:

```text
main_dir/teachers/skranz/courses/SS26/Umwelt
```

`ullme_user_courseids()` lists and sorts the course directories for the active
user, role, and semester. The first course is selected when no preferred
selection remains available.

Creating a course creates its directory, material subdirectories, and
`course.yaml`. Course IDs are restricted to letters, numbers, underscores, and
hyphens and must start with a letter.

## Course YAML

Each course directory contains:

```text
course.yaml
```

Its logical structure is:

```yaml
courseid: Umwelt
coursename: Umweltökonomik
```

Settings are normalized before writing.

The intended JSON Schema, expressed as YAML, is stored at:

```text
inst/specs/course.schema.yaml
```

Runtime YAML reads and writes do not currently invoke schema validation.

## Temporary directories

Temporary working directories are created by `ullme_tempdir()` below
`<main_dir>/temp`. Recursive removal is centralized in
`ullme_remove_tempdir()`. It canonicalizes both paths, refuses the temp root
itself, requires the target to be a strict descendant, and rejects symbolic
links or tree entries resolving outside that exact temporary directory.

Non-temporary user paths scheduled for deletion are first checked against the
user's authorized roots and atomically moved into one of these guarded
temporary directories. Do not add direct `unlink` calls in application code,
tests, examples, or documentation snippets. Directory-tree removal must go
through checked helper functions such as `ullme_remove_tempdir()`,
`ullme_remove_course_dir()`, `ullme_remove_teacher_dir()`, or the lower-level
`ullme_remove_checked_directory()` wrapper.

## Materials

Each course stores material below one common root:

```text
<course-dir>/materials
<course-dir>/materials/slides
<course-dir>/materials/ps
```

New courses create only `slides` and `ps` below the root by default. Existing
files found in legacy top-level category directories are copied into the
corresponding material subdirectory when material storage is initialized.

The Materials tab renders material folders and files as a file
tree. Clicking the Name or Modified heading sorts siblings and toggles the sort
direction. Folder checkboxes select descendant files; empty folder checkboxes
select the folder itself so it can be deleted. Selected files can be dragged
onto another folder to move them, while files or complete folder trees dragged
from the local computer onto a folder are uploaded directly into that directory.
Drops on the material file area itself upload into the main `materials` root.
Folder traversal preserves nested and empty directories. Compact move, copy,
and delete controls remain available as keyboard-friendly alternatives.

`inst/www/ullme-materials.js` owns pointer and drag gestures for the tree:
rectangle selection (with Ctrl/Cmd additive selection), multi-file dragging,
and resolution of row drop targets. Dropping onto a file resolves to that
file's parent directory. Rendering, sorting, and server messaging remain in
`ullme-teacher.js`.

All UI file operations pass paths relative to the active course's `materials`
directory to `delete_material_file()`, `move_material_file()`,
`copy_material_file()`, or `create_material_directory()` in `R/ullme_io.R`.
Those helpers derive the material root from the active app and course,
canonicalize it, reject absolute and parent paths,
check existing ancestors (including resolved links), and re-check containment
before changing the filesystem. Batch deletion accepts files and empty
directories, but never the `materials` root and never recursively deletes a
non-empty directory.

The browser supports the upload icon, clicking the drop area, and drag and
drop. The selected destination determines which hidden Shiny file input receives
the files, with a dedicated root input for `materials` itself. After R stores an
upload, it refreshes course state and calls
`window.ullme.materialUploadComplete(...)`; the browser then clears both the
DOM file input and its Shiny value so later uploads are treated as new input.

Normal files are copied with cleaned filenames. German filename characters are
transliterated (`Ü` to `Ue`, `ä` to `ae`, `ß` to `ss`, and so on) before the
ASCII safety filter is applied. ZIP files are unpacked into the
selected destination. ZIP entries with absolute paths or parent-directory
traversal are rejected.

`teacherApp(max_upload_mb=100)` and `studentApp(max_upload_mb=100)` raise
Shiny's process-wide request-size option
to at least the configured value. Upload state itself remains instance-specific.

## Chat And Image Flow

Chat submission follows this sequence:

1. JavaScript appends the user message immediately.
2. JavaScript appends an assistant placeholder with an `assistantMessageId`.
3. JavaScript sends `ullme_submit_chat_event`.
4. R starts an asynchronous model request; ellmer owns the model/tool loop.
5. Tool request and result callbacks update a visible activity line and write
   structured trace records beneath the interaction directory.
6. Streaming updates replace the placeholder as text or thinking arrives.
7. The completed update adds assistant actions and unlocks the composer.

uLLMe always consumes ellmer's rich content stream internally, even when
thinking is hidden. Tool-only model output therefore counts as provider
activity and cannot be mistaken for a stalled connection.

Mutating tools that require approval return an unresolved promise to ellmer.
The approval dialog resolves that promise with the committed or rejected
result, after which ellmer resumes the same model/tool conversation. Model and
browser response watchdogs pause while user approval is pending. Stopping the
chat rejects any pending change and settles its tool promise.

Only one pending `Thinking...` placeholder is rendered. Both browser and server
apply a three-minute response watchdog. Provider errors replace that placeholder
with a visible error, and a Shiny disconnect also finalizes the browser request
instead of leaving the composer permanently busy. Server cleanup runs even when
delivery of the final browser callback fails.

While a response is active, the composer send button becomes a stop button.
Streaming requests use ellmer's stream controller, so stopping marks the request
inactive, cancels transport consumption, preserves any partial answer, and
immediately unlocks the composer. Gemma 4 uses its own NVIDIA request profile:
thinking is disabled through `chat_template_kwargs` and the Nemotron-specific
`reasoning_budget` parameter is omitted.

When `store_ai_interactions=TRUE` (the default), main chat, instance-builder,
and Definition Assistant requests write prompt, response, thinking, error, and
status metadata beneath the active course's `ai_interactions/` directory.
Main-chat tool activity is stored as ordered YAML records under
`tool_events/`; sensitive argument names are redacted and long values are
truncated.

For student apps, `never_save_chats=TRUE` is the default and overrides both
`store_ai_interactions` and the Tutor's `chat_history` flag. Chat text then
exists only in the live app process. Anonymous, content-free usage metadata is
written separately to one CSV per chat under `main_dir/session_stats/`.

`R/usage_statistics.R` owns teacher analytics. Each teacher has an incremental
manifest, per-session normalized caches, course summaries, and a teacher-wide
daily summary under:

```text
main_dir/teachers/<teacherid>/usage_statistics/
```

The teacher app sends the cached dashboard immediately, then uses `later` to
read new or changed source files and rebuild affected course summaries in
small batches. Teacher summaries are combined from the course level. A lock
directory prevents concurrent teacher sessions from writing the same
aggregate, and completed CSV files are replaced through temporary files.

The first assistant message comes from `ullme_intro_msg()` and can later become
course- or user-specific.

Images can be selected with the composer button or pasted from the clipboard.
The browser uses `FileReader` for immediate previews and assigns files to the
hidden Shiny input. R copies them under:

```text
main_dir/users/<userid>/cur_session/images/<session-token>/<upload-id>_<filename>
```

The image root is exposed as the `ullme-uploads` Shiny resource path.

The model selector is included in the chat payload and validated against the
active provider catalog. For NVIDIA, the live `/models` result is intersected
with the ordered allowlist in `R/nvidia_api.R`, while preserving NVIDIA's exact
returned IDs. Gemma 4 31B is the first default; an explicitly configured
allowlisted model wins when it is live. The selector can also restrict results
to models known to accept both image and text. Speech-model helpers currently
advertise Magpie TTS ZeroShot and Nemotron VoiceChat without implementing
speech inference. Copy and redo actions are client-side; redo resends the saved
submit payload for that assistant message.

## Audio Recording

`inst/www/ullme-audio.js` uses the browser `MediaRecorder` API. The composer
provides cancel, timer/status, done, format, quality, and microphone-sensitivity
controls.

Format selection prefers efficient Opus-based WebM and falls back through Ogg
and MP4 according to browser support. Quality maps to requested bit rates of
32, 64, or 128 kbps. Browsers may adjust or ignore these hints.

A canvas waveform uses a Web Audio `AnalyserNode`. Microphone sensitivity
changes waveform scaling, not guaranteed hardware gain.

Audio preferences are stored in browser `localStorage`. Finished recordings
are assigned to `ullme_audio_upload` and copied to:

```text
main_dir/users/<userid>/cur_session/audio/<session-token>/<audio-id>_<filename>
```

R returns the stored record through
`window.ullmeAudio.receiveStoredAudio(...)` and keeps the latest record in
`app$last_audio_recording`.
