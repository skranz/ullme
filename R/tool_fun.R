ullme_tool_course_dir = function(semester="sel", courseid, app=getApp()) {
  semester = ullme_tool_semester(semester, app=app)
  courseid = ullme_clean_courseid(courseid)
  path = ullme_course_dir(
    main_dir=app$glob$main_dir,
    userid=app$userid,
    role="teacher",
    semester=semester,
    courseid=courseid
  )
  if (!dir.exists(path)) stop("The requested course does not exist.")
  path
}


ullme_tool_relative_path = function(path, label="path") {
  path = gsub("\\\\", "/", paste0(path)[1])
  if (!ullme_safe_relative_material_path(path)) stop(label, " must be a safe relative path.")
  path
}


ullme_tool_change_result = function(result) {
  list(
    ok=isTRUE(result$ok),
    status=result$status %||% if (isTRUE(result$ok)) "committed" else "error",
    operation_id=result$id %||% "",
    message=result$message %||% ""
  )
}


utool_cur_user = function(app=getApp()) {
  list(
    userid=app$userid,
    role=app$role,
    allowed_roles=as.list(app$allowed_roles)
  )
}


utool_list_courses = function(semester="sel", app=getApp()) {
  semester = ullme_tool_semester(semester, app=app)
  list(
    semester=semester,
    courseids=as.list(ullme_user_courseids(
      main_dir=app$glob$main_dir,
      userid=app$userid,
      role="teacher",
      semester=semester
    ))
  )
}


utool_list_material_files = function(courseid, semester="sel",
                                      category="", app=getApp()) {
  course_dir = ullme_tool_course_dir(semester, courseid, app=app)
  files = ullme_course_material_files(course_dir)
  category = paste0(category %||% "")[1]
  if (nzchar(category)) {
    if (!category %in% names(files)) stop("Invalid material category.")
    files = files[category]
  }
  lapply(files, as.list)
}


utool_read_definition_yaml = function(kind, definitionid, source,
                                       app=getApp()) {
  kind = ullme_definition_kind(kind)
  definitionid = ullme_clean_definition_id(definitionid)
  directory = ullme_definition_dir(kind, definitionid, source, app=app)
  filename = if (identical(kind, "tutor")) "tutor.yaml" else "ullme.yaml"
  path = file.path(directory, filename)
  if (!file.exists(path)) stop("The requested definition YAML does not exist.")
  list(
    kind=kind,
    definitionid=definitionid,
    source=source,
    filename=filename,
    content=paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n")
  )
}


utool_list_ai_tutors = function(app=getApp()) {
  lapply(ullme_ai_tutor_catalog(app=app), function(tutor) {
    list(
      tutorid=tutor$tutorid,
      label=tutor$label,
      source=tutor$source,
      description=tutor$description,
      required_material_roles=tutor$required_material_roles
    )
  })
}


utool_list_skills = function(app=getApp()) {
  lapply(ullme_skill_catalog(app=app), function(skill) {
    list(
      skillid=skill$skillid,
      label=skill$label,
      source=skill$source,
      description=skill$description
    )
  })
}


ullme_tool_course_file_path = function(course_dir, path, must_exist=TRUE) {
  path = ullme_tool_relative_path(path, "path")
  target = normalizePath(file.path(course_dir, path), winslash="/", mustWork=FALSE)
  root = normalizePath(course_dir, winslash="/", mustWork=TRUE)
  if (!ullme_path_is_within(target, root, allow_root=FALSE)) {
    stop("The requested file is outside the course.")
  }
  if (isTRUE(must_exist) && (!file.exists(target) || dir.exists(target))) {
    stop("The requested course file does not exist.")
  }
  target
}


