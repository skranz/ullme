ullme_chat_debug = function(app=NULL, ...) {
  if (is.null(app) || !isTRUE(app$chat_debug)) return(invisible(FALSE))
  tryCatch({
    cat(
      format(Sys.time(), "%Y-%m-%d %H:%M:%OS3"),
      " ullme chat debug: ",
      paste0(..., collapse=""),
      "\n",
      sep="",
      file=stderr()
    )
    flush.console()
  }, error=function(e) NULL)
  invisible(TRUE)
}


ullme_chat_key = function(model, task_profile="", app=getApp()) {
  restore.point("ullme_chat_key")
  paste(
    app$api_config$provider,
    model,
    task_profile,
    app$userid %||% "",
    app$semester %||% "",
    app$courseid %||% "",
    app$tutorid %||% "",
    app$instanceid %||% "",
    if (isTRUE(app$enable_ai_tools)) "tools" else "no_tools",
    sep="|"
  )
}


ullme_ai_connection_status = function(model=NULL, waiting=FALSE,
                                       app=getApp()) {
  restore.point("ullme_ai_connection_status")
  config = app$api_config
  model = paste0(model %||% config$model %||% "configured model")[1]
  provider = switch(
    paste0(config$provider %||% "")[1],
    nvidia="NVIDIA NIM",
    local="the local model server",
    fake="the test model",
    paste0(config$provider %||% "the model provider")[1]
  )
  base_url = sub("^https?://", "", paste0(config$base_url %||% "")[1])
  host = sub("/.*$", "", base_url)
  destination = paste0(
    provider,
    if (nzchar(host)) paste0(" at ", host) else ""
  )
  if (isTRUE(waiting)) {
    return(paste0(
      "Still waiting for ", model, " through ", destination,
      ". No model output has arrived yet."
    ))
  }
  paste0(
    "Trying to connect to ", model, " through ", destination, "… ",
    "If no model output arrives within ",
    format(app$chat_connect_timeout_seconds %||% 60, trim=TRUE),
    " seconds, this request will stop."
  )
}


ullme_await_promise = function(promise, seconds=180,
                                on_timeout=function() NULL) {
  seconds = suppressWarnings(as.numeric(seconds)[1])
  if (is.na(seconds) || seconds <= 0) stop("seconds must be positive.")
  settled = FALSE
  value = NULL
  error = NULL
  promises::then(
    promise,
    onFulfilled=function(result) {
      value <<- result
      settled <<- TRUE
      NULL
    },
    onRejected=function(condition) {
      error <<- condition
      settled <<- TRUE
      NULL
    }
  )
  deadline = as.numeric(Sys.time()) + seconds
  while (!settled && as.numeric(Sys.time()) < deadline) {
    remaining = deadline - as.numeric(Sys.time())
    later::run_now(timeoutSecs=max(0, min(0.1, remaining)), all=TRUE)
  }
  if (!settled) {
    try(on_timeout(), silent=TRUE)
    stop(paste0(
      "The model request timed out after ",
      format(seconds, trim=TRUE),
      " seconds."
    ))
  }
  if (!is.null(error)) stop(error)
  value
}


ullme_promise_timeout = function(promise, seconds=180,
                                  is_paused=function() FALSE) {
  seconds = suppressWarnings(as.numeric(seconds)[1])
  if (is.na(seconds) || seconds <= 0) return(promise)
  promises::promise(function(resolve, reject) {
    settled = FALSE
    remaining = seconds
    last_check = as.numeric(Sys.time())
    check_timeout = NULL
    check_timeout = function() {
      if (settled) return(invisible(NULL))
      now = as.numeric(Sys.time())
      paused = tryCatch(isTRUE(is_paused()), error=function(e) FALSE)
      if (!paused) remaining <<- remaining - max(0, now - last_check)
      last_check <<- now
      if (remaining <= 0) {
        settled <<- TRUE
        reject(simpleError(paste0(
          "The model request timed out after ",
          format(seconds, trim=TRUE),
          " active seconds."
        )))
        return(invisible(NULL))
      }
      later::later(
        check_timeout,
        delay=max(0.05, min(1, remaining))
      )
      invisible(NULL)
    }
    later::later(check_timeout, delay=max(0.05, min(1, remaining)))
    promises::then(
      promise,
      onFulfilled=function(value) {
        if (settled) return(invisible(NULL))
        settled <<- TRUE
        resolve(value)
        invisible(NULL)
      },
      onRejected=function(error) {
        if (settled) return(invisible(NULL))
        settled <<- TRUE
        reject(error)
        invisible(NULL)
      }
    )
  })
}


