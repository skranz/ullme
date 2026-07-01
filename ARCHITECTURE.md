# uLLMe Architecture

## Runtime And State Ownership

uLLMe is an R package built on Shiny and shinyEvents. `ullmeApp()` creates an
`eventsApp()` and registers explicit event and change handlers instead of using
reactive expressions throughout the application.

Each Shiny app instance has its own `app` object. User- and session-specific
state therefore lives directly on `app`, including:

- `app$userid`
- `app$role` and `app$allowed_roles`
- `app$semester`
- `app$courseids` and `app$courseid`
- user, session, image, and audio paths
- the current material category

`app$glob` is shared across app instances. It is reserved for genuinely shared
configuration, currently `app$glob$main_dir`. Per-user state must not be stored
there.

## Browser And Server Ownership

R builds a stable HTML shell and loads:

```text
inst/www/ullme-chat.css
inst/www/ullme-chat.js
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

All roles use one compact application bar containing:

- the `uLLMe` brand
- role selector
- semester selector
- course selector for teacher and student roles
- add-course button for teacher and student roles
- personal-settings button

The personal-settings popover displays the instance userid and gives teachers
direct access to the AI Tutor and Skill libraries.

Teacher mode divides the workspace into two equal panes. The course pane is on
the left and chat is on the right. The course pane has these tabs:

1. AI Tutors
2. Materials
3. Settings

AI Tutors contains the tutor families installed in the selected course and
opens a library of resolved tutor definitions. Materials and Settings remain
mounted in the stable shell and are switched client-side. The material upload
command is an icon at the right side of the tab row and is shown only for the
Materials tab.

Skills belong to the teacher assistant rather than the course tab row. A
composer button opens the resolved Skill catalog. Selecting a Skill displays
its introduction, starter prompts, and composer placeholder above the composer
until the teacher clears it or selects another Skill.

Both catalogs, installed Tutor cards, and personal settings can open the shared
Definition Workspace. It is a large overlay rather than a permanent third
column. Its source-grouped sidebar shows Package, General, Personal, and
course-local definitions, including shadowed copies. The editor exposes the
Markdown and YAML files inside the selected definition.

Package and General definitions are read-only in teacher mode. Personal
definitions and course-local Tutor definitions are editable. Teachers can
create personal definitions, copy a definition into their personal library, or
copy a resolved Tutor definition into the selected course before editing it.
YAML is parsed and definition IDs are checked before a file is saved.

Editable copies can be deleted independently of course Tutor installation.
Deleting a copy restores normal definition resolution. Skills download as ZIP
bundles and import from validated ZIP bundles; Tutor definitions download and
import as YAML. Imports target Personal storage or, for Tutors, the selected
course. Conflicts replace complete copies rather than merging files.

The Definition Assistant is an optional adaptive panel. Opening it collapses
the source library into a definition picker and divides the workspace between
the editor and chat. Assistant rewrites modify only the browser's unsaved
editor draft and provide Undo; the existing Save action remains the only path
to disk. The fake-AI implementation exercises this protocol while structured
responses from a real model remain to be connected.

Student and admin modes reuse the same chat pane at full width. They do not
create a separate chat implementation.

## shinyEvents Boundary

`ullme_register_handlers()` registers the main application boundary:

- `ullme_submit_chat_event`: submits text, model, message IDs, and image
  metadata.
- `ullme_image_upload`: stores images selected or pasted into the chat.
- `ullme_role_select_event`: updates `app$role` and refreshes courses.
- `ullme_semester_select_event`: updates `app$semester` and refreshes courses.
- `ullme_course_select_event`: updates `app$courseid`.
- `ullme_add_course_event`: creates and selects a course.
- `ullme_course_settings_save_event`: writes course settings to `course.yaml`.
- `ullme_material_category_event`: records the active material category.
- `ullme_material_delete_event`: validates and deletes a material file.
- `ullme_material_upload_<category>`: stores files for one material category.
- `ullme_ai_tutor_add_event`: installs a resolved tutor definition in the
  selected course.
- `ullme_ai_tutor_toggle_event`: enables or disables an installed course tutor.
- `ullme_skill_activate_event`: activates one resolved Skill for the teacher
  assistant.
- `ullme_skill_clear_event`: clears the active Skill.
- `ullme_definition_action_event`: opens the Definition Workspace and performs
  server-validated create, copy, delete, import, download, and save operations.
- `ullme_definition_import_tutor` and `ullme_definition_import_skill`: upload
  Tutor YAML and Skill ZIP files for validation and import preview.
- `ullme_definition_chat_event`: constructs definition-scoped context and
  returns an in-memory rewrite draft.

Audio handlers are registered separately by `ullme_register_audio_handlers()`.

After role, semester, course, settings, material, Tutor, or Skill changes, R
calls `window.ullme.updateCourseList(...)`. The browser updates selectors,
role-aware layout classes, settings fields, tutor cards, Skill state, and
material lists without rebuilding the UI.

## Users, Roles, And Semesters

`ullmeApp()` accepts `userid`, `role`, and `allowed_roles`. Supported roles
are `teacher`, `student`, and `admin`.

The role-independent user directory is:

```text
main_dir/users/<userid>
```

Role-specific directories are:

```text
main_dir/teachers/<userid>
main_dir/students/<userid>
```

Course storage is currently available for teacher and student roles. Admin has
no course directory.

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
main_dir/<role>s/<userid>/courses/<semester>/<courseid>
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
times:
  - weekday: monday
    start: "10:00"
    end: "12:00"
```

