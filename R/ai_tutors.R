ullme_package_dir = function(subdir) {
  restore.point("ullme_package_dir")
  path = system.file(subdir, package="ullme")
  if (nzchar(path)) return(path)

  source_path = file.path(getwd(), "inst", subdir)
  if (dir.exists(source_path)) return(normalizePath(source_path, winslash="/"))
  source_path
}


ullme_ai_tutor_definition_roots = function(app=getApp()) {
  restore.point("ullme_ai_tutor_definition_roots")
  course_dir = ullme_active_course_dir(app=app)
  roots = list(
    course = if (is.null(course_dir)) character(0) else file.path(course_dir, "ai_tutor_definitions"),
    personal = file.path(app$glob$main_dir, "teachers", app$userid, "ai_tutors"),
    general = file.path(app$glob$main_dir, "ai_tutors", "general"),
    package = ullme_package_dir("ai_tutors")
  )
  roots
}


ullme_definition_ids = function(root) {
  restore.point("ullme_definition_ids")
  if (length(root) == 0 || !dir.exists(root)) return(character(0))
  entries = list.files(root, full.names=TRUE, no..=TRUE)
  ids = basename(entries[dir.exists(entries)])
  sort(ids[grepl("^[A-Za-z][A-Za-z0-9_-]*$", ids)])
}


ullme_ai_tutor_definition = function(tutorid, app=getApp()) {
  restore.point("ullme_ai_tutor_definition")
  tutorid = ullme_clean_definition_id(tutorid)
  roots = ullme_ai_tutor_definition_roots(app=app)

  for (source in names(roots)) {
    root = roots[[source]]
    if (length(root) == 0) next
    path = file.path(root, tutorid)
    definition_path = file.path(path, "tutor.yaml")
    if (!dir.exists(path) || !file.exists(definition_path)) next
    definition = tryCatch(yaml::read_yaml(definition_path), error=function(e) NULL)
    if (is.null(definition) || !is.list(definition)) next
    return(ullme_normalize_ai_tutor_definition(
      definition=definition,
      tutorid=tutorid,
      source=source
    ))
  }
  NULL
}


ullme_ai_tutor_catalog = function(app=getApp()) {
  restore.point("ullme_ai_tutor_catalog")
  roots = ullme_ai_tutor_definition_roots(app=app)
  ids = unique(unlist(lapply(roots, ullme_definition_ids), use.names=FALSE))
  definitions = lapply(ids, ullme_ai_tutor_definition, app=app)
  definitions = definitions[!vapply(definitions, is.null, logical(1))]
  definitions[order(vapply(definitions, function(x) x$label, character(1)))]
}


ullme_normalize_ai_tutor_definition = function(definition, tutorid, source) {
  restore.point("ullme_normalize_ai_tutor_definition")
  if (is.null(definition)) definition = list()
  label = definition$label %||% definition$name %||% definition$title %||% tutorid
  description = definition$description %||% definition$descr_teacher %||% definition$descr %||% ""
  required_roles = definition$required_material_roles %||% definition$materials %||% list()
  if (is.list(required_roles)) required_roles = names(required_roles) %||% unlist(required_roles)

  list(
    tutorid = tutorid,
    label = paste0(label)[1],
    description = paste0(description, collapse="\n"),
    source = source,
    required_material_roles = as.list(paste0(required_roles))
  )
}


ullme_clean_definition_id = function(id) {
  restore.point("ullme_clean_definition_id")
  id = paste0(id)[1]
  if (is.na(id) || !grepl("^[A-Za-z][A-Za-z0-9_-]*$", id)) {
    stop("Definition IDs must start with a letter and contain only letters, numbers, underscores, or hyphens.")
  }
  id
}


ullme_course_ai_tutors_dir = function(course_dir) {
  restore.point("ullme_course_ai_tutors_dir")
  file.path(course_dir, "ai_tutors")
}


ullme_course_ai_tutor_dir = function(course_dir, tutorid) {
  restore.point("ullme_course_ai_tutor_dir")
  file.path(ullme_course_ai_tutors_dir(course_dir), ullme_clean_definition_id(tutorid))
}