ullme_teacher_chat = function(model=NULL, system_prompt=NULL,
                               task_profile="", app=getApp()) {
  config = app$api_config
  model = ullme_model_id(model, app=app)
  key = ullme_chat_key(model, task_profile=task_profile, app=app)
  chat = app$teacher_chats[[key]]
  if (is.null(chat)) {
    chat = ullme_api_chat(
      config,
      model=model,
      system_prompt=system_prompt,
      task_profile=task_profile
    )
    if (!is.null(chat)) {
      if (isTRUE(app$enable_ai_tools)) {
        tools = ullme_tools(app=app)
        if (identical(task_profile, "instance_builder")) {
          tools = tools["write_rtutor_instances_yaml"]
        }
        chat$register_tools(tools)
        chat$on_tool_request(function(request) {
          ullme_handle_tool_lifecycle_event("request", request, app=app)
        })
        chat$on_tool_result(function(result) {
          ullme_handle_tool_lifecycle_event("result", result, app=app)
        })
      }
      app$teacher_chats[[key]] = chat
    }
  } else if (!is.null(system_prompt)) {
    chat$set_system_prompt(system_prompt)
  }
  chat
}


ullme_ask_ai = function(input, model=NULL, context=list(),
                         system_instructions=NULL, app=getApp()) {
  if (ullme_uses_fake_ai(app=app)) {
    return(paste0("Fake AI answer to:\n", input))
  }
  chat = ullme_ai_request_chat(
    model=model,
    context=context,
    system_instructions=system_instructions,
    app=app
  )
  chat$chat(input, echo="none")
}


ullme_ai_request_chat = function(model=NULL, context=list(),
                                  system_instructions=NULL,
                                  task_profile="",
                                  app=getApp()) {
  restore.point("ullme_ai_request_chat")
  if (identical(app$role, "student")) {
    chat = ullme_student_chat(model=model, app=app)
    if (is.null(chat)) stop("No model is configured.")
    return(chat)
  }
  if (!identical(app$role, "teacher")) {
    stop("The AI assistant is not available for this role.")
  }
  tool_names = if (!isTRUE(app$enable_ai_tools)) {
    character(0)
  } else if (identical(task_profile, "instance_builder")) {
    "write_rtutor_instances_yaml"
  } else {
    NULL
  }
  prompt = ullme_teacher_system_prompt(
    app=app,
    context=context,
    tool_names=tool_names
  )
  if (!is.null(system_instructions) && nzchar(system_instructions)) {
    prompt = paste(prompt, system_instructions, sep="\n\n")
  }
  chat = ullme_teacher_chat(
    model=model,
    system_prompt=prompt,
    task_profile=task_profile,
    app=app
  )
  if (is.null(chat)) stop("No model is configured.")
  chat
}


.ullme_stream_chunk_part = function(chunk) {
  if (is.character(chunk)) {
    return(list(type="text", value=paste0(chunk, collapse="")))
  }
  classes = tryCatch(class(chunk), error=function(e) character(0))
  if (any(grepl("ContentThinking", classes, fixed=TRUE))) {
    value = paste0(.ullme_content_property(chunk, "thinking", ""))[1]
    return(list(type="thinking", value=value))
  }
  if (any(grepl("ContentText", classes, fixed=TRUE))) {
    value = paste0(.ullme_content_property(chunk, "text", ""))[1]
    return(list(type="text", value=value))
  }
  if (any(grepl("ContentToolRequest", classes, fixed=TRUE))) {
    return(list(type="tool_request", value=chunk))
  }
  if (any(grepl("ContentToolResult", classes, fixed=TRUE))) {
    return(list(type="tool_result", value=chunk))
  }
  list(type="other", value="")
}


