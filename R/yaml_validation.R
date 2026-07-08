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


ullme_validate_definition_yaml = function(kind, definitionid, content) {
  kind = ullme_definition_kind(kind)
  definitionid = ullme_clean_definition_id(definitionid)
  filename = if (identical(kind, "tutor")) "tutor.yml" else "ullme.yaml"
  parsed = ullme_parse_yaml_text(content, filename)
  if (!parsed$ok) return(parsed)

  value = parsed$value
  id_field = if (identical(kind, "tutor")) "tutorid" else "skillid"
  errors = ullme_validate_required_fields(value, id_field, filename)
  if (length(errors) == 0) {
    declared = paste0(value[[id_field]])[1]
    if (!identical(declared, definitionid)) {
      errors = c(errors, paste0(id_field, " must match the definition directory name '",
                                definitionid, "'."))
    }
  }
  warnings = character(0)
  if (is.list(value) && !nzchar(trimws(paste0(value$label %||% "")[1]))) {
    warnings = c(warnings, "label is empty.")
  }
  if (identical(kind, "tutor") && is.list(value)) {
    scalar_fields = c(
      "lang", "label", "description", "system_prompt",
      "default_personality"
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
    for (field in c("multiple_instances", "chat_history")) {
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
    for (prompt_field in c("system_prompt", "shown_text")) {
      prompt = paste0(value[[prompt_field]] %||% "", collapse="\n")
      hits = regmatches(
        prompt,
        gregexpr("\\{\\{[A-Za-z][A-Za-z0-9_]*\\}\\}", prompt, perl=TRUE)
      )[[1]]
      placeholders = if (length(hits) == 1 && identical(hits, "")) {
        character(0)
      } else {
        unique(substring(hits, 3, nchar(hits) - 2L))
      }
      unknown = setdiff(placeholders, c(document_ids, customization))
      if (length(unknown) > 0) {
        errors = c(
          errors,
          paste0(prompt_field, " contains unknown placeholders: ",
                 paste(unknown, collapse=", "), ".")
        )
      }
    }
  }
  ullme_validation_result(length(errors) == 0, errors, warnings, value)
}


ullme_validate_yaml_by_path = function(path, content, app=NULL) {
  name = tolower(basename(path))
  if (identical(name, "course.yaml")) return(ullme_validate_course_yaml(content))
  ullme_parse_yaml_text(content, basename(path))
}
