library(ullme)

main_dir = tempfile("ullme-debug-session-")
dir.create(main_dir, recursive=TRUE)
debug_dir = file.path(main_dir, "debug_session")
dir.create(file.path(debug_dir, "old", "nested"), recursive=TRUE)
writeLines("old", file.path(debug_dir, "old.txt"))
writeLines("old nested", file.path(debug_dir, "old", "nested", "call.txt"))

app = new.env(parent=emptyenv())
app$glob = list(main_dir=main_dir)
app$role = "student"
app$chat_debug = TRUE
app$userid = "student_a"
app$teacherid = "teacher_a"
app$semester = "SS26"
app$courseid = "course_a"
app$tutorid = "tutor_a"
app$instanceid = "instance_a"

ullme_debug_session_init(app=app)
stopifnot(
  dir.exists(debug_dir),
  file.exists(file.path(debug_dir, "000-session.txt")),
  !file.exists(file.path(debug_dir, "old.txt")),
  !file.exists(file.path(debug_dir, "old", "nested", "call.txt"))
)

state = new.env(parent=emptyenv())
state$app = app
state$tutor = list(tutorid="tutor_a")
state$model = "test-model"
record = ullme_debug_session_model_call_start(
  state,
  node_id="answer_node",
  attempt=2L,
  parallel_call=3L
)
call_path = ullme_debug_session_model_call_finish(
  record,
  state,
  system_prompt="Complete system prompt",
  prompt="Complete rendered prompt",
  answer="Complete answer",
  thinking="Internal reasoning"
)
content = paste(readLines(call_path, warn=FALSE), collapse="\n")
stopifnot(
  grepl("tutorid: tutor_a", content, fixed=TRUE),
  grepl("instanceid: instance_a", content, fixed=TRUE),
  grepl("node: answer_node", content, fixed=TRUE),
  grepl("attempt: 2", content, fixed=TRUE),
  grepl("parallel_call: 3", content, fixed=TRUE),
  grepl("Complete system prompt", content, fixed=TRUE),
  grepl("Complete rendered prompt", content, fixed=TRUE),
  grepl("Complete answer", content, fixed=TRUE),
  grepl("Internal reasoning", content, fixed=TRUE)
)

ullme_debug_session_init(app=app)
remaining = list.files(debug_dir, recursive=TRUE, all.files=TRUE, no..=TRUE)
stopifnot(
  identical(remaining, "000-session.txt"),
  identical(app$debug_session_call_seq, 0L)
)

ullme_clear_debug_session_dir(debug_dir)
