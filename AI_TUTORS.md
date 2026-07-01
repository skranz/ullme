# uLLMe AI Tutors

## Purpose

An AI tutor is a student-facing conversational assistant for a course or for particular course material.

Examples include a tutor for the complete course, a tutor for each problem set, a tutor for a chapter, or an exam-preparation tutor.

AI tutors are first-class course features because they have student visibility, material bindings, persistent conversations, pedagogical rules, and student-specific state.

## Main Levels

uLLMe uses four levels.

### Tutor Definition

A reusable and shareable definition of tutor behavior.

It contains:

- pedagogical instructions,
- prompt construction rules,
- required material roles,
- allowed tutor tools,
- student customization options,
- rules for creating tutor instances.

Tutor definitions may exist at package, general, personal, or course-local level.

### Course Tutor Instance

A small course-level record showing that a tutor is used in one course.

Suggested structure:

```text
<course-dir>/ai_tutors/<tutorid>/
  tutor.yaml
  instances/
  analytics/
```

`tutor.yaml` may contain only:

```yaml
tutorid: ps_tutor
enabled: true
```

The course tutor instance may also contain small course-wide settings.

### Tutor Instance

A concrete tutor shown to students and bound to actual course material.

For a problem-set tutor, one course tutor instance may create several tutor instances:

```text
instances/
  ps1.yaml
  ps2.yaml
  ps3.yaml
```

An instance definition may contain:

```yaml
instanceid: ps1
enabled: true

binding:
  object_type: ps
  object_id: ps1

materials:
  problem_set: ps1
  solution: ps1_sol
```

A whole-course tutor normally has only one tutor instance.

### Tutor Session

A tutor session is one student's conversation with one tutor instance.

The initial implementation should normally keep one resumable session per student and tutor instance.

A session contains:

- tutor and instance IDs,
- student ID,
- course reference,
- timestamps,
- conversation messages,
- tool calls and other structured events,
- a snapshot of the effective tutor instructions used to start the session.

## Tutor Definition Storage and Resolution

Suggested storage:

```text
inst/ai_tutors/
  <tutorid>/

<main-dir>/ai_tutors/general/
  <tutorid>/

<main-dir>/teachers/<userid>/ai_tutors/
  <tutorid>/

<course-dir>/ai_tutor_definitions/
  <tutorid>/
```

Resolve a tutor definition by taking the first complete definition found:

```text
course-local definition
personal definition
general definition
package definition
```

Do not merge fields across levels.

If a teacher customizes a tutor for one course, copy the complete currently resolved definition into the course-local directory. From then on, the course uses that local copy. Otherwise, the course automatically follows updates to the personal, general, or package definition.

Formal version management is not required initially.

## Teacher UI

The course's AI Tutors tab shows installed Tutor families and opens the resolved
Tutor catalog. Installed cards and catalog entries can open the shared
Definition Workspace.

The workspace exposes Markdown and YAML files directly. Package and General
definitions are read-only for teachers. A teacher can create a Personal Tutor
definition, make a Personal copy of an existing definition, or use **Customize
for course** to copy the complete resolved definition into
`ai_tutor_definitions/<tutorid>/` before editing it.

Personal and course-local copies can be deleted; deletion does not uninstall a
course Tutor and instead restores the next definition in the resolution order.
Tutor definitions can be downloaded or imported as YAML. Importing may target
the Personal library or the selected course and replaces a complete conflicting
copy only after an explicit preview.

The optional Definition Assistant can rewrite the current file as an unsaved
draft. Teachers review, undo, or explicitly save the result. Shared read-only
definitions must first be copied to Personal or course-local storage.

## Enabled State

Both levels may have an `enabled` field:

- the course tutor instance can enable or disable the tutor family for the course,
- each tutor instance can be enabled or disabled individually.

Later, availability rules such as release dates can be kept separate from `enabled`.

## Material Binding

Tutor definitions should describe how instances are generated and how material roles are resolved.

For example, a problem-set tutor may specify:

- create one instance for each `ps` object,
- bind the current problem set as student material,
- find the linked `ps_sol` object,
- expose solutions only through controlled tutor logic or tools.

Tutor instances should refer to object IDs rather than hard-coded filesystem paths.

## Session Storage

Raw student sessions should be stored in a protected student or session area, for example:

```text
<main-dir>/users/<studentid>/tutor_sessions/
  <course-ref>/
    <tutorid>/
      <instanceid>/
        session.yaml
        messages.jsonl
        events.jsonl
```

Teacher-facing analytics may be stored under:

```text
<course-dir>/ai_tutors/<tutorid>/analytics/
```

Raw conversations and teacher analytics should remain separate.

## Analytics and Privacy

From the beginning, sessions should record structured events such as:

- session started,
- message sent,
- answer generated,
- tool called,
- hint requested,
- protected solution accessed.

Teacher analytics may summarize:

- usage counts,
- common difficulties,
- frequently requested hints,
- unresolved concepts.

Access to raw conversations, retention, anonymization, and student information must be defined explicitly before analytics are exposed.

## Initial Implementation

The first implementation should support:

1. loading tutor definitions with the stated precedence,
2. creating a course tutor instance,
3. generating tutor instances from course objects,
4. enabling or disabling tutors and individual instances,
5. showing enabled instances to students,
6. creating one resumable session per student and instance,
7. storing messages and structured events,
8. enforcing material, solution, and tool permissions,
9. writing aggregate teacher analytics separately from raw sessions.
