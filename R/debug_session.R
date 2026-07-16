ullme_debug_session_dir = function(app=getApp()) {
  file.path(ullme_main_dir(app=app), "debug_session")
}


ullme_debug_path_is_within = function(path, root, allow_root=FALSE) {
  path = normalizePath(path, winslash="/", mustWork=FALSE)
  root = normalizePath(root, winslash="/", mustWork=TRUE)
  if (identical(.Platform$OS.type, "windows")) {
    path = tolower(path)
    root = tolower(root)
  }
  (isTRUE(allow_root) && identical(path, root)) ||
    startsWith(path, paste0(root, "/"))
}


ullme_clear_debug_session_dir = function(directory) {
  if (!dir.exists(directory)) {
    if (!dir.create(directory, recursive=TRUE, showWarnings=FALSE)) {
      stop("Could not create the debug-session directory.")
    }
    return(invisible(directory))
  }
  directory = normalizePath(directory, winslash="/", mustWork=TRUE)
  link = Sys.readlink(directory)
  if (length(link) == 1L && !is.na(link) && nzchar(link)) {
    stop("The debug-session directory must not be a symbolic link.")
  }
  files = list.files(
    directory,
    recursive=TRUE,
    full.names=TRUE,
    all.files=TRUE,
    no..=TRUE,
    include.dirs=FALSE
  )
  if (length(files)) {
    safe = vapply(
      files,
      ullme_debug_path_is_within,
      logical(1),
      root=directory
    )
    if (!all(safe)) stop("Refusing to clear a debug file outside debug_session.")
    removed = file.remove(files)
    if (!all(removed)) stop("Could not clear all previous debug-session files.")
  }
  remaining_files = list.files(
    directory,
    recursive=TRUE,
    full.names=TRUE,
    all.files=TRUE,
    no..=TRUE,
    include.dirs=FALSE
  )
  if (length(remaining_files)) {
    stop("Previous debug-session files remain after cleanup.")
  }
  invisible(directory)
}


ullme_debug_session_init = function(app=getApp()) {
  if (!identical(app$role, "student") || !isTRUE(app$chat_debug)) {
    app$debug_session_dir = NULL
    app$debug_session_call_seq = 0L
    return(invisible(NULL))
  }
  directory = ullme_debug_session_dir(app=app)
  ullme_clear_debug_session_dir(directory)
  app$debug_session_dir = normalizePath(
    directory,
    winslash="/",
    mustWork=TRUE
  )
  app$debug_session_call_seq = 0L
  writeLines(
    c(
      "uLLMe student debug session",
      paste0("started_at: ", format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")),
      paste0("userid: ", app$userid %||% ""),
      paste0("teacherid: ", app$teacherid %||% ""),
      paste0("semester: ", app$semester %||% ""),
      paste0("courseid: ", app$courseid %||% "")
    ),
    file.path(app$debug_session_dir, "000-session.txt"),
    useBytes=TRUE
  )
  invisible(app$debug_session_dir)
}


ullme_debug_session_model_call_start = function(state, node_id,
                                                 attempt=1L,
                                                 parallel_call=1L) {
  app = state$app
  if (!identical(app$role, "student") || !isTRUE(app$chat_debug) ||
      is.null(app$debug_session_dir)) return(NULL)
  app$debug_session_call_seq = as.integer(
    app$debug_session_call_seq %||% 0L
  ) + 1L
  list(
    index=app$debug_session_call_seq,
    node=paste0(node_id %||% "")[1],
    attempt=as.integer(attempt)[1],
    parallel_call=as.integer(parallel_call)[1],
    started_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  )
}


ullme_debug_session_model_call_finish = function(record, state,
                                                  system_prompt, prompt,
                                                  answer="", thinking="",
                                                  error="") {
  if (is.null(record)) return(invisible(NULL))
  app = state$app
  directory = app$debug_session_dir
  if (is.null(directory) || !dir.exists(directory)) return(invisible(NULL))
  safe_node = gsub("[^A-Za-z0-9_-]+", "-", record$node)
  if (!nzchar(safe_node)) safe_node = "unknown-node"
  path = file.path(
    directory,
    sprintf("%03d-%s.txt", record$index, safe_node)
  )
  head = c(
    "ULLME STUDENT MODEL CALL",
    paste0("started_at: ", record$started_at),
    paste0("finished_at: ", format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")),
    paste0("userid: ", app$userid %||% ""),
    paste0("teacherid: ", app$teacherid %||% ""),
    paste0("semester: ", app$semester %||% ""),
    paste0("courseid: ", app$courseid %||% ""),
    paste0("tutorid: ", app$tutorid %||% state$tutor$tutorid %||% ""),
    paste0("instanceid: ", app$instanceid %||% ""),
    paste0("node: ", record$node),
    paste0("attempt: ", record$attempt),
    paste0("parallel_call: ", record$parallel_call),
    paste0("model: ", state$model %||% ""),
    paste0("status: ", if (nzchar(paste0(error)[1])) "error" else "completed")
  )
  sections = c(
    head,
    "",
    "===== SYSTEM PROMPT =====",
    paste0(system_prompt %||% "", collapse="\n"),
    "",
    "===== PROMPT =====",
    paste0(prompt %||% "", collapse="\n"),
    "",
    "===== ANSWER =====",
    paste0(answer %||% "", collapse="\n")
  )
  if (nzchar(paste0(thinking %||% "")[1])) {
    sections = c(
      sections, "", "===== THINKING =====",
      paste0(thinking, collapse="\n")
    )
  }
  if (nzchar(paste0(error %||% "")[1])) {
    sections = c(
      sections, "", "===== ERROR =====",
      paste0(error, collapse="\n")
    )
  }
  writeLines(sections, path, useBytes=TRUE)
  invisible(path)
}
