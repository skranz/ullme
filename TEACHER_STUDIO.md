# Teacher Studio

Teacher mode uses a workbench layout with three regions:

1. a compact navigation rail;
2. a large central work surface; and
3. a collapsible, context-aware AI pane.

Student mode remains chat-first.

## Work surfaces

- **Materials** provides material categories plus an **All course files** view.
  Any authorized text file up to 2 MB can be opened in the universal editor.
  Binary files remain visible but are not text-editable.
- **Organize** renders course object indexes as ordered problem sets,
  solutions, slides, scripts, and events. It also shows unassigned materials.
  Each object index can be opened as YAML.
- **Tutors** manages the AI Tutors installed in the selected course.
- **Definitions** embeds the Tutor and Skill definition workspace in the main
  work surface.
- **Settings** edits course metadata.
- **History** opens approval policies and transaction/undo history.

The AI pane receives the selected course, current work surface, and open file
path as context. It can be collapsed when more editor space is needed.

## Organize with AI

The organizer groups formats of the same document, proposes ordered indexes,
and maps solution files to problem sets. Its proposal remains a draft:

1. review the proposed object groups;
2. inspect individual YAML files if desired;
3. choose **Apply proposal**; and
4. approve the transaction when the user's policy is `ask`.

Applying a proposal uses the same validation, backup, audit, and undo layer as
manual edits.
