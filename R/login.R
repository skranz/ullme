ullme_login_check = function(login_check=c("none", "sel")) {
  match.arg(login_check)
}


ullme_login_value_supplied = function(value) {
  if (is.null(value) || length(value) == 0) return(FALSE)
  if (is.character(value) && length(value) == 1L) {
    return(!is.na(value) && nzchar(trimws(value)))
  }
  TRUE
}


ullme_login_args_have_db = function(login_args) {
  if (!is.null(login_args$conn)) return(TRUE)
  db_arg = login_args$db.arg
  if (is.list(db_arg) &&
      !is.null(db_arg$dbname) &&
      nzchar(paste0(db_arg$dbname)[1])) {
    return(TRUE)
  }
  !is.null(login_args$dbname) && nzchar(paste0(login_args$dbname)[1])
}


ullme_login_options_requested = function(login_args=list(),
                                         login_fixed_password=NULL,
                                         login_db_dir=NULL,
                                         login_db=NULL,
                                         dbname=NULL,
                                         smtp=NULL,
                                         email.text.fun=NULL,
                                         use.signup=NULL) {
  if (!is.null(login_args) && length(login_args) > 0L) return(TRUE)
  isTRUE(use.signup) ||
    ullme_login_value_supplied(login_fixed_password) ||
    ullme_login_value_supplied(login_db_dir) ||
    ullme_login_value_supplied(login_db) ||
    ullme_login_value_supplied(dbname) ||
    ullme_login_value_supplied(smtp) ||
    !is.null(email.text.fun)
}


ullme_login_check_email_fun = function(email2userid=ullme_email2userid,
                                       email.domain=NULL) {
  force(email2userid)
  force(email.domain)
  function(email, ...) {
    if (!is.null(email.domain) && nzchar(paste0(email.domain)[1])) {
      domain = paste0(email.domain)[1]
      if (!startsWith(domain, "@")) domain = paste0("@", domain)
      if (!endsWith(tolower(paste0(email)[1]), tolower(domain))) {
        return(list(
          ok=FALSE,
          msg=paste0("You can only create an account with an email that ends with ", domain)
        ))
      }
    }
    res = tryCatch(email2userid(email), error=function(e) NULL)
    if (is.null(res)) {
      return(list(
        ok=FALSE,
        msg="This email address is not allowed for this uLLMe app."
      ))
    }
    list(ok=TRUE, msg="")
  }
}


ullme_login_db_path = function(main_dir, login_db_dir=NULL, login_db=NULL,
                               dbname=NULL, login_dbname="loginDB.sqlite") {
  db_path = login_db %||% dbname
  if (!is.null(db_path) && nzchar(paste0(db_path)[1])) {
    return(paste0(db_path)[1])
  }
  db_dir = login_db_dir
  if (is.null(db_dir) || !nzchar(paste0(db_dir)[1])) {
    db_dir = file.path(main_dir, "logindb")
  }
  dir.create(db_dir, recursive=TRUE, showWarnings=FALSE)
  file.path(db_dir, paste0(login_dbname %||% "loginDB.sqlite")[1])
}