.ullme_content_property = function(content, name, default=NULL) {
  tryCatch(
    get("prop", envir=asNamespace("S7"))(content, name),
    error=function(e) {
      tryCatch(methods::slot(content, name), error=function(e) default)
    }
  )
}


ullme_tool_request_record = function(content) {
  list(
    call_id=paste0(.ullme_content_property(content, "id", ""))[1],
    tool=paste0(.ullme_content_property(content, "name", "unknown_tool"))[1],
    arguments=ullme_tool_trace_value(
      .ullme_content_property(content, "arguments", list())
    )
  )
}


ullme_tool_result_record = function(content) {
  request = .ullme_content_property(content, "request", NULL)
  error = .ullme_content_property(content, "error", NULL)
  value = .ullme_content_property(content, "value", NULL)
  if (inherits(error, "condition")) error = conditionMessage(error)
  value_status = if (is.list(value)) paste0(value$status %||% "")[1] else ""
  status = if (!is.null(error)) {
    "error"
  } else if (value_status %in% c(
    "error", "rejected", "denied", "cancelled", "failed"
  )) {
    value_status
  } else {
    "completed"
  }
  list(
    call_id=if (is.null(request)) "" else
      paste0(.ullme_content_property(request, "id", ""))[1],
    tool=if (is.null(request)) "unknown_tool" else
      paste0(.ullme_content_property(request, "name", "unknown_tool"))[1],
    status=status,
    error=if (is.null(error)) "" else paste0(error)[1],
    value=ullme_tool_trace_value(value)
  )
}


ullme_request_stream_state = function(request) {
  restore.point("ullme_request_stream_state")
  list(
    text=if (is.null(request$state)) "" else request$state$text %||% "",
    thinking=if (is.null(request$state)) "" else
      request$state$thinking %||% ""
  )
}


ullme_send_tool_activity = function(request, activity="",
                                     waiting_for_approval=FALSE,
                                     app=getApp()) {
  restore.point("ullme_send_tool_activity")
  if (is.null(request) || !isTRUE(request$active)) return(invisible(FALSE))
  state = ullme_request_stream_state(request)
  ullme_send_chat_stream_update(
    message_id=request$message_id,
    text=state$text,
    thinking=state$thinking,
    done=FALSE,
    activity=activity,
    waiting_for_user=isTRUE(waiting_for_approval),
    app=app
  )
  invisible(TRUE)
}


ullme_handle_tool_lifecycle_event = function(kind, content, app=getApp()) {
  tryCatch({
    request = app$active_chat_request
    if (is.null(request) || !isTRUE(request$active)) return(invisible(NULL))
    request$received_provider_output = TRUE
    record = if (identical(kind, "request")) {
      ullme_tool_request_record(content)
    } else {
      ullme_tool_result_record(content)
    }
    record$event = kind
    record$at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
    ullme_ai_interaction_tool_event(
      request$interaction_dir,
      record,
      request=request
    )
    tool_label = gsub("_", " ", record$tool, fixed=TRUE)
    activity = if (identical(kind, "request")) {
      paste0("Running ", tool_label, "\u2026")
    } else if (!identical(record$status %||% "", "completed")) {
      paste0("The ", tool_label, " tool failed. Continuing\u2026")
    } else {
      paste0("Finished ", tool_label, ". Continuing\u2026")
    }
    ullme_send_tool_activity(request, activity=activity, app=app)
    invisible(NULL)
  }, error=function(e) {
    warning("Could not record tool lifecycle event: ", conditionMessage(e))
    invisible(NULL)
  })
}


ullme_set_request_approval_wait = function(request, waiting, operation_id="",
                                            app=getApp()) {
  restore.point("ullme_set_request_approval_wait")
  if (is.null(request)) return(invisible(FALSE))
  request$waiting_for_approval = isTRUE(waiting)
  if (!isTRUE(request$active)) return(invisible(FALSE))
  activity = if (isTRUE(waiting)) {
    "Waiting for your approval\u2026"
  } else {
    "Approval decision received. Continuing\u2026"
  }
  ullme_ai_interaction_tool_event(
    request$interaction_dir,
    list(
      event=if (isTRUE(waiting)) "approval_wait" else "approval_resolved",
      operation_id=paste0(operation_id)[1],
      at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
    ),
    request=request
  )
  ullme_send_tool_activity(
    request,
    activity=activity,
    waiting_for_approval=isTRUE(waiting),
    app=app
  )
}


