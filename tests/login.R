library(ullme)

main_dir = tempfile("ullme-login-")
dir.create(file.path(main_dir, "general"), recursive=TRUE)

yaml::write_yaml(
  list(
    skranz="sebastian_kranz",
    esol="erin_solstice"
  ),
  file.path(main_dir, "general", "teachers.yaml")
)

stopifnot(
  identical(
    ullme_email2userid("Sebastian.Kranz@uni-ulm.de"),
    "sebastian_kranz"
  ),
  is.null(ullme_email2userid("sebastian.kranz@example.org"))
)

teacher_dirs = ullme_make_teacher_dirs(main_dir)
stopifnot(
  dir.exists(file.path(main_dir, "teachers", "skranz", "config")),
  file.exists(file.path(
    main_dir, "teachers", "skranz", "config", "allowed_users.yaml"
  )),
  length(teacher_dirs) == 2L
)

skranz_users = ullme_read_allowed_users(main_dir, "skranz")
stopifnot(
  isTRUE(skranz_users$sebastian_kranz$main_teacher),
  isTRUE(skranz_users$sebastian_kranz$can_set_users)
)

ullme_write_allowed_users(
  main_dir=main_dir,
  teacherid="esol",
  users=list(
    erin_solstice=list(main_teacher=TRUE, can_set_users=TRUE),
    sebastian_kranz=list(can_set_users=FALSE)
  )
)

ullme_write_user_email(
  main_dir=main_dir,
  userid="sebastian_kranz",
  email="sebastian.kranz@uni-ulm.de"
)
studentid = ullme_user_studentid(main_dir, "sebastian_kranz")
teacherids = ullme_allowed_teacherids_for_userid(
  main_dir=main_dir,
  userid="sebastian_kranz"
)

app = new.env(parent=emptyenv())
app$glob = list(main_dir=main_dir)
app$email2userid = ullme_email2userid

stopifnot(
  ullme_valid_studentid(studentid),
  identical(
    ullme_read_user_email(main_dir, "sebastian_kranz"),
    "sebastian.kranz@uni-ulm.de"
  ),
  identical(sort(teacherids), c("esol", "skranz")),
  is.null(ullme_teacherid_for_email("unknown@uni-ulm.de", app=app))
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

path_app = new.env(parent=emptyenv())
path_app$glob = list(main_dir=main_dir)
path_app$userid = "sebastian_kranz"
path_app$studentid = studentid
path_app$role = "student"
ullme_set_app_user_paths(path_app, unique_resources=TRUE)
stopifnot(
  startsWith(path_app$user_dir, file.path(main_dir, "users")),
  identical(
    path_app$role_user_dir,
    file.path(main_dir, "students", studentid)
  ),
  grepl("^ullme-uploads-[A-Za-z0-9]{16}$",
        path_app$uploads_resource_prefix),
  grepl("^ullme-audio-[A-Za-z0-9]{16}$",
        path_app$audio_resource_prefix)
)

teacher_app = new.env(parent=emptyenv())
teacher_app$glob = list(main_dir=main_dir)
teacher_app$userid = "sebastian_kranz"
teacher_app$teacherid = "skranz"
teacher_app$role = "teacher"
ullme_set_app_user_paths(teacher_app, unique_resources=TRUE)
stopifnot(
  identical(
    teacher_app$role_user_dir,
    file.path(main_dir, "teachers", "skranz")
  )
)

if (requireNamespace("shinyEventsLogin", quietly=TRUE)) {
  secret_course = file.path(
    main_dir,
    "teachers",
    "skranz",
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
