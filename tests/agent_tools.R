library(ullme)

test_main_dir = tempfile("ullme-agent-tools-main-")
dir.create(test_main_dir, recursive=TRUE)
cleanup_app = new.env(parent=emptyenv())
cleanup_app$glob = list(main_dir=test_main_dir)
root = ullme_tempdir(pattern=".ullme-agent-tools-check-", app=cleanup_app)

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
dir.create(file.path(root, "teachers", "alice"), recursive=TRUE)

valid_tutor = paste(
  "tutorid: tutor1",
  "lang: en",
  "label: Tutor One",
  "description: Helps",
  "system_prompt: |",
  "  Help with {{personality}}.",
  "default_personality: Friendly",
  "docs_per_instance: {}",
  "docs_per_course: {}",
  "allowed_tools: []",
  "allowed_student_customization: [personality]",
  sep="\n"
)
stopifnot(ullme_validate_definition_yaml("tutor", "tutor1", valid_tutor)$ok)
stopifnot(!ullme_validate_definition_yaml("tutor", "other", valid_tutor)$ok)
stopifnot(!ullme_parse_yaml_text("a: [", "bad.yaml")$ok)
registry = ullme_tool_registry()
new_tools = c(
  "read_tutor_instances_yaml",
  "rewrite_tutor_instances_yaml",
  "write_rtutor_instances_yaml",
  "convert_material_files"
)
stopifnot(
  all(new_tools %in% names(registry)),
  all(vapply(
    paste0("utool_", new_tools),
    exists,
    logical(1),
    mode="function",
    envir=asNamespace("ullme")
  ))
)

course_dir = file.path(
  root, "teachers", "alice", "courses", "WS2526", "micro"
)
dir.create(file.path(course_dir, "materials", "ps"), recursive=TRUE)
dir.create(file.path(course_dir, "ai_tutors", "tutor1"), recursive=TRUE)
writeLines(valid_tutor, file.path(course_dir, "ai_tutors", "tutor1", "tutor.yml"))
writeLines("problem", file.path(course_dir, "materials", "ps", "problem.md"))
instances_yaml = paste(
  "course_docs: {}",
  "instances:",
  "  - instanceid: problem",
  "    docs: {}",
  sep="\n"
)
saved_instances = ullme_save_course_ai_tutor_instances_yaml(
  "tutor1", instances_yaml, origin="ui", app=app
)
stopifnot(
  saved_instances$ok,
  file.exists(file.path(course_dir, "ai_tutors", "tutor1", "instances.yml"))
)
read_instances = utool_read_tutor_instances_yaml("tutor1", app=app)
stopifnot(
  identical(read_instances$tutorid, "tutor1"),
  grepl("instanceid: problem", read_instances$content, fixed=TRUE)
)
app$agent_approval_override = "allow"
app$headless = TRUE
tool_written = utool_write_rtutor_instances_yaml(
  "tutor1",
  instances_yaml,
  app=app
)
stopifnot(
  tool_written$ok,
  identical(tool_written$status, "committed"),
  isTRUE(tool_written$validation$valid),
  identical(tool_written$validation$instance_count, 1L),
  identical(tool_written$validation$instance_ids, list("problem"))
)

target = file.path(root, "teachers", "alice", "note.yaml")
writeLines("value: before", target)
operation = ullme_new_change(
  action="test_write",
  summary="Test write",
  changes=list(ullme_change_write(target, "value: after")),
  origin="ui",
  app=app
)
result = ullme_submit_change(operation, app=app)
stopifnot(result$ok, identical(readLines(target), "value: after"))

history = ullme_change_history(app=app)
stopifnot(length(history) >= 2L)
undo = ullme_undo_change(history[[1]]$id, origin="ui", app=app)
stopifnot(undo$ok, identical(readLines(target), "value: before"))

outside = file.path(root, "outside", "bad.yaml")
dir.create(dirname(outside), recursive=TRUE)
unauthorized = ullme_new_change(
  action="bad",
  summary="Unauthorized",
  changes=list(ullme_change_write(outside, "x: 1")),
  origin="ui",
  app=app
)
stopifnot(inherits(
  try(ullme_submit_change(unauthorized, app=app), silent=TRUE),
  "try-error"
))

ullme_remove_tempdir(root, app=cleanup_app)
