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
`docs_per_course` mappings define document IDs, preferred formats, conversion
preferences, preferred material directories, and image extraction. When no
saved instance assignment exists, uLLMe suggests assignments from matching
course files for review.
