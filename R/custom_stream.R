ullme_custom_stream_supported = function(app=getApp(), task_profile="") {
  provider = paste0(app$api_config$provider %||% "")[1]
  identical(task_profile, "") &&
    provider %in% c("nvidia", "local") &&
    !isTRUE(app$enable_ai_tools)
}


ullme_custom_stream_system_prompt = function(context=list(),
                                             system_instructions=NULL,
                                             task_profile="",
                                             app=getApp()) {
  if (identical(app$role, "student")) return(NULL)
  if (!identical(app$role, "teacher")) {
    stop("The custom stream backend is only available for teacher/student chat.")
  }
  prompt = ullme_teacher_system_prompt(
    app=app,
    context=context,
    tool_names=character(0)
  )
  if (!is.null(system_instructions) && nzchar(system_instructions)) {
    prompt = paste(prompt, system_instructions, sep="\n\n")
  }
  prompt
}


ullme_custom_stream_messages = function(input, system_prompt=NULL) {
  messages = list()
  if (!is.null(system_prompt) && nzchar(system_prompt)) {
    messages[[length(messages) + 1L]] = list(
      role="system",
      content=system_prompt
    )
  }
  messages[[length(messages) + 1L]] = list(
    role="user",
    content=paste0(input, collapse="\n")
  )
  messages
}


ullme_custom_stream_body = function(input, model, context=list(),
                                    system_instructions=NULL,
                                    task_profile="",
                                    app=getApp()) {
  system_prompt = ullme_custom_stream_system_prompt(
    context=context,
    system_instructions=system_instructions,
    task_profile=task_profile,
    app=app
  )
  profile = if (identical(app$api_config$provider, "nvidia")) {
    ullme_nvidia_chat_profile(model, task_profile=task_profile)
  } else {
    list(max_tokens=16384, api_args=list())
  }
  body = c(
    list(
      model=model,
      messages=ullme_custom_stream_messages(
        input,
        system_prompt=system_prompt
      ),
      temperature=1,
      top_p=0.95,
      max_tokens=profile$max_tokens,
      stream=TRUE
    ),
    profile$api_args
  )
  body
}


ullme_custom_stream_headers = function(config) {
  headers = c(
    "Content-Type"="application/json",
    "Accept"="text/event-stream"
  )
  key = if (is.null(config$credentials)) "" else config$credentials()
  if (nzchar(key)) {
    headers = c(headers, "Authorization"=paste("Bearer", key))
  }
  headers
}


ullme_custom_stream_extract_delta = function(event) {
  choices = event$choices %||% list()
  if (!length(choices)) return(list(text="", thinking=""))
  choice = choices[[1]]
  delta = choice$delta %||% choice$message %||% list()
  text = paste0(
    delta$content %||%
      delta$text %||%
      choice$text %||%
      "",
    collapse=""
  )
  thinking = paste0(
    delta$reasoning_content %||%
      delta$thinking %||%
      "",
    collapse=""
  )
  list(text=text, thinking=thinking)
}


ullme_custom_stream_process_event = function(payload, state, on_update,
                                             include_thinking=FALSE,
                                             app=getApp()) {
  payload = trimws(payload)
  if (!nzchar(payload)) return(invisible(FALSE))
  if (identical(payload, "[DONE]")) {
    state$seen_done = TRUE
    return(invisible(TRUE))
  }
  event = tryCatch(
    jsonlite::fromJSON(payload, simplifyVector=FALSE),
    error=function(e) {
      state$parse_errors = c(state$parse_errors, conditionMessage(e))
      NULL
    }
  )
  if (is.null(event)) return(invisible(FALSE))
  delta = ullme_custom_stream_extract_delta(event)
  changed = FALSE
  if (nzchar(delta$text)) {
    state$text = paste0(state$text, delta$text)
    changed = TRUE
  }
  if (nzchar(delta$thinking) && isTRUE(include_thinking)) {
    state$thinking = paste0(state$thinking, delta$thinking)
    changed = TRUE
  }
  if (!changed) return(invisible(FALSE))
  now = as.numeric(Sys.time())
  response_size = nchar(state$text, type="bytes") +
    nchar(state$thinking, type="bytes")
  update_interval = if (response_size < 4000) {
    0.08
  } else if (response_size < 12000) {
    0.14
  } else {
    0.25
  }
  if (now - state$last_update >= update_interval) {
    on_update(state$text, state$thinking, FALSE)
    state$last_update = now
  }
  invisible(TRUE)
}


ullme_custom_stream_process_buffer = function(state, on_update,
                                              include_thinking=FALSE,
                                              app=getApp()) {
  if (!grepl("\n", state$buffer, fixed=TRUE)) return(invisible(FALSE))
  lines = strsplit(state$buffer, "\n", fixed=TRUE)[[1]]
  complete = grepl("\n$", state$buffer)
  if (complete) {
    state$buffer = ""
  } else {
    state$buffer = lines[[length(lines)]]
    lines = lines[-length(lines)]
  }
  data_lines = character(0)
  flush_event = function() {
    if (!length(data_lines)) return(invisible(FALSE))
    payload = paste(data_lines, collapse="\n")
    data_lines <<- character(0)
    ullme_custom_stream_process_event(
      payload,
      state=state,
      on_update=on_update,
      include_thinking=include_thinking,
      app=app
    )
  }
  for (line in lines) {
    line = sub("\r$", "", line)
    if (!nzchar(line)) {
      flush_event()
    } else if (startsWith(line, "data:")) {
      data_lines = c(data_lines, sub("^data:[ ]?", "", line))
    }
  }
  flush_event()
  invisible(TRUE)
}


