ullme_login_check = function(login_check=c("none", "sel")) {
  match.arg(login_check)
}


ullme_login_email = function(value) {
  email = tolower(trimws(paste0(value %||% "")[1]))
  valid = !is.na(email) &&
    grepl("^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$", email)
  if (!isTRUE(valid)) {
    stop("Please log in with a valid email address.", call.=FALSE)
  }
  email
}


ullme_login_student_userid = function(email) {
  email = ullme_login_email(email)
  if (!requireNamespace("digest", quietly=TRUE)) {
    stop("Student login requires the digest package.", call.=FALSE)
  }
  paste0(
    "email_",
    substr(
      digest::digest(email, algo="sha256", serialize=FALSE),
      1,
      32
    )
  )
}


ullme_allowed_teachers_path = function(main_dir) {
  yaml_path = file.path(main_dir, "allowed_teachers.yaml")
  yml_path = file.path(main_dir, "allowed_teachers.yml")
  if (file.exists(yaml_path)) return(yaml_path)
  if (file.exists(yml_path)) return(yml_path)
  yaml_path
}


ullme_allowed_teachers = function(main_dir) {
  path = ullme_allowed_teachers_path(main_dir)
  if (!file.exists(path)) {
    stop(
      "Teacher login requires ", path,
      ". Add entries such as 'teacher@example.org: teacher_id'.",
      call.=FALSE
    )
  }
  value = yaml::read_yaml(path, eval.expr=FALSE)
  if (is.list(value) &&
      length(value) == 1L &&
      !is.null(names(value)) &&
      names(value)[[1]] %in% c("allowed_teachers", "teachers")) {
    value = value[[1]]
  }
  if (is.null(value) || !is.list(value) || is.null(names(value))) {
    stop(
      "allowed_teachers.yaml must map email addresses to teacher IDs.",
      call.=FALSE
    )
  }
  emails = vapply(names(value), ullme_login_email, character(1))
  teacherids = vapply(value, function(teacherid) {
    teacherid = paste0(teacherid %||% "")[1]
    clean = ullme_clean_user_name(teacherid)
    if (!nzchar(teacherid) || !identical(clean, teacherid)) {
      stop(
        "Invalid teacher ID in allowed_teachers.yaml: ",
        teacherid,
        call.=FALSE
      )
    }
    clean
  }, character(1))
  if (anyDuplicated(emails)) {
    stop(
      "Each email address may occur only once in allowed_teachers.yaml.",
      call.=FALSE
    )
  }
  setNames(teacherids, emails)
}


ullme_teacherid_for_email = function(email, app=getApp()) {
  email = ullme_login_email(email)
  teachers = app$allowed_teachers %||% character()
  teacherid = unname(teachers[email])
  if (!length(teacherid) || is.na(teacherid) || !nzchar(teacherid)) {
    return(NULL)
  }
  teacherid[[1]]
}


ullme_sel_login_has_authentication = function(login_args) {
  fixed_password = login_args$fixed.password
  has_fixed_password =
    !is.null(fixed_password) &&
    length(fixed_password) == 1L &&
    !is.na(fixed_password) &&
    nzchar(paste0(fixed_password))
  db_arg = login_args$db.arg
  has_database =
    !identical(login_args$use.signup, FALSE) &&
    (
      !is.null(login_args$conn) ||
      (
        is.list(db_arg) &&
        !is.null(db_arg$dbname) &&
        nzchar(paste0(db_arg$dbname)[1])
      )
    )
  query_mode = paste0(login_args$login.by.query.key %||% "no")[1]
  cookie_mode = paste0(login_args$login.by.cookie %||% "no")[1]
  uses_token = query_mode %in% c("allow", "require") ||
    cookie_mode %in% c("allow", "require")
  has_token_backend = uses_token &&
    !is.null(login_args$token.dir) &&
    nzchar(paste0(login_args$token.dir)[1])
  isTRUE(has_fixed_password || has_database || has_token_backend)
}


ullme_validate_sel_login_args = function(login_args) {
  if (is.null(login_args)) login_args = list()
  if (!is.list(login_args)) stop("login_args must be a list.", call.=FALSE)
  reserved = intersect(
    names(login_args),
    c(
      "app", "container.id", "login.fun",
      "userid.equals.email", "only.lowercase", "set.need.authentication"
    )
  )
  if (length(reserved)) {
    stop(
      "These login_args are managed by uLLMe: ",
      paste(reserved, collapse=", "),
      ".",
      call.=FALSE
    )
  }
  if (!ullme_sel_login_has_authentication(login_args)) {
    stop(
      "login_check='sel' requires an authentication backend in login_args: ",
      "a non-empty fixed.password, a configured signup database, or a ",
      "query/cookie token backend.",
      call.=FALSE
    )
  }
  if (!is.null(login_args$fixed.password) &&
      is.null(login_args$use.signup)) {
    login_args$use.signup = FALSE
  }
  login_args
}


ullme_login_shell_ui = function() {
  tagList(
    tags$head(
      tags$meta(
        name="viewport",
        content="width=device-width, initial-scale=1"
      ),
      tags$style(HTML(paste0(
        "html,body{min-height:100%;background:#f4f7f5;}",
        "#mainUI>.well{max-width:430px;margin:10vh auto 0;",
        "border:1px solid #dce5e0;border-radius:12px;",
        "background:#fff;box-shadow:0 16px 45px rgba(31,64,51,.09);}"
      )))
    ),
    uiOutput("mainUI")
  )
}


