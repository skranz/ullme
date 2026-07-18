library(ullme)

source(file.path("R", "yaml_validation.R"))
source(file.path("R", "ai_tutors.R"))
source(file.path("R", "tutor_flow.R"))

definition = yaml::read_yaml(file.path("inst", "ai_tutors", "ps_tutor_en.yml"))
normalized = ullme_normalize_ai_tutor_definition(
  definition,
  tutorid="ps_tutor_en",
  source="package"
)
stopifnot(
  length(normalized$node_yaml) == length(normalized$nodes),
  isTRUE(normalized$show_final_output),
  grepl("switch_input:", normalized$node_yaml$switch_image, fixed=TRUE)
)
definition$show_final_output = FALSE
normalized_hidden = ullme_normalize_ai_tutor_definition(
  definition, tutorid="ps_tutor_en", source="package"
)
stopifnot(identical(normalized_hidden$show_final_output, FALSE))
field_catalog = ullme_node_field_catalog()
field_paths = unlist(lapply(field_catalog, function(group) {
  vapply(group$fields %||% list(), `[[`, character(1), "path")
}), use.names=FALSE)
field_ui = htmltools::renderTags(ullme_node_field_picker_ui("test_node"))
field_html = paste(field_ui$head, field_ui$html, collapse="\n")
stopifnot(
  all(c(
    "prompt", "show_before", "show_after", "next",
    "switch_to.DEFAULT", "ask_for_input", "placeholder.hist",
    "placeholder.output_node"
  ) %in% field_paths),
  !anyDuplicated(field_paths),
  grepl('id="test_node_field"', field_html, fixed=TRUE),
  grepl("Instructions sent to the model", field_html, fixed=TRUE),
  grepl('data-kind="placeholder"', field_html, fixed=TRUE),
  grepl("Conversation and workflow history", field_html, fixed=TRUE)
)
definition$nodes$describe_image$show_after = paste(
  "Image description:", "{{output}}", "Prior: {{output.switch_image}}",
  sep="\n"
)
valid = ullme_validate_tutor_yaml(
  tutorid="ps_tutor_en",
  content=yaml::as.yaml(definition)
)
stopifnot(isTRUE(valid$ok))

definition$nodes$safety_review[["next"]] = "general"
cyclic = ullme_validate_tutor_yaml(
  tutorid="ps_tutor_en",
  content=yaml::as.yaml(definition)
)
stopifnot(
  !isTRUE(cyclic$ok),
  any(grepl(
    "directed acyclic graph",
    unlist(cyclic$errors, use.names=FALSE),
    fixed=TRUE
  ))
)

stopifnot(
  identical(ullme_clean_tutor_node_id("check_answer_2"), "check_answer_2"),
  inherits(try(ullme_clean_tutor_node_id("bad-node"), silent=TRUE), "try-error")
)

test_root = file.path(tempdir(), "ullme_main")
dir.create(test_root, recursive=TRUE, showWarnings=FALSE)
test_main = tempfile("tutor-node-main-", tmpdir=test_root)
dir.create(test_main, recursive=TRUE)
cleanup_app = new.env(parent=emptyenv())
cleanup_app$glob = list(main_dir=test_main)
root = ullme_tempdir(pattern=".ullme-tutor-node-check-", app=cleanup_app)

app = new.env(parent=emptyenv())
app$glob = list(main_dir=root)
app$userid = "alice"
app$role = "teacher"
app$allowed_roles = "teacher"
app$semester = "WS2526"
app$courseid = "micro"
app$user_dir = file.path(root, "users", "alice")
app$pending_changes = list()
dir.create(app$user_dir, recursive=TRUE)
tutor_dir = file.path(
  root, "teachers", "alice", "courses", "WS2526", "micro",
  "ai_tutors", "tutor1"
)
dir.create(tutor_dir, recursive=TRUE)
writeLines(c(
  "tutorid: tutor1",
  "lang: en",
  "label: Tutor One",
  "description: Helps",
  "shown_text: Welcome.",
  "default_personality: Friendly",
  "docs_per_instance: {}",
  "docs_per_course: {}",
  "allowed_tools: []",
  "allowed_student_customization: []",
  "start_node: answer",
  "nodes:",
  "  answer:",
  "    prompt: '{{input}}'",
  "prompt_fragments:",
  "  init_prompt: Help."
), file.path(tutor_dir, "tutor.yml"))

