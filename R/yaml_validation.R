ullme_validation_result = function(ok=TRUE, errors=character(0),
                                    warnings=character(0), value=NULL) {
  list(
    ok=isTRUE(ok) && length(errors) == 0,
    errors=as.list(paste0(errors)),
    warnings=as.list(paste0(warnings)),
    value=value
  )
}


ullme_validation_stop = function(result, prefix="Validation failed") {
  if (isTRUE(result$ok)) return(invisible(result))
  errors = paste0(unlist(result$errors, use.names=FALSE), collapse="\n")
  if (!nzchar(errors)) errors = "The value is invalid."
  stop(prefix, ":\n", errors, call.=FALSE)
}


ullme_parse_yaml_text = function(content, label="YAML") {
  ullme_require_yaml()
  content = paste0(content, collapse="\n")
  parsed = tryCatch(
    yaml::yaml.load(content, eval.expr=FALSE),
    error=function(e) e
  )
  if (inherits(parsed, "error")) {
    return(ullme_validation_result(
      ok=FALSE,
      errors=paste0(label, " syntax error: ", conditionMessage(parsed))
    ))
  }
  ullme_validation_result(value=parsed)
}


ullme_parse_yaml_file = function(path, label=basename(path)) {
  if (!file.exists(path) || dir.exists(path)) {
    return(ullme_validation_result(
      ok=FALSE,
      errors=paste0(label, " does not exist.")
    ))
  }
  content = paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n")
  ullme_parse_yaml_text(content=content, label=label)
}


ullme_validate_required_fields = function(value, fields, label="YAML") {
  if (!is.list(value) || is.null(names(value))) {
    return(paste0(label, " must contain a YAML mapping."))
  }
  missing = fields[!vapply(fields, function(field) {
    item = value[[field]]
    !is.null(item) && length(item) > 0 &&
      (is.list(item) || nzchar(trimws(paste0(item)[1])))
  }, logical(1))]
  if (length(missing) == 0) return(character(0))
  paste0(label, " is missing required field", if (length(missing) > 1) "s" else "",
         ": ", paste(missing, collapse=", "), ".")
}


ullme_validate_course_value = function(course) {
  errors = character(0)
  warnings = character(0)
  if (!is.list(course) || is.null(names(course))) {
    errors = c(errors, "course.yaml must contain a mapping.")
    return(ullme_validation_result(FALSE, errors, warnings, course))
  }

  courseid = paste0(course$courseid %||% "")[1]
  if (!grepl("^[A-Za-z][A-Za-z0-9_-]*$", courseid)) {
    errors = c(errors, "courseid must start with a letter and contain only letters, numbers, underscores, or hyphens.")
  }
  coursename = paste0(course$coursename %||% "")[1]
  if (!nzchar(trimws(coursename))) warnings = c(warnings, "coursename is empty.")

  ullme_validation_result(length(errors) == 0, errors, warnings, course)
}


ullme_validate_course_yaml = function(content) {
  parsed = ullme_parse_yaml_text(content, "course.yaml")
  if (!parsed$ok) return(parsed)
  ullme_validate_course_value(parsed$value)
}


