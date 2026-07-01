ullme_course_organization_payload = function(course_dir) {
  types = lapply(ullme_object_type_ids(), function(oid) {
    type = ullme_read_object_type(oid)
    list(
      oid=oid,
      name=type$name,
      type=type$type,
      doc_dir=type$doc_dir %||% NULL,
      linked_to=type$linked_to %||% NULL,
      progresses=type$progresses %||% NULL,
      description=type$descr
    )
  })

  indexes = list()
  referenced = character(0)
  for (type in types) {
    oid = type$oid
    path = ullme_existing_course_object_index_path(course_dir, oid)
    value = ullme_read_course_object_index(course_dir, oid)
    if (is.null(value)) next
    objects = ullme_object_index_instances(value, oid)
    indexes[[length(indexes) + 1L]] = list(
      oid=oid,
      path=gsub("\\\\", "/", sub(
        paste0("^", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1",
                        normalizePath(course_dir, winslash="/")), "/?"),
        "",
        normalizePath(path, winslash="/", mustWork=FALSE)
      )),
      objects=objects
    )
    for (object in objects) {
      records = ullme_object_instance_file_records(object$files)
      for (record in records) {
        item = gsub("\\\\", "/", record$path)
        if (!grepl("/", item, fixed=TRUE) && !is.null(type$doc_dir)) {
          item = paste(type$doc_dir, item, sep="/")
        }
        referenced = c(referenced, item)
      }
      extras = gsub("\\\\", "/", unlist(object$extra_files %||% list(), use.names=FALSE))
      extras = vapply(extras, function(item) {
        if (!grepl("/", item, fixed=TRUE) && !is.null(type$doc_dir)) {
          paste(type$doc_dir, item, sep="/")
        } else item
      }, character(1), USE.NAMES=FALSE)
      referenced = c(referenced, extras)
    }
  }

  material = ullme_course_material_files(course_dir)
  all_files = ullme_material_relative_paths(material)
  list(
    types=types,
    indexes=indexes,
    unassigned=as.list(sort(setdiff(all_files, unique(referenced)))),
    referenced=as.list(sort(unique(referenced)))
  )
}


ullme_material_relative_paths = function(material) {
  unlist(lapply(names(material), function(category) {
    files = material[[category]]
    if (length(files) == 0) return(character(0))
    paste(category, files, sep="/")
  }), use.names=FALSE)
}


ullme_organization_instance_id = function(path, oid) {
  stem = tools::file_path_sans_ext(basename(path))
  if (identical(oid, "ps_sol")) {
    stem = gsub("([_-]?(solutions?|sol))$", "_sol", stem, ignore.case=TRUE)
  }
  id = gsub("[^A-Za-z0-9_.-]+", "_", stem)
  id = gsub("^[_\\.]+|[_\\.]+$", "", id)
  if (!grepl("^[A-Za-z]", id)) id = paste0(oid, "_", id)
  id
}


ullme_organization_group_files = function(paths, oid) {
  if (length(paths) == 0) return(list())
  ids = vapply(paths, ullme_organization_instance_id, character(1), oid=oid)
  groups = split(paths, ids)
  order_names = names(groups)[order(
    vapply(groups, function(items) min(match(items, paths)), integer(1))
  )]
  lapply(seq_along(order_names), function(i) {
    id = order_names[[i]]
    files = groups[[id]]
    object = list(
      id=id,
      order=i,
      files=lapply(files, function(path) {
        list(
          path=path,
          format=tolower(tools::file_ext(path)),
          role="primary"
        )
      })
    )
    if (identical(oid, "ps_sol")) {
      target = gsub("([_-]?(solutions?|sol))$", "", id, ignore.case=TRUE)
      object$linked_to = target
    }
    object
  })
}


ullme_propose_course_organization_heuristic = function(app=getApp()) {
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) stop("Select a course first.")
  material = ullme_course_material_files(course_dir)
  paths = ullme_material_relative_paths(material)

  lower = tolower(paths)
  category = sub("/.*$", "", paths)
  solution = grepl("(^|[/_. -])(sol|solution|solutions)([/_. -]|$)", lower) |
    grepl("(sol|solution|solutions)\\.[^.]+$", lower)
  classified = list(
    ps=paths[category == "ps" & !solution],
    ps_sol=paths[category == "ps" & solution],
    slides=paths[category == "slides"],
    script=paths[
      category %in% c("background", "general") &
        grepl("script|lecture.?notes|notes", lower)
    ]
  )
  classified = classified[vapply(classified, length, integer(1)) > 0]
  indexes = lapply(names(classified), function(oid) {
    value = list(
      oid=oid,
      objects=ullme_organization_group_files(classified[[oid]], oid)
    )
    list(
      oid=oid,
      path=paste0("objects/", oid, ".yaml"),
      value=value,
      content=trimws(yaml::as.yaml(value)),
      exists=file.exists(ullme_course_object_index_path(course_dir, oid)),
      base_hash=ullme_path_hash(ullme_course_object_index_path(course_dir, oid))
    )
  })
  ullme_validate_organization_proposal(indexes, course_dir)

  token = paste0("organization_", ullme_change_id())
  proposal = list(
    token=token,
    courseid=app$courseid,
    created_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z"),
    indexes=indexes,
    classified_count=sum(vapply(classified, length, integer(1))),
    unclassified=as.list(setdiff(paths, unique(unlist(classified, use.names=FALSE))))
  )
  if (is.null(app$organization_proposals)) app$organization_proposals = list()
  app$organization_proposals[[token]] = proposal
  proposal
}