startup_stubs = ullme_course_ai_tutor_stubs(app=app)
stopifnot(
  length(startup_stubs) == 1L,
  identical(startup_stubs[[1]]$tutorid, "tutor1"),
  isTRUE(startup_stubs[[1]]$loading),
  identical(names(startup_stubs[[1]]), c("tutorid", "label", "loading"))
)

created = ullme_save_course_ai_tutor_node(
  "tutor1", "review", "create",
  "prompt: Review the draft.",
  app=app
)
stopifnot(created$ok)
saved = ullme_save_course_ai_tutor_node(
  "tutor1", "answer", "save",
  paste("prompt: '{{input}}'", "next: review", sep="\n"),
  app=app
)
stopifnot(
  saved$ok,
  identical(
    yaml::read_yaml(file.path(tutor_dir, "tutor.yml"))$nodes$answer[["next"]],
    "review"
  )
)
renamed = ullme_save_course_ai_tutor_node(
  "tutor1", "feedback", "save",
  original_nodeid="review",
  yaml_content="prompt: Review the draft.",
  app=app
)
renamed_value = yaml::read_yaml(file.path(tutor_dir, "tutor.yml"))
stopifnot(
  renamed$ok,
  isTRUE(renamed$validation$is_valid),
  !"review" %in% names(renamed_value$nodes),
  "feedback" %in% names(renamed_value$nodes),
  identical(renamed_value$nodes$answer[["next"]], "feedback")
)
referenced_delete = ullme_save_course_ai_tutor_node(
  "tutor1", "feedback", "delete", app=app
)
stopifnot(
  referenced_delete$ok,
  !isTRUE(referenced_delete$validation$is_valid),
  !"feedback" %in% names(
    yaml::read_yaml(file.path(tutor_dir, "tutor.yml"))$nodes
  )
)
unlinked = ullme_save_course_ai_tutor_node(
  "tutor1", "answer", "save", "prompt: '{{input}}'", app=app
)
stopifnot(
  unlinked$ok,
  isTRUE(unlinked$validation$is_valid)
)
start_renamed = ullme_save_course_ai_tutor_node(
  "tutor1", "entry", "save",
  original_nodeid="answer",
  yaml_content="prompt: '{{input}}'",
  app=app
)
start_renamed_value = yaml::read_yaml(file.path(tutor_dir, "tutor.yml"))
stopifnot(
  start_renamed$ok,
  isTRUE(start_renamed$validation$is_valid),
  identical(start_renamed_value$start_node, "entry")
)
renamed_back = ullme_save_course_ai_tutor_node(
  "tutor1", "answer", "save",
  original_nodeid="entry",
  yaml_content="prompt: '{{input}}'",
  app=app
)
stopifnot(
  renamed_back$ok,
  isTRUE(renamed_back$validation$is_valid)
)

semantic_value = yaml::read_yaml(file.path(tutor_dir, "tutor.yml"))
semantic_value$start_node = "missing_node"
semantic_save = ullme_save_course_ai_tutor(
  "tutor1",
  mode="yaml",
  yaml_content=yaml::as.yaml(semantic_value),
  app=app
)
stopifnot(
  semantic_save$ok,
  !isTRUE(semantic_save$validation$is_valid)
)
invalid_teacher_state = ullme_course_ai_tutors(app=app)[[1]]
stopifnot(
  !isTRUE(invalid_teacher_state$is_valid),
  length(invalid_teacher_state$validation_errors) > 0L
)
semantic_value$start_node = "answer"
repaired_save = ullme_save_course_ai_tutor(
  "tutor1",
  mode="yaml",
  yaml_content=yaml::as.yaml(semantic_value),
  app=app
)
stopifnot(repaired_save$ok, isTRUE(repaired_save$validation$is_valid))

invalid_yaml = paste(
  readLines(file.path(tutor_dir, "tutor.yml"), warn=FALSE),
  "broken: [",
  sep="\n"
)
syntax_rejected = try(
  ullme_save_course_ai_tutor(
    "tutor1", mode="yaml", yaml_content=invalid_yaml, app=app
  ),
  silent=TRUE
)
stopifnot(
  inherits(syntax_rejected, "try-error"),
  identical(
    yaml::read_yaml(file.path(tutor_dir, "tutor.yml"))$start_node,
    "answer"
  )
)

ullme_remove_tempdir(root, app=cleanup_app)
