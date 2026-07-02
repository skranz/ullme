ullme_definition_kind = function(kind) {
  restore.point("ullme_definition_kind")
  kind = tolower(paste0(kind)[1])
  if (kind %in% c("tutor", "tutors", "ai_tutor", "ai_tutors")) return("tutor")
  if (kind %in% c("skill", "skills")) return("skill")
  stop("Definition kind must be 'tutor' or 'skill'.")
}


ullme_definition_roots = function(kind, app=getApp()) {
  restore.point("ullme_definition_roots")
  kind = ullme_definition_kind(kind)
  if (identical(kind, "tutor")) {
    return(ullme_ai_tutor_definition_roots(app=app))
  }
  ullme_skill_roots(app=app)
}


ullme_definition_dir = function(kind, definitionid, source, app=getApp()) {
  restore.point("ullme_definition_dir")
  kind = ullme_definition_kind(kind)
  definitionid = ullme_clean_definition_id(definitionid)
  roots = ullme_definition_roots(kind=kind, app=app)
  source = paste0(source)[1]
  if (is.na(source) || !source %in% names(roots)) stop("Invalid definition source.")
  root = roots[[source]]
  if (length(root) == 0) stop("The requested definition source is unavailable.")
  file.path(root, definitionid)
}


ullme_definition_metadata_at = function(kind, definitionid, source, app=getApp()) {
  restore.point("ullme_definition_metadata_at")
  kind = ullme_definition_kind(kind)
  if (identical(kind, "tutor")) {
    return(ullme_ai_tutor_definition_at(
      tutorid=definitionid,
      source=source,
      app=app
    ))
  }
  ullme_skill_definition_at(
    skillid=definitionid,
    source=source,
    app=app,
    include_instructions=FALSE
  )
}


ullme_definition_is_editable = function(kind, source, app=getApp()) {
  restore.point("ullme_definition_is_editable")
  if (!identical(app$role, "teacher")) return(FALSE)
  kind = ullme_definition_kind(kind)
  source = paste0(source)[1]
  identical(source, "personal") ||
    (identical(kind, "tutor") && identical(source, "course"))
}


ullme_definition_library = function(app=getApp()) {
  restore.point("ullme_definition_library")
  library = list()
  for (kind in c("tutor", "skill")) {
    roots = ullme_definition_roots(kind=kind, app=app)
    for (source in names(roots)) {
      ids = ullme_definition_ids(roots[[source]])
      for (definitionid in ids) {
        metadata = ullme_definition_metadata_at(
          kind=kind,
          definitionid=definitionid,
          source=source,
          app=app
        )
        if (is.null(metadata)) next
        metadata$instructions = NULL
        metadata$id = definitionid
        metadata$kind = kind
        metadata$source = source
        metadata$editable = ullme_definition_is_editable(
          kind=kind,
          source=source,
          app=app
        )
        library[[length(library) + 1L]] = metadata
      }
    }
  }
  if (length(library) == 0) return(list())

  source_order = c("course", "personal", "general", "package")
  ord = order(
    vapply(library, function(x) match(x$kind, c("tutor", "skill")), integer(1)),
    vapply(library, function(x) match(x$source, source_order), integer(1)),
    tolower(vapply(library, function(x) x$label, character(1)))
  )
  library[ord]
}


ullme_definition_text_files = function(definition_dir) {
  restore.point("ullme_definition_text_files")
  if (!dir.exists(definition_dir)) return(character(0))
  files = list.files(
    definition_dir,
    recursive=TRUE,
    full.names=FALSE,
    all.files=TRUE,
    no..=TRUE,
    include.dirs=FALSE
  )
  files = gsub("\\\\", "/", files)
  files = files[grepl("\\.(md|ya?ml)$", files, ignore.case=TRUE)]
  files = files[file.exists(file.path(definition_dir, files))]
  sort(unique(files))
}