utool_read_course_file = function(courseid, path, semester="sel",
                                   app=getApp()) {
  course_dir = ullme_tool_course_dir(semester, courseid, app=app)
  target = ullme_tool_course_file_path(course_dir, path, must_exist=TRUE)
  if (!ullme_file_is_text(target)) stop("The requested course file is binary.")
  if (file.info(target)$size > 2 * 1024^2) stop("The requested text file is larger than 2 MB.")
  list(
    courseid=courseid,
    semester=ullme_tool_semester(semester, app=app),
    path=gsub("\\\\", "/", path),
    content=paste(readLines(target, warn=FALSE, encoding="UTF-8"), collapse="\n"),
    hash=ullme_path_hash(target)
  )
}


utool_list_object_types = function(app=getApp()) {
  lapply(ullme_object_type_ids(), function(oid) {
    value = ullme_read_object_type(oid)
    list(
      oid=oid,
      name=value$name,
      type=value$type,
      doc_dir=value$doc_dir %||% NULL,
      linked_to=value$linked_to %||% NULL,
      progresses=value$progresses %||% NULL,
      description=value$descr
    )
  })
}


utool_read_object_index = function(courseid, oid, semester="sel",
                                    app=getApp()) {
  course_dir = ullme_tool_course_dir(semester, courseid, app=app)
  path = ullme_existing_course_object_index_path(course_dir, oid)
  if (!file.exists(path)) {
    return(list(ok=TRUE, exists=FALSE, oid=oid, objects=list()))
  }
  content = paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n")
  validation = ullme_validate_object_index_yaml(content, oid, course_dir)
  list(
    ok=validation$ok,
    exists=TRUE,
    oid=oid,
    content=content,
    warnings=validation$warnings,
    errors=validation$errors
  )
}


utool_list_changes = function(limit=20, app=getApp()) {
  limit = max(1L, min(100L, as.integer(limit)))
  ullme_change_history(app=app, limit=limit)
}


utool_change_status = function(operation_id, app=getApp()) {
  operation_id = paste0(operation_id)[1]
  if (!is.null(app$pending_changes[[operation_id]])) {
    return(list(ok=TRUE, operation_id=operation_id, status="pending_approval"))
  }
  result = app$change_results[[operation_id]]
  if (!is.null(result)) return(result)
  history = ullme_change_history(app=app, limit=1000L)
  found = Filter(function(entry) identical(entry$id, operation_id), history)
  if (length(found) > 0) return(found[[1]])
  list(ok=FALSE, operation_id=operation_id, status="unknown",
       message="No change with this operation ID was found.")
}


utool_change_status = function(operation_id, app=getApp()) {
  operation_id = paste0(operation_id)[1]
  if (!is.null(app$pending_changes[[operation_id]])) {
    return(list(ok=TRUE, operation_id=operation_id, status="pending_approval"))
  }
  result = app$change_results[[operation_id]]
  if (!is.null(result)) return(result)
  history = ullme_change_history(app=app, limit=1000L)
  found = Filter(function(entry) identical(entry$id, operation_id), history)
  if (length(found) > 0) return(found[[1]])
  list(ok=FALSE, operation_id=operation_id, status="unknown",
       message="No change with this operation ID was found.")
}


utool_copy_material = function(source_courseid, source_category, source_path,
                                target_courseid, target_category,
                                source_semester="sel", target_semester="sel",
                                target_path="", overwrite=FALSE,
                                app=getApp()) {
  source_dir = ullme_tool_course_dir(source_semester, source_courseid, app=app)
  target_dir = ullme_tool_course_dir(target_semester, target_courseid, app=app)
  if (!source_category %in% ullme_course_material_categories() ||
      !target_category %in% ullme_course_material_categories()) {
    stop("Invalid material category.")
  }
  source_path = ullme_tool_relative_path(source_path, "source_path")
  target_path = paste0(target_path %||% "")[1]
  if (!nzchar(target_path)) target_path = basename(source_path)
  target_path = ullme_tool_relative_path(target_path, "target_path")
  source = file.path(ullme_course_material_dir(source_dir, source_category), source_path)
  target = file.path(ullme_course_material_dir(target_dir, target_category), target_path)
  if (!file.exists(source) || dir.exists(source)) stop("The source material file does not exist.")

  operation = ullme_new_change(
    action="copy_materials",
    summary=paste0("Copy material ", basename(source), " to ", target_courseid,
                   "/", target_category, "/", target_path),
    origin="agent",
    details=list(
      source_courseid=source_courseid,
      target_courseid=target_courseid
    ),
    changes=list(ullme_change_copy(source, target, overwrite=overwrite)),
    app=app
  )
  ullme_tool_change_result(ullme_submit_change(operation, app=app))
}


