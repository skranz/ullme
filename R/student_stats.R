ullme_student_session_id = function(root=NULL) {
  alphabet = c(LETTERS, letters, as.character(0:9))
  for (attempt in seq_len(100L)) {
    id = paste0(sample(alphabet, 16L, replace=TRUE), collapse="")
    if (is.null(root) || !file.exists(file.path(root, paste0(id, ".csv")))) {
      return(id)
    }
  }
  stop("Could not create a unique anonymous student session ID.")
}


ullme_student_session_stats_dir = function(app=getApp()) {
  file.path(app$glob$main_dir, "session_stats")
}


ullme_student_session_stats_columns = function() {
  c(
    "date", "teacherid", "courseid", "tutorid", "model",
    "input_token", "output_token", "thinking_token",
    "ttf_ms", "total_sec", "error"
  )
}


ullme_student_session_stats_init = function(app=getApp()) {
  if (!identical(app$role, "student")) return(invisible(NULL))
  root = ullme_student_session_stats_dir(app=app)
  dir.create(root, recursive=TRUE, showWarnings=FALSE)
  if (!dir.exists(root)) stop("Could not create the session statistics directory.")
  app$anonymous_chatid = ullme_student_session_id(root=root)
  app$session_stats_path = file.path(
    root,
    paste0(app$anonymous_chatid, ".csv")
  )
  writeLines(
    paste(ullme_student_session_stats_columns(), collapse=","),
    app$session_stats_path,
    useBytes=TRUE
  )
  invisible(app$anonymous_chatid)
}


ullme_nested_value = function(value, path) {
  for (name in path) {
    if (!is.list(value) || is.null(value[[name]])) return(NULL)
    value = value[[name]]
  }
  value
}


ullme_assistant_turn_reasoning_tokens = function(turn) {
  json = tryCatch(turn@json, error=function(e) NULL)
  if (!is.list(json)) return(NA_real_)
  paths = list(
    c("usage", "completion_tokens_details", "reasoning_tokens"),
    c("usage", "output_tokens_details", "reasoning_tokens"),
    c("usage", "thinking_tokens"),
    c("usage", "reasoning_tokens")
  )
  for (path in paths) {
    value = suppressWarnings(as.numeric(ullme_nested_value(json, path))[1])
    if (!is.na(value)) return(value)
  }
  NA_real_
}


ullme_chat_usage_snapshot = function(chat) {
  if (is.null(chat)) {
    return(list(
      input=NA_real_,
      output=NA_real_,
      thinking=NA_real_
    ))
  }
  tokens = tryCatch(chat$get_tokens(), error=function(e) NULL)
  input = output = NA_real_
  if (is.data.frame(tokens)) {
    token_sum = function(name) {
      if (!name %in% names(tokens)) return(NA_real_)
      if (!NROW(tokens)) return(0)
      values = suppressWarnings(as.numeric(tokens[[name]]))
      if (!length(values) || all(is.na(values))) return(NA_real_)
      sum(values, na.rm=TRUE)
    }
    input = token_sum("input")
    output = token_sum("output")
  }
  turns = tryCatch(chat$get_turns(), error=function(e) list())
  assistant_turns = Filter(function(turn) {
    any(grepl("Assistant", class(turn), fixed=TRUE))
  }, turns)
  reasoning = vapply(
    assistant_turns,
    ullme_assistant_turn_reasoning_tokens,
    numeric(1)
  )
  thinking = if (!length(assistant_turns)) {
    0
  } else if (all(is.na(reasoning))) {
    NA_real_
  } else {
    sum(reasoning, na.rm=TRUE)
  }
  list(input=input, output=output, thinking=thinking)
}


ullme_usage_difference = function(final, initial, field) {
  final_value = suppressWarnings(as.numeric(final[[field]])[1])
  initial_value = suppressWarnings(as.numeric(initial[[field]])[1])
  if (is.na(final_value) || is.na(initial_value)) return(NA_real_)
  max(0, final_value - initial_value)
}


ullme_student_stats_request = function(model, app=getApp()) {
  request = new.env(parent=emptyenv())
  request$model = paste0(model %||% app$api_config$model %||% "")[1]
  request$stats_path = app$session_stats_path %||% NULL
  request$teacherid = app$teacherid %||% ""
  request$courseid = app$courseid %||% ""
  request$tutorid = app$tutorid %||% ""
  request$started_at = as.numeric(Sys.time())
  request$first_output_at = NA_real_
  request$last_output_at = NA_real_
  request$chat = NULL
  request$usage_start = ullme_chat_usage_snapshot(NULL)
  request$stats_written = FALSE
  request
}


ullme_student_stats_attach_chat = function(request, chat,
                                            usage_start=NULL) {
  if (is.null(request)) return(invisible(FALSE))
  request$chat = chat
  request$usage_start = usage_start %||%
    ullme_chat_usage_snapshot(chat)
  invisible(TRUE)
}


ullme_student_stats_mark_output = function(request, at=Sys.time()) {
  if (is.null(request)) return(invisible(FALSE))
  now = suppressWarnings(as.numeric(at)[1])
  if (is.na(now)) return(invisible(FALSE))
  if (is.na(request$first_output_at)) request$first_output_at = now
  request$last_output_at = now
  invisible(TRUE)
}


ullme_student_stats_append = function(request, reply="", error_code="",
                                       app=getApp()) {
  if (!identical(app$role, "student") ||
      is.null(request) ||
      isTRUE(request$stats_written)) {
    return(invisible(FALSE))
  }
  request$stats_written = TRUE
  stats_path = request$stats_path %||% NULL
  if (is.null(stats_path) || !file.exists(stats_path)) {
    return(invisible(FALSE))
  }
  has_reply = nzchar(trimws(paste0(reply %||% "", collapse="\n")))
  if (has_reply) error_code = ""
  if (!has_reply && !nzchar(paste0(error_code %||% "")[1])) {
    error_code = "no_reply"
  }
  final_usage = ullme_chat_usage_snapshot(request$chat)
  ttf_ms = if (is.na(request$first_output_at)) {
    NA_real_
  } else {
    round(max(0, request$first_output_at - request$started_at) * 1000)
  }
  total_sec = if (is.na(request$last_output_at)) {
    NA_real_
  } else {
    round(max(0, request$last_output_at - request$started_at), 3)
  }
  row = data.frame(
    date=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z"),
    teacherid=request$teacherid %||% "",
    courseid=request$courseid %||% "",
    tutorid=request$tutorid %||% "",
    model=request$model %||% "",
    input_token=ullme_usage_difference(
      final_usage, request$usage_start, "input"
    ),
    output_token=ullme_usage_difference(
      final_usage, request$usage_start, "output"
    ),
    thinking_token=ullme_usage_difference(
      final_usage, request$usage_start, "thinking"
    ),
    ttf_ms=ttf_ms,
    total_sec=total_sec,
    error=paste0(error_code %||% "")[1],
    stringsAsFactors=FALSE
  )
  tryCatch({
    utils::write.table(
      row,
      file=stats_path,
      sep=",",
      row.names=FALSE,
      col.names=FALSE,
      append=TRUE,
      quote=TRUE,
      qmethod="double",
      na=""
    )
    TRUE
  }, error=function(e) FALSE)
}
