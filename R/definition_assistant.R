ullme_definition_assistant_context = function(kind, definitionid, source,
                                               current_file, current_content,
                                               app=getApp(),
                                               max_chars=200000) {
  restore.point("ullme_definition_assistant_context")
  definition_dir = ullme_definition_dir(
    kind=kind,
    definitionid=definitionid,
    source=source,
    app=app
  )
  files = ullme_definition_text_files(definition_dir=definition_dir)
  if (!current_file %in% files) stop("The selected definition file is invalid.")

  sections = lapply(files, function(file) {
    content = if (identical(file, current_file)) {
      current_content
    } else {
      paste(readLines(
        file.path(definition_dir, file),
        warn=FALSE,
        encoding="UTF-8"
      ), collapse="\n")
    }
    content = substr(content, 1, max_chars)
    paste0("FILE: ", file, "\n", content)
  })
  paste(unlist(sections), collapse="\n\n---\n\n")
}


ullme_fake_definition_rewrite = function(file, content, instruction) {
  restore.point("ullme_fake_definition_rewrite")
  instruction_line = gsub("[\r\n]+", " ", trimws(instruction))
  if (grepl("\\.ya?ml$", file, ignore.case=TRUE)) {
    return(paste0(
      sub("[\r\n]+$", "", content),
      "\n\n# Fake AI draft request: ",
      instruction_line,
      "\n"
    ))
  }
  paste0(
    sub("[\r\n]+$", "", content),
    "\n\n## Fake AI draft\n\n",
    "Revision requested: ",
    instruction_line,
    "\n"
  )
}


ullme_definition_rewrite_type = function() {
  restore.point("ullme_definition_rewrite_type")
  ellmer::type_object(
    content=ellmer::type_string(
      "Complete replacement content for the selected file."
    ),
    explanation=ellmer::type_string(
      "Short explanation of the changes.",
      required=FALSE
    ),
    warnings=ellmer::type_array(
      ellmer::type_string(),
      "Potential issues the teacher should review.",
      required=FALSE
    )
  )
}


ullme_definition_ai_rewrite = function(kind, definitionid, source, file,
                                        content, instruction, context,
                                        model=NULL, app=getApp()) {
  restore.point("ullme_definition_ai_rewrite")
  values = list(
    kind=kind,
    definitionid=definitionid,
    source=source,
    file=file
  )
  system_prompt = paste(
    ullme_prompt("teacher_base", values=values),
    ullme_prompt("teacher_language", values=values),
    ullme_prompt("rewrite_definition", values=values),
    sep="\n\n"
  )
  chat = ullme_task_chat(system_prompt=system_prompt, model=model, app=app)
  request = paste0(
    "Teacher instruction:\n", instruction,
    "\n\nCurrent selected file:\nFILE: ", file, "\n", content,
    "\n\nOther definition files and context:\n", context
  )
  interaction = ullme_ai_interaction_start(
    input=paste(system_prompt, request, sep="\n\n"),
    visible_text=instruction,
    model=model %||% app$api_config$model,
    kind="definition_assistant",
    app=app
  )
  result = tryCatch(
    chat$chat_structured(
      request,
      type=ullme_definition_rewrite_type(),
      echo="none"
    ),
    error=function(e) {
      ullme_ai_interaction_finish(
        interaction,
        status="error",
        error=conditionMessage(e)
      )
      stop(e)
    }
  )
  draft = paste0(result$content %||% "")[1]
  if (!nzchar(draft)) {
    error = "The model returned an empty draft."
    ullme_ai_interaction_finish(interaction, status="error", error=error)
    stop(error)
  }
  tryCatch(
    ullme_validate_definition_content(kind, definitionid, file, draft),
    error=function(e) {
      ullme_ai_interaction_finish(
        interaction,
        status="error",
        text=draft,
        error=conditionMessage(e)
      )
      stop(e)
    }
  )
  ullme_ai_interaction_finish(
    interaction,
    text=paste0(
      result$explanation %||% "Draft created.",
      "\n\n",
      draft
    )
  )
  list(
    content=draft,
    explanation=paste0(result$explanation %||% "Draft created.")[1],
    warnings=as.list(unlist(result$warnings %||% list(), use.names=FALSE))
  )
}


ullme_handle_definition_chat = function(kind="skill", definitionid=NULL,
                                         source=NULL, file=NULL, content=NULL,
                                         message=NULL, requestid=NULL, model=NULL,
                                         app=getApp(), ...) {
  restore.point("ullme_handle_definition_chat")
  requestid = paste0(requestid %||% "")[1]
  response = tryCatch({
    if (!identical(app$role, "teacher")) stop("Only teachers can use the Definition Assistant.")
    kind = ullme_definition_kind(kind)
    if (!identical(kind, "skill")) {
      stop("The Definition Assistant edits Skills only.")
    }
    definitionid = ullme_clean_definition_id(definitionid)
    source = paste0(source)[1]
    file = gsub("\\\\", "/", paste0(file)[1])
    content = paste0(content, collapse="\n")
    message = trimws(paste0(message, collapse="\n"))
    if (!nzchar(message)) stop("Enter an instruction for the Definition Assistant.")
    if (nchar(message, type="bytes") > 16000) stop("The assistant instruction is too long.")
    if (nchar(content, type="bytes") > 2 * 1024^2) stop("The current file is too large.")
    if (!ullme_definition_is_editable(kind=kind, source=source, app=app)) {
      stop("Make a Personal Skill copy before applying AI rewrites.")
    }
    if (is.null(ullme_definition_metadata_at(
      kind=kind,
      definitionid=definitionid,
      source=source,
      app=app
    ))) {
      stop("The selected definition does not exist.")
    }

    context = ullme_definition_assistant_context(
      kind=kind,
      definitionid=definitionid,
      source=source,
      current_file=file,
      current_content=content,
      app=app
    )
    if (ullme_uses_fake_ai(app=app)) {
      draft = ullme_fake_definition_rewrite(
        file=file,
        content=content,
        instruction=message
      )
      assistant_message = paste0(
        "I applied a fake-AI draft to ",
        file,
        ". Review it in the editor and save only if you want to keep it."
      )
      warnings = list()
    } else {
      rewrite = ullme_definition_ai_rewrite(
        kind=kind,
        definitionid=definitionid,
        source=source,
        file=file,
        content=content,
        instruction=message,
        context=context,
        model=model,
        app=app
      )
      draft = rewrite$content
      assistant_message = paste(
        c(
          rewrite$explanation,
          if (length(rewrite$warnings) > 0) {
            paste0("Review: ", paste(unlist(rewrite$warnings), collapse=" "))
          } else NULL
        ),
        collapse="\n"
      )
      warnings = rewrite$warnings
    }
    list(
      ok=TRUE,
      requestid=requestid,
      kind=kind,
      definitionid=definitionid,
      source=source,
      message=assistant_message,
      draft=list(file=file, content=draft),
      warnings=warnings,
      context_chars=nchar(context)
    )
  }, error=function(e) {
    list(
      ok=FALSE,
      requestid=requestid,
      message=ullme_safe_ai_error(e, app$api_config),
      draft=NULL
    )
  })

  callJS(
    .fun="window.ullme.receiveDefinitionAssistantMessage",
    .args=list(response),
    .app=app
  )
  invisible(response)
}