ullme_validate_tutor_doc_specs = function(value, field,
                                           allow_fixed_paths=FALSE) {
  errors = character(0)
  if (is.null(value)) return(errors)
  if (!is.list(value)) {
    return(paste0(field, " must be a mapping of document IDs to settings."))
  }
  if (length(value) == 0) return(errors)
  ids = names(value)
  if (is.null(ids) || any(!grepl("^[A-Za-z][A-Za-z0-9_]*$", ids))) {
    errors = c(errors, paste0(field, " contains an invalid document ID."))
    return(errors)
  }
  for (docid in ids) {
    spec = value[[docid]]
    label = paste0(field, ".", docid)
    if (isTRUE(allow_fixed_paths) &&
        is.character(spec) && length(spec) == 1L && !is.na(spec)) {
      if (!ullme_safe_relative_material_path(spec)) {
        errors = c(errors, paste0(
          label, " must be a relative path below the materials directory."
        ))
      }
      next
    }
    if (!is.list(spec)) {
      errors = c(errors, paste0(
        label, " must be a mapping",
        if (isTRUE(allow_fixed_paths)) " or a fixed filename" else "",
        "."
      ))
      next
    }
    if (!nzchar(trimws(paste0(spec$descr %||% "")[1]))) {
      errors = c(errors, paste0(label, ".descr is required."))
    }
    directory = paste0(spec$pref_doc_dir %||% "")[1]
    if (!ullme_safe_relative_material_path(directory)) {
      errors = c(errors, paste0(label, ".pref_doc_dir must be a relative material directory."))
    }
    file_types = spec$file_types %||% list()
    if (!is.list(file_types) && !is.character(file_types)) {
      errors = c(errors, paste0(label, ".file_types must be a list."))
    } else {
      file_types = tolower(sub(
        "^\\.", "",
        trimws(paste0(unlist(file_types, use.names=FALSE)))
      ))
      if (!length(file_types) || any(!nzchar(file_types))) {
        errors = c(errors, paste0(
          label,
          ".file_types must list at least one allowed file type."
        ))
      } else {
        unsupported = setdiff(file_types, ullme_document_candidate_formats())
        if (length(unsupported)) {
          errors = c(errors, paste0(
            label, ".file_types contains unsupported type",
            if (length(unsupported) > 1) "s" else "",
            ": ", paste(unsupported, collapse=", "), "."
          ))
        }
      }
    }
    legacy = intersect(names(spec), c("pref_format", "auto_convert"))
    if (length(legacy)) {
      errors = c(errors, paste0(
        label, " uses obsolete field",
        if (length(legacy) > 1) "s" else "",
        " ", paste(legacy, collapse=", "),
        "; use file_types in preferred order."
      ))
    }
    if (!is.null(spec$add_images) &&
        !is.logical(spec$add_images)) {
      errors = c(errors, paste0(label, ".add_images must be true or false."))
    }
  }
  errors
}


ullme_validate_tutor_placeholder_documents = function(value) {
  errors = character(0)
  if (is.null(value)) return(errors)
  if (!is.list(value)) {
    return("placeholder_documents must map placeholder names to file paths.")
  }
  ids = names(value)
  if (length(value) && (
      is.null(ids) || any(!grepl("^[A-Za-z][A-Za-z0-9_]*$", ids)))) {
    return("placeholder_documents contains an invalid placeholder name.")
  }
  for (placeholder in ids %||% character(0)) {
    path = value[[placeholder]]
    if (!is.character(path) || length(path) != 1L || is.na(path) ||
        !ullme_safe_relative_material_path(path)) {
      errors = c(errors, paste0(
        "placeholder_documents.", placeholder,
        " must be a relative file path below the materials directory."
      ))
    }
  }
  errors
}


ullme_validate_tutor_file_permissions = function(value) {
  errors = character(0)
  if (is.null(value)) return(errors)
  if (!is.list(value)) return("file_permissions must be a list.")
  for (i in seq_along(value)) {
    permission = value[[i]]
    label = paste0("file_permissions[", i, "]")
    if (!is.list(permission)) {
      errors = c(errors, paste0(label, " must be a mapping."))
      next
    }
    type = paste0(permission$type %||% "")[1]
    if (!type %in% c("read_only", "write_and_read", "read_and_write")) {
      errors = c(errors, paste0(
        label, ".type must be read_only or write_and_read."
      ))
    }
    main_path = paste0(permission$main_path %||% "")[1]
    if (!ullme_safe_relative_material_path(main_path)) {
      errors = c(errors, paste0(label, ".main_path must be a relative path."))
    }
    directories = paste0(unlist(
      permission$directories %||% list(),
      use.names=FALSE
    ))
    if (!length(directories)) {
      errors = c(errors, paste0(label, ".directories must not be empty."))
    } else if (any(!vapply(
      directories,
      ullme_safe_relative_material_path,
      logical(1)
    ))) {
      errors = c(errors, paste0(
        label, ".directories must contain only relative paths."
      ))
    }
    if (!is.null(permission$recursive) &&
        (!is.logical(permission$recursive) ||
         length(permission$recursive) != 1L)) {
      errors = c(errors, paste0(label, ".recursive must be true or false."))
    }
    extensions = paste0(unlist(
      permission$extensions %||% list(),
      use.names=FALSE
    ))
    if (any(!grepl("^\\.?[A-Za-z0-9][A-Za-z0-9_-]*$", extensions))) {
      errors = c(errors, paste0(label, ".extensions contains an invalid value."))
    }
  }
  errors
}