ullme_definition_file_records = function(definition_dir, editable=FALSE, max_bytes=1024^2) {
  restore.point("ullme_definition_file_records")
  files = ullme_definition_text_files(definition_dir=definition_dir)
  lapply(files, function(file) {
    path = file.path(definition_dir, file)
    size = file.info(path)$size
    too_large = is.na(size) || size > max_bytes
    content = if (too_large) {
      "This file is too large to display in the definition editor."
    } else {
      paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n")
    }
    list(
      path=file,
      content=content,
      editable=isTRUE(editable) && !too_large,
      size=if (is.na(size)) NULL else unname(size)
    )
  })
}


ullme_definition_exists_at = function(kind, definitionid, source, app=getApp()) {
  restore.point("ullme_definition_exists_at")
  !is.null(tryCatch(
    ullme_definition_metadata_at(
      kind=kind,
      definitionid=definitionid,
      source=source,
      app=app
    ),
    error=function(e) NULL
  ))
}


ullme_definition_workspace_payload = function(kind="tutor", definitionid=NULL,
                                               source=NULL, app=getApp(),
                                               notice=NULL, error=NULL,
                                               draft=NULL) {
  restore.point("ullme_definition_workspace_payload")
  kind = ullme_definition_kind(kind)
  library = ullme_definition_library(app=app)
  same_kind = which(vapply(library, function(x) identical(x$kind, kind), logical(1)))

  definitionid = paste0(definitionid %||% "")[1]
  source = paste0(source %||% "")[1]
  selected_index = integer(0)
  if (nzchar(definitionid)) {
    selected_index = which(vapply(library, function(x) {
      identical(x$kind, kind) &&
        identical(x$id, definitionid) &&
        (!nzchar(source) || identical(x$source, source))
    }, logical(1)))
  }
  if (length(selected_index) == 0 && length(same_kind) > 0) {
    selected_index = same_kind[[1]]
  }

  selected = NULL
  if (length(selected_index) > 0) {
    selected = library[[selected_index[[1]]]]
    definition_dir = ullme_definition_dir(
      kind=selected$kind,
      definitionid=selected$id,
      source=selected$source,
      app=app
    )
    selected$files = ullme_definition_file_records(
      definition_dir=definition_dir,
      editable=selected$editable
    )
    selected$personal_exists = ullme_definition_exists_at(
      kind=selected$kind,
      definitionid=selected$id,
      source="personal",
      app=app
    )
    selected$course_exists = identical(selected$kind, "tutor") &&
      ullme_definition_exists_at(
        kind="tutor",
        definitionid=selected$id,
        source="course",
        app=app
      )
    selected$can_make_personal = !identical(selected$source, "personal")
    selected$can_customize_course = identical(selected$kind, "tutor") &&
      !is.null(ullme_active_course_dir(app=app)) &&
      !identical(selected$source, "course")
    selected$can_delete = selected$editable &&
      selected$source %in% c("personal", "course")
  }

  list(
    kind=kind,
    library=library,
    selected=selected,
    can_create=isTRUE(identical(app$role, "teacher")),
    courseid=app$courseid %||% "",
    notice=notice,
    error=error,
    draft=draft
  )
}


ullme_send_definition_workspace = function(kind="tutor", definitionid=NULL,
                                            source=NULL, app=getApp(),
                                            notice=NULL, error=NULL,
                                            draft=NULL) {
  restore.point("ullme_send_definition_workspace")
  payload = ullme_definition_workspace_payload(
    kind=kind,
    definitionid=definitionid,
    source=source,
    app=app,
    notice=notice,
    error=error,
    draft=draft
  )
  callJS(
    .fun="window.ullme.openDefinitionWorkspace",
    .args=list(payload),
    .app=app
  )
  invisible(payload)
}


ullme_validate_definition_content = function(kind, definitionid, file, content) {
  restore.point("ullme_validate_definition_content")
  kind = ullme_definition_kind(kind)
  definitionid = ullme_clean_definition_id(definitionid)
  file = gsub("\\\\", "/", paste0(file)[1])
  content = paste0(content, collapse="\n")
  if (nchar(content, type="bytes") > 2 * 1024^2) {
    stop("Definition files must be no larger than 2 MB.")
  }

  if (grepl("\\.ya?ml$", file, ignore.case=TRUE)) {
    core_yaml = (identical(kind, "tutor") && identical(file, "tutor.yaml")) ||
      (identical(kind, "skill") && identical(file, "ullme.yaml"))
    if (core_yaml) {
      result = ullme_validate_definition_yaml(
        kind=kind,
        definitionid=definitionid,
        content=content
      )
    } else {
      result = ullme_parse_yaml_text(content, file)
    }
    ullme_validation_stop(result)
  }
  if (identical(kind, "skill") && identical(file, "SKILL.md") &&
      !nzchar(trimws(content))) {
    stop("SKILL.md must not be empty.")
  }
  TRUE
}


