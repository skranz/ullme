# uLLMe AI Tutors

An AI Tutor is a student-facing assistant whose behavior and required
documents are declared in YAML.

## Package templates

Reusable templates are flat package files:

```text
inst/ai_tutors/<tutorid>.yml
```

The core fields are:

- `tutorid`, `lang`, `label`, `description`, and `shown_text`;
- `system_prompt`;
- `default_personality`;
- `docs_per_instance`;
- `placeholder_documents`;
- `multiple_instances` and `chat_history`;
- `file_permissions`;
- `allowed_tools`; and
- `allowed_student_customization`.

`shown_text` is rendered as the Tutor's first chat message in the student
application. It supports the same Markdown and MathJax rendering as other
assistant messages.

Prompt placeholders refer directly to document IDs and customization IDs. For
example, `{{ps}}`, `{{ps_sol}}`, and `{{personality}}`.

## Course copies

Adding a Tutor copies the complete package template to:

```text
<course>/ai_tutors/<tutorid>/tutor.yml
```

The course copy is authoritative and editable. A running course Tutor never
reads the package template directly.

## Document specifications

`docs_per_instance` defines documents that differ between Tutor instances.
`placeholder_documents` maps prompt placeholder names directly to files below
the course's `materials` folder:

```yaml
placeholder_documents:
  knowledge_start: knowledge.md
```

Missing placeholder files render as `[content missing]`.

`docs_per_instance` metadata entries may contain:

```yaml
descr: Human-readable description
file_types: [md, tex, pdf]
pref_doc_dir: ps
add_images: true
```

The Definition tab edits these mappings as tables. The YAML tab exposes the
complete course definition.

## Instance assignments

Reviewed document assignments are stored in:

```text
<course>/ai_tutors/<tutorid>/instances.yml
```

Example:

```yaml
course_docs: {}
instances:
  - instanceid: ps1
    docs:
      ps: [ps/ps1.pdf]
      ps_sol: [ps/ps1_sol.pdf]
```

If no saved assignment exists, uLLMe scans each document role's
`pref_doc_dir`, groups likely matching files, and presents suggestions in the
Instances tab. The teacher reviews and saves the resulting table.

Set `multiple_instances: false` for one course-wide Tutor. Such Tutors do not
read or create `instances.yml`, and the teacher and student applications hide
their instance controls. The default is `true` for backwards compatibility.

## File tools

`file_permissions` defines the course paths exposed through Tutor tools:

```yaml
file_permissions:
  - type: read_only
    main_path: materials
    directories: [scripts, slides]
    recursive: true
    extensions: [md, tex, txt, Rmd, qmd]
allowed_tools: [read_allowed_files, list_allowed_files]
```

`list_allowed_files` reports the configured directories and whether each
permission permits reading or writing. `read_allowed_files` rejects files
outside those directories, below a non-recursive level, or with an unlisted
extension. `write_and_read` is supported for future write-capable tools.

## Sessions

A Tutor session belongs to one student, course Tutor, and Tutor instance.
With `chat_history: true`, conversations are stored per student, semester,
course, and Tutor and shown in a left sidebar. The ten most recent chats are
shown first, with older chats under **More**. The default is `false`.

`studentApp(never_save_chats=TRUE)` is the application-level privacy override
and is the default. It disables both saved student conversations and the
student interaction debug log, and suppresses the history sidebar regardless
of `chat_history`. Set it to `FALSE` only when the deployment has an
appropriate data-protection basis for retaining chat text.

Student apps write content-free usage records to
`main_dir/session_stats/<anonymous-session-id>.csv`. A new random 16-character
ID is created for the initial chat and each explicitly started new chat.
Rows contain semester, course and Tutor identifiers, model and token counts,
time until the first visible output in milliseconds (`ttf_ms`), time until the
last visible output token in seconds (`total_sec`), and an error code only when
no reply was produced; they never contain prompts or replies.

The teacher Usage pane incrementally combines these anonymous records across
all courses and semesters. Cached per-course and teacher-wide summaries live
under `teachers/<teacherid>/usage_statistics/`. Source files are fingerprinted
by filename, size, and modification time, so unchanged sessions are not read
again.
