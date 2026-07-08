ullme_prompts_dir = function() {
  restore.point("ullme_prompts_dir")
  path = system.file("prompts", package="ullme")
  if (nzchar(path)) return(path)
  source_path = file.path(getwd(), "inst", "prompts")
  if (dir.exists(source_path)) {
    return(normalizePath(source_path, winslash="/", mustWork=TRUE))
  }
  stop("Cannot find uLLMe prompt fragments.")
}


ullme_read_prompt = function(name) {
  restore.point("ullme_read_prompt")
  name = paste0(name)[1]
  if (!grepl("^[A-Za-z][A-Za-z0-9_-]*$", name)) stop("Invalid prompt name.")
  path = file.path(ullme_prompts_dir(), paste0(name, ".txt"))
  if (!file.exists(path)) stop("Prompt fragment not found: ", name)
  paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n")
}


ullme_render_prompt = function(text, values=list(), strict=TRUE) {
  restore.point("ullme_render_prompt")
  text = paste0(text, collapse="\n")
  pattern = "\\{\\{[A-Za-z][A-Za-z0-9_]*\\}\\}"
  repeat {
    hit = regexpr(pattern, text, perl=TRUE)
    if (hit[[1]] < 0) break
    token = regmatches(text, hit)
    key = substr(token, 3, nchar(token) - 2)
    value = values[[key]]
    if (is.null(value)) {
      if (isTRUE(strict)) stop("Missing prompt value: ", key)
      value = token
    }
    value = paste0(value, collapse="\n")
    start = hit[[1]]
    end = start + attr(hit, "match.length") - 1L
    text = paste0(
      if (start > 1L) substr(text, 1L, start - 1L) else "",
      value,
      if (end < nchar(text)) substr(text, end + 1L, nchar(text)) else ""
    )
    if (!isTRUE(strict) && identical(value, token)) break
  }
  text
}


ullme_prompt = function(name, values=list(), strict=TRUE) {
  restore.point("ullme_prompt")
  ullme_render_prompt(ullme_read_prompt(name), values=values, strict=strict)
}


ullme_prompt_with_literal_values = function(name, values=list()) {
  restore.point("ullme_prompt_with_literal_values")
  open = "__ULLME_LITERAL_OPEN_BRACES__"
  close = "__ULLME_LITERAL_CLOSE_BRACES__"
  escaped = lapply(values, function(value) {
    value = gsub("{{", open, paste0(value, collapse="\n"), fixed=TRUE)
    gsub("}}", close, value, fixed=TRUE)
  })
  rendered = ullme_prompt(name, values=escaped, strict=TRUE)
  rendered = gsub(open, "{{", rendered, fixed=TRUE)
  gsub(close, "}}", rendered, fixed=TRUE)
}


ullme_tool_prompt_summary = function(tool_names=NULL) {
  restore.point("ullme_tool_prompt_summary")
  registry = ullme_tool_registry()
  if (!is.null(tool_names)) {
    unknown = setdiff(tool_names, names(registry))
    if (length(unknown)) {
      stop("Unknown tool prompt name: ", paste(unknown, collapse=", "))
    }
    registry = registry[tool_names]
  }
  paste(vapply(names(registry), function(name) {
    paste0("- ", name, ": ", registry[[name]]$description)
  }, character(1)), collapse="\n")
}


ullme_skill_prompt_summary = function(app=getApp()) {
  restore.point("ullme_skill_prompt_summary")
  skills = ullme_skill_catalog(app=app)
  if (length(skills) == 0) return("- No Skill definitions are currently available.")
  paste(vapply(skills, function(skill) {
    paste0(
      "- ", skill$skillid, " (", skill$label, ", ", skill$source, "): ",
      skill$description
    )
  }, character(1)), collapse="\n")
}


ullme_teacher_prompt_values = function(app=getApp(), context=list(),
                                        tool_names=NULL) {
  restore.point("ullme_teacher_prompt_values")
  course = tryCatch(ullme_course_summary(app=app)$course, error=function(e) NULL)
  coursename = paste0(course$coursename %||% app$courseid %||% "")[1]
  active = ullme_active_skill(app=app)
  open_file = paste0(context$course_file %||% "")[1]
  list(
    userid=app$userid %||% "",
    semester=app$semester %||% "",
    courseid=app$courseid %||% "",
    coursename=coursename,
    studio_view=paste0(context$studio_view %||% "")[1],
    open_file=open_file,
    tools=ullme_tool_prompt_summary(tool_names=tool_names),
    skills=ullme_skill_prompt_summary(app=app),
    active_skill=if (is.null(active)) {
      "No Skill is active."
    } else {
      paste0(
        "Active Skill: ", active$skillid, " (", active$label, ")\n\n",
        active$instructions %||% ""
      )
    },
    project_state=ullme_teacher_project_state_text(app=app)
  )
}


ullme_teacher_system_prompt = function(app=getApp(), context=list(),
                                        tool_names=NULL) {
  restore.point("ullme_teacher_system_prompt")
  values = ullme_teacher_prompt_values(
    app=app,
    context=context,
    tool_names=tool_names
  )
  fragments = c(
    "teacher_base",
    "teacher_language",
    "teacher_onboarding",
    "teacher_context",
    "teacher_tools",
    "teacher_skills"
  )
  paste(vapply(
    fragments,
    ullme_prompt,
    character(1),
    values=values
  ), collapse="\n\n")
}