ullme_prompt_placeholders = function(text) {
  text = paste0(text %||% "", collapse="\n")
  hits = regmatches(
    text,
    gregexpr("\\{\\{[A-Za-z][A-Za-z0-9_.]*\\}\\}", text, perl=TRUE)
  )[[1]]
  if (length(hits) == 1L && identical(hits, "")) return(character(0))
  unique(substring(hits, 3L, nchar(hits) - 2L))
}


ullme_validate_tutor_workflow = function(value, document_ids,
                                          customization_ids) {
  errors = character(0)
  start = paste0(value$start_node %||% "")[1]
  nodes = value$nodes
  fragments = value$prompt_fragments
  if (!grepl("^[A-Za-z][A-Za-z0-9_]*$", start)) {
    errors = c(errors, "start_node must be a valid node ID.")
  }
  if (!is.list(nodes) || !length(nodes) || is.null(names(nodes))) {
    return(c(errors, "nodes must be a non-empty mapping of node IDs."))
  }
  node_ids = names(nodes)
  if (any(!grepl("^[A-Za-z][A-Za-z0-9_]*$", node_ids))) {
    errors = c(errors, "nodes contains an invalid node ID.")
  }
  if (nzchar(start) && !start %in% node_ids) {
    errors = c(errors, "start_node does not name a defined node.")
  }
  if (!is.list(fragments) || !length(fragments) || is.null(names(fragments))) {
    errors = c(errors, "prompt_fragments must be a non-empty mapping.")
    fragments = list()
  }
  fragment_ids = names(fragments) %||% character(0)
  if (!"init_prompt" %in% fragment_ids) {
    errors = c(errors, "prompt_fragments.init_prompt is required.")
  } else if (!nzchar(trimws(paste0(fragments$init_prompt, collapse="\n")))) {
    errors = c(errors, "prompt_fragments.init_prompt must not be empty.")
  }
  if (length(fragment_ids) &&
      any(!grepl("^[A-Za-z][A-Za-z0-9_]*$", fragment_ids))) {
    errors = c(errors, "prompt_fragments contains an invalid fragment ID.")
  }
  runtime_ids = c(
    "input", "output", "hist", "hist_or_init_prompt", "image_uploaded"
  )
  reserved = intersect(runtime_ids, c(
    document_ids, customization_ids, fragment_ids
  ))
  if (length(reserved)) {
    errors = c(errors, paste0(
      "Runtime placeholder names cannot be reused as document, customization, ",
      "or fragment IDs: ", paste(reserved, collapse=", "), "."
    ))
  }
  known_placeholders = unique(c(
    document_ids, customization_ids, fragment_ids, runtime_ids
  ))
  unknown_placeholders = function(text) {
    found = ullme_prompt_placeholders(text)
    setdiff(
      found[!grepl("^output[.][A-Za-z][A-Za-z0-9_]*$", found)],
      known_placeholders
    )
  }
  for (fragment_id in fragment_ids) {
    unknown = unknown_placeholders(fragments[[fragment_id]])
    if (length(unknown)) {
      errors = c(errors, paste0(
        "prompt_fragments.", fragment_id,
        " contains unknown placeholders: ", paste(unknown, collapse=", "), "."
      ))
    }
  }
  targets = character(0)
  for (node_id in node_ids) {
    node = nodes[[node_id]]
    label = paste0("nodes.", node_id)
    if (!is.list(node)) {
      errors = c(errors, paste0(label, " must be a mapping."))
      next
    }
    prompt = paste0(node$prompt %||% "", collapse="\n")
    next_node = paste0(node[["next"]] %||% "")[1]
    switch_input = paste0(node$switch_input %||% "")[1]
    switch_to = node$switch_to
    ask = isTRUE(node$ask_for_input)
    for (field in c("show_before", "show_after")) {
      if (!is.null(node[[field]]) &&
          (!is.character(node[[field]]) || length(node[[field]]) != 1L ||
           is.na(node[[field]]))) {
        errors = c(errors, paste0(label, ".", field, " must be text."))
      }
      if (!nzchar(trimws(prompt)) &&
          nzchar(trimws(paste0(node[[field]] %||% "", collapse="\n")))) {
        errors = c(errors, paste0(label, ".", field, " requires a model prompt."))
      }
    }
    if (!is.null(node$ask_for_input) &&
        (!is.logical(node$ask_for_input) || length(node$ask_for_input) != 1L)) {
      errors = c(errors, paste0(label, ".ask_for_input must be true or false."))
    }
    if (!is.null(node$add_to_history) &&
        (!is.logical(node$add_to_history) || length(node$add_to_history) != 1L)) {
      errors = c(errors, paste0(label, ".add_to_history must be true or false."))
    }
    if (ask && !nzchar(trimws(paste0(node$show_text %||% "", collapse="\n")))) {
      errors = c(errors, paste0(label, ".show_text is required when ask_for_input is true."))
    }
    if (nzchar(next_node) && !is.null(switch_to)) {
      errors = c(errors, paste0(label, " cannot define both next and switch_to."))
    }
    if (!is.null(switch_to)) {
      if (!is.list(switch_to) || !length(switch_to) || is.null(names(switch_to))) {
        errors = c(errors, paste0(label, ".switch_to must be a non-empty mapping."))
      } else {
        if (!nzchar(switch_input)) {
          errors = c(errors, paste0(label, ".switch_input is required with switch_to."))
        } else if (!switch_input %in% c("image_uploaded", "output")) {
          errors = c(errors, paste0(
            label, ".switch_input must be image_uploaded or output."
          ))
        }
        targets = c(targets, paste0(unlist(switch_to, use.names=FALSE)))
      }
    } else if (nzchar(switch_input)) {
      errors = c(errors, paste0(label, ".switch_input requires switch_to."))
    }
    if (nzchar(next_node)) targets = c(targets, next_node)
    if (!nzchar(prompt) && is.null(switch_to) && !ask) {
      errors = c(errors, paste0(label, " must call the model, route, or ask for input."))
    }
    if (ask && !nzchar(prompt)) {
      errors = c(errors, paste0(label, ".prompt is required to process resumed input."))
    }
    parallel_n = suppressWarnings(as.integer(node$n_parallel %||% 1L)[1])
    if (!is.null(node$n_parallel)) {
      if (is.na(parallel_n) || parallel_n < 1L || parallel_n > 9L) {
        errors = c(errors, paste0(label, ".n_parallel must be between 1 and 9."))
      }
    }
    if (!is.null(node$n_retries)) {
      n = suppressWarnings(as.integer(node$n_retries)[1])
      if (is.na(n) || n < 0L || n > 3L) {
        errors = c(errors, paste0(label, ".n_retries must be between 0 and 3."))
      }
    }
    aggregate = paste0(node$aggregate %||% "")[1]
    if (nzchar(aggregate) && !identical(aggregate, "majority_vote")) {
      errors = c(errors, paste0(label, ".aggregate must be majority_vote."))
    }
    if (identical(aggregate, "majority_vote") &&
        (!identical(switch_input, "output") || is.null(switch_to))) {
      errors = c(errors, paste0(
        label, ".aggregate majority_vote requires switch_input: output and switch_to."
      ))
    }
    if (!is.na(parallel_n) && parallel_n > 1L && !nzchar(aggregate)) {
      errors = c(errors, paste0(label, ".aggregate is required when n_parallel is greater than 1."))
    }
    for (field in c("prompt", "waiting_message", "show_before", "show_after", "show_text")) {
      unknown = unknown_placeholders(node[[field]] %||% "")
      if (length(unknown)) {
        errors = c(errors, paste0(
          label, ".", field, " contains unknown placeholders: ",
          paste(unknown, collapse=", "), "."
        ))
      }
    }
  }
  missing_targets = setdiff(unique(targets[nzchar(targets)]), node_ids)
  if (length(missing_targets)) {
    errors = c(errors, paste0(
      "Workflow routes to undefined nodes: ",
      paste(missing_targets, collapse=", "), "."
    ))
  }
  if (!length(missing_targets) && length(node_ids)) {
    adjacency = setNames(vector("list", length(node_ids)), node_ids)
    indegree = setNames(integer(length(node_ids)), node_ids)
    for (node_id in node_ids) {
      node = nodes[[node_id]]
      if (!is.list(node)) next
      outgoing = character(0)
      next_node = paste0(node[["next"]] %||% "")[1]
      if (nzchar(next_node)) outgoing = c(outgoing, next_node)
      if (is.list(node$switch_to)) {
        outgoing = c(
          outgoing,
          paste0(unlist(node$switch_to, use.names=FALSE))
        )
      }
      outgoing = unique(outgoing[outgoing %in% node_ids])
      adjacency[[node_id]] = outgoing
      for (target in outgoing) indegree[[target]] = indegree[[target]] + 1L
    }
    queue = node_ids[indegree == 0L]
    visited = character(0)
    while (length(queue)) {
      node_id = queue[[1]]
      queue = queue[-1]
      visited = c(visited, node_id)
      for (target in adjacency[[node_id]]) {
        indegree[[target]] = indegree[[target]] - 1L
        if (identical(indegree[[target]], 0L)) queue = c(queue, target)
      }
    }
    cycle_nodes = setdiff(node_ids, visited)
    if (length(cycle_nodes)) {
      errors = c(errors, paste0(
        "Workflow nodes must form a directed acyclic graph; a cycle involves: ",
        paste(cycle_nodes, collapse=", "), "."
      ))
    }
  }
  errors
}