ullme_start_custom_ai_stream = function(input, model=NULL, context=list(),
                                        system_instructions=NULL,
                                        include_thinking=FALSE,
                                        task_profile="",
                                        on_update=function(...) NULL,
                                        on_event=function(...) NULL,
                                        app=getApp()) {
  if (!requireNamespace("curl", quietly=TRUE)) {
    stop("The custom stream backend requires the curl package.")
  }
  if (!requireNamespace("jsonlite", quietly=TRUE)) {
    stop("The custom stream backend requires the jsonlite package.")
  }
  if (!ullme_custom_stream_supported(app=app, task_profile=task_profile)) {
    stop(
      "The custom stream backend currently supports only ordinary ",
      "OpenAI-compatible chat without AI tools."
    )
  }
  model = ullme_model_id(model, app=app)
  ullme_chat_debug(
    app,
    "start_custom_ai_stream begin role=", app$role %||% "",
    " task_profile=", task_profile,
    " model=", model,
    " input_bytes=", nchar(paste0(input, collapse="\n"), type="bytes")
  )
  state = new.env(parent=emptyenv())
  state$text = ""
  state$thinking = ""
  state$buffer = ""
  state$raw = ""
  state$last_update = 0
  state$seen_done = FALSE
  state$parse_errors = character(0)
  state$chunk_count = 0L
  state$active = TRUE
  state$settled = FALSE

  config = app$api_config
  url = paste0(sub("/+$", "", config$base_url), "/chat/completions")
  body = ullme_custom_stream_body(
    input=input,
    model=model,
    context=context,
    system_instructions=system_instructions,
    task_profile=task_profile,
    app=app
  )
  body_json = jsonlite::toJSON(
    body,
    auto_unbox=TRUE,
    null="null",
    digits=NA
  )
  handle = curl::new_handle(url=url)
  curl::handle_setopt(
    handle,
    customrequest="POST",
    postfields=body_json,
    connecttimeout=app$chat_connect_timeout_seconds %||% 60,
    timeout=app$chat_timeout_seconds %||% 180
  )
  curl::handle_setheaders(
    handle,
    .list=ullme_custom_stream_headers(config)
  )
  pool = curl::new_pool(total_con=1, host_con=1, max_streams=1)
  reject_promise = NULL

  controller = list()
  controller$cancel = function(reason="Request cancelled") {
    if (isTRUE(state$settled)) return(invisible(FALSE))
    state$active = FALSE
    state$settled = TRUE
    try(curl::multi_cancel(handle), silent=TRUE)
    if (!is.null(reject_promise)) {
      reject_promise(simpleError(paste0(reason %||% "Request cancelled")))
    }
    invisible(TRUE)
  }

  promise = promises::promise(function(resolve, reject) {
    reject_promise <<- reject
    settle_ok = function(value) {
      if (isTRUE(state$settled)) return(invisible(NULL))
      state$settled = TRUE
      state$active = FALSE
      resolve(value)
      invisible(NULL)
    }
    settle_error = function(message) {
      if (isTRUE(state$settled)) return(invisible(NULL))
      state$settled = TRUE
      state$active = FALSE
      reject(simpleError(message))
      invisible(NULL)
    }
    data_callback = function(data, final=FALSE) {
      if (!isTRUE(state$active)) return(invisible(NULL))
      if (length(data)) {
        state$chunk_count = state$chunk_count + 1L
        text = rawToChar(data)
        state$raw = paste0(state$raw, text)
        state$buffer = paste0(state$buffer, text)
        ullme_chat_debug(
          app,
          "custom stream chunk #", state$chunk_count,
          " bytes=", length(data)
        )
        ullme_custom_stream_process_buffer(
          state,
          on_update=on_update,
          include_thinking=include_thinking,
          app=app
        )
      }
      invisible(NULL)
    }
    done_callback = function(response) {
      status = suppressWarnings(as.integer(response$status %||% 0L))
      ullme_chat_debug(
        app,
        "custom stream done status=", status,
        " chunks=", state$chunk_count,
        " text_bytes=", nchar(state$text, type="bytes")
      )
      if (status >= 300L || status < 200L) {
        message = paste0(
          "Custom stream request failed with HTTP status ",
          status,
          "."
        )
        if (nzchar(state$raw)) {
          message = paste(message, substr(state$raw, 1L, 1000L))
        }
        settle_error(message)
        return(invisible(NULL))
      }
      if (nzchar(state$buffer)) {
        state$buffer = paste0(state$buffer, "\n")
        ullme_custom_stream_process_buffer(
          state,
          on_update=on_update,
          include_thinking=include_thinking,
          app=app
        )
      }
      on_update(state$text, state$thinking, TRUE)
      settle_ok(list(text=state$text, thinking=state$thinking))
      invisible(NULL)
    }
    fail_callback = function(message) {
      ullme_chat_debug(app, "custom stream failed message=", message)
      settle_error(paste0(message)[1])
    }
    curl::multi_add(
      handle,
      done=done_callback,
      fail=fail_callback,
      data=data_callback,
      pool=pool
    )
    pump = NULL
    pump = function() {
      if (!isTRUE(state$active) || isTRUE(state$settled)) {
        return(invisible(NULL))
      }
      tryCatch(
        curl::multi_run(timeout=0, pool=pool),
        error=function(e) settle_error(conditionMessage(e))
      )
      if (isTRUE(state$active) && !isTRUE(state$settled)) {
        later::later(pump, delay=0.02)
      }
      invisible(NULL)
    }
    later::later(pump, delay=0)
  })
  ullme_chat_debug(app, "start_custom_ai_stream after schedule")
  list(
    promise=promise,
    state=state,
    controller=controller,
    chat=NULL,
    usage_start=ullme_chat_usage_snapshot(NULL)
  )
}
