# Teacher Studio

The teacher app starts in the global **Usage** view. It shows anonymous request,
token, latency, model, Tutor, error, course, and semester statistics across all
courses. Aggregation runs after startup without delaying the initial cached
dashboard; the Refresh action checks for new or changed session files.

Teacher mode uses a workbench layout with three regions:

1. a compact navigation rail;
2. a large central work surface; and
3. a collapsible, context-aware AI pane.

Student mode remains chat-first.

## Navigation

The rail starts with a single **Add** menu, followed by the global **Usage**
entry and fixed **Materials** and **Settings** entries. Each AI Tutor installed
in the selected course gets its own Tutor entry.

The **Add** menu currently offers:

- **Add Tutor**, which copies a reusable template into the course; and
- **New Course**, which creates and selects a course.

There is no separate Organize or Definitions work surface.

## AI Tutor work surface

Selecting a Tutor always opens that specific course Tutor. Its definition is
stored at:

```text
ai_tutors/<tutorid>/tutor.yml
```

This is a complete, editable course copy. Package Tutors are templates used
only when adding a Tutor; the course never runs a template directly.

The Tutor work surface has:

- **Instances**, an editable table relating each Tutor instance to document
  roles such as `ps` and `ps_sol`;
- **Definition**, form-based editing for common metadata, teaching
  instructions, per-instance documents, and per-course documents; and
- **YAML**, direct editing of the complete course-local definition.

Package Tutor templates are flat files at
`inst/ai_tutors/<tutorid>.yml`. Their `docs_per_instance` and
`docs_per_course` mappings define document IDs, ordered allowed file types,
preferred material directories, and image extraction. The
**Make Instances** action asks for teacher guidance, then runs the AI helper in
the right sidebar. It receives the recursive filenames beneath `materials/ps`,
uses the allowed file types and their preference order, and writes the
validated instance YAML without converting documents. The write is automatic
but remains backed up and undoable through the shared edit history.