utool_rewrite_definition_yaml = function(kind, definitionid, source,
                                          yaml_content, app=getApp()) {
  kind = ullme_definition_kind(kind)
  definitionid = ullme_clean_definition_id(definitionid)
  source = paste0(source)[1]
  if (!ullme_definition_is_editable(kind, source, app=app)) {
    stop("Only personal definitions and course-local Tutor definitions are editable.")
  }
  validation = ullme_validate_definition_yaml(kind, definitionid, yaml_content)
  ullme_validation_stop(validation)
  directory = ullme_definition_dir(kind, definitionid, source, app=app)
  filename = if (identical(kind, "tutor")) "tutor.yaml" else "ullme.yaml"
  target = file.path(directory, filename)
  if (!file.exists(target)) stop("The requested definition YAML does not exist.")

  operation = ullme_new_change(
    action="rewrite_definitions",
    summary=paste0("Rewrite ", kind, " definition ", definitionid, "/", filename),
    origin="agent",
    details=list(kind=kind, definitionid=definitionid, source=source),
    changes=list(ullme_change_write(target, yaml_content)),
    app=app
  )
  ullme_tool_change_result(ullme_submit_change(operation, app=app))
}


utool_rewrite_course_text_file = function(courseid, path, content,
                                           semester="sel", app=getApp()) {
  course_dir = ullme_tool_course_dir(semester, courseid, app=app)
  path = ullme_tool_relative_path(path, "path")
  target = ullme_tool_course_file_path(course_dir, path, must_exist=TRUE)
  if (!ullme_file_is_text(target)) stop("Binary files cannot be rewritten as text.")
  if (nchar(content, type="bytes") > 2 * 1024^2) {
    stop("Text files must be no larger than 2 MB.")
  }
  validation = ullme_validate_course_file_content(
    path=path,
    content=content,
    app=app,
    course_dir=course_dir
  )
  ullme_validation_stop(validation)
  change = ullme_change_write(target, content)
  change$warnings = validation$warnings
  operation = ullme_new_change(
    action="rewrite_course_files",
    summary=paste0("Rewrite course file ", courseid, "/", path),
    origin="agent",
    details=list(courseid=courseid, path=path),
    changes=list(change),
    app=app
  )
  ullme_tool_change_result(ullme_submit_change(operation, app=app))
}


utool_write_object_index = function(courseid, oid, yaml_content,
                                     semester="sel", app=getApp()) {
  course_dir = ullme_tool_course_dir(semester, courseid, app=app)
  oid = ullme_clean_object_id(oid)
  validation = ullme_validate_object_index_yaml(
    yaml_content,
    oid=oid,
    course_dir=course_dir,
    require_files=TRUE
  )
  ullme_validation_stop(validation)
  target = ullme_course_object_index_path(course_dir, oid)
  change = ullme_change_write(target, yaml_content)
  change$warnings = validation$warnings
  operation = ullme_new_change(
    action="write_object_indexes",
    summary=paste0("Write ", oid, " object index for ", courseid),
    origin="agent",
    details=list(courseid=courseid, oid=oid),
    changes=list(change),
    app=app
  )
  ullme_tool_change_result(ullme_submit_change(operation, app=app))
}


utool_undo_change = function(operation_id="last", app=getApp()) {
  ullme_tool_change_result(ullme_undo_change(
    operation_id=operation_id,
    origin="agent",
    app=app
  ))
}
