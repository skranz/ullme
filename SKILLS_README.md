# uLLMe Skills

## Purpose

A skill is a reusable package of instructions and resources that helps the teacher assistant perform a recurring task well.

Examples include creating a quiz, summarizing a lecture, drafting a problem set, classifying course materials, or creating a study document.

A skill is not a separate assistant. The teacher interacts with one general teacher assistant, which may activate skills and use tools.

## Relation to Agent Skills

uLLMe skills should follow the Agent Skills concept where possible.

Each skill is stored in its own directory:

```text
<skillid>/
  SKILL.md
  ullme.yaml
  assets/
  references/
```

`SKILL.md` contains the portable skill definition:

- skill name,
- activation description,
- instructions for the LLM,
- references to templates, examples, and other resources.

`ullme.yaml` contains uLLMe-specific structured information:

- UI label and description,
- introductory text shown to the teacher,
- starter prompts,
- required course inputs,
- expected outputs,
- required tools,
- shortcut settings,
- suggestion or scheduling metadata.

Runtime state, generated files, schedules, and permissions are not part of the portable skill definition.

## Storage Levels

Skills are independent of courses.

uLLMe should support:

```text
inst/skills/
  <skillid>/

<main-dir>/skills/general/
  <skillid>/

<main-dir>/users/<userid>/skills/
  <skillid>/
```

Later, teachers may publish skills to a shared catalog.

General skills are curated defaults. Personal skills belong to one user and may be customized. Shared skills should be installed or copied into a user's personal skill collection before use.

## Skill Resolution

If the same skill ID exists at several levels, use the first complete definition found:

```text
personal skill
general skill
package skill
```

Do not merge arbitrary YAML fields across levels. Customization should normally create a complete personal copy.

## Activation

Skills can be activated in two ways.

### Conversational activation

The teacher asks for a task in normal conversation. The assistant sees a catalog of available skill names and descriptions and may activate the appropriate skill through a controlled uLLMe tool.

### Explicit UI activation

The teacher selects a skill in the UI. uLLMe activates the skill directly and injects its instructions into the LLM context. The LLM should not need another tool call to rediscover the selected skill.

The UI may show:

- an introductory message,
- example requests,
- a composer placeholder,
- shortcut buttons.

These texts belong in `ullme.yaml`. They are normally shown only to the teacher and are not automatically added as user messages.

## Prompt Construction

Do not place all complete skills into every assistant prompt.

Use progressive disclosure:

1. Initially provide only the names and descriptions of available skills.
2. When a skill is activated, add the full `SKILL.md` instructions.
3. Load referenced assets or documents only when needed.
4. Supply course, semester, selected materials, and other runtime information separately.

A skill explains how to perform a task. Tools perform low-level operations such as reading course files or writing a generated document.

## Permissions

Skills never grant permissions.

uLLMe decides:

- which skills are available,
- which tools are exposed,
- which files may be read or written,
- which user and course are active,
- whether an operation requires confirmation.

All authorization must be enforced by server-side code.

## Skill Lifetime

A selected skill should normally be active for one task rather than for an entire long-running teacher conversation.

uLLMe may store an active skill ID on the app and include that skill in subsequent requests until the task is completed, cancelled, or another skill is selected.

## Initial Implementation

The first implementation should support:

1. package, general, and personal skill discovery,
2. parsing `SKILL.md` and `ullme.yaml`,
3. a skill catalog in the teacher assistant,
4. direct activation from the UI,
5. conversational activation through a restricted tool,
6. skill-specific UI introductions and starter prompts,
7. controlled access to required tools and course context.