ullme_organization_response_type = function() {
  ellmer::type_object(
    indexes=ellmer::type_array(
      ellmer::type_object(
        oid=ellmer::type_string("Supported uLLMe object type ID."),
        yaml_content=ellmer::type_string(
          "Complete YAML object-index document without Markdown fences."
        )
      ),
      "Proposed object-index files."
    ),
    notes=ellmer::type_string(
      "Short explanation of classification decisions and ambiguities.",
      required=FALSE
    )
  )
}


ullme_ai_organization_indexes = function(course_dir, model=NULL, app=getApp()) {
  payload = ullme_course_organization_payload(course_dir)
  paths = ullme_material_relative_paths(ullme_course_material_files(course_dir))
  course = ullme_read_course_yaml(course_dir)
  values = list(
    courseid=app$courseid %||% "",
    coursename=course$coursename %||% app$courseid %||% ""
  )
  system_prompt = paste(
    ullme_prompt("teacher_base", values=values),
    ullme_prompt("teacher_language", values=values),
    ullme_prompt("organize_materials", values=values),
    sep="\n\n"
  )
  chat = ullme_task_chat(system_prompt=system_prompt, model=model, app=app)
  request = paste0(
    "AVAILABLE OBJECT TYPES AND EXISTING INDEXES:\n",
    trimws(yaml::as.yaml(list(types=payload$types, indexes=payload$indexes))),
    "\n\nMATERIAL FILE MANIFEST:\n",
    trimws(yaml::as.yaml(as.list(paths)))
  )
  response = chat$chat_structured(
    request,
    type=ullme_organization_response_type(),
    echo="none"
  )
  records = response$indexes %||% list()
  if (!is.list(records) || length(records) == 0) {
    stop("The model did not propose any object indexes.")
  }
  indexes = lapply(records, function(record) {
    oid = ullme_clean_object_id(paste0(record$oid %||% "")[1])
    if (!oid %in% ullme_object_type_ids()) {
      stop("The model proposed an unsupported object type: ", oid)
    }
    content = trimws(paste0(record$yaml_content %||% "")[1])
    if (!nzchar(content)) stop("The model returned an empty ", oid, " index.")
    validation = ullme_validate_object_index_yaml(
      content=content,
      oid=oid,
      course_dir=course_dir,
      require_files=TRUE
    )
    ullme_validation_stop(validation, paste0("Invalid proposed ", oid, " index"))
    path = ullme_course_object_index_path(course_dir, oid)
    list(
      oid=oid,
      path=paste0("objects/", oid, ".yaml"),
      value=validation$value,
      content=content,
      exists=file.exists(path),
      base_hash=ullme_path_hash(path)
    )
  })
  ids = vapply(indexes, function(index) index$oid, character(1))
  if (anyDuplicated(ids)) stop("The model proposed the same object index more than once.")
  ullme_validate_organization_proposal(indexes, course_dir)
  list(indexes=indexes, notes=paste0(response$notes %||% "")[1])
}


ullme_proposal_referenced_paths = function(indexes) {
  unique(unlist(lapply(indexes, function(index) {
    type = ullme_read_object_type(index$oid)
    objects = ullme_object_index_instances(index$value, index$oid)
    unlist(lapply(objects, function(object) {
      records = ullme_object_instance_file_records(object$files)
      paths = vapply(records, function(record) record$path, character(1))
      paths = vapply(paths, function(path) {
        path = gsub("\\\\", "/", path)
        if (!grepl("/", path, fixed=TRUE) && !is.null(type$doc_dir)) {
          paste(type$doc_dir, path, sep="/")
        } else path
      }, character(1))
      extras = unlist(object$extra_files %||% list(), use.names=FALSE)
      extras = vapply(extras, function(path) {
        path = gsub("\\\\", "/", path)
        if (!grepl("/", path, fixed=TRUE) && !is.null(type$doc_dir)) {
          paste(type$doc_dir, path, sep="/")
        } else path
      }, character(1))
      c(paths, extras)
    }), use.names=FALSE)
  }), use.names=FALSE))
}


