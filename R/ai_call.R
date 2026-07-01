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
  if (!identical(app$role, "teacher")) {
    stop("The real AI assistant is currently available only in teacher mode.")
  }
  prompt = ullme_teacher_system_prompt(app=app, context=context)
  if (!is.null(system_instructions) && nzchar(system_instructions)) {
    prompt = paste(prompt, system_instructions, sep="\n\n")
  }
  chat = ullme_teacher_chat(model=model, system_prompt=prompt, app=app)
  if (is.null(chat)) stop("No model is configured.")
  chat$chat(input, echo="none")
}


ullme_task_chat = function(system_prompt, model=NULL, app=getApp()) {
  config = app$api_config
  model = ullme_model_id(model, app=app)
  ullme_api_chat(config, model=model, system_prompt=system_prompt)
}
