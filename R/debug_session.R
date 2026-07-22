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
    app$debug_session_node_call_seq = list()
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
  app$debug_session_node_call_seq = list()
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
  node = paste0(node_id %||% "")[1]
  node_calls = app$debug_session_node_call_seq %||% list()
  node_call = as.integer(node_calls[[node]] %||% 0L) + 1L
  node_calls[[node]] = node_call
  app$debug_session_node_call_seq = node_calls
  list(
    index=app$debug_session_call_seq,
    node=node,
    node_call=node_call,
    attempt=as.integer(attempt)[1],
    parallel_call=as.integer(parallel_call)[1],
    started_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  )
}


ullme_debug_session_model_call_finish = function(record, state,
                                                  system_prompt, prompt,
                                                  answer="", thinking="",
                                                  error="", response=NULL) {
  if (is.null(record)) return(invisible(NULL))
  app = state$app
  directory = app$debug_session_dir
  if (is.null(directory) || !dir.exists(directory)) return(invisible(NULL))
  safe_node = gsub("[^A-Za-z0-9_-]+", "-", record$node)
  if (!nzchar(safe_node)) safe_node = "unknown-node"
  stem = sprintf(
    "%03d-%s-call-%03d",
    record$index, safe_node, as.integer(record$node_call %||% 1L)
  )
  path = file.path(directory, paste0(stem, ".txt"))
  json_path = file.path(directory, paste0(stem, ".json"))
  finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  status = if (nzchar(paste0(error)[1])) "error" else "completed"
  head = c(
    "ULLME STUDENT MODEL CALL",
    paste0("started_at: ", record$started_at),
    paste0("finished_at: ", finished_at),
    paste0("userid: ", app$userid %||% ""),
    paste0("teacherid: ", app$teacherid %||% ""),
    paste0("semester: ", app$semester %||% ""),
    paste0("courseid: ", app$courseid %||% ""),
    paste0("tutorid: ", app$tutorid %||% state$tutor$tutorid %||% ""),
    paste0("instanceid: ", app$instanceid %||% ""),
    paste0("node: ", record$node),
    paste0("node_call: ", record$node_call %||% 1L),
    paste0("attempt: ", record$attempt),
    paste0("parallel_call: ", record$parallel_call),
    paste0("model: ", state$model %||% ""),
    paste0("status: ", status)
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
  if (is.null(response)) {
    response = list(
      text=paste0(answer %||% "", collapse="\n"),
      thinking=paste0(thinking %||% "", collapse="\n")
    )
  }
  jsonlite::write_json(
    list(
      started_at=record$started_at,
      finished_at=finished_at,
      userid=app$userid %||% "",
      teacherid=app$teacherid %||% "",
      semester=app$semester %||% "",
      courseid=app$courseid %||% "",
      tutorid=app$tutorid %||% state$tutor$tutorid %||% "",
      instanceid=app$instanceid %||% "",
      node=record$node,
      node_call=record$node_call %||% 1L,
      attempt=record$attempt,
      parallel_call=record$parallel_call,
      model=state$model %||% "",
      status=status,
      response=response,
      error=if (nzchar(paste0(error)[1])) paste0(error)[1] else NULL
    ),
    json_path,
    auto_unbox=TRUE,
    null="null",
    pretty=TRUE,
    digits=NA
  )
  invisible(path)
}