ullme_prepare_login_args = function(main_dir, login_args=list(),
                                    login_fixed_password=NULL,
                                    login_db_dir=NULL,
                                    login_db=NULL,
                                    dbname=NULL,
                                    login_dbname="loginDB.sqlite",
                                    smtp=NULL,
                                    email.text.fun=NULL,
                                    email.domain=NULL,
                                    app.url=NULL,
                                    app.title=NULL,
                                    login.title=NULL,
                                    help.text=NULL,
                                    lang=NULL,
                                    use.signup=NULL,
                                    email2userid=ullme_email2userid) {
  restore.point("ullme_prepare_login_args")
  if (is.null(login_args)) login_args = list()
  if (!is.list(login_args)) stop("login_args must be a list.", call.=FALSE)

  args = list()
  if (ullme_login_value_supplied(login_fixed_password)) {
    args$fixed.password = paste0(login_fixed_password)[1]
  }

  wants_signup = isTRUE(use.signup) ||
    ullme_login_value_supplied(login_db_dir) ||
    ullme_login_value_supplied(login_db) ||
    ullme_login_value_supplied(dbname) ||
    ullme_login_value_supplied(smtp) ||
    !is.null(email.text.fun)
  if (!is.null(use.signup)) args$use.signup = isTRUE(use.signup)
  if (isTRUE(wants_signup) && !identical(use.signup, FALSE)) {
    args$use.signup = TRUE
    if (!ullme_login_args_have_db(login_args)) {
      args$dbname = ullme_login_db_path(
        main_dir=main_dir,
        login_db_dir=login_db_dir,
        login_db=login_db,
        dbname=dbname,
        login_dbname=login_dbname
      )
    }
    if (is.null(login_args$check.email.fun)) {
      args$check.email.fun = ullme_login_check_email_fun(
        email2userid=email2userid,
        email.domain=email.domain
      )
    }
  }

  if (ullme_login_value_supplied(smtp)) args$smtp = smtp
  if (!is.null(email.text.fun)) args$email.text.fun = email.text.fun
  if (!is.null(email.domain)) args$email.domain = email.domain
  if (!is.null(app.url)) {
    args$app.url = paste0(app.url)[1]
  } else if (isTRUE(wants_signup) && is.null(login_args$app.url)) {
    args$app.url = ""
  }
  if (!is.null(app.title)) args$app.title = paste0(app.title)[1]
  if (!is.null(login.title)) args$login.title = paste0(login.title)[1]
  if (!is.null(help.text)) args$help.text = paste0(help.text)[1]
  if (!is.null(lang)) args$lang = paste0(lang)[1]

  utils::modifyList(args, login_args)
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
  userid = ullme_email2userid(email)
  if (is.null(userid)) {
    stop("This email address is not allowed for uLLMe.", call.=FALSE)
  }
  userid
}


ullme_allowed_teachers_path = function(main_dir) {
  ullme_teachers_yaml_path(main_dir)
}


ullme_allowed_teachers = function(main_dir) {
  ullme_read_teachers(main_dir=main_dir, required=TRUE)
}


ullme_teacherid_for_email = function(email, app=getApp()) {
  email = ullme_login_email(email)
  userid = app$email2userid(email)
  if (is.null(userid)) return(NULL)
  teacherids = ullme_allowed_teacherids_for_userid(
    main_dir=app$glob$main_dir,
    userid=userid
  )
  if (length(teacherids) == 1L) teacherids[[1]] else NULL
}