ullme_propose_course_organization = function(model=NULL, app=getApp()) {
  if (ullme_uses_fake_ai(app=app)) {
    return(ullme_propose_course_organization_heuristic(app=app))
  }
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) stop("Select a course first.")
  result = ullme_ai_organization_indexes(
    course_dir=course_dir,
    model=model,
    app=app
  )
  paths = ullme_material_relative_paths(ullme_course_material_files(course_dir))
  referenced = ullme_proposal_referenced_paths(result$indexes)
  token = paste0("organization_", ullme_change_id())
  proposal = list(
    token=token,
    courseid=app$courseid,
    created_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z"),
    indexes=result$indexes,
    classified_count=length(intersect(paths, referenced)),
    unclassified=as.list(setdiff(paths, referenced)),
    notes=result$notes
  )
  if (is.null(app$organization_proposals)) app$organization_proposals = list()
  app$organization_proposals[[token]] = proposal
  proposal
}


ullme_validate_organization_proposal = function(indexes, course_dir) {
  values = lapply(indexes, function(index) index$value)
  names(values) = vapply(indexes, function(index) index$oid, character(1))
  for (index in indexes) {
    linked = identical(index$oid, "ps_sol")
    validation = ullme_validate_object_index_yaml(
      content=index$content,
      oid=index$oid,
      course_dir=if (linked) NULL else course_dir,
      require_files=!linked
    )
    ullme_validation_stop(validation, paste0("Invalid proposed ", index$oid, " index"))
  }
  if (!is.null(values$ps_sol) && !is.null(values$ps)) {
    ps_ids = vapply(
      ullme_object_index_instances(values$ps, "ps"),
      function(object) paste0(object$id %||% object$docid %||% "")[1],
      character(1)
    )
    mappings = vapply(
      ullme_object_index_instances(values$ps_sol, "ps_sol"),
      function(object) paste0(object$linked_to %||% "")[1],
      character(1)
    )
    unknown = unique(setdiff(mappings[nzchar(mappings)], ps_ids))
    if (length(unknown) > 0) {
      stop("The proposed solution mappings reference unknown problem sets: ",
           paste(unknown, collapse=", "), ".")
    }
  }
  invisible(TRUE)
}


ullme_handle_organization_propose = function(model=NULL, app=getApp(), ...) {
  if (!identical(app$role, "teacher")) return(invisible(FALSE))
  proposal = tryCatch(
    ullme_propose_course_organization(model=model, app=app),
    error=function(e) list(
      error=ullme_safe_ai_error(e, app$api_config),
      indexes=list()
    )
  )
  callJS(
    .fun="window.ullme.openOrganizationProposal",
    .args=list(proposal),
    .app=app
  )
  invisible(proposal)
}


ullme_handle_organization_apply = function(token=NULL, app=getApp(), ...) {
  if (!identical(app$role, "teacher")) return(invisible(FALSE))
  token = paste0(token)[1]
  proposal = app$organization_proposals[[token]]
  if (is.null(proposal) || !identical(proposal$courseid, app$courseid)) {
    return(invisible(FALSE))
  }
  course_dir = ullme_active_course_dir(app=app)
  changes = lapply(proposal$indexes, function(index) {
    ullme_change_write(file.path(course_dir, index$path), index$content)
  })
  if (length(changes) == 0) return(invisible(FALSE))
  operation = ullme_new_change(
    action="write_object_indexes",
    summary=paste0("Apply proposed material organization for ", app$courseid),
    origin="agent",
    details=list(courseid=app$courseid, proposal_token=token),
    changes=changes,
    app=app
  )
  result = tryCatch(
    {
      for (index in proposal$indexes) {
        target = file.path(course_dir, index$path)
        current_hash = ullme_path_hash(target)
        expected_hash = index$base_hash
        if (is.null(expected_hash) || length(expected_hash) == 0) {
          expected_hash = NA_character_
        } else {
          expected_hash = as.character(expected_hash)[1]
        }
        unchanged = (is.na(current_hash) && is.na(expected_hash)) ||
          identical(current_hash, expected_hash)
        if (!isTRUE(unchanged)) {
          stop(index$path, " changed after this proposal was created. Generate a new proposal.")
        }
      }
      ullme_validate_organization_proposal(proposal$indexes, course_dir)
      ullme_submit_change(operation, app=app)
    },
    error=function(e) list(ok=FALSE, status="error", message=conditionMessage(e))
  )
  if (!identical(result$status, "pending_approval") && isTRUE(result$ok)) {
    app$organization_proposals[[token]] = NULL
    ullme_send_course_state(app=app)
  }
  callJS(
    .fun="window.ullme.organizationApplyComplete",
    .args=list(ullme_tool_change_result(result)),
    .app=app
  )
  invisible(result)
}