ullme_validate_tutor_yaml = function(tutorid, content) {
  tutorid = ullme_clean_definition_id(tutorid)
  filename = "tutor.yml"
  parsed = ullme_parse_yaml_text(content, filename)
  if (!parsed$ok) return(parsed)

  value = parsed$value
  id_field = "tutorid"
  errors = ullme_validate_required_fields(value, id_field, filename)
  if (length(errors) == 0) {
    declared = paste0(value[[id_field]])[1]
    if (!identical(declared, tutorid)) {
      errors = c(errors, paste0(id_field, " must match the definition directory name '",
                                tutorid, "'."))
    }
  }
  warnings = character(0)
  if (is.list(value) && !nzchar(trimws(paste0(value$label %||% "")[1]))) {
    warnings = c(warnings, "label is empty.")
  }
  if (is.list(value)) {
    scalar_fields = c(
      "lang", "label", "description", "shown_text",
      "default_personality", "start_node"
    )
    for (field in scalar_fields) {
      if (!nzchar(trimws(paste0(value[[field]] %||% "")[1]))) {
        errors = c(errors, paste0(field, " is required."))
      }
    }
    for (field in c("docs_per_instance", "docs_per_course")) {
      if (field %in% names(value)) {
        errors = c(
          errors,
          ullme_validate_tutor_doc_specs(
            value[[field]],
            field
          )
        )
      }
    }
    errors = c(
      errors,
      ullme_validate_tutor_placeholder_documents(
        value$placeholder_documents
      )
    )
    for (field in c("allowed_tools", "allowed_student_customization")) {
      if (!field %in% names(value)) {
        errors = c(errors, paste0(field, " is required, even when empty."))
      } else if (!is.list(value[[field]]) &&
                 !is.character(value[[field]])) {
        errors = c(errors, paste0(field, " must be a list of IDs."))
      }
    }
    tools = paste0(unlist(
      value$allowed_tools %||% list(),
      use.names=FALSE
    ))
    if (any(!grepl("^[A-Za-z][A-Za-z0-9_.-]*$", tools))) {
      errors = c(errors, "allowed_tools contains an invalid ID.")
    }
    customization = paste0(unlist(
      value$allowed_student_customization %||% list(),
      use.names=FALSE
    ))
    if (any(!grepl("^[A-Za-z][A-Za-z0-9_]*$", customization))) {
      errors = c(errors, "allowed_student_customization contains an invalid ID.")
    }
        for (field in c(
          "multiple_instances", "chat_history", "show_final_output"
        )) {
      if (!is.null(value[[field]]) &&
          (!is.logical(value[[field]]) || length(value[[field]]) != 1L)) {
        errors = c(errors, paste0(field, " must be true or false."))
      }
    }
    errors = c(
      errors,
      ullme_validate_tutor_file_permissions(value$file_permissions)
    )
    document_ids = c(
      names(value$docs_per_instance %||% list()),
      names(value$docs_per_course %||% list()),
      names(value$placeholder_documents %||% list())
    )
    shown_unknown = setdiff(
      ullme_prompt_placeholders(value$shown_text),
      c(document_ids, customization)
    )
    if (length(shown_unknown)) {
      errors = c(errors, paste0(
        "shown_text contains unknown placeholders: ",
        paste(shown_unknown, collapse=", "), "."
      ))
    }
    errors = c(errors, ullme_validate_tutor_workflow(
      value,
      document_ids=document_ids,
      customization_ids=customization
    ))
  }
  ullme_validation_result(length(errors) == 0, errors, warnings, value)
}


ullme_validate_yaml_by_path = function(path, content, app=NULL) {
  name = tolower(basename(path))
  if (identical(name, "course.yaml")) return(ullme_validate_course_yaml(content))
  ullme_parse_yaml_text(content, basename(path))
}
