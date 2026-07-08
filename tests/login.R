library(ullme)

main_dir = tempfile("ullme-login-")
dir.create(main_dir, recursive=TRUE)

yaml::write_yaml(
  list(
    "teacher.one@example.org"="teacher_one",
    "teacher.two@example.org"="teacher_two",
    "delegate@example.org"="teacher_one"
  ),
  file.path(main_dir, "allowed_teachers.yaml")
)

teachers = ullme_allowed_teachers(main_dir)
app = new.env(parent=emptyenv())
app$allowed_teachers = teachers

stopifnot(
  identical(
    ullme_allowed_teachers_path(main_dir),
    file.path(main_dir, "allowed_teachers.yaml")
  ),
  identical(
    ullme_teacherid_for_email("TEACHER.ONE@example.org", app=app),
    "teacher_one"
  ),
  identical(
    ullme_teacherid_for_email("delegate@example.org", app=app),
    "teacher_one"
  ),
  is.null(ullme_teacherid_for_email("unknown@example.org", app=app))
)

fixed = ullme_validate_sel_login_args(list(fixed.password="test-secret"))
stopifnot(
  identical(fixed$fixed.password, "test-secret"),
  identical(fixed$use.signup, FALSE)
)
stopifnot(is.list(ullme_validate_sel_login_args(list(
  use.signup=TRUE,
  db.arg=list(dbname="login.sqlite")
))))
stopifnot(is.list(ullme_validate_sel_login_args(list(
  login.by.query.key="require",
  token.dir="tokens"
))))

missing_backend = try(ullme_validate_sel_login_args(list()), silent=TRUE)
reserved = try(ullme_validate_sel_login_args(list(
  fixed.password="secret",
  login.fun=identity
)), silent=TRUE)
bad_email = try(ullme_login_email("not-an-email"), silent=TRUE)
stopifnot(
  inherits(missing_backend, "try-error"),
  inherits(reserved, "try-error"),
  inherits(bad_email, "try-error")
)

if (requireNamespace("digest", quietly=TRUE)) {
  first = ullme_login_student_userid("student.one@example.org")
  second = ullme_login_student_userid("student.two@example.org")
  stopifnot(
    grepl("^email_[a-f0-9]{32}$", first),
    identical(first, ullme_login_student_userid(
      "STUDENT.ONE@example.org"
    )),
    !identical(first, second)
  )
}

path_app = new.env(parent=emptyenv())
path_app$glob = list(main_dir=main_dir)
path_app$userid = "student_one"
path_app$role = "student"
ullme_set_app_user_paths(path_app, unique_resources=TRUE)
stopifnot(
  startsWith(path_app$user_dir, file.path(main_dir, "users")),
  grepl("^ullme-uploads-[A-Za-z0-9]{16}$",
        path_app$uploads_resource_prefix),
  grepl("^ullme-audio-[A-Za-z0-9]{16}$",
        path_app$audio_resource_prefix)
)

if (requireNamespace("shinyEventsLogin", quietly=TRUE)) {
  secret_course = file.path(
    main_dir,
    "teachers",
    "teacher_one",
    "courses",
    ullme_semester(),
    "secret_course"
  )
  dir.create(secret_course, recursive=TRUE)
  login_app = teacherApp(
    main_dir=main_dir,
    userid="ignored_before_login",
    api_provider="fake",
    login_check="sel",
    login_args=list(fixed.password="test-secret")
  )
  login_ui = htmltools::renderTags(login_app$ui)
  login_ui_text = paste(
    login_ui$head,
    login_ui$html,
    collapse="\n"
  )
  stopifnot(
    identical(login_app$userid, "login_pending"),
    identical(login_app$teacherid, "login_pending"),
    !length(login_app$courseids),
    !isTRUE(login_app$is.authenticated),
    grepl("mainUI", login_ui_text, fixed=TRUE),
    !grepl("secret_course", login_ui_text, fixed=TRUE),
    !grepl("ullme_app", login_ui_text, fixed=TRUE)
  )
}

ullme_remove_checked_directory(
  main_dir,
  root=dirname(main_dir),
  expected_name=basename(main_dir),
  label="login test directory"
)
