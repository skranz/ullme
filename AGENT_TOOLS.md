# uLLMe Agent Tools

uLLMe agent tools use a trusted application context. The model can select a
course, material category, definition ID, or relative filename, but it cannot
select a user identity or an arbitrary absolute path.

The registry is defined by `ullme_tool_registry()`. The OpenAI-compatible
streaming client turns its entries into JSON tool schemas and dispatches calls
through `ullme_execute_tool()` in the current app context.

## Available tools

Read-only tools:

- `cur_user`
- `teacher_info`
- `list_courses`
- `list_material_files`
- `read_definition_yaml`
- `list_ai_tutors`
- `read_tutor_instances_yaml`
- `read_course_file`
- `list_changes`
- `change_status`

Modifying tools:

- `copy_material`
- `rewrite_definition_yaml`
- `rewrite_tutor_instances_yaml`
- `write_rtutor_instances_yaml`
- `convert_material_files`
- `rewrite_course_text_file`
- `undo_change`

Modifying tools prepare a transaction before touching the filesystem. The
current user's `settings.yaml` determines whether each agent action is allowed,
shown in an approval dialog, or denied.

```yaml
agent_tools:
  approval:
    default: ask
    read: allow
    copy_materials: ask
    rewrite_definitions: ask
    undo: ask
```

## Transactions and undo

All teacher-mode writes managed by uLLMe use the transaction layer, including
manual definition edits, imports, course settings, and material changes.

Every transaction:

1. resolves and authorizes its target paths;
2. validates YAML and operation-specific semantics;
3. records the files' current hashes;
4. optionally waits for user approval;
5. backs up replaced or deleted paths;
6. commits the changes and records their resulting hashes; and
7. writes a manifest and history entry.

History is stored below:

```text
users/<userid>/change_history/
  index.yaml
  log.jsonl
  backups/<operation-id>/
    manifest.yaml
    before/
```

Undo restores the backups or removes newly-created targets. It refuses to
overwrite a file whose hash changed after the original operation. Undo is
itself a logged, undoable transaction.

Only changes made through uLLMe can be logged. Direct filesystem changes made
outside the application are detected as conflicts but cannot be audited.
