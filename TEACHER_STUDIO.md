# Teacher Studio

Teacher mode uses a workbench layout with three regions:

1. a compact navigation rail;
2. a large central work surface; and
3. a collapsible, context-aware AI pane.

Student mode remains chat-first.

## Navigation

The rail contains fixed entries for **Materials**, **Settings**, and
**History**. Each AI Tutor installed in the selected course gets its own Tutor
entry. Skills added to the course get Skill entries; the currently active one
is highlighted.

The **Add** menu currently offers:

- **Add AI Tutor**, which copies a reusable template into the course; and
- **Add Skill**, which adds and activates a reusable teacher workflow.

There is no separate Organize or Definitions work surface.

## AI Tutor work surface

Selecting a Tutor always opens that specific course Tutor. Its definition is
stored at:

```text
ai_tutors/<tutorid>/tutor.yaml
```

This is a complete, editable course copy. General, personal, and package
Tutors are templates used only when adding a Tutor; the course never runs a
template directly.

The Tutor work surface has:

- **Instances**, a table relating each Tutor instance to material roles such
  as problem set and solution;
- **Definition**, form-based editing for common metadata, teaching
  instructions, and optional instance-matching rules; and
- **YAML**, direct editing of the complete course-local definition.

A Tutor opts into the file-matching helper with
`instance_generation.file_matcher`. The matcher scans a material directory,
captures an instance ID from primary files, and associates related files with
patterns containing `{{id}}`.
