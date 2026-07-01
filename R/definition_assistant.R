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


ullme_handle_definition_chat = function(kind="tutor", definitionid=NULL,
                                         source=NULL, file=NULL, content=NULL,
                                         message=NULL, requestid=NULL,
                                         app=getApp(), ...) {
  restore.point("ullme_handle_definition_chat")
  requestid = paste0(requestid %||% "")[1]
  response = tryCatch({
    if (!identical(app$role, "teacher")) stop("Only teachers can use the Definition Assistant.")
    kind = ullme_definition_kind(kind)
    definitionid = ullme_clean_definition_id(definitionid)
    source = paste0(source)[1]
    file = gsub("\\\\", "/", paste0(file)[1])
    content = paste0(content, collapse="\n")
    message = trimws(paste0(message, collapse="\n"))
    if (!nzchar(message)) stop("Enter an instruction for the Definition Assistant.")
    if (nchar(message, type="bytes") > 16000) stop("The assistant instruction is too long.")
    if (nchar(content, type="bytes") > 2 * 1024^2) stop("The current file is too large.")
    if (!ullme_definition_is_editable(kind=kind, source=source, app=app)) {
      stop("Make a Personal or course-local copy before applying AI rewrites.")
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
    if (!ullme_uses_fake_ai(app=app)) {
      stop("Structured Definition Assistant responses are not connected to a model yet.")
    }

    draft = ullme_fake_definition_rewrite(
      file=file,
      content=content,
      instruction=message
    )
    list(
      ok=TRUE,
      requestid=requestid,
      kind=kind,
      definitionid=definitionid,
      source=source,
      message=paste0(
        "I applied a fake-AI draft to ",
        file,
        ". Review it in the editor and save only if you want to keep it."
      ),
      draft=list(file=file, content=draft),
      context_chars=nchar(context)
    )
  }, error=function(e) {
    list(
      ok=FALSE,
      requestid=requestid,
      message=conditionMessage(e),
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