ullme_sel_login_has_authentication = function(login_args) {
  fixed_password = login_args$fixed.password
  has_fixed_password =
    !is.null(fixed_password) &&
    length(fixed_password) == 1L &&
    !is.na(fixed_password) &&
    nzchar(paste0(fixed_password))
  has_database =
    !identical(login_args$use.signup, FALSE) &&
    ullme_login_args_have_db(login_args)
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
  if (identical(app$role, "student") &&
      !identical(app$userid, "login_pending")) {
    app$studentid = ullme_user_studentid(
      main_dir=main_dir,
      userid=app$userid,
      create=TRUE
    )
  }
  storage_id = ullme_app_role_storage_id(app=app)
  app$role_user_dir = ullme_role_user_dir(
    main_dir=main_dir,
    userid=storage_id,
    role=app$role
  )
  app$cur_session_dir = ullme_cur_session_dir(user_dir=app$user_dir)
  app$uploads_dir =
    ullme_cur_session_images_dir(cur_session_dir=app$cur_session_dir)
  app$audio_dir =
    ullme_cur_session_audio_dir(cur_session_dir=app$cur_session_dir)
  suffix = if (isTRUE(unique_resources)) {
    paste0("-", ullme_resource_token())
  } else {
    ""
  }
  app$uploads_resource_prefix = paste0("ullme-uploads", suffix)
  app$audio_resource_prefix = paste0("ullme-audio", suffix)
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


ullme_teacher_selection_ui = function(userid, teacherids, app=getApp()) {
  restore.point("ullme_teacher_selection_ui")
  tags$main(
    class="ullme-login-choice",
    style=paste0(
      "max-width:520px;margin:12vh auto;padding:24px;",
      "border:1px solid #dfe7e2;border-radius:12px;",
      "background:#fff;color:#1f2924;font-family:sans-serif;"
    ),
    tags$h2("Choose teacher workspace"),
    tags$p("Your account has access to more than one teacher workspace."),
    tags$div(
      style="display:grid;gap:8px;margin-top:16px;",
      lapply(teacherids, function(teacherid) {
        tags$button(
          type="button",
          style=paste0(
            "min-height:38px;border:1px solid #cad7d0;border-radius:8px;",
            "background:#f6faf8;color:#173d30;font:inherit;"
          ),
          onclick=paste0(
            "Shiny.setInputValue('ullme_teacher_select_event',{teacherid:'",
            htmltools::htmlEscape(teacherid),
            "',nonce:Math.random()},{priority:'event'});"
          ),
          teacherid
        )
      })
    )
  )
}


ullme_activate_authenticated_user = function(userid, teacherid=NULL,
                                             app=getApp()) {
  restore.point("ullme_activate_authenticated_user")
  app$userid = userid
  if (file.exists(ullme_teachers_yaml_path(app$glob$main_dir))) {
    try(
      ullme_sync_user_teacherids(main_dir=app$glob$main_dir, userid=userid),
      silent=TRUE
    )
  }
  if (identical(app$role, "teacher")) {
    app$teacherid = teacherid
  }
  ullme_set_app_user_paths(app=app, unique_resources=TRUE)
  if (identical(app$role, "teacher")) {
    app$courseids = ullme_user_courseids(
      main_dir=app$glob$main_dir,
      userid=app$teacherid,
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
  invisible(TRUE)
}


ullme_login_success = function(userid, app=getApp(), ...) {
  result = tryCatch({
    email = ullme_login_email(userid)
    clean_userid = app$email2userid(email)
    if (is.null(clean_userid)) {
      stop("This email address is not allowed for uLLMe.", call.=FALSE)
    }
    app$login_email = email
    ullme_write_user_email(
      main_dir=app$glob$main_dir,
      userid=clean_userid,
      email=email
    )
    if (identical(app$role, "teacher")) {
      ullme_make_teacher_dirs(main_dir=app$glob$main_dir)
      teacherids = ullme_allowed_teacherids_for_userid(
        main_dir=app$glob$main_dir,
        userid=clean_userid
      )
      if (length(teacherids) == 0) {
        stop(
          "The user ", clean_userid,
          " is not listed in any teacher allowed_users.yaml.",
          call.=FALSE
        )
      }
      if (length(teacherids) > 1L) {
        app$pending_teacher_userid = clean_userid
        app$pending_teacherids = teacherids
        setUI(
          "mainUI",
          ullme_teacher_selection_ui(
            userid=clean_userid,
            teacherids=teacherids,
            app=app
          )
        )
        return(list(ok=TRUE, message="Choose teacher workspace."))
      }
      ullme_activate_authenticated_user(
        userid=clean_userid,
        teacherid=teacherids[[1]],
        app=app
      )
    } else {
      ullme_activate_authenticated_user(
        userid=clean_userid,
        app=app
      )
    }
    list(ok=TRUE, message="")
  }, error=function(e) {
    ullme_set_app_authenticated(FALSE, app=app)
    message = conditionMessage(e)
    setUI("mainUI", ullme_login_denied_ui(message))
    list(ok=FALSE, message=message)
  })
  invisible(result)
}


ullme_handle_teacher_select = function(teacherid=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_teacher_select")
  result = tryCatch({
    teacherid = ullme_clean_user_name(teacherid)
    userid = app$pending_teacher_userid %||% ""
    allowed = app$pending_teacherids %||% character(0)
    if (!nzchar(userid) || !teacherid %in% allowed) {
      stop("This teacher workspace is not available for the active login.")
    }
    ullme_activate_authenticated_user(
      userid=userid,
      teacherid=teacherid,
      app=app
    )
    app$pending_teacher_userid = NULL
    app$pending_teacherids = NULL
    list(ok=TRUE, message="")
  }, error=function(e) {
    setUI("mainUI", ullme_login_denied_ui(conditionMessage(e)))
    list(ok=FALSE, message=conditionMessage(e))
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
    ullme_make_teacher_dirs(main_dir=app$glob$main_dir)
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