Up to three time slots are retained. Settings are normalized before writing,
and missing `times` become an empty list.

The intended JSON Schema, expressed as YAML, is stored at:

```text
inst/specs/course.schema.yaml
```

Runtime YAML reads and writes do not currently invoke schema validation. There
is also a known contract mismatch to resolve before enabling validation: the UI
writes full lowercase weekday names such as `monday`, while the schema
currently enumerates two-letter values such as `mo`.

## Materials

Each course stores material below one common root:

```text
<course-dir>/materials/general
<course-dir>/materials/slides
<course-dir>/materials/ps
<course-dir>/materials/quiz
<course-dir>/materials/background
```

`general` is the destination for material that has not yet been classified.
Existing files found in legacy top-level category directories are copied into
the corresponding new directory when material storage is initialized.

The browser supports the upload icon, clicking the drop area, and drag and
drop. The selected category determines which hidden Shiny file input receives
the files. After R stores an upload, it refreshes course state and calls
`window.ullme.materialUploadComplete(...)`; the browser then clears both the
DOM file input and its Shiny value so later uploads are treated as new input.

Normal files are copied with cleaned filenames. ZIP files are unpacked into the
selected category. ZIP entries with absolute paths or parent-directory
traversal are rejected.

Deletion accepts a category and relative path. R rejects absolute paths and
parent traversal, normalizes the target, verifies that it remains inside the
category directory, and only then deletes the file.

`ullmeApp(max_upload_mb=100)` raises Shiny's process-wide request-size option
to at least the configured value. Upload state itself remains instance-specific.

## Chat And Image Flow

Chat submission follows this sequence:

1. JavaScript appends the user message immediately.
2. JavaScript appends an assistant placeholder with an `assistantMessageId`.
3. JavaScript sends `ullme_submit_chat_event`.
4. R calls `ullme_ask_ai()`.
5. R calls `window.ullme.receiveAssistantMessage(...)`.
6. JavaScript replaces the placeholder and adds assistant actions.

The first assistant message comes from `ullme_intro_msg()` and can later become
course- or user-specific.

Images can be selected with the composer button or pasted from the clipboard.
The browser uses `FileReader` for immediate previews and assigns files to the
hidden Shiny input. R copies them under:

```text
main_dir/users/<userid>/cur_session/images/<session-token>/<upload-id>_<filename>
```

The image root is exposed as the `ullme-uploads` Shiny resource path.

The model selector is included in the chat payload but backend model routing is
still a placeholder. Copy and redo actions are client-side; redo resends the
saved submit payload for that assistant message.

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
