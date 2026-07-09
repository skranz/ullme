ullme_allowed_users_for_js = function(app=getApp()) {
  restore.point("ullme_allowed_users_for_js")
  if (!identical(app$role, "teacher")) return(NULL)
  main_dir = app$glob$main_dir
  teacherid = app$teacherid %||% ""
  if (!nzchar(teacherid) || identical(teacherid, "login_pending")) return(NULL)
  teachers = ullme_read_teachers(main_dir=main_dir)
  users = ullme_read_allowed_users(
    main_dir=main_dir,
    teacherid=teacherid,
    teachers=teachers
  )
  main_userid = unname(teachers[teacherid] %||% "")
  if (length(main_userid) == 0L || is.na(main_userid)) main_userid = ""
  list(
    teacherid=teacherid,
    current_userid=app$userid,
    can_set_users=ullme_user_can_set_allowed_users(
      main_dir=main_dir,
      teacherid=teacherid,
      userid=app$userid
    ),
    users=unname(lapply(names(users), function(userid) {
      spec = users[[userid]]
      list(
        userid=userid,
        email=ullme_read_user_email(main_dir=main_dir, userid=userid),
        main_teacher=isTRUE(spec$main_teacher) ||
          identical(userid, main_userid),
        can_set_users=isTRUE(spec$can_set_users)
      )
    }))
  )
}


ullme_allowed_userid_from_input = function(value, app=getApp()) {
  restore.point("ullme_allowed_userid_from_input")
  value = trimws(paste0(value %||% "")[1])
  if (!nzchar(value)) stop("Allowed user rows need an email or userid.")
  if (grepl("@", value, fixed=TRUE)) {
    email = ullme_login_email(value)
    userid = app$email2userid(email)
    if (is.null(userid)) {
      stop("This email address is not allowed: ", email, call.=FALSE)
    }
    ullme_write_user_email(
      main_dir=app$glob$main_dir,
      userid=userid,
      email=email
    )
    return(userid)
  }
  ullme_clean_user_name(value)
}


ullme_allowed_users_from_rows = function(rows, app=getApp()) {
  restore.point("ullme_allowed_users_from_rows")
  if (!is.list(rows)) rows = list()
  main_dir = app$glob$main_dir
  teacherid = app$teacherid
  teachers = ullme_read_teachers(main_dir=main_dir)
  main_userid = unname(teachers[teacherid] %||% "")
  if (length(main_userid) == 0L || is.na(main_userid)) main_userid = ""
  if (!nzchar(main_userid)) {
    stop("The active teacher is not listed in general/teachers.yaml.")
  }
  result = list()
  for (row in rows) {
    if (!is.list(row)) next
    raw = row$email_or_userid %||% row$userid %||% row$email %||% ""
    if (!nzchar(trimws(paste0(raw)[1]))) next
    userid = ullme_allowed_userid_from_input(raw, app=app)
    result[[userid]] = list(
      main_teacher=identical(userid, main_userid),
      can_set_users=isTRUE(row$can_set_users) ||
        identical(userid, main_userid)
    )
  }
  result[[main_userid]] = list(
    main_teacher=TRUE,
    can_set_users=TRUE
  )
  ullme_normalize_allowed_users(
    value=result,
    teacherid=teacherid,
    teachers=teachers
  )
}


ullme_save_allowed_users = function(rows, app=getApp()) {
  restore.point("ullme_save_allowed_users")
  if (!identical(app$role, "teacher")) {
    stop("Only teachers can edit allowed users.")
  }
  main_dir = app$glob$main_dir
  teacherid = app$teacherid %||% ""
  if (!nzchar(teacherid) || identical(teacherid, "login_pending")) {
    stop("No teacher workspace is active.")
  }
  if (!ullme_user_can_set_allowed_users(
    main_dir=main_dir,
    teacherid=teacherid,
    userid=app$userid
  )) {
    stop("You do not have permission to edit allowed users.")
  }
  old_users = ullme_read_allowed_users(main_dir=main_dir, teacherid=teacherid)
  users = ullme_allowed_users_from_rows(rows=rows, app=app)
  path = ullme_allowed_users_path(main_dir=main_dir, teacherid=teacherid)
  content = ullme_allowed_users_yaml(users)
  operation = ullme_new_change(
    action="allowed_users",
    summary=paste0("Update allowed users for teacher ", teacherid),
    origin="ui",
    details=list(teacherid=teacherid),
    changes=list(ullme_change_write(path, content)),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  if (!isTRUE(result$ok)) {
    stop(result$message %||% "Could not save allowed users.")
  }
  affected = unique(c(names(old_users), names(users)))
  for (userid in affected) {
    ullme_sync_user_teacherids(main_dir=main_dir, userid=userid)
  }
  result
}


ullme_handle_allowed_users_save = function(users=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_allowed_users_save")
  result = tryCatch({
    ullme_save_allowed_users(rows=users %||% list(), app=app)
    ullme_send_course_state(app=app)
    list(ok=TRUE, message="Allowed users saved.")
  }, error=function(e) {
    list(ok=FALSE, message=conditionMessage(e))
  })
  callJS(
    .fun="window.ullme.allowedUsersSaveComplete",
    .args=list(result),
    .app=app
  )
  invisible(result)
}
