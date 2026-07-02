# uLLMe AI Tutors

An AI Tutor is a student-facing assistant whose behavior and required
documents are declared in YAML.

## Package templates

Reusable templates are flat package files:

```text
inst/ai_tutors/<tutorid>.yml
```

The core fields are:

- `tutorid`, `lang`, `label`, and `description`;
- `system_prompt`;
- `default_personality`;
- `docs_per_instance`;
- `docs_per_course`;
- `allowed_tools`; and
- `allowed_student_customization`.

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
`docs_per_course` defines documents shared by every instance. Each entry may
contain:

```yaml
descr: Human-readable description
pref_format: [md, tex, pdf]
auto_convert: [pdf]
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

## Sessions

A Tutor session belongs to one student, course Tutor, and Tutor instance.
Conversation storage and analytics remain separate from the definition and
document-assignment files.