ullme_save_definition_file = function(kind, definitionid, source, file, content,
                                       app=getApp()) {
  restore.point("ullme_save_definition_file")
  kind = ullme_definition_kind(kind)
  definitionid = ullme_clean_definition_id(definitionid)
  source = paste0(source)[1]
  if (!ullme_definition_is_editable(kind=kind, source=source, app=app)) {
    stop("This definition is read-only.")
  }

  definition_dir = ullme_definition_dir(
    kind=kind,
    definitionid=definitionid,
    source=source,
    app=app
  )
  file = gsub("\\\\", "/", paste0(file)[1])
  available = ullme_definition_text_files(definition_dir=definition_dir)
  if (is.na(file) || !file %in% available) stop("Invalid definition file.")
  ullme_validate_definition_content(
    kind=kind,
    definitionid=definitionid,
    file=file,
    content=content
  )

  target = file.path(definition_dir, file)
  operation = ullme_new_change(
    action="definition_edit",
    summary=paste0("Save ", kind, " definition ", definitionid, "/", file),
    origin="ui",
    details=list(kind=kind, definitionid=definitionid, source=source),
    changes=list(ullme_change_write(target, content)),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  isTRUE(result$ok)
}


ullme_copy_definition_dir = function(source_dir, target_dir, app=getApp()) {
  restore.point("ullme_copy_definition_dir")
  if (!dir.exists(source_dir)) stop("The source definition does not exist.")
  if (dir.exists(target_dir) || file.exists(target_dir)) {
    stop("The target definition already exists.")
  }

  parent = dirname(target_dir)
  dir.create(parent, recursive=TRUE, showWarnings=FALSE)
  stage = ullme_tempdir(pattern=".ullme-copy-", app=app)
  on.exit(ullme_remove_tempdir(stage, app=app), add=TRUE)

  files = list.files(
    source_dir,
    recursive=TRUE,
    full.names=FALSE,
    all.files=TRUE,
    no..=TRUE,
    include.dirs=FALSE
  )
  for (file in files) {
    source = file.path(source_dir, file)
    target = file.path(stage, file)
    dir.create(dirname(target), recursive=TRUE, showWarnings=FALSE)
    if (!file.copy(source, target, overwrite=FALSE)) {
      stop("Could not copy definition file: ", file)
    }
  }
  if (!file.rename(stage, target_dir)) stop("Could not finish copying the definition.")
  TRUE
}


ullme_copy_definition = function(kind, definitionid, source, target_source,
                                  app=getApp()) {
  restore.point("ullme_copy_definition")
  if (!identical(app$role, "teacher")) stop("Only teachers can copy definitions.")
  kind = ullme_definition_kind(kind)
  definitionid = ullme_clean_definition_id(definitionid)
  source = paste0(source)[1]
  target_source = paste0(target_source)[1]
  if (!target_source %in% c("personal", "course")) stop("Invalid copy destination.")
  if (identical(target_source, "course") && !identical(kind, "tutor")) {
    stop("Only AI Tutor definitions can be customized for a course.")
  }
  if (identical(target_source, "course") && is.null(ullme_active_course_dir(app=app))) {
    stop("Select a course before creating a course-local definition.")
  }

  source_metadata = ullme_definition_metadata_at(
    kind=kind,
    definitionid=definitionid,
    source=source,
    app=app
  )
  if (is.null(source_metadata)) stop("The source definition does not exist.")
  if (ullme_definition_exists_at(
    kind=kind,
    definitionid=definitionid,
    source=target_source,
    app=app
  )) {
    return(FALSE)
  }

  source_dir = ullme_definition_dir(
    kind=kind,
    definitionid=definitionid,
    source=source,
    app=app
  )
  target_dir = ullme_definition_dir(
    kind=kind,
    definitionid=definitionid,
    source=target_source,
    app=app
  )
  operation = ullme_new_change(
    action="definition_copy",
    summary=paste0("Create ", target_source, " copy of ", kind, " ", definitionid),
    origin="ui",
    details=list(
      kind=kind,
      definitionid=definitionid,
      source=source,
      target_source=target_source
    ),
    changes=list(ullme_change_copy(source_dir, target_dir, overwrite=FALSE)),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  isTRUE(result$ok)
}


ullme_create_definition = function(kind, definitionid, label="", app=getApp()) {
  restore.point("ullme_create_definition")
  if (!identical(app$role, "teacher")) stop("Only teachers can create definitions.")
  kind = ullme_definition_kind(kind)
  definitionid = ullme_clean_definition_id(definitionid)
  label = trimws(paste0(label)[1])
  if (!nzchar(label)) label = definitionid
  if (ullme_definition_exists_at(
    kind=kind,
    definitionid=definitionid,
    source="personal",
    app=app
  )) {
    stop("A personal definition with this ID already exists.")
  }

  target_dir = ullme_definition_dir(
    kind=kind,
    definitionid=definitionid,
    source="personal",
    app=app
  )
  if (dir.exists(target_dir) || file.exists(target_dir)) {
    stop("A personal definition directory with this ID already exists.")
  }
  stage = ullme_tempdir(pattern=".ullme-definition-create-", app=app)
  on.exit(ullme_remove_tempdir(stage, app=app), add=TRUE)
  if (identical(kind, "tutor")) {
    yaml::write_yaml(
      list(
        tutorid=definitionid,
        label=label,
        description="Describe what this AI Tutor helps students do.",
        pedagogical_instructions="Add the tutor's pedagogical instructions here.",
        required_material_roles=list(),
        allowed_tools=list()
      ),
      file.path(stage, "tutor.yaml")
    )
  } else {
    frontmatter = trimws(yaml::as.yaml(list(
      name=label,
      description="Describe the recurring task this Skill performs."
    )))
    writeLines(
      c(
        "---",
        strsplit(frontmatter, "\n", fixed=TRUE)[[1]],
        "---",
        "",
        paste0("# ", label),
        "",
        "Add the Skill instructions here."
      ),
      file.path(stage, "SKILL.md"),
      useBytes=TRUE
    )
    yaml::write_yaml(
      list(
        skillid=definitionid,
        label=label,
        description="Describe the recurring task this Skill performs.",
        intro="Introduce the Skill to the teacher.",
        starter_prompts=list(),
        composer_placeholder="Describe what you want to create",
        required_course_inputs=list(),
        expected_outputs=list(),
        required_tools=list()
      ),
      file.path(stage, "ullme.yaml")
    )
  }
  operation = ullme_new_change(
    action="definition_create",
    summary=paste0("Create personal ", kind, " definition ", definitionid),
    origin="ui",
    details=list(kind=kind, definitionid=definitionid, source="personal"),
    changes=list(ullme_change_copy(stage, target_dir, overwrite=FALSE)),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  isTRUE(result$ok)
}


ullme_delete_definition_copy = function(kind, definitionid, source, app=getApp()) {
  restore.point("ullme_delete_definition_copy")
  if (!identical(app$role, "teacher")) stop("Only teachers can delete definitions.")
  kind = ullme_definition_kind(kind)
  definitionid = ullme_clean_definition_id(definitionid)
  source = paste0(source)[1]
  if (!source %in% c("personal", "course") ||
      !ullme_definition_is_editable(kind=kind, source=source, app=app)) {
    stop("Only Personal and course-local definition copies can be deleted.")
  }
  if (identical(source, "course") && !identical(kind, "tutor")) {
    stop("Skills do not have course-local definitions.")
  }
  if (!ullme_definition_exists_at(
    kind=kind,
    definitionid=definitionid,
    source=source,
    app=app
  )) {
    stop("The definition copy no longer exists.")
  }

  definition_dir = ullme_definition_dir(
    kind=kind,
    definitionid=definitionid,
    source=source,
    app=app
  )
  operation = ullme_new_change(
    action="definition_delete",
    summary=paste0("Delete ", source, " ", kind, " definition ", definitionid),
    origin="ui",
    details=list(kind=kind, definitionid=definitionid, source=source),
    changes=list(ullme_change_delete(definition_dir)),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  if (!isTRUE(result$ok)) stop(result$message %||% "Could not delete the definition copy.")

  if (identical(kind, "tutor")) {
    return(ullme_ai_tutor_definition(definitionid, app=app))
  }
  ullme_skill_definition(definitionid, app=app, include_instructions=FALSE)
}


ullme_handle_definition_action = function(action="open", kind="tutor",
                                           definitionid=NULL, source=NULL,
                                           file=NULL, content=NULL, label=NULL,
                                           import_token=NULL, target_source=NULL,
                                           replace=FALSE,
                                           app=getApp(), ...) {
  restore.point("ullme_handle_definition_action")
  if (!identical(app$role, "teacher")) return(invisible(FALSE))
  action = paste0(action)[1]
  kind = tryCatch(ullme_definition_kind(kind), error=function(e) "tutor")
  definitionid = paste0(definitionid %||% "")[1]
  source = paste0(source %||% "")[1]
  notice = NULL
  error = NULL
  draft = NULL

  result = tryCatch({
    if (identical(action, "save")) {
      ullme_save_definition_file(
        kind=kind,
        definitionid=definitionid,
        source=source,
        file=file,
        content=content,
        app=app
      )
      notice = paste0(basename(file), " saved.")
    } else if (identical(action, "copy-personal")) {
      copied = ullme_copy_definition(
        kind=kind,
        definitionid=definitionid,
        source=source,
        target_source="personal",
        app=app
      )
      source = "personal"
      notice = if (copied) "Personal copy created." else "Opened the existing personal copy."
    } else if (identical(action, "copy-course")) {
      copied = ullme_copy_definition(
        kind=kind,
        definitionid=definitionid,
        source=source,
        target_source="course",
        app=app
      )
      source = "course"
      notice = if (copied) "Course-local Tutor definition created." else "Opened the existing course-local definition."
    } else if (identical(action, "create")) {
      ullme_create_definition(
        kind=kind,
        definitionid=definitionid,
        label=label,
        app=app
      )
      source = "personal"
      notice = if (identical(kind, "tutor")) "AI Tutor definition created." else "Skill created."
    } else if (identical(action, "delete")) {
      fallback = ullme_delete_definition_copy(
        kind=kind,
        definitionid=definitionid,
        source=source,
        app=app
      )
      source = ""
      notice = if (is.null(fallback)) {
        "Definition copy deleted. No fallback definition is available."
      } else {
        paste0("Definition copy deleted. Now using the ", fallback$source, " definition.")
      }
    } else if (identical(action, "download")) {
      ullme_prepare_definition_download(
        kind=kind,
        definitionid=definitionid,
        source=source,
        app=app
      )
    } else if (identical(action, "import")) {
      imported = ullme_apply_definition_import(
        token=import_token,
        target_source=target_source,
        replace=isTRUE(replace),
        app=app
      )
      kind = imported$kind
      definitionid = imported$id
      source = imported$source
      notice = imported$notice
    } else if (!identical(action, "open")) {
      stop("Unknown definition action.")
    }
    TRUE
  }, error=function(e) {
    error <<- conditionMessage(e)
    if (identical(action, "save")) {
      draft <<- list(file=paste0(file)[1], content=paste0(content, collapse="\n"))
    }
    FALSE
  })

  if (isTRUE(result) && !action %in% c("open", "download")) {
    ullme_send_course_state(app=app)
  }
  if (isTRUE(result) && identical(action, "download")) return(invisible(TRUE))
  ullme_send_definition_workspace(
    kind=kind,
    definitionid=definitionid,
    source=source,
    app=app,
    notice=notice,
    error=error,
    draft=draft
  )
  invisible(result)
}
