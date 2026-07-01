ullme_prompts_dir = function() {
  path = system.file("prompts", package="ullme")
  if (nzchar(path)) return(path)
  source_path = file.path(getwd(), "inst", "prompts")
  if (dir.exists(source_path)) {
    return(normalizePath(source_path, winslash="/", mustWork=TRUE))
  }
  stop("Cannot find uLLMe prompt fragments.")
}


ullme_read_prompt = function(name) {
  name = paste0(name)[1]
  if (!grepl("^[A-Za-z][A-Za-z0-9_-]*$", name)) stop("Invalid prompt name.")
  path = file.path(ullme_prompts_dir(), paste0(name, ".txt"))
  if (!file.exists(path)) stop("Prompt fragment not found: ", name)
  paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n")
}


ullme_render_prompt = function(text, values=list(), strict=TRUE) {
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
  ullme_render_prompt(ullme_read_prompt(name), values=values, strict=strict)
}


ullme_tool_prompt_summary = function() {
  registry = ullme_tool_registry()
  paste(vapply(names(registry), function(name) {
    paste0("- ", name, ": ", registry[[name]]$description)
  }, character(1)), collapse="\n")
}


ullme_skill_prompt_summary = function(app=getApp()) {
  skills = ullme_skill_catalog(app=app)
  if (length(skills) == 0) return("- No Skill definitions are currently available.")
  paste(vapply(skills, function(skill) {
    paste0(
      "- ", skill$skillid, " (", skill$label, ", ", skill$source, "): ",
      skill$description
    )
  }, character(1)), collapse="\n")
}


ullme_teacher_prompt_values = function(app=getApp(), context=list()) {
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
    tools=ullme_tool_prompt_summary(),
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


ullme_teacher_system_prompt = function(app=getApp(), context=list()) {
  values = ullme_teacher_prompt_values(app=app, context=context)
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