ullme_start_ai_stream = function(input, model=NULL, context=list(),
                                  system_instructions=NULL,
                                  include_thinking=FALSE,
                                  task_profile="",
                                  on_update=function(...) NULL,
                                  on_event=function(...) NULL,
                                  app=getApp()) {
  ullme_chat_debug(
    app,
    "start_ai_stream begin role=", app$role %||% "",
    " task_profile=", task_profile,
    " model=", paste0(model %||% app$api_config$model %||% "")[1],
    " input_bytes=", nchar(paste0(input, collapse="\n"), type="bytes")
  )
  chat = ullme_ai_request_chat(
    model=model,
    context=context,
    system_instructions=system_instructions,
    task_profile=task_profile,
    app=app
  )
  ullme_chat_debug(app, "start_ai_stream chat ready")
  usage_start = ullme_chat_usage_snapshot(NULL)
  controller = ellmer::stream_controller()
  stream_mode = if (identical(task_profile, "instance_builder")) {
    "content"
  } else {
    "text"
  }
  ullme_chat_debug(app, "start_ai_stream controller ready")
  stream_args = list(
    input,
    stream=stream_mode,
    controller=controller
  )
  if (identical(app$role, "teacher") && isTRUE(app$enable_ai_tools)) {
    stream_args$tool_mode = "sequential"
  }
  ullme_chat_debug(
    app,
    "start_ai_stream before stream_async tool_mode=",
    paste0(stream_args$tool_mode %||% "default")[1],
    " stream=", stream_mode
  )
  stream = do.call(chat$stream_async, stream_args)
  ullme_chat_debug(app, "start_ai_stream after stream_async")
  state = new.env(parent=emptyenv())
  state$text = ""
  state$thinking = ""
  state$last_update = 0
  state$chunk_count = 0L
  await_each = coro::await_each
  runner = coro::async(function() {
    ullme_chat_debug(app, "stream runner begin")
    tryCatch({
      for (chunk in await_each(stream)) {
        state$chunk_count = state$chunk_count + 1L
        chunk_class = tryCatch(
          paste(class(chunk), collapse="/"),
          error=function(e) "<class error>"
        )
        ullme_chat_debug(
          app,
          "stream chunk begin #", state$chunk_count,
          " class=", chunk_class
        )
        part = .ullme_stream_chunk_part(chunk)
        value_bytes = NA_integer_
        if (is.character(part$value)) {
          value_bytes = nchar(part$value, type="bytes")
        }
        ullme_chat_debug(
          app,
          "stream chunk part #", state$chunk_count,
          " type=", part$type,
          " value_bytes=", paste0(value_bytes)[1]
        )
        if (identical(part$type, "text")) {
          state$text = paste0(state$text, part$value)
        } else if (identical(part$type, "thinking") &&
                   isTRUE(include_thinking)) {
          state$thinking = paste0(state$thinking, part$value)
        } else if (part$type %in% c("tool_request", "tool_result")) {
          ullme_chat_debug(
            app,
            "stream event begin #", state$chunk_count,
            " type=", part$type
          )
          on_event(part$type, part$value)
          ullme_chat_debug(
            app,
            "stream event end #", state$chunk_count,
            " type=", part$type
          )
        }
        now = as.numeric(Sys.time())
        changed = part$type %in% c("text", "thinking") &&
          nzchar(part$value) &&
          (!identical(part$type, "thinking") || isTRUE(include_thinking))
        response_size = nchar(state$text, type="bytes") +
          nchar(state$thinking, type="bytes")
        if (response_size < 4000) {
          update_interval = 0.08
        } else if (response_size < 12000) {
          update_interval = 0.14
        } else {
          update_interval = 0.25
        }
        if (changed && now - state$last_update >= update_interval) {
          ullme_chat_debug(
            app,
            "stream on_update begin #", state$chunk_count,
            " text_bytes=", nchar(state$text, type="bytes"),
            " thinking_bytes=", nchar(state$thinking, type="bytes")
          )
          on_update(state$text, state$thinking, FALSE)
          ullme_chat_debug(
            app,
            "stream on_update end #", state$chunk_count
          )
          state$last_update = now
        }
      }
      ullme_chat_debug(
        app,
        "stream final on_update begin chunks=", state$chunk_count,
        " text_bytes=", nchar(state$text, type="bytes"),
        " thinking_bytes=", nchar(state$thinking, type="bytes")
      )
      on_update(state$text, state$thinking, TRUE)
      ullme_chat_debug(app, "stream final on_update end")
      list(text=state$text, thinking=state$thinking)
    }, error=function(e) {
      ullme_chat_debug(
        app,
        "stream runner error chunks=", state$chunk_count,
        " message=", conditionMessage(e)
      )
      stop(e)
    })
  })
  ullme_chat_debug(app, "start_ai_stream before runner")
  promise = runner()
  ullme_chat_debug(app, "start_ai_stream after runner")
  list(
    promise=promise,
    state=state,
    controller=controller,
    chat=chat,
    usage_start=usage_start
  )
}