ullme_set_app_authenticated = function(value, app=getApp()) {
  app$is.authenticated = isTRUE(value)
  if (exists("setAppIsAuthenticated", mode="function", inherits=TRUE)) {
    try(setAppIsAuthenticated(isTRUE(value)), silent=TRUE)
  }
  invisible(app$is.authenticated)
}


ullme_resource_token = function(length=16L) {
  alphabet = c(letters, LETTERS, as.character(0:9))
  paste0(sample(alphabet, length, replace=TRUE), collapse="")
}


ullme_set_app_user_paths = function(app=getApp(), unique_resources=FALSE) {
  main_dir = app$glob$main_dir
  app$user_dir = ullme_user_dir(main_dir=main_dir, userid=app$userid)
  app$role_user_dir = ullme_role_user_dir(
    main_dir=main_dir,
    userid=app$userid,
    role=app$role
  )
  app$cur_session_dir = ullme_cur_session_dir(user_dir=app$user_dir)
  app$uploads_dir =
    ullme_cur_session_images_dir(cur_session_dir=app$cur_session_dir)
  app$audio_dir =
    ullme_cur_session_audio_dir(cur_session_dir=app$cur_session_dir)
  app$definition_downloads_dir =
    file.path(app$cur_session_dir, "definition_downloads")
  suffix = if (isTRUE(unique_resources)) {
    paste0("-", ullme_resource_token())
  } else {
    ""
  }
  app$uploads_resource_prefix = paste0("ullme-uploads", suffix)
  app$audio_resource_prefix = paste0("ullme-audio", suffix)
  app$definition_downloads_resource_prefix =
    paste0("ullme-definition-downloads", suffix)
  app$resource_paths_registered = FALSE
  invisible(app)
}


ullme_login_denied_ui = function(message) {
  tags$main(
    style=paste0(
      "max-width:520px;margin:12vh auto;padding:24px;",
      "border:1px solid #ead8d8;border-radius:12px;",
      "background:#fff;color:#6f2929;font-family:sans-serif;"
    ),
    tags$h2("Access denied"),
    tags$p(message),
    tags$p("Reload the page to try another account.")
  )
}


ullme_login_failed = function(msg="Log-in failed.", lop, app=getApp(), ...) {
  ullme_set_app_authenticated(FALSE, app=app)
  setUI(
    lop$ns("loginAlert"),
    tags$div(
      style="color:#8a2f2f;margin-top:8px;",
      paste0(msg %||% "Log-in failed.")[1]
    )
  )
  invisible(FALSE)
}


ullme_login_success = function(userid, app=getApp(), ...) {
  result = tryCatch({
    email = ullme_login_email(userid)
    if (identical(app$role, "teacher")) {
      teacherid = ullme_teacherid_for_email(email, app=app)
      if (is.null(teacherid)) {
        stop(
          "The email address ", email,
          " is not listed in allowed_teachers.yaml.",
          call.=FALSE
        )
      }
      app$userid = teacherid
      app$teacherid = teacherid
    } else {
      app$userid = ullme_login_student_userid(email)
    }
    app$login_email = email
    ullme_set_app_user_paths(app=app, unique_resources=TRUE)
    if (identical(app$role, "teacher")) {
      app$courseids = ullme_user_courseids(
        main_dir=app$glob$main_dir,
        userid=app$userid,
        role=app$role,
        semester=app$semester
      )
      app$courseid = ullme_selected_courseid(
        app$courseids,
        preferred=app$courseid
      )
    }
    ullme_add_resource_paths(app=app)
    ullme_set_app_authenticated(TRUE, app=app)
    setUI("mainUI", ullme_app_ui(app=app))
    ullme_init_app(session=app$session, app=app)
    list(ok=TRUE, message="")
  }, error=function(e) {
    ullme_set_app_authenticated(FALSE, app=app)
    message = conditionMessage(e)
    setUI("mainUI", ullme_login_denied_ui(message))
    list(ok=FALSE, message=message)
  })
  invisible(result)
}


ullme_make_login_module = function(app=getApp()) {
  if (!requireNamespace("shinyEventsLogin", quietly=TRUE)) {
    stop(
      "login_check='sel' requires shinyEventsLogin. Install it with ",
      "remotes::install_github('skranz/shinyEventsLogin').",
      call.=FALSE
    )
  }
  login_args = ullme_validate_sel_login_args(app$login_args)
  if (!is.null(login_args$allowed.userids)) {
    login_args$allowed.userids = vapply(
      login_args$allowed.userids,
      ullme_login_email,
      character(1)
    )
  }
  if (identical(app$role, "teacher")) {
    allowed = names(app$allowed_teachers)
    if (!is.null(login_args$allowed.userids)) {
      configured = tolower(trimws(paste0(login_args$allowed.userids)))
      allowed = intersect(allowed, configured)
    }
    login_args$allowed.userids = allowed
  }
  arguments = utils::modifyList(
    list(
      container.id="mainUI",
      login.fun=ullme_login_success,
      login.failed.fun=ullme_login_failed,
      app=app,
      app.title="uLLMe",
      login.title="<h3>Sign in to uLLMe</h3>",
      help.text="Use your email address as the user name.",
      userid.equals.email=TRUE,
      only.lowercase=TRUE,
      set.need.authentication=TRUE
    ),
    login_args
  )
  do.call(shinyEventsLogin::loginModule, arguments)
}


ullme_init_login = function(app=getApp()) {
  shinyEventsLogin::initLoginDispatch(app$login_module, app=app)
  invisible(TRUE)
}