ullme_course_ai_tutor_path = function(course_dir, tutorid) {
  restore.point("ullme_course_ai_tutor_path")
  file.path(ullme_course_ai_tutor_dir(course_dir, tutorid), "tutor.yaml")
}


ullme_course_ai_tutors = function(app=getApp()) {
  restore.point("ullme_course_ai_tutors")
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) return(list())
  root = ullme_course_ai_tutors_dir(course_dir)
  ids = ullme_definition_ids(root)

  tutors = lapply(ids, function(tutorid) {
    path = ullme_course_ai_tutor_path(course_dir, tutorid)
    if (!file.exists(path)) return(NULL)
    course_tutor = tryCatch(yaml::read_yaml(path), error=function(e) NULL)
    if (is.null(course_tutor) || !is.list(course_tutor)) return(NULL)
    definition = ullme_ai_tutor_definition(tutorid=tutorid, app=app)
    if (is.null(definition)) {
      definition = list(
        tutorid=tutorid,
        label=tutorid,
        description="The tutor definition is currently unavailable.",
        source="missing",
        required_material_roles=list()
      )
    }
    definition$enabled = !identical(course_tutor$enabled, FALSE)
    definition$instance_count = ullme_ai_tutor_instance_count(course_dir, tutorid)
    definition
  })
  tutors = tutors[!vapply(tutors, is.null, logical(1))]
  tutors[order(vapply(tutors, function(x) x$label, character(1)))]
}


ullme_ai_tutor_instance_count = function(course_dir, tutorid) {
  restore.point("ullme_ai_tutor_instance_count")
  dir = file.path(ullme_course_ai_tutor_dir(course_dir, tutorid), "instances")
  if (!dir.exists(dir)) return(0L)
  length(list.files(dir, pattern="\\.(yaml|yml)$", ignore.case=TRUE, no..=TRUE))
}


ullme_add_course_ai_tutor = function(tutorid, app=getApp()) {
  restore.point("ullme_add_course_ai_tutor")
  if (!identical(app$role, "teacher")) return(FALSE)
  tutorid = ullme_clean_definition_id(tutorid)
  definition = ullme_ai_tutor_definition(tutorid=tutorid, app=app)
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(definition) || is.null(course_dir)) return(FALSE)

  tutor_dir = ullme_course_ai_tutor_dir(course_dir, tutorid)
  dir.create(file.path(tutor_dir, "instances"), recursive=TRUE, showWarnings=FALSE)
  path = ullme_course_ai_tutor_path(course_dir, tutorid)
  if (!file.exists(path)) {
    yaml::write_yaml(list(tutorid=tutorid, enabled=TRUE), path)
  }
  TRUE
}


ullme_set_course_ai_tutor_enabled = function(tutorid, enabled, app=getApp()) {
  restore.point("ullme_set_course_ai_tutor_enabled")
  if (!identical(app$role, "teacher")) return(FALSE)
  tutorid = ullme_clean_definition_id(tutorid)
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) return(FALSE)
  path = ullme_course_ai_tutor_path(course_dir, tutorid)
  if (!file.exists(path)) return(FALSE)

  course_tutor = yaml::read_yaml(path)
  if (is.null(course_tutor)) course_tutor = list()
  course_tutor$tutorid = tutorid
  course_tutor$enabled = isTRUE(enabled)
  yaml::write_yaml(course_tutor, path)
  TRUE
}


ullme_handle_ai_tutor_add = function(tutorid=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_ai_tutor_add")
  added = tryCatch(
    ullme_add_course_ai_tutor(tutorid=tutorid, app=app),
    error=function(e) FALSE
  )
  if (added) ullme_send_course_state(app=app)
  invisible(added)
}


ullme_handle_ai_tutor_toggle = function(tutorid=NULL, enabled=FALSE, app=getApp(), ...) {
  restore.point("ullme_handle_ai_tutor_toggle")
  changed = tryCatch(
    ullme_set_course_ai_tutor_enabled(tutorid=tutorid, enabled=enabled, app=app),
    error=function(e) FALSE
  )
  if (changed) ullme_send_course_state(app=app)
  invisible(changed)
}