ullme_start_ai_chat = function(input, model=NULL, context=list(),
                                system_instructions=NULL,
                                task_profile="",
                                app=getApp()) {
  chat = ullme_ai_request_chat(
    model=model,
    context=context,
    system_instructions=system_instructions,
    task_profile=task_profile,
    app=app
  )
  usage_start = ullme_chat_usage_snapshot(NULL)
  chat_args = list(input)
  if (identical(app$role, "teacher") && isTRUE(app$enable_ai_tools)) {
    chat_args$tool_mode = "sequential"
  }
  list(
    promise=do.call(chat$chat_async, chat_args),
    chat=chat,
    usage_start=usage_start
  )
}


ullme_start_ai_chat_sync = function(input, model=NULL, context=list(),
                                    system_instructions=NULL,
                                    task_profile="",
                                    app=getApp()) {
  ullme_chat_debug(
    app,
    "start_ai_chat_sync begin role=", app$role %||% "",
    " task_profile=", task_profile,
    " model=", paste0(model %||% app$api_config$model %||% "")[1],
    " input_bytes=", nchar(paste0(input, collapse="\n"), type="bytes")
  )
  chat = ullme_ai_request_chat(
    model=model,
    context=context,
    system_instructions=system_instructions,
    task_profile=task_profile,
    app=app
  )
  ullme_chat_debug(app, "start_ai_chat_sync chat ready")
  usage_start = ullme_chat_usage_snapshot(NULL)
  chat_args = list(input, echo="none")
  if (identical(app$role, "teacher") && isTRUE(app$enable_ai_tools)) {
    chat_args$tool_mode = "sequential"
  }
  ullme_chat_debug(
    app,
    "start_ai_chat_sync before chat tool_mode=",
    paste0(chat_args$tool_mode %||% "default")[1]
  )
  answer = do.call(chat$chat, chat_args)
  ullme_chat_debug(
    app,
    "start_ai_chat_sync after chat answer_bytes=",
    nchar(paste0(answer, collapse=""), type="bytes")
  )
  list(
    answer=answer,
    chat=chat,
    usage_start=usage_start
  )
}


ullme_chat_last_thinking = function(chat) {
  turn = tryCatch(chat$last_turn(), error=function(e) NULL)
  contents = tryCatch(turn@contents, error=function(e) list())
  thinking = vapply(contents, function(content) {
    if (!any(grepl("ContentThinking", class(content), fixed=TRUE))) return("")
    tryCatch(paste0(content@thinking)[1], error=function(e) "")
  }, character(1))
  paste0(thinking[nzchar(thinking)], collapse="")
}


ullme_task_chat = function(system_prompt, model=NULL, app=getApp()) {
  config = app$api_config
  model = ullme_model_id(model, app=app)
  ullme_api_chat(config, model=model, system_prompt=system_prompt)
}
