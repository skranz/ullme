ullme_clean_user_name = function(userid) {
  restore.point("ullme_clean_user_name")
  userid = paste0(userid)[1]
  userid = gsub("[^A-Za-z0-9._-]+", "_", userid)
  userid = gsub("^_+|_+$", "", userid)
  if (!nzchar(userid)) userid = "user"
  userid
}


ullme_email2userid = function(email, domain="uni-ulm.de") {
  restore.point("ullme_email2userid")
  email = tolower(trimws(paste0(email %||% "")[1]))
  domain = tolower(trimws(paste0(domain %||% "")[1]))
  valid = !is.na(email) &&
    grepl("^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$", email)
  if (!isTRUE(valid)) {
    message("Invalid email address: ", email)
    return(NULL)
  }
  parts = strsplit(email, "@", fixed=TRUE)[[1]]
  if (length(parts) != 2L || !identical(parts[[2]], domain)) {
    message("Only @", domain, " email addresses are allowed.")
    return(NULL)
  }
  userid = gsub("[^A-Za-z0-9]+", "_", parts[[1]])
  userid = gsub("^_+|_+$", "", userid)
  if (!nzchar(userid)) return(NULL)
  userid
}


ullme_normalize_role = function(role) {
  restore.point("ullme_normalize_role")
  role = tolower(paste0(role)[1])
  if (!role %in% c("teacher", "student", "admin")) {
    stop("role must be 'teacher', 'student', or 'admin'.")
  }
  role
}


ullme_normalize_roles = function(roles) {
  restore.point("ullme_normalize_roles")
  roles = unique(tolower(paste0(roles)))
  roles = roles[nzchar(roles)]
  if (length(roles) == 0) stop("allowed_roles must contain at least one role.")
  vapply(roles, ullme_normalize_role, character(1), USE.NAMES=FALSE)
}


ullme_user_dir = function(main_dir, userid) {
  restore.point("ullme_user_dir")
  file.path(main_dir, "users", userid)
}


ullme_user_email_path = function(main_dir, userid) {
  restore.point("ullme_user_email_path")
  file.path(ullme_user_dir(main_dir=main_dir, userid=userid), "email.txt")
}


ullme_write_user_email = function(main_dir, userid, email) {
  restore.point("ullme_write_user_email")
  email = tolower(trimws(paste0(email %||% "")[1]))
  if (!nzchar(email)) return(invisible(FALSE))
  path = ullme_user_email_path(main_dir=main_dir, userid=userid)
  dir.create(dirname(path), recursive=TRUE, showWarnings=FALSE)
  writeLines(email, path, useBytes=TRUE)
  invisible(TRUE)
}


