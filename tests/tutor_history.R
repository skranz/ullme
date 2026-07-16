library(ullme)

test_root = file.path(tempdir(), "ullme_main")
dir.create(test_root, recursive=TRUE, showWarnings=FALSE)
test_main_dir = tempfile("tutor-history-main-", tmpdir=test_root)
dir.create(test_main_dir, recursive=TRUE)
cleanup_app = new.env(parent=emptyenv())
cleanup_app$glob = list(main_dir=test_main_dir)
root = ullme_tempdir(pattern=".ullme-tutor-history-check-", app=cleanup_app)

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

course_dir = file.path(
  root, "teachers", "alice", "courses", "WS2526", "micro"
)
tutor_dir = file.path(course_dir, "ai_tutors", "tutor1")
dir.create(tutor_dir, recursive=TRUE)
writeLines(
  c(
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
  ),
  file.path(tutor_dir, "tutor.yml")
)

course_settings = ullme_save_course_settings(
  app=app,
  course=list(coursename="Microeconomics")
)
stopifnot(
  course_settings$ok,
  ullme_edit_history_state("course_settings", app=app)$can_undo
)

instances_path = file.path(tutor_dir, "instances.yml")
first_yaml = paste(
  "course_docs: {}",
  "instances:",
  "  - instanceid: first",
  "    docs: {}",
  sep="\n"
)
first = ullme_submit_change(
  ullme_new_change(
    action="test_instances",
    summary="First instance assignment",
    origin="ui",
    changes=list(ullme_change_write(instances_path, first_yaml)),
    app=app
  ),
  app=app
)
stopifnot(first$ok)

state = ullme_edit_history_state("tutor_instances", "tutor1", app=app)
stopifnot(state$can_undo, !state$can_redo)
tutors = ullme_course_ai_tutors(app=app)
stopifnot(
  length(tutors) == 1L,
  tutors[[1]]$edit_history$instances$can_undo,
  !tutors[[1]]$edit_history$definition$can_undo
)
shown_text_save = ullme_save_course_ai_tutor(
  tutorid="tutor1",
  mode="ui",
  fields=list(shown_text="Welcome to the edited Tutor."),
  app=app
)
stopifnot(
  shown_text_save$ok,
  identical(
    yaml::read_yaml(file.path(tutor_dir, "tutor.yml"))$shown_text,
    "Welcome to the edited Tutor."
  ),
  ullme_edit_history_state(
    "tutor_definition", "tutor1", app=app
  )$can_undo
)
undone = ullme_undo_change(state$undo_id, origin="ui", app=app)
stopifnot(undone$ok, !file.exists(instances_path))

state = ullme_edit_history_state("tutor_instances", "tutor1", app=app)
stopifnot(!state$can_undo, state$can_redo)
redone = ullme_undo_change(state$redo_id, origin="ui", app=app)
stopifnot(
  redone$ok,
  file.exists(instances_path),
  grepl("instanceid: first", paste(readLines(instances_path), collapse="\n"))
)

state = ullme_edit_history_state("tutor_instances", "tutor1", app=app)
stopifnot(state$can_undo, !state$can_redo)

catalog = ullme_ai_tutor_catalog(app=app)
stopifnot(length(catalog) > 0)
templateid = catalog[[1]]$tutorid
stopifnot(ullme_add_course_ai_tutor(
  templateid=templateid,
  tutorid="custom_tutor",
  app=app
))
custom_path = file.path(course_dir, "ai_tutors", "custom_tutor", "tutor.yml")
stopifnot(
  file.exists(custom_path),
  identical(yaml::read_yaml(custom_path)$tutorid, "custom_tutor")
)
stopifnot(
  inherits(
    try(ullme_add_course_ai_tutor(
      templateid=templateid,
      tutorid="custom_tutor",
      app=app
    ), silent=TRUE),
    "try-error"
  )
)
stopifnot(
  ullme_delete_course_ai_tutor("custom_tutor", app=app),
  !dir.exists(dirname(custom_path))
)

ullme_remove_tempdir(root, app=cleanup_app)
