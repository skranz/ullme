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
- `start_node`, `nodes`, and `prompt_fragments`;
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

Tutor definitions use the workflow format only. Files whose names end in
`_old.yml` or `_old.yaml` are retained as references but are not offered as
package templates.

## Workflows

Each student submission starts at `start_node`, unless the Tutor is resuming a
node that previously used `ask_for_input: true`. Node behavior is inferred from
its fields:

```yaml
start_node: route
nodes:
  route:
    switch_input: image_uploaded
    switch_to:
      "TRUE": inspect
      "FALSE": answer
      DEFAULT: answer

  inspect:
    waiting_message: I am inspecting the image...
    prompt: |
      {{hist_or_init_prompt}}
      Inspect the student's attached work: {{input}}
    next: answer

  answer:
    add_to_history: false
    prompt: |
      {{hist}}
      Return the final student-facing response.

prompt_fragments:
  init_prompt: |
    You are a Tutor. Act as follows: {{personality}}
    Course material: {{notes}}
```

- `prompt` performs a model call.
- `next` continues unconditionally after that call.
- `switch_input` accepts `image_uploaded` or `output`.
- `switch_to` maps the switch value to a node; `DEFAULT` is the fallback.
- A prompt node without `next` or `switch_to` returns its output to the
  student.
- Intermediate outputs are hidden from the student.
- `add_to_history: false` excludes a node output from later `{{hist}}` values,
  while `{{output}}` still contains it for the immediately following node.
- `waiting_message` replaces the temporary activity text while the node runs.
- `ask_for_input: true` shows `show_text`, suspends the workflow, and processes
  the student's next submission with that node's prompt.
- `n_parallel` runs several independent calls. `aggregate: majority_vote`
  supports classifier nodes: values are trimmed, case-normalized, restricted
  to declared routes, and must produce an absolute majority.
- `aggregate: collect` keeps every parallel response. The combined response is
  available as `{{output}}`; `{{outputs}}` renders the individual responses
  with numbered separators.
- `temperature` optionally overrides the model temperature for a node (from
  `0` through `2`).
- `output_schema` parses and validates a node's response as YAML.
  `retries_if_invalid` can request up to three format-only correction calls.

The runtime stops workflows after 40 node executions to contain accidental
cycles. Node IDs and all route targets are validated when YAML is saved.

`prompt_fragments.init_prompt` is rendered as the system message for every
model node. Document and customization placeholders such as `{{ps}}`,
`{{ps_sol}}`, and `{{personality}}` are resolved there. Runtime placeholders
available in node prompts are:

- `{{input}}`: the student submission that started or resumed the workflow;
- `{{output}}`: the immediately preceding model output;
- `{{output.node_id}}`: the combined output of a named completed node;
- `{{outputs}}`: all individual outputs of the immediately preceding node;
- `{{outputs.node_id}}`: all individual outputs of a named completed node;
- `{{output.node_id.1}}`: one numbered output of a named completed node;
- `{{hist}}`: prior visible conversation plus retained internal node outputs;
- `{{hist_or_init_prompt}}`: the workflow history (the init prompt is already
  the system message); and
- `{{image_uploaded}}`: `TRUE` or `FALSE`.

Structured output schemas use either an explicit form:

```yaml
output_schema:
  required: [verdict, first_error_step]
  allow_extra_fields: false
  fields:
    verdict:
      type: string
      enum: [correct, incorrect, unclear]
    first_error_step:
      type: string
      nullable: true
    confidence:
      type: number
retries_if_invalid: 1
```

or a compact form in which every listed field is required:

```yaml
output_schema:
  verdict: [correct, incorrect, unclear]
  student_evidence: string
```

Supported types are `any`, `string`, `string_or_null`, `number`, `integer`,
`boolean`, `mapping`/`object`, `sequence`/`array`, and `null`. The runtime
appends the schema to the model prompt automatically. A model may wrap its YAML
in a single fenced code block; the stored output remains unchanged.

Uploaded images remain available to later calls in the same workflow, including
after a clarification pause. Internal calls are not rendered or added to the
visible student transcript.

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

The Teacher Studio edits Tutor definitions in one YAML text area. Instance
assignments retain their dedicated editor and instance-builder assistant.
The assistant returns structured YAML text and does not use tools. The app
accepts direct YAML, the requested begin/end-delimited form, or a fenced YAML
block. `teacherApp(instance_builder_retries=1L)` controls how many correction
requests may follow a non-empty response that fails parsing or validation.

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
    label: Problem Set 1
    docs:
      ps: [ps/ps1.pdf]
      ps_sol: [ps/ps1_sol.pdf]
```

`instanceid` is the stable URL/configuration identifier. `label` is the
human-readable name shown in both the Teacher Studio and the Student App; when
it is omitted, uLLMe falls back to `instanceid`.

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
normal student interaction log, and suppresses the history sidebar regardless
of `chat_history`. Set it to `FALSE` only when the deployment has an
appropriate data-protection basis for retaining chat text.

For local development, `studentApp(chat_debug=TRUE)` explicitly writes every
model call from the current app process to `main_dir/debug_session`, even when
`never_save_chats=TRUE`. Each text file contains Tutor/instance/node metadata,
the full system and node prompts, and the full answer, thinking, or error. A
new debug-enabled Student App removes all old files in that folder with
`file.remove()` before starting. Do not enable this option in production.

The current process still keeps a live transcript for `{{hist}}` and suspended
workflow continuation. With `never_save_chats=TRUE`, that transcript is never
written to disk and is discarded with the live chat.

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
