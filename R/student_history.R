ullme_student_chat_history_enabled = function(app=getApp()) {
  if (isTRUE(app$never_save_chats)) return(FALSE)
  tutor = ullme_student_selected_tutor(app=app)
  !is.null(tutor) && isTRUE(tutor$chat_history)
}


ullme_student_chat_history_root = function(app=getApp()) {
  if (!ullme_student_chat_history_enabled(app=app)) return(NULL)
  parts = c(
    app$teacherid %||% "teacher",
    app$semester %||% "semester",
    app$courseid %||% "course",
    app$tutorid %||% "tutor"
  )
  parts = gsub("[^A-Za-z0-9._-]+", "_", parts)
  do.call(
    file.path,
    as.list(c(app$role_user_dir, "chat_history", parts))
  )
}


ullme_student_chat_history_id = function() {
  id = paste0(
    format(Sys.time(), "%Y%m%d-%H%M%OS3"),
    "-", sprintf("%06d", sample.int(999999L, 1L))
  )
  gsub("[^0-9A-Za-z.-]+", "-", id)
}


ullme_student_chat_history_dir = function(chat_id, app=getApp()) {
  root = ullme_student_chat_history_root(app=app)
  if (is.null(root)) return(NULL)
  chat_id = paste0(chat_id %||% "")[1]
  if (!grepl("^[0-9A-Za-z][0-9A-Za-z.-]*$", chat_id)) {
    stop("Invalid chat history ID.")
  }
  file.path(root, chat_id)
}


ullme_student_chat_history_read = function(chat_id, app=getApp()) {
  directory = ullme_student_chat_history_dir(chat_id, app=app)
  if (is.null(directory) || !dir.exists(directory)) return(NULL)
  metadata = tryCatch(
    yaml::read_yaml(file.path(directory, "metadata.yml"), eval.expr=FALSE),
    error=function(e) list()
  )
  messages = tryCatch(
    yaml::read_yaml(file.path(directory, "messages.yml"), eval.expr=FALSE),
    error=function(e) list()
  )
  if (!is.list(messages)) messages = list()
  list(
    id=chat_id,
    started_at=paste0(metadata$started_at %||% "")[1],
    updated_at=paste0(metadata$updated_at %||% "")[1],
    messages=messages
  )
}


ullme_student_chat_history_list = function(app=getApp()) {
  root = ullme_student_chat_history_root(app=app)
  if (is.null(root) || !dir.exists(root)) return(list())
  directories = list.dirs(root, recursive=FALSE, full.names=TRUE)
  histories = lapply(basename(directories), function(chat_id) {
    history = ullme_student_chat_history_read(chat_id, app=app)
    if (is.null(history)) return(NULL)
    stamp = history$updated_at
    if (!nzchar(stamp)) stamp = history$started_at
    history$sort_time = stamp
    history$label = if (nzchar(history$started_at)) {
      parsed = suppressWarnings(as.POSIXct(
        history$started_at,
        format="%Y-%m-%dT%H:%M:%OS%z"
      ))
      if (is.na(parsed)) history$started_at else
        format(parsed, "%d.%m.%Y %H:%M")
    } else {
      chat_id
    }
    history$messages = NULL
    history
  })
  histories = Filter(Negate(is.null), histories)
  if (!length(histories)) return(list())
  histories[order(
    vapply(histories, function(item) item$sort_time, character(1)),
    decreasing=TRUE
  )]
}


ullme_student_chat_history_write = function(history, app=getApp()) {
  directory = ullme_student_chat_history_dir(history$id, app=app)
  if (is.null(directory)) return(invisible(FALSE))
  dir.create(directory, recursive=TRUE, showWarnings=FALSE)
  yaml::write_yaml(
    list(
      id=history$id,
      tutorid=app$tutorid,
      courseid=app$courseid,
      semester=app$semester,
      started_at=history$started_at,
      updated_at=history$updated_at
    ),
    file.path(directory, "metadata.yml")
  )
  yaml::write_yaml(
    history$messages %||% list(),
    file.path(directory, "messages.yml")
  )
  invisible(TRUE)
}


ullme_student_chat_history_new = function(app=getApp()) {
  if (!ullme_student_chat_history_enabled(app=app)) {
    app$student_chat_id = NULL
    app$student_history_messages = list()
    app$student_history_seed_messages = list()
    return(NULL)
  }
  now = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  history = list(
    id=ullme_student_chat_history_id(),
    started_at=now,
    updated_at=now,
    messages=list()
  )
  ullme_student_chat_history_write(history, app=app)
  app$student_chat_id = history$id
  app$student_history_messages = list()
  app$student_history_seed_messages = list()
  history
}


ullme_student_chat_history_select = function(chat_id=NULL, app=getApp()) {
  if (!ullme_student_chat_history_enabled(app=app)) return(NULL)
  history = if (is.null(chat_id) || !nzchar(paste0(chat_id)[1])) {
    NULL
  } else {
    ullme_student_chat_history_read(chat_id, app=app)
  }
  if (is.null(history)) return(ullme_student_chat_history_new(app=app))
  app$student_chat_id = history$id
  app$student_history_messages = history$messages %||% list()
  app$student_history_seed_messages = app$student_history_messages
  history
}


