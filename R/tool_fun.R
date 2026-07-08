ullme_tool_course_dir = function(semester="sel", courseid, app=getApp()) {
  restore.point("ullme_tool_course_dir")
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
  restore.point("ullme_tool_relative_path")
  path = gsub("\\\\", "/", paste0(path)[1])
  if (!ullme_safe_relative_material_path(path)) stop(label, " must be a safe relative path.")
  path
}


ullme_tool_change_result = function(result) {
  restore.point("ullme_tool_change_result")
  list(
    ok=isTRUE(result$ok),
    status=result$status %||% if (isTRUE(result$ok)) "committed" else "error",
    operation_id=result$id %||% "",
    message=result$message %||% ""
  )
}


utool_cur_user = function(app=getApp()) {
  restore.point("utool_cur_user")
  list(
    userid=app$userid,
    role=app$role,
    allowed_roles=as.list(app$allowed_roles)
  )
}


utool_list_courses = function(semester="sel", app=getApp()) {
  restore.point("utool_list_courses")
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
  restore.point("utool_list_material_files")
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
  restore.point("utool_read_definition_yaml")
  kind = ullme_definition_kind(kind)
  definitionid = ullme_clean_definition_id(definitionid)
  if (identical(kind, "tutor")) {
    path = if (identical(source, "course")) {
      course_dir = ullme_active_course_dir(app=app)
      if (is.null(course_dir)) NULL else
        ullme_existing_course_ai_tutor_path(course_dir, definitionid)
    } else if (identical(source, "package")) {
      ullme_ai_tutor_template_path(definitionid)
    } else {
      NULL
    }
    filename = if (is.null(path)) "tutor.yml" else basename(path)
  } else {
    directory = ullme_definition_dir(kind, definitionid, source, app=app)
    filename = "ullme.yaml"
    path = file.path(directory, filename)
  }
  if (is.null(path) || !file.exists(path)) {
    stop("The requested definition YAML does not exist.")
  }
  list(
    kind=kind,
    definitionid=definitionid,
    source=source,
    filename=filename,
    content=paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n")
  )
}


utool_list_ai_tutors = function(app=getApp()) {
  restore.point("utool_list_ai_tutors")
  lapply(ullme_course_ai_tutors(app=app), function(tutor) {
    list(
      tutorid=tutor$tutorid,
      label=tutor$label,
      description=tutor$description,
      enabled=tutor$enabled,
      instance_count=tutor$instance_count,
      docs_per_instance=tutor$doc_ids_per_instance,
      placeholder_documents=tutor$placeholder_document_ids
    )
  })
}


utool_read_tutor_instances_yaml = function(tutorid, app=getApp()) {
  restore.point("utool_read_tutor_instances_yaml")
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) stop("Select a course first.")
  tutorid = ullme_clean_definition_id(tutorid)
  tutor_path = ullme_existing_course_ai_tutor_path(course_dir, tutorid)
  if (!file.exists(tutor_path)) stop("The requested course AI Tutor does not exist.")
  instance_data = ullme_read_course_ai_tutor_instances(course_dir, tutorid)
  list(
    tutorid=tutorid,
    filename="instances.yml",
    content=ullme_course_ai_tutor_instances_yaml(
      course_dir=course_dir,
      tutorid=tutorid,
      instances=instance_data$instances,
      course_docs=instance_data$course_docs
    )
  )
}


