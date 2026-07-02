ullme_skill_roots = function(app=getApp()) {
  restore.point("ullme_skill_roots")
  list(
    personal = file.path(app$glob$main_dir, "users", app$userid, "skills"),
    general = file.path(app$glob$main_dir, "skills", "general"),
    package = ullme_package_dir("skills")
  )
}


ullme_skill_definition = function(skillid, app=getApp(), include_instructions=TRUE) {
  restore.point("ullme_skill_definition")
  skillid = ullme_clean_definition_id(skillid)
  roots = ullme_skill_roots(app=app)

  for (source in names(roots)) {
    skill = ullme_skill_definition_at(
      skillid=skillid,
      source=source,
      app=app,
      include_instructions=include_instructions
    )
    if (!is.null(skill)) return(skill)
  }
  NULL
}


ullme_skill_definition_at = function(skillid, source, app=getApp(), include_instructions=TRUE) {
  restore.point("ullme_skill_definition_at")
  skillid = ullme_clean_definition_id(skillid)
  roots = ullme_skill_roots(app=app)
  source = paste0(source)[1]
  if (!source %in% names(roots)) return(NULL)

  path = file.path(roots[[source]], skillid)
  skill_path = file.path(path, "SKILL.md")
  metadata_path = file.path(path, "ullme.yaml")
  if (!dir.exists(path) || !file.exists(skill_path) || !file.exists(metadata_path)) return(NULL)
  metadata = tryCatch(yaml::read_yaml(metadata_path), error=function(e) NULL)
  if (is.null(metadata) || !is.list(metadata)) return(NULL)
  instructions = NULL
  if (isTRUE(include_instructions)) {
    instructions = paste(readLines(skill_path, warn=FALSE, encoding="UTF-8"), collapse="\n")
  }
  ullme_normalize_skill_definition(
    metadata=metadata,
    instructions=instructions,
    skillid=skillid,
    source=source
  )
}


ullme_skill_catalog = function(app=getApp()) {
  restore.point("ullme_skill_catalog")
  roots = ullme_skill_roots(app=app)
  ids = unique(unlist(lapply(roots, ullme_definition_ids), use.names=FALSE))
  skills = lapply(ids, ullme_skill_definition, app=app, include_instructions=FALSE)
  skills = skills[!vapply(skills, is.null, logical(1))]
  skills[order(vapply(skills, function(x) x$label, character(1)))]
}


ullme_normalize_skill_definition = function(metadata, instructions, skillid, source) {
  restore.point("ullme_normalize_skill_definition")
  if (is.null(metadata)) metadata = list()
  label = metadata$label %||% metadata$name %||% metadata$title %||% skillid
  description = metadata$description %||% metadata$descr %||% ""
  intro = metadata$intro %||% metadata$introductory_text %||% ""
  starter_prompts = metadata$starter_prompts %||% list()
  placeholder = metadata$composer_placeholder %||% metadata$placeholder %||% "Ask anything"

  list(
    skillid = skillid,
    label = paste0(label)[1],
    description = paste0(description, collapse="\n"),
    intro = paste0(intro, collapse="\n"),
    starter_prompts = as.list(paste0(unlist(starter_prompts, use.names=FALSE))),
    composer_placeholder = paste0(placeholder)[1],
    source = source,
    instructions = instructions
  )
}


ullme_skill_for_js = function(skill) {
  restore.point("ullme_skill_for_js")
  if (is.null(skill)) return(NULL)
  skill$instructions = NULL
  skill
}


ullme_skill_catalog_for_js = function(app=getApp()) {
  restore.point("ullme_skill_catalog_for_js")
  lapply(ullme_skill_catalog(app=app), ullme_skill_for_js)
}


ullme_course_skills_path = function(app=getApp()) {
  restore.point("ullme_course_skills_path")
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) return(NULL)
  file.path(course_dir, "skills.yaml")
}


ullme_course_skillids = function(app=getApp()) {
  restore.point("ullme_course_skillids")
  path = ullme_course_skills_path(app=app)
  if (is.null(path) || !file.exists(path)) return(character(0))
  value = tryCatch(yaml::read_yaml(path), error=function(e) NULL)
  if (!is.list(value)) return(character(0))
  ids = unlist(value$skills %||% list(), use.names=FALSE)
  ids = unique(paste0(ids))
  ids[grepl("^[A-Za-z][A-Za-z0-9_-]*$", ids)]
}


ullme_course_skills_for_js = function(app=getApp()) {
  restore.point("ullme_course_skills_for_js")
  skills = lapply(ullme_course_skillids(app=app), function(skillid) {
    ullme_skill_definition(skillid=skillid, app=app, include_instructions=FALSE)
  })
  skills = skills[!vapply(skills, is.null, logical(1))]
  lapply(skills, ullme_skill_for_js)
}


ullme_add_course_skill = function(skillid, app=getApp()) {
  restore.point("ullme_add_course_skill")
  skillid = ullme_clean_definition_id(skillid)
  path = ullme_course_skills_path(app=app)
  if (is.null(path)) stop("Select a course first.")
  ids = ullme_course_skillids(app=app)
  if (skillid %in% ids) return(TRUE)
  content = trimws(yaml::as.yaml(list(skills=as.list(c(ids, skillid)))))
  operation = ullme_new_change(
    action="course_skill_add",
    summary=paste0("Add Skill ", skillid, " to course ", app$courseid),
    origin="ui",
    details=list(courseid=app$courseid, skillid=skillid),
    changes=list(ullme_change_write(path, content)),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  isTRUE(result$ok)
}


ullme_active_skill = function(app=getApp()) {
  restore.point("ullme_active_skill")
  skillid = app$active_skillid
  if (is.null(skillid) || !nzchar(skillid)) return(NULL)
  if (!skillid %in% ullme_course_skillids(app=app)) return(NULL)
  ullme_skill_definition(skillid=skillid, app=app)
}


ullme_handle_skill_activate = function(skillid=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_skill_activate")
  if (!identical(app$role, "teacher")) return(invisible(FALSE))
  skill = tryCatch(ullme_skill_definition(skillid=skillid, app=app), error=function(e) NULL)
  if (is.null(skill)) return(invisible(FALSE))
  added = tryCatch(
    ullme_add_course_skill(skillid=skill$skillid, app=app),
    error=function(e) FALSE
  )
  if (!isTRUE(added)) return(invisible(FALSE))
  app$active_skillid = skill$skillid
  ullme_send_course_state(app=app)
  invisible(TRUE)
}


ullme_handle_skill_clear = function(app=getApp(), ...) {
  restore.point("ullme_handle_skill_clear")
  app$active_skillid = ""
  ullme_send_course_state(app=app)
  invisible(TRUE)
}