ullme_student_chat_history_delete = function(chat_id, app=getApp()) {
  if (!ullme_student_chat_history_enabled(app=app)) return(invisible(FALSE))
  directory = ullme_student_chat_history_dir(chat_id, app=app)
  root = ullme_student_chat_history_root(app=app)
  if (is.null(directory) || is.null(root) || !dir.exists(directory)) {
    return(invisible(FALSE))
  }
  directory = normalizePath(directory, winslash="/", mustWork=TRUE)
  root = normalizePath(root, winslash="/", mustWork=TRUE)
  if (!ullme_path_is_within(directory, root, allow_root=FALSE)) {
    stop("The selected chat history is outside the Tutor history directory.")
  }
  deleting_current = identical(chat_id, app$student_chat_id %||% "")
  if (deleting_current && isTRUE(app$chat_response_active)) {
    stop("Wait for the current response to finish before deleting this chat.")
  }
  ullme_remove_checked_directory(
    directory=directory,
    root=root,
    expected_name=basename(directory),
    label="chat history directory"
  )
  if (deleting_current) {
    model = ullme_model_id(NULL, app=app)
    key = ullme_chat_key(model, task_profile="student_tutor", app=app)
    app$teacher_chats[[key]] = NULL
    histories = ullme_student_chat_history_list(app=app)
    next_id = if (length(histories)) histories[[1]]$id else NULL
    ullme_student_chat_history_select(chat_id=next_id, app=app)
  }
  invisible(TRUE)
}


ullme_student_chat_history_init = function(app=getApp()) {
  app$student_chat_id = NULL
  app$student_history_messages = list()
  app$student_history_seed_messages = list()
  if (!ullme_student_chat_history_enabled(app=app)) return(invisible(NULL))
  histories = ullme_student_chat_history_list(app=app)
  chat_id = if (length(histories)) histories[[1]]$id else NULL
  ullme_student_chat_history_select(chat_id=chat_id, app=app)
  invisible(app$student_chat_id)
}


ullme_student_chat_history_append = function(role, text, message_id="",
                                              app=getApp()) {
  if (!ullme_student_chat_history_enabled(app=app)) return(invisible(FALSE))
  if (is.null(app$student_chat_id)) ullme_student_chat_history_new(app=app)
  role = paste0(role)[1]
  if (!role %in% c("user", "assistant")) stop("Invalid chat history role.")
  message_id = paste0(message_id %||% "")[1]
  messages = app$student_history_messages %||% list()
  if (nzchar(message_id)) {
    existing = vapply(messages, function(message) {
      identical(paste0(message$id %||% "")[1], message_id)
    }, logical(1))
    if (any(existing)) messages = messages[!existing]
  }
  messages[[length(messages) + 1L]] = list(
    id=message_id,
    role=role,
    text=paste0(text %||% "", collapse="\n"),
    created_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  )
  app$student_history_messages = messages
  current = ullme_student_chat_history_read(app$student_chat_id, app=app)
  if (is.null(current)) {
    now = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
    current = list(
      id=app$student_chat_id,
      started_at=now,
      updated_at=now
    )
  }
  current$updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  current$messages = messages
  ullme_student_chat_history_write(current, app=app)
}


ullme_student_chat_history_transcript = function(app=getApp()) {
  messages = app$student_history_seed_messages %||% list()
  if (!length(messages)) return("")
  lines = vapply(messages, function(message) {
    role = if (identical(message$role, "assistant")) "Tutor" else "Student"
    paste0(role, ":\n", paste0(message$text %||% "", collapse="\n"))
  }, character(1))
  paste(
    "Previous messages in this conversation:",
    paste(lines, collapse="\n\n"),
    sep="\n\n"
  )
}


ullme_student_chat_history_state = function(app=getApp()) {
  if (!ullme_student_chat_history_enabled(app=app)) {
    return(list(enabled=FALSE))
  }
  histories = ullme_student_chat_history_list(app=app)
  messages = lapply(app$student_history_messages %||% list(), function(message) {
    role = paste0(message$role %||% "")[1]
    text = paste0(message$text %||% "", collapse="\n")
    list(
      id=message$id %||% "",
      role=role,
      text=text,
      html=if (identical(role, "assistant")) {
        ullme_chat_output_html(text, app=app)
      } else {
        ""
      }
    )
  })
  compact = lapply(histories, function(history) {
    list(id=history$id, label=history$label)
  })
  list(
    enabled=TRUE,
    current_id=app$student_chat_id %||% "",
    recent=head(compact, 10L),
    older=if (length(compact) > 10L) compact[-seq_len(10L)] else list(),
    messages=messages
  )
}


ullme_send_student_chat_history = function(app=getApp()) {
  callJS(
    .fun="window.ullme.updateStudentChatHistory",
    .args=list(ullme_student_chat_history_state(app=app)),
    .app=app
  )
  invisible(TRUE)
}


ullme_handle_student_chat_history = function(chat_id=NULL, new_chat=FALSE,
                                              delete_chat_id=NULL,
                                              app=getApp(), ...) {
  if (!ullme_student_chat_history_enabled(app=app)) return(invisible(FALSE))
  delete_chat_id = paste0(delete_chat_id %||% "")[1]
  if (nzchar(delete_chat_id)) {
    deleting_current = identical(
      delete_chat_id,
      app$student_chat_id %||% ""
    )
    deleted = tryCatch(
      ullme_student_chat_history_delete(delete_chat_id, app=app),
      error=function(e) FALSE
    )
    if (isTRUE(deleted) && isTRUE(deleting_current)) {
      ullme_student_session_stats_init(app=app)
    }
    ullme_send_student_chat_history(app=app)
    return(invisible(isTRUE(deleted)))
  }
  model = ullme_model_id(NULL, app=app)
  key = ullme_chat_key(model, task_profile="student_tutor", app=app)
  app$teacher_chats[[key]] = NULL
  ullme_student_session_stats_init(app=app)
  if (isTRUE(new_chat)) {
    ullme_student_chat_history_new(app=app)
  } else {
    ullme_student_chat_history_select(chat_id=chat_id, app=app)
  }
  ullme_send_student_chat_history(app=app)
  invisible(TRUE)
}
