ullme_custom_stream_supported = function(app=getApp(), task_profile="") {
  provider = paste0(app$api_config$provider %||% "")[1]
  task_profile %in% c("", "instance_builder") &&
    provider %in% c("nvidia", "uulm_api")
}


ullme_custom_stream_system_prompt = function(context=list(),
                                             system_instructions=NULL,
                                             task_profile="",
                                             app=getApp()) {
  if (identical(app$role, "student")) {
    return(ullme_student_system_prompt(app=app))
  }
  if (!identical(app$role, "teacher")) {
    stop("The custom stream backend is only available for teacher/student chat.")
  }
  prompt = ullme_teacher_system_prompt(
    app=app,
    context=context,
    tool_names=ullme_custom_stream_tool_names(
      task_profile=task_profile,
      app=app
    )
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


ullme_custom_stream_upload_path = function(upload, app=getApp()) {
  id = paste0(upload$id %||% "")[1]
  if (!nzchar(id) || grepl("[^A-Za-z0-9._-]", id)) return(NULL)
  root = app$uploads_dir %||% ""
  if (!nzchar(root) || !dir.exists(root)) return(NULL)
  candidates = list.files(
    root,
    recursive=TRUE,
    full.names=TRUE,
    all.files=FALSE,
    no..=TRUE
  )
  if (!length(candidates)) return(NULL)
  candidates = candidates[
    file.exists(candidates) &
      !dir.exists(candidates) &
      startsWith(basename(candidates), paste0(id, "_"))
  ]
  if (!length(candidates)) return(NULL)
  size = suppressWarnings(as.numeric(upload$size %||% NA_real_)[1])
  if (!is.na(size)) {
    sizes = suppressWarnings(file.info(candidates)$size)
    matches = candidates[!is.na(sizes) & sizes == size]
    if (length(matches)) candidates = matches
  }
  normalizePath(candidates[[length(candidates)]], winslash="/", mustWork=FALSE)
}


ullme_custom_stream_image_mime = function(upload, path) {
  mime = paste0(upload$type %||% "")[1]
  if (grepl("^image/[A-Za-z0-9.+-]+$", mime)) return(mime)
  ext = tolower(tools::file_ext(path))
  switch(
    ext,
    jpg="image/jpeg",
    jpeg="image/jpeg",
    png="image/png",
    gif="image/gif",
    webp="image/webp",
    "image/png"
  )
}


ullme_custom_stream_clean_base64 = function(base64) {
  gsub("[[:space:]]", "", paste0(base64, collapse=""))
}


ullme_custom_stream_image_part_from_base64 = function(base64, mime,
                                                      app=getApp()) {
  url = paste0(
    "data:",
    mime,
    ";base64,",
    ullme_custom_stream_clean_base64(base64)
  )
  list(
    type="image_url",
    image_url=list(url=url)
  )
}


ullme_custom_stream_image_part = function(upload, app=getApp()) {
  path = ullme_custom_stream_upload_path(upload, app=app)
  if (is.null(path) || !file.exists(path) || dir.exists(path)) {
    ullme_chat_debug(
      app,
      "custom stream image using data_url id=",
      paste0(upload$id %||% "")[1],
      " data_url_bytes=",
      nchar(paste0(upload$data_url %||% "")[1], type="bytes")
    )
    return(ullme_custom_stream_data_url_image_part(upload, app=app))
  }
  size = suppressWarnings(file.info(path)$size)
  if (is.na(size) || size > 12 * 1024^2) {
    stop("Uploaded image is too large for the custom stream backend.")
  }
  mime = ullme_custom_stream_image_mime(upload, path)
  bytes = readBin(path, what="raw", n=size)
  ullme_chat_debug(
    app,
    "custom stream image using stored file id=",
    paste0(upload$id %||% "")[1],
    " bytes=", size,
    " mime=", mime
  )
  ullme_custom_stream_image_part_from_base64(
    jsonlite::base64_enc(bytes),
    mime,
    app=app
  )
}


ullme_custom_stream_data_url_image_part = function(upload, app=getApp()) {
  data_url = paste0(upload$data_url %||% "")[1]
  if (!nzchar(data_url)) return(NULL)
  if (!grepl(
    "^data:image/(png|jpeg|jpg|gif|webp);base64,",
    data_url,
    ignore.case=TRUE
  )) {
    return(NULL)
  }
  if (nchar(data_url, type="bytes") > 16 * 1024^2) {
    stop("Uploaded image is too large for the custom stream backend.")
  }
  mime = sub("^data:([^;]+);base64,.*$", "\\1", data_url)
  base64 = sub("^data:[^;]+;base64,", "", data_url)
  ullme_custom_stream_image_part_from_base64(
    base64,
    mime,
    app=app
  )
}


ullme_custom_stream_user_message = function(input, uploads=NULL,
                                            app=getApp()) {
  text = paste0(input, collapse="\n")
  uploads = uploads %||% list()
  if (!length(uploads)) {
    return(list(role="user", content=text))
  }
  content = list()
  if (nzchar(text) && !identical(text, "[uploaded image]")) {
    content[[length(content) + 1L]] = list(type="text", text=text)
  } else {
    content[[length(content) + 1L]] = list(type="text", text="Please inspect the uploaded image.")
  }
  for (upload in uploads) {
    image_part = ullme_custom_stream_image_part(upload, app=app)
    if (!is.null(image_part)) content[[length(content) + 1L]] = image_part
  }
  image_parts = sum(vapply(
    content,
    function(part) identical(part$type %||% "", "image_url"),
    logical(1)
  ))
  ullme_chat_debug(
    app,
    "custom stream user message uploads=", length(uploads),
    " image_parts=", image_parts,
    " content_parts=", length(content)
  )
  list(role="user", content=content)
}


ullme_custom_stream_initial_messages = function(input, system_prompt=NULL,
                                                uploads=NULL,
                                                app=getApp()) {
  messages = list()
  if (!is.null(system_prompt) && nzchar(system_prompt)) {
    messages[[length(messages) + 1L]] = list(
      role="system",
      content=system_prompt
    )
  }
  messages[[length(messages) + 1L]] = ullme_custom_stream_user_message(
    input=input,
    uploads=uploads,
    app=app
  )
  messages
}


ullme_custom_stream_tool_names = function(task_profile="", app=getApp()) {
  if (!isTRUE(app$enable_ai_tools)) return(character(0))
  if (identical(app$role, "student")) {
    tutor = ullme_student_selected_tutor(app=app)
    requested = paste0(unlist(
      tutor$allowed_tools %||% list(),
      use.names=FALSE
    ))
    return(intersect(requested, names(ullme_student_tool_registry())))
  }
  if (!identical(app$role, "teacher")) return(character(0))
  if (identical(task_profile, "instance_builder")) {
    return(character(0))
  }
  names(ullme_tool_registry())
}


ullme_custom_stream_tool_arg_schema = function(arg_spec) {
  schema_type = switch(
    arg_spec$type,
    string="string",
    boolean="boolean",
    number="number",
    "string"
  )
  list(
    type=schema_type,
    description=arg_spec$description
  )
}


ullme_custom_stream_tool_schema = function(name, app=getApp()) {
  if (identical(app$role, "student")) {
    registry = ullme_student_tool_registry()
    spec = registry[[name]]
    if (is.null(spec)) stop("Unknown student Tutor tool: ", name)
    implementation = get(
      paste0("utool_", name),
      envir=environment(ullme_custom_stream_tool_schema),
      inherits=TRUE
    )
    arguments = formals(implementation)
    arguments$app = NULL
    properties = lapply(names(arguments), function(argument) list(
      type="string",
      description=paste0("Value for ", argument, ".")
    ))
    names(properties) = names(arguments)
    required = names(arguments)[vapply(
      arguments,
      identical,
      logical(1),
      quote(expr=)
    )]
    parameters = list(
      type="object",
      properties=properties,
      additionalProperties=FALSE
    )
    if (length(required)) parameters$required = as.list(required)
    return(list(type="function", `function`=list(
      name=name,
      description=spec$description,
      parameters=parameters
    )))
  }
  registry = ullme_tool_registry()
  spec = registry[[name]]
  if (is.null(spec)) stop("Unknown uLLMe tool: ", name)
  implementation = get(
    paste0("utool_", name),
    envir=environment(ullme_custom_stream_tool_schema),
    inherits=TRUE
  )
  hidden = c("app", "userid", "teacherid")
  args = setdiff(names(formals(implementation)), hidden)
  arg_specs = ullme_tool_arg_spec(
    args=args,
    specs=spec$arguments %||% list()
  )
  properties = lapply(arg_specs, ullme_custom_stream_tool_arg_schema)
  if (!length(properties)) {
    properties = structure(list(), names=character(0))
  }
  required = names(Filter(function(value) isTRUE(value$required), arg_specs))
  parameters = list(
    type="object",
    properties=properties,
    additionalProperties=FALSE
  )
  if (length(required)) parameters$required = as.list(required)
  list(
    type="function",
    `function`=list(
      name=name,
      description=spec$description,
      parameters=parameters
    )
  )
}


ullme_custom_stream_tools = function(task_profile="", app=getApp()) {
  tool_names = ullme_custom_stream_tool_names(
    task_profile=task_profile,
    app=app
  )
  lapply(tool_names, ullme_custom_stream_tool_schema, app=app)
}


ullme_custom_stream_message_has_images = function(message) {
  content = message$content
  if (!is.list(content)) return(FALSE)
  any(vapply(
    content,
    function(part) identical(part$type %||% "", "image_url"),
    logical(1)
  ))
}


ullme_custom_stream_messages_have_images = function(messages) {
  any(vapply(messages, ullme_custom_stream_message_has_images, logical(1)))
}


ullme_custom_stream_body = function(input, model, context=list(),
                                    system_instructions=NULL,
                                    task_profile="",
                                    messages=NULL,
                                    uploads=NULL,
                                    temperature=NULL,
                                    app=getApp()) {
  system_prompt = if (is.null(messages)) {
    ullme_custom_stream_system_prompt(
      context=context,
      system_instructions=system_instructions,
      task_profile=task_profile,
      app=app
    )
  } else {
    NULL
  }
  profile = if (identical(app$api_config$provider, "nvidia")) {
    ullme_nvidia_chat_profile(model, task_profile=task_profile)
  } else {
    list(max_tokens=16384, api_args=list())
  }
  body = c(
    list(
      model=model,
      messages=messages %||%
        ullme_custom_stream_initial_messages(
          input,
          system_prompt=system_prompt,
          uploads=uploads,
          app=app
        ),
      temperature=temperature %||% 1,
      top_p=0.95,
      max_tokens=profile$max_tokens,
      stream=TRUE
    ),
    profile$api_args
  )
  tools = if (ullme_custom_stream_messages_have_images(body$messages)) {
    list()
  } else {
    ullme_custom_stream_tools(task_profile=task_profile, app=app)
  }
  if (length(tools)) {
    body$tools = tools
    body$tool_choice = "auto"
  }
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


ullme_custom_stream_tool_index = function(call) {
  index = suppressWarnings(as.integer(call$index %||% NA_integer_)[1])
  if (is.na(index)) index = 0L
  paste0(index)
}


ullme_custom_stream_accumulate_tool_calls = function(event, state) {
  choices = event$choices %||% list()
  if (!length(choices)) return(invisible(FALSE))
  choice = choices[[1]]
  delta = choice$delta %||% list()
  calls = delta$tool_calls %||% list()
  if (!length(calls)) return(invisible(FALSE))
  if (is.null(state$tool_calls)) state$tool_calls = list()
  for (call in calls) {
    key = ullme_custom_stream_tool_index(call)
    existing = state$tool_calls[[key]] %||% list(
      index=suppressWarnings(as.integer(key)),
      id="",
      type="function",
      `function`=list(name="", arguments="")
    )
    if (nzchar(paste0(call$id %||% "")[1])) {
      existing$id = paste0(call$id)[1]
    }
    if (nzchar(paste0(call$type %||% "")[1])) {
      existing$type = paste0(call$type)[1]
    }
    fn = call$`function` %||% list()
    if (nzchar(paste0(fn$name %||% "")[1])) {
      existing$`function`$name = paste0(fn$name)[1]
    }
    if (nzchar(paste0(fn$arguments %||% "")[1])) {
      existing$`function`$arguments = paste0(
        existing$`function`$arguments %||% "",
        paste0(fn$arguments, collapse="")
      )
    }
    state$tool_calls[[key]] = existing
  }
  invisible(TRUE)
}


ullme_custom_stream_normalize_tool_calls = function(tool_calls) {
  if (!length(tool_calls)) return(list())
  calls = tool_calls[order(as.integer(names(tool_calls)))]
  lapply(calls, function(call) {
    call$index = NULL
    call$type = call$type %||% "function"
    call
  })
}


ullme_custom_stream_tool_args = function(call) {
  text = paste0(call$`function`$arguments %||% "")[1]
  if (!nzchar(trimws(text))) return(list())
  parsed = jsonlite::fromJSON(text, simplifyVector=FALSE)
  if (!is.list(parsed)) return(list())
  parsed
}


ullme_custom_stream_tool_request_event = function(call, app=getApp()) {
  request = app$active_chat_request
  if (is.null(request) || !isTRUE(request$active)) return(invisible(FALSE))
  record = list(
    event="request",
    call_id=paste0(call$id %||% "")[1],
    tool=paste0(call$`function`$name %||% "unknown_tool")[1],
    arguments=tryCatch(
      ullme_custom_stream_tool_args(call),
      error=function(e) paste0(call$`function`$arguments %||% "")[1]
    ),
    at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  )
  request$received_provider_output = TRUE
  ullme_ai_interaction_tool_event(
    request$interaction_dir,
    record,
    request=request
  )
  tool_label = gsub("_", " ", record$tool, fixed=TRUE)
  ullme_send_tool_activity(
    request,
    activity=paste0("Running ", tool_label, "..."),
    app=app
  )
  invisible(TRUE)
}


ullme_custom_stream_tool_result_event = function(call, result, app=getApp()) {
  request = app$active_chat_request
  if (is.null(request) || !isTRUE(request$active)) return(invisible(FALSE))
  status = if (is.list(result)) {
    paste0(result$status %||% "")[1]
  } else {
    ""
  }
  if (!nzchar(status)) status = "completed"
  tool_name = paste0(call$`function`$name %||% "unknown_tool")[1]
  record = list(
    event="result",
    call_id=paste0(call$id %||% "")[1],
    tool=tool_name,
    status=status,
    value=ullme_tool_trace_value(result),
    at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z")
  )
  ullme_ai_interaction_tool_event(
    request$interaction_dir,
    record,
    request=request
  )
  tool_label = gsub("_", " ", record$tool, fixed=TRUE)
  activity = if (status %in% c(
    "error", "rejected", "denied", "cancelled", "failed"
  )) {
    paste0("The ", tool_label, " tool failed. Continuing...")
  } else {
    paste0("Finished ", tool_label, ". Continuing...")
  }
  ullme_send_tool_activity(request, activity=activity, app=app)
  invisible(TRUE)
}


ullme_custom_stream_execute_tool = function(call, app=getApp()) {
  name = paste0(call$`function`$name %||% "")[1]
  if (identical(app$role, "student")) {
    allowed = ullme_custom_stream_tool_names(app=app)
    if (!name %in% allowed) {
      return(list(ok=FALSE, status="rejected", message=paste0(
        "This Tutor does not allow tool: ", name
      )))
    }
    args = tryCatch(
      ullme_custom_stream_tool_args(call),
      error=function(e) list(.parse_error=conditionMessage(e))
    )
    if (!is.null(args$.parse_error)) {
      return(list(ok=FALSE, status="error", message=paste0(
        "Could not parse tool arguments: ", args$.parse_error
      )))
    }
    implementation = get(
      paste0("utool_", name),
      envir=environment(ullme_custom_stream_execute_tool),
      inherits=TRUE
    )
    ullme_custom_stream_tool_request_event(call, app=app)
    result = tryCatch(
      do.call(implementation, c(args, list(app=app))),
      error=function(e) list(
        ok=FALSE, status="error", message=conditionMessage(e)
      )
    )
    ullme_custom_stream_tool_result_event(call, result, app=app)
    return(result)
  }
  registry = ullme_tool_registry()
  spec = registry[[name]]
  if (is.null(spec)) {
    return(list(ok=FALSE, status="error", message=paste0(
      "Unknown uLLMe tool: ",
      name
    )))
  }
  args = tryCatch(
    ullme_custom_stream_tool_args(call),
    error=function(e) {
      list(.parse_error=conditionMessage(e))
    }
  )
  if (!is.null(args$.parse_error)) {
    return(list(ok=FALSE, status="error", message=paste0(
      "Could not parse tool arguments: ",
      args$.parse_error
    )))
  }
  implementation = get(
    paste0("utool_", name),
    envir=environment(ullme_custom_stream_execute_tool),
    inherits=TRUE
  )
  ullme_custom_stream_tool_request_event(call, app=app)
  result = ullme_execute_tool(
    implementation=implementation,
    args=args,
    perm=spec$perm,
    app=app
  )
  wrap_result = function(value) {
    ullme_custom_stream_tool_result_event(call, value, app=app)
    value
  }
  if (inherits(result, "promise")) {
    return(promises::then(result, onFulfilled=wrap_result))
  }
  wrap_result(result)
}


ullme_custom_stream_tool_result_message = function(call, result) {
  content = tryCatch(
    paste0(jsonlite::toJSON(result, auto_unbox=TRUE, null="null", digits=NA)),
    error=function(e) paste0(result, collapse="\n")
  )
  list(
    role="tool",
    tool_call_id=paste0(call$id %||% "")[1],
    name=paste0(call$`function`$name %||% "")[1],
    content=content
  )
}


ullme_custom_stream_promise_value = function(value) {
  promises::promise(function(resolve, reject) resolve(value))
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
  ullme_custom_stream_accumulate_tool_calls(event, state)
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
                                        system_prompt_override=NULL,
                                        include_thinking=FALSE,
                                        task_profile="",
                                        uploads=NULL,
                                        temperature=NULL,
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
      "OpenAI-compatible chat."
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
  state$request_count = 0L
  state$tool_calls = list()
  state$active = TRUE
  state$settled = FALSE

  config = app$api_config
  url = paste0(sub("/+$", "", config$base_url), "/chat/completions")
  system_prompt = if (!is.null(system_prompt_override)) {
    paste0(system_prompt_override, collapse="\n")
  } else {
    ullme_custom_stream_system_prompt(
      context=context,
      system_instructions=system_instructions,
      task_profile=task_profile,
      app=app
    )
  }
  state$messages = ullme_custom_stream_initial_messages(
    input=input,
    system_prompt=system_prompt,
    uploads=uploads,
    app=app
  )
  pool = curl::new_pool(total_con=1, host_con=1, max_streams=1)
  current_handle = NULL
  reject_promise = NULL

  controller = list()
  controller$cancel = function(reason="Request cancelled") {
    if (isTRUE(state$settled)) return(invisible(FALSE))
    state$active = FALSE
    state$settled = TRUE
    if (!is.null(current_handle)) {
      try(curl::multi_cancel(current_handle), silent=TRUE)
    }
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
    start_request = NULL
    continue_after_tools = function(calls) {
      if (!isTRUE(state$active) || isTRUE(state$settled)) {
        return(invisible(NULL))
      }
      assistant_message = list(
        role="assistant",
        content=if (nzchar(state$current_text %||% "")) {
          state$current_text
        } else {
          NULL
        },
        tool_calls=ullme_custom_stream_normalize_tool_calls(calls)
      )
      state$messages[[length(state$messages) + 1L]] = assistant_message
      tool_promises = lapply(assistant_message$tool_calls, function(call) {
        result = ullme_custom_stream_execute_tool(call, app=app)
        if (inherits(result, "promise")) return(result)
        ullme_custom_stream_promise_value(result)
      })
      promises::then(
        promises::promise_all(.list=tool_promises),
        onFulfilled=function(results) {
          for (i in seq_along(assistant_message$tool_calls)) {
            state$messages[[length(state$messages) + 1L]] =
              ullme_custom_stream_tool_result_message(
                assistant_message$tool_calls[[i]],
                results[[i]]
              )
          }
          start_request()
          invisible(NULL)
        },
        onRejected=function(error) {
          settle_error(conditionMessage(error))
          invisible(NULL)
        }
      )
      invisible(NULL)
    }
    start_request = function() {
      if (!isTRUE(state$active) || isTRUE(state$settled)) {
        return(invisible(NULL))
      }
      state$request_count = state$request_count + 1L
      state$buffer = ""
      state$raw = ""
      state$current_text = ""
      state$tool_calls = list()
      body = ullme_custom_stream_body(
        input=input,
        model=model,
        context=context,
        system_instructions=system_instructions,
        task_profile=task_profile,
        messages=state$messages,
        uploads=uploads,
        temperature=temperature,
        app=app
      )
      body_image_parts = sum(vapply(body$messages, function(message) {
        content = message$content
        if (!is.list(content)) return(0L)
        sum(vapply(
          content,
          function(part) identical(part$type %||% "", "image_url"),
          logical(1)
        ))
      }, integer(1)))
      ullme_chat_debug(
        app,
        "custom stream request body request=", state$request_count,
        " messages=", length(body$messages),
        " image_parts=", body_image_parts,
        " tools=", length(body$tools %||% list())
      )
      body_json = jsonlite::toJSON(
        body,
        auto_unbox=TRUE,
        null="null",
        digits=NA
      )
      handle = curl::new_handle(url=url)
      current_handle <<- handle
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
            " request=", state$request_count,
            " bytes=", length(data)
          )
          before_text = state$text
          ullme_custom_stream_process_buffer(
            state,
            on_update=on_update,
            include_thinking=include_thinking,
            app=app
          )
          if (!identical(before_text, state$text)) {
            state$current_text = paste0(
              state$current_text,
              substring(state$text, nchar(before_text) + 1L)
            )
          }
        }
        invisible(NULL)
      }
      done_callback = function(response) {
        status = suppressWarnings(as.integer(
          response$status_code %||% response$status %||% 0L
        ))
        ullme_chat_debug(
          app,
          "custom stream done status=", status,
          " request=", state$request_count,
          " chunks=", state$chunk_count,
          " text_bytes=", nchar(state$text, type="bytes"),
          " tool_calls=", length(state$tool_calls)
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
          before_text = state$text
          state$buffer = paste0(state$buffer, "\n")
          ullme_custom_stream_process_buffer(
            state,
            on_update=on_update,
            include_thinking=include_thinking,
            app=app
          )
          if (!identical(before_text, state$text)) {
            state$current_text = paste0(
              state$current_text,
              substring(state$text, nchar(before_text) + 1L)
            )
          }
        }
        if (length(state$tool_calls)) {
          continue_after_tools(state$tool_calls)
          return(invisible(NULL))
        }
        state$messages[[length(state$messages) + 1L]] = list(
          role="assistant",
          content=state$current_text
        )
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
      invisible(TRUE)
    }
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
    start_request()
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
