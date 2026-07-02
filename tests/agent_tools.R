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
  "label: Tutor One",
  "description: Helps",
  sep="\n"
)
stopifnot(ullme_validate_definition_yaml("tutor", "tutor1", valid_tutor)$ok)
stopifnot(!ullme_validate_definition_yaml("tutor", "other", valid_tutor)$ok)
stopifnot(!ullme_parse_yaml_text("a: [", "bad.yaml")$ok)

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
stopifnot(length(history) == 1L)
undo = ullme_undo_change(history[[1]]$id, origin="ui", app=app)
stopifnot(undo$ok, identical(readLines(target), "value: before"))

outside = file.path(root, "ai_tutors", "general", "bad.yaml")
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
