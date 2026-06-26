ullme_clean_user_name = function(username) {
  restore.point("ullme_clean_user_name")
  username = paste0(username)[1]
  username = gsub("[^A-Za-z0-9._-]+", "_", username)
  username = gsub("^_+|_+$", "", username)
  if (!nzchar(username)) username = "user"
  username
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


ullme_user_dir = function(main_dir, username) {
  restore.point("ullme_user_dir")
  file.path(main_dir, "users", username)
}


ullme_role_user_dir = function(main_dir, username, role) {
  restore.point("ullme_role_user_dir")
  file.path(main_dir, paste0(role, "s"), username)
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
    ullme_role_user_dir(main_dir=app$glob$main_dir, username=app$username, role="teacher"),
    ullme_role_user_dir(main_dir=app$glob$main_dir, username=app$username, role="student"),
    app$cur_session_dir,
    app$uploads_dir,
    app$audio_dir
  )
  vapply(dirs, dir.create, logical(1), recursive=TRUE, showWarnings=FALSE)
  invisible(dirs)
}
