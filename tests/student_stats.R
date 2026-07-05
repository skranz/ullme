library(ullme)

main_dir = tempfile("ullme-student-stats-")
dir.create(main_dir, recursive=TRUE)
app = studentApp(
  main_dir=main_dir,
  userid="student_a",
  teacherid="teacher_a",
  courseid="course_a",
  tutorid="tutor_a",
  api_provider="fake"
)

stopifnot(
  isTRUE(app$never_save_chats),
  !ullme_student_chat_history_enabled(app=app)
)
app$semester = "SS26"

first_id = ullme_student_session_stats_init(app=app)
first_path = app$session_stats_path
stopifnot(
  grepl("^[A-Za-z0-9]{16}$", first_id),
  identical(basename(first_path), paste0(first_id, ".csv")),
  identical(dirname(first_path), file.path(main_dir, "session_stats")),
  file.exists(first_path)
)

request = ullme_student_stats_request("fake-model", app=app)
ullme_student_stats_mark_output(
  request,
  at=request$started_at + 1.25
)
ullme_student_stats_mark_output(
  request,
  at=request$started_at + 2.5
)

second_id = ullme_student_session_stats_init(app=app)
second_path = app$session_stats_path
stopifnot(
  !identical(second_id, first_id),
  file.exists(first_path),
  file.exists(second_path)
)

stopifnot(ullme_student_stats_append(
  request,
  reply="This reply must not be stored.",
  error_code="ignored_when_reply_exists",
  app=app
))

first_rows = utils::read.csv(first_path, stringsAsFactors=FALSE)
stopifnot(
  identical(names(first_rows), ullme_student_session_stats_columns()),
  NROW(first_rows) == 1L,
  identical(first_rows$teacherid[[1]], "teacher_a"),
  identical(first_rows$semester[[1]], "SS26"),
  identical(first_rows$courseid[[1]], "course_a"),
  identical(first_rows$tutorid[[1]], "tutor_a"),
  identical(first_rows$model[[1]], "fake-model"),
  identical(first_rows$ttf_ms[[1]], 1250L),
  abs(first_rows$total_sec[[1]] - 2.5) < 0.001,
  is.na(first_rows$error[[1]]),
  !grepl("reply", paste(readLines(first_path), collapse="\n"), fixed=TRUE)
)

failed = ullme_student_stats_request("fake-model", app=app)
stopifnot(ullme_student_stats_append(
  failed,
  reply="",
  error_code="provider_error",
  app=app
))
second_rows = utils::read.csv(second_path, stringsAsFactors=FALSE)
stopifnot(
  NROW(second_rows) == 1L,
  identical(second_rows$error[[1]], "provider_error"),
  is.na(second_rows$ttf_ms[[1]]),
  is.na(second_rows$total_sec[[1]])
)

unlink(main_dir, recursive=TRUE)
