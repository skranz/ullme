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

  times = course$times %||% list()
  if (!is.list(times)) {
    errors = c(errors, "times must be a list.")
  } else {
    if (length(times) > 3) errors = c(errors, "times may contain at most three entries.")
    valid_days = c("monday", "tuesday", "wednesday", "thursday", "friday",
                   "saturday", "sunday", "mo", "tu", "we", "th", "fr", "sa", "su")
    for (i in seq_along(times)) {
      item = times[[i]]
      if (!is.list(item)) {
        errors = c(errors, paste0("times[", i, "] must be a mapping."))
        next
      }
      day = tolower(paste0(item$weekday %||% "")[1])
      start = paste0(item$start %||% "")[1]
      end = paste0(item$end %||% "")[1]
      if (!day %in% valid_days) errors = c(errors, paste0("times[", i, "].weekday is invalid."))
      time_pattern = "^([01][0-9]|2[0-3]):[0-5][0-9]$"
      if (!grepl(time_pattern, start)) errors = c(errors, paste0("times[", i, "].start must use HH:MM."))
      if (!grepl(time_pattern, end)) errors = c(errors, paste0("times[", i, "].end must use HH:MM."))
      if (grepl(time_pattern, start) && grepl(time_pattern, end) && start >= end) {
        errors = c(errors, paste0("times[", i, "] must end after it starts."))
      }
    }
  }
  ullme_validation_result(length(errors) == 0, errors, warnings, course)
}


ullme_validate_course_yaml = function(content) {
  parsed = ullme_parse_yaml_text(content, "course.yaml")
  if (!parsed$ok) return(parsed)
  ullme_validate_course_value(parsed$value)
}


ullme_validate_definition_yaml = function(kind, definitionid, content) {
  kind = ullme_definition_kind(kind)
  definitionid = ullme_clean_definition_id(definitionid)
  filename = if (identical(kind, "tutor")) "tutor.yaml" else "ullme.yaml"
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
  ullme_validation_result(length(errors) == 0, errors, warnings, value)
}


ullme_validate_yaml_by_path = function(path, content, app=NULL) {
  name = tolower(basename(path))
  if (identical(name, "course.yaml")) return(ullme_validate_course_yaml(content))
  ullme_parse_yaml_text(content, basename(path))
}