ullme_read_user_email = function(main_dir, userid) {
  restore.point("ullme_read_user_email")
  path = ullme_user_email_path(main_dir=main_dir, userid=userid)
  if (!file.exists(path)) return("")
  paste0(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n")
}


ullme_user_studentid_path = function(main_dir, userid) {
  restore.point("ullme_user_studentid_path")
  file.path(ullme_user_dir(main_dir=main_dir, userid=userid), "studentid.txt")
}


ullme_valid_studentid = function(studentid) {
  restore.point("ullme_valid_studentid")
  studentid = paste0(studentid %||% "")[1]
  !is.na(studentid) && grepl("^[A-Za-z][A-Za-z0-9]{11}$", studentid)
}


ullme_new_studentid = function(main_dir) {
  restore.point("ullme_new_studentid")
  first = letters
  rest = c(letters, LETTERS, as.character(0:9))
  repeat {
    studentid = paste0(
      sample(first, 1),
      paste0(sample(rest, 11, replace=TRUE), collapse="")
    )
    if (!dir.exists(file.path(main_dir, "students", studentid))) {
      return(studentid)
    }
  }
}


ullme_user_studentid = function(main_dir, userid, create=TRUE) {
  restore.point("ullme_user_studentid")
  path = ullme_user_studentid_path(main_dir=main_dir, userid=userid)
  if (file.exists(path)) {
    studentid = trimws(readLines(path, warn=FALSE, encoding="UTF-8")[[1]])
    if (ullme_valid_studentid(studentid)) return(studentid)
  }
  if (!isTRUE(create)) return(NULL)
  studentid = ullme_new_studentid(main_dir=main_dir)
  dir.create(dirname(path), recursive=TRUE, showWarnings=FALSE)
  writeLines(studentid, path, useBytes=TRUE)
  studentid
}


ullme_user_teacherids_path = function(main_dir, userid) {
  restore.point("ullme_user_teacherids_path")
  file.path(ullme_user_dir(main_dir=main_dir, userid=userid), "teacherids.txt")
}


ullme_read_user_teacherids = function(main_dir, userid) {
  restore.point("ullme_read_user_teacherids")
  path = ullme_user_teacherids_path(main_dir=main_dir, userid=userid)
  if (!file.exists(path)) return(character(0))
  ids = trimws(readLines(path, warn=FALSE, encoding="UTF-8"))
  ids[nzchar(ids)]
}


ullme_write_user_teacherids = function(main_dir, userid, teacherids) {
  restore.point("ullme_write_user_teacherids")
  teacherids = sort(unique(trimws(paste0(teacherids))))
  teacherids = teacherids[nzchar(teacherids)]
  path = ullme_user_teacherids_path(main_dir=main_dir, userid=userid)
  dir.create(dirname(path), recursive=TRUE, showWarnings=FALSE)
  writeLines(teacherids, path, useBytes=TRUE)
  invisible(teacherids)
}


ullme_general_dir = function(main_dir) {
  restore.point("ullme_general_dir")
  file.path(main_dir, "general")
}


ullme_teachers_yaml_path = function(main_dir) {
  restore.point("ullme_teachers_yaml_path")
  yaml_path = file.path(ullme_general_dir(main_dir), "teachers.yaml")
  yml_path = file.path(ullme_general_dir(main_dir), "teachers.yml")
  if (file.exists(yaml_path)) return(yaml_path)
  if (file.exists(yml_path)) return(yml_path)
  yaml_path
}


ullme_read_teachers = function(main_dir, required=FALSE) {
  restore.point("ullme_read_teachers")
  path = ullme_teachers_yaml_path(main_dir)
  if (!file.exists(path)) {
    if (isTRUE(required)) {
      stop(
        "Teacher login requires ", path,
        ". Add entries such as 'skranz: sebastian_kranz'.",
        call.=FALSE
      )
    }
    return(character(0))
  }
  value = yaml::read_yaml(path, eval.expr=FALSE)
  if (is.list(value) &&
      length(value) == 1L &&
      !is.null(names(value)) &&
      names(value)[[1]] %in% c("teachers", "allowed_teachers")) {
    value = value[[1]]
  }
  if (is.null(value) || !is.list(value) || is.null(names(value))) {
    stop("teachers.yaml must map teacher IDs to main user IDs.", call.=FALSE)
  }
  teacherids = vapply(names(value), function(teacherid) {
    clean = ullme_clean_user_name(teacherid)
    if (!identical(clean, teacherid)) {
      stop("Invalid teacher ID in teachers.yaml: ", teacherid, call.=FALSE)
    }
    clean
  }, character(1))
  userids = vapply(value, function(userid) {
    userid = paste0(userid %||% "")[1]
    clean = ullme_clean_user_name(userid)
    if (!nzchar(userid) || !identical(clean, userid)) {
      stop("Invalid main userid in teachers.yaml: ", userid, call.=FALSE)
    }
    clean
  }, character(1))
  if (anyDuplicated(teacherids)) {
    stop("Each teacher ID may occur only once in teachers.yaml.", call.=FALSE)
  }
  setNames(userids, teacherids)
}


ullme_teacher_dir = function(main_dir, teacherid) {
  restore.point("ullme_teacher_dir")
  file.path(main_dir, "teachers", teacherid)
}


ullme_teacher_config_dir = function(main_dir, teacherid) {
  restore.point("ullme_teacher_config_dir")
  file.path(ullme_teacher_dir(main_dir=main_dir, teacherid=teacherid), "config")
}


ullme_allowed_users_path = function(main_dir, teacherid) {
  restore.point("ullme_allowed_users_path")
  file.path(
    ullme_teacher_config_dir(main_dir=main_dir, teacherid=teacherid),
    "allowed_users.yaml"
  )
}


ullme_normalize_allowed_users = function(value, teacherid, teachers=NULL) {
  restore.point("ullme_normalize_allowed_users")
  if (is.null(value)) value = list()
  if (!is.list(value) || (length(value) > 0L && is.null(names(value)))) {
    stop("allowed_users.yaml must map user IDs to permission records.")
  }
  result = list()
  for (userid in names(value)) {
    clean = ullme_clean_user_name(userid)
    if (!identical(clean, userid)) {
      stop("Invalid userid in allowed_users.yaml: ", userid, call.=FALSE)
    }
    spec = value[[userid]]
    if (is.null(spec)) spec = list()
    if (!is.list(spec)) stop("Permission records must be YAML mappings.")
    result[[userid]] = list(
      main_teacher=isTRUE(spec$main_teacher),
      can_set_users=isTRUE(spec$can_set_users)
    )
  }
  if (is.null(teachers)) teachers = character(0)
  main_userid = unname(teachers[teacherid] %||% "")
  if (length(main_userid) == 0L || is.na(main_userid)) main_userid = ""
  if (nzchar(main_userid)) {
    current = result[[main_userid]] %||% list()
    result[[main_userid]] = list(
      main_teacher=TRUE,
      can_set_users=TRUE || isTRUE(current$can_set_users)
    )
  }
  result[sort(names(result))]
}


ullme_read_allowed_users = function(main_dir, teacherid, teachers=NULL) {
  restore.point("ullme_read_allowed_users")
  path = ullme_allowed_users_path(main_dir=main_dir, teacherid=teacherid)
  value = if (file.exists(path)) {
    yaml::read_yaml(path, eval.expr=FALSE)
  } else {
    list()
  }
  ullme_normalize_allowed_users(
    value=value,
    teacherid=teacherid,
    teachers=teachers %||% ullme_read_teachers(main_dir)
  )
}


ullme_allowed_users_yaml = function(users) {
  restore.point("ullme_allowed_users_yaml")
  if (length(users) == 0) return("{}")
  trimws(yaml::as.yaml(users))
}


ullme_write_allowed_users = function(main_dir, teacherid, users) {
  restore.point("ullme_write_allowed_users")
  teachers = ullme_read_teachers(main_dir)
  users = ullme_normalize_allowed_users(
    users,
    teacherid=teacherid,
    teachers=teachers
  )
  path = ullme_allowed_users_path(main_dir=main_dir, teacherid=teacherid)
  dir.create(dirname(path), recursive=TRUE, showWarnings=FALSE)
  writeLines(ullme_allowed_users_yaml(users), path, useBytes=TRUE)
  invisible(users)
}


ullme_make_teacher_dirs = function(main_dir) {
  restore.point("ullme_make_teacher_dirs")
  teachers = ullme_read_teachers(main_dir=main_dir, required=TRUE)
  for (teacherid in names(teachers)) {
    dir.create(
      ullme_teacher_config_dir(main_dir=main_dir, teacherid=teacherid),
      recursive=TRUE,
      showWarnings=FALSE
    )
    path = ullme_allowed_users_path(main_dir=main_dir, teacherid=teacherid)
    if (!file.exists(path)) {
      users = list()
      users[[teachers[[teacherid]]]] = list(
        main_teacher=TRUE,
        can_set_users=TRUE
      )
      ullme_write_allowed_users(
        main_dir=main_dir,
        teacherid=teacherid,
        users=users
      )
    }
  }
  invisible(file.path(main_dir, "teachers", names(teachers)))
}


ullme_allowed_teacherids_for_userid = function(main_dir, userid) {
  restore.point("ullme_allowed_teacherids_for_userid")
  userid = ullme_clean_user_name(userid)
  teachers = ullme_read_teachers(main_dir=main_dir, required=TRUE)
  teacherids = names(teachers)
  allowed = teacherids[vapply(teacherids, function(teacherid) {
    users = ullme_read_allowed_users(
      main_dir=main_dir,
      teacherid=teacherid,
      teachers=teachers
    )
    userid %in% names(users)
  }, logical(1))]
  ullme_write_user_teacherids(main_dir=main_dir, userid=userid, teacherids=allowed)
  allowed
}


ullme_teacher_user_access = function(main_dir, teacherid, userid) {
  restore.point("ullme_teacher_user_access")
  users = ullme_read_allowed_users(main_dir=main_dir, teacherid=teacherid)
  users[[userid]] %||% NULL
}


ullme_user_can_set_allowed_users = function(main_dir, teacherid, userid) {
  restore.point("ullme_user_can_set_allowed_users")
  access = ullme_teacher_user_access(
    main_dir=main_dir,
    teacherid=teacherid,
    userid=userid
  )
  is.list(access) && isTRUE(access$can_set_users)
}


ullme_sync_user_teacherids = function(main_dir, userid) {
  restore.point("ullme_sync_user_teacherids")
  ullme_allowed_teacherids_for_userid(main_dir=main_dir, userid=userid)
}


ullme_role_user_dir = function(main_dir, userid, role) {
  restore.point("ullme_role_user_dir")
  file.path(main_dir, paste0(role, "s"), userid)
}


ullme_app_role_storage_id = function(app=getApp()) {
  restore.point("ullme_app_role_storage_id")
  if (identical(app$role, "teacher")) {
    return(app$teacherid %||% app$userid)
  }
  if (identical(app$role, "student")) {
    return(app$studentid %||% app$userid)
  }
  app$userid
}


ullme_cur_session_dir = function(user_dir) {
  restore.point("ullme_cur_session_dir")
  file.path(user_dir, "cur_session")
}


ullme_cur_session_images_dir = function(cur_session_dir) {
  restore.point("ullme_cur_session_images_dir")
  file.path(cur_session_dir, "images")
}


ullme_cur_session_audio_dir = function(cur_session_dir) {
  restore.point("ullme_cur_session_audio_dir")
  file.path(cur_session_dir, "audio")
}


ullme_init_user_dirs = function(app=getApp()) {
  restore.point("ullme_init_user_dirs")
  dirs = c(
    app$user_dir,
    app$role_user_dir,
    app$cur_session_dir,
    app$uploads_dir,
    app$audio_dir,
    ullme_change_history_dir(app=app),
    ullme_change_backup_root(app=app)
  )
  vapply(dirs, dir.create, logical(1), recursive=TRUE, showWarnings=FALSE)
  invisible(dirs)
}
