ullme_chat_key = function(model, app=getApp()) {
  paste(
    app$api_config$provider,
    model,
    app$userid %||% "",
    app$semester %||% "",
    app$courseid %||% "",
    sep="|"
  )
}


ullme_teacher_chat = function(model=NULL, system_prompt=NULL, app=getApp()) {
  config = app$api_config
  model = ullme_model_id(model, app=app)
  key = ullme_chat_key(model, app=app)
  chat = app$teacher_chats[[key]]
  if (is.null(chat)) {
    chat = ullme_api_chat(config, model=model, system_prompt=system_prompt)
    if (!is.null(chat)) {
      chat$register_tools(ullme_tools(app=app))
      app$teacher_chats[[key]] = chat
    }
  } else if (!is.null(system_prompt)) {
    chat$set_system_prompt(system_prompt)
  }
  chat
}


ullme_ask_ai = function(input, model=NULL, context=list(),
                         system_instructions=NULL, app=getApp()) {
  restore.point("ullme_ask_ai")
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
                                  app=getApp()) {
  restore.point("ullme_ai_request_chat")
  if (!identical(app$role, "teacher")) {
    stop("The real AI assistant is currently available only in teacher mode.")
  }
  prompt = ullme_teacher_system_prompt(app=app, context=context)
  if (!is.null(system_instructions) && nzchar(system_instructions)) {
    prompt = paste(prompt, system_instructions, sep="\n\n")
  }
  chat = ullme_teacher_chat(model=model, system_prompt=prompt, app=app)
  if (is.null(chat)) stop("No model is configured.")
  chat
}


.ullme_stream_chunk_part = function(chunk) {
  if (is.character(chunk)) {
    return(list(type="text", value=paste0(chunk, collapse="")))
  }
  classes = class(chunk)
  if (any(grepl("ContentThinking", classes, fixed=TRUE))) {
    value = tryCatch(paste0(chunk@thinking)[1], error=function(e) "")
    return(list(type="thinking", value=value))
  }
  if (any(grepl("ContentText", classes, fixed=TRUE))) {
    value = tryCatch(paste0(chunk@text)[1], error=function(e) "")
    return(list(type="text", value=value))
  }
  list(type="other", value="")
}


ullme_start_ai_stream = function(input, model=NULL, context=list(),
                                  system_instructions=NULL,
                                  include_thinking=FALSE,
                                  on_update=function(...) NULL,
                                  app=getApp()) {
  restore.point("ullme_start_ai_stream")
  chat = ullme_ai_request_chat(
    model=model,
    context=context,
    system_instructions=system_instructions,
    app=app
  )
  stream = chat$stream_async(
    input,
    tool_mode="sequential",
    stream=if (isTRUE(include_thinking)) "content" else "text"
  )
  state = new.env(parent=emptyenv())
  state$text = ""
  state$thinking = ""
  state$last_update = 0
  await_each = coro::await_each
  runner = coro::async(function() {
    for (chunk in await_each(stream)) {
      part = .ullme_stream_chunk_part(chunk)
      if (identical(part$type, "text")) {
        state$text = paste0(state$text, part$value)
      } else if (identical(part$type, "thinking")) {
        state$thinking = paste0(state$thinking, part$value)
      }
      now = as.numeric(Sys.time())
      changed = nzchar(part$value) &&
        part$type %in% c("text", "thinking")
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
        on_update(state$text, state$thinking, FALSE)
        state$last_update = now
      }
    }
    on_update(state$text, state$thinking, TRUE)
    list(text=state$text, thinking=state$thinking)
  })
  list(promise=runner(), state=state)
}


ullme_start_ai_chat = function(input, model=NULL, context=list(),
                                system_instructions=NULL,
                                app=getApp()) {
  restore.point("ullme_start_ai_chat")
  chat = ullme_ai_request_chat(
    model=model,
    context=context,
    system_instructions=system_instructions,
    app=app
  )
  list(
    promise=chat$chat_async(input, tool_mode="sequential"),
    chat=chat
  )
}


ullme_chat_last_thinking = function(chat) {
  restore.point("ullme_chat_last_thinking")
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