utool_list_skills = function(app=getApp()) {
  restore.point("utool_list_skills")
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
  restore.point("ullme_tool_course_file_path")
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
  restore.point("utool_read_course_file")
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


utool_list_changes = function(limit=20, app=getApp()) {
  restore.point("utool_list_changes")
  limit = max(1L, min(100L, as.integer(limit)))
  ullme_change_history(app=app, limit=limit)
}


utool_change_status = function(operation_id, app=getApp()) {
  restore.point("utool_change_status")
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
  restore.point("utool_change_status")
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
  restore.point("utool_copy_material")
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
  result = ullme_submit_change(operation, app=app)
  if (isTRUE(result$ok) && identical(result$status, "committed") &&
      !isTRUE(app$headless)) {
    ullme_send_course_state(app=app)
  }
  ullme_tool_change_result(result)
}


utool_rewrite_definition_yaml = function(kind, definitionid, source,
                                          yaml_content, app=getApp()) {
  restore.point("utool_rewrite_definition_yaml")
  kind = ullme_definition_kind(kind)
  definitionid = ullme_clean_definition_id(definitionid)
  source = paste0(source)[1]
  if (!ullme_definition_is_editable(kind, source, app=app)) {
    stop("Only course AI Tutors and personal Skills are editable.")
  }
  validation = ullme_validate_definition_yaml(kind, definitionid, yaml_content)
  ullme_validation_stop(validation)
  if (identical(kind, "tutor")) {
    course_dir = ullme_active_course_dir(app=app)
    if (!identical(source, "course") || is.null(course_dir)) {
      stop("AI Tutor rewrites target the selected course copy.")
    }
    target = ullme_existing_course_ai_tutor_path(course_dir, definitionid)
    filename = basename(target)
  } else {
    directory = ullme_definition_dir(kind, definitionid, source, app=app)
    filename = "ullme.yaml"
    target = file.path(directory, filename)
  }
  if (!file.exists(target)) stop("The requested definition YAML does not exist.")

  operation = ullme_new_change(
    action="rewrite_definitions",
    summary=paste0("Rewrite ", kind, " definition ", definitionid, "/", filename),
    origin="agent",
    details=list(kind=kind, definitionid=definitionid, source=source),
    changes=list(ullme_change_write(target, yaml_content)),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  if (isTRUE(result$ok) && identical(result$status, "committed") &&
      !isTRUE(app$headless)) {
    ullme_send_course_state(app=app)
  }
  ullme_tool_change_result(result)
}


utool_rewrite_tutor_instances_yaml = function(tutorid, yaml_content,
                                               app=getApp()) {
  restore.point("utool_rewrite_tutor_instances_yaml")
  result = ullme_save_course_ai_tutor_instances_yaml(
    tutorid=tutorid,
    yaml_content=yaml_content,
    origin="agent",
    app=app
  )
  if (isTRUE(result$ok) && identical(result$status, "committed") &&
      !isTRUE(app$headless)) {
    ullme_send_course_state(app=app)
  }
  ullme_tool_change_result(result)
}


ullme_rtutor_instances_yaml_info = function(tutorid, yaml_content) {
  restore.point("ullme_rtutor_instances_yaml_info")
  parsed = ullme_parse_yaml_text(
    paste0(yaml_content %||% "", collapse="\n"),
    "instances.yml"
  )
  ullme_validation_stop(parsed)
  value = parsed$value
  instances = value$instances %||% list()
  course_docs = value$course_docs %||% list()
  instance_ids = vapply(instances, function(instance) {
    paste0(instance$instanceid %||% "")[1]
  }, character(1))
  assigned_files = unique(paste0(unlist(c(
    course_docs,
    lapply(instances, function(instance) instance$docs %||% list())
  ), recursive=TRUE, use.names=FALSE)))
  assigned_files = assigned_files[nzchar(assigned_files)]
  list(
    valid=TRUE,
    tutorid=tutorid,
    filename="instances.yml",
    instance_count=length(instances),
    instance_ids=as.list(instance_ids),
    course_document_roles=as.list(names(course_docs)),
    assigned_file_count=length(assigned_files),
    assigned_files=as.list(assigned_files)
  )
}


utool_write_rtutor_instances_yaml = function(tutorid, yaml_content,
                                               app=getApp()) {
  restore.point("utool_write_rtutor_instances_yaml")
  tutorid = ullme_clean_definition_id(tutorid)
  result = ullme_save_course_ai_tutor_instances_yaml(
    tutorid=tutorid,
    yaml_content=yaml_content,
    origin="instance_builder",
    app=app
  )
  info = ullme_rtutor_instances_yaml_info(tutorid, yaml_content)
  if (isTRUE(result$ok) && identical(result$status, "committed") &&
      !isTRUE(app$headless)) {
    ullme_send_course_state(app=app)
  }
  c(ullme_tool_change_result(result), list(validation=info))
}


utool_convert_material_files = function(courseid, paths, tutorid,
                                         semester="sel", from="",
                                         to="preferred", overwrite=FALSE,
                                         app=getApp()) {
  restore.point("utool_convert_material_files")
  course_dir = ullme_tool_course_dir(semester, courseid, app=app)
  result = ullme_convert_material_files(
    paths=paths,
    to=to,
    from=from,
    tutorid=tutorid,
    overwrite=overwrite,
    origin="agent",
    course_dir=course_dir,
    app=app
  )
  if (isTRUE(result$ok) && identical(result$status, "committed") &&
      !isTRUE(app$headless)) {
    ullme_send_course_state(app=app)
  }
  result
}


utool_rewrite_course_text_file = function(courseid, path, content,
                                           semester="sel", app=getApp()) {
  restore.point("utool_rewrite_course_text_file")
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


utool_undo_change = function(operation_id="last", app=getApp()) {
  restore.point("utool_undo_change")
  ullme_tool_change_result(ullme_undo_change(
    operation_id=operation_id,
    origin="agent",
    app=app
  ))
}
