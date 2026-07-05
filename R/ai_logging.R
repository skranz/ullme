ullme_ai_interactions_dir = function(app=getApp()) {
  if (!isTRUE(app$store_ai_interactions)) return(NULL)
  if (identical(app$role, "student")) {
    if (isTRUE(app$never_save_chats)) return(NULL)
    parts = c(
      app$teacherid %||% "teacher",
      app$courseid %||% "course",
      app$tutorid %||% "tutor",
      app$instanceid %||% "instance"
    )
    parts = gsub("[^A-Za-z0-9._-]+", "_", parts)
    return(do.call(
      file.path,
      as.list(c(app$cur_session_dir, "ai_interactions", parts))
    ))
  }
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) return(NULL)
  file.path(course_dir, "ai_interactions")
}


ullme_ai_interaction_start = function(input, visible_text="", model="",
                                       kind="chat", app=getApp()) {
  root = ullme_ai_interactions_dir(app=app)
  if (is.null(root)) return(NULL)
  dir.create(root, recursive=TRUE, showWarnings=FALSE)
  id = paste0(
    format(Sys.time(), "%Y%m%d-%H%M%OS3"),
    "-", sprintf("%06d", sample.int(999999L, 1L))
  )
  id = gsub("[^0-9A-Za-z.-]+", "-", id)
  directory = file.path(root, id)
  dir.create(directory, recursive=FALSE, showWarnings=FALSE)
  writeLines(paste0(input), file.path(directory, "request.txt"), useBytes=TRUE)
  if (nzchar(paste0(visible_text)[1])) {
    writeLines(
      paste0(visible_text),
      file.path(directory, "visible-user-text.txt"),
      useBytes=TRUE
    )
  }
  yaml::write_yaml(list(
    id=id,
    kind=kind,
    model=paste0(model)[1],
    started_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  ), file.path(directory, "metadata.yaml"))
  directory
}


ullme_ai_interaction_finish = function(directory, status="completed",
                                        text="", thinking="", error="") {
  if (is.null(directory) || !dir.exists(directory)) return(invisible(FALSE))
  if (nzchar(paste0(text)[1])) {
    writeLines(paste0(text), file.path(directory, "response.txt"), useBytes=TRUE)
  }
  if (nzchar(paste0(thinking)[1])) {
    writeLines(paste0(thinking), file.path(directory, "thinking.txt"), useBytes=TRUE)
  }
  if (nzchar(paste0(error)[1])) {
    writeLines(paste0(error), file.path(directory, "error.txt"), useBytes=TRUE)
  }
  metadata_path = file.path(directory, "metadata.yaml")
  metadata = tryCatch(
    yaml::read_yaml(metadata_path, eval.expr=FALSE),
    error=function(e) list()
  )
  metadata$status = status
  metadata$finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  yaml::write_yaml(metadata, metadata_path)
  invisible(TRUE)
}


ullme_tool_trace_value = function(value, name="", max_chars=2000L) {
  if (grepl(
    "(api.?key|access.?token|secret|password|credential)",
    tolower(paste0(name)[1])
  )) {
    return("[redacted]")
  }
  if (is.null(value) || is.logical(value) || is.numeric(value)) return(value)
  if (inherits(value, "condition")) return(conditionMessage(value))
  if (is.character(value)) {
    value = paste0(value, collapse="\n")
    if (nchar(value, type="chars") > max_chars) {
      value = paste0(substr(value, 1L, max_chars), "\n[truncated]")
    }
    return(value)
  }
  if (is.list(value)) {
    result = lapply(seq_along(value), function(i) {
      item_name = names(value)[i] %||% ""
      ullme_tool_trace_value(value[[i]], name=item_name, max_chars=max_chars)
    })
    names(result) = names(value)
    return(result)
  }
  text = paste(capture.output(str(value, max.level=2)), collapse="\n")
  ullme_tool_trace_value(text, name=name, max_chars=max_chars)
}


ullme_ai_interaction_tool_event = function(directory, event, request=NULL) {
  if (is.null(directory) || !dir.exists(directory)) return(invisible(FALSE))
  events_dir = file.path(directory, "tool_events")
  dir.create(events_dir, recursive=TRUE, showWarnings=FALSE)
  if (!is.null(request)) {
    request$tool_event_seq = as.integer(request$tool_event_seq %||% 0L) + 1L
    index = request$tool_event_seq
  } else {
    existing = list.files(events_dir, pattern="^[0-9]{4}-.*[.]ya?ml$")
    index = length(existing) + 1L
  }
  kind = gsub("[^a-z0-9_-]+", "-", tolower(event$event %||% "event"))
  path = file.path(events_dir, sprintf("%04d-%s.yml", index, kind))
  yaml::write_yaml(ullme_tool_trace_value(event), path)
  invisible(path)
}
