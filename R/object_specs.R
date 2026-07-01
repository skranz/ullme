ullme_object_types_dir = function() {
  ullme_package_dir("objects")
}


ullme_object_type_ids = function() {
  root = ullme_object_types_dir()
  if (!dir.exists(root)) return(character(0))
  paths = list.files(root, pattern="\\.ya?ml$", full.names=TRUE, ignore.case=TRUE)
  sort(unique(tools::file_path_sans_ext(basename(paths))))
}


ullme_clean_object_id = function(oid) {
  oid = paste0(oid)[1]
  if (is.na(oid) || !grepl("^[A-Za-z][A-Za-z0-9_-]*$", oid)) {
    stop("Object IDs must start with a letter and contain only letters, numbers, underscores, or hyphens.")
  }
  oid
}


ullme_object_type_path = function(oid) {
  oid = ullme_clean_object_id(oid)
  root = ullme_object_types_dir()
  candidates = file.path(root, paste0(oid, c(".yml", ".yaml")))
  found = candidates[file.exists(candidates)]
  if (length(found) == 0) return(candidates[[1]])
  found[[1]]
}


ullme_validate_object_type_value = function(value, expected_oid=NULL) {
  errors = ullme_validate_required_fields(
    value,
    c("oid", "name", "level", "type", "descr"),
    "Object type"
  )
  if (length(errors) > 0) return(ullme_validation_result(FALSE, errors, value=value))
  oid = paste0(value$oid)[1]
  if (!is.null(expected_oid) && !identical(oid, expected_oid)) {
    errors = c(errors, "Object type oid must match its filename.")
  }
  if (!paste0(value$level)[1] %in% "course") errors = c(errors, "Object type level must currently be 'course'.")
  if (!paste0(value$type)[1] %in% c("doc", "event")) errors = c(errors, "Object type type must be 'doc' or 'event'.")
  if (identical(paste0(value$type)[1], "doc") &&
      !nzchar(paste0(value$doc_dir %||% "")[1])) {
    errors = c(errors, "Document object types require doc_dir.")
  }
  ullme_validation_result(length(errors) == 0, errors, value=value)
}


ullme_read_object_type = function(oid) {
  oid = ullme_clean_object_id(oid)
  path = ullme_object_type_path(oid)
  result = ullme_parse_yaml_file(path, paste0("object type ", oid))
  ullme_validation_stop(result)
  result = ullme_validate_object_type_value(result$value, expected_oid=oid)
  ullme_validation_stop(result)
  result$value
}


ullme_course_objects_dir = function(course_dir) {
  file.path(course_dir, "objects")
}


ullme_course_object_index_path = function(course_dir, oid) {
  file.path(ullme_course_objects_dir(course_dir), paste0(ullme_clean_object_id(oid), ".yaml"))
}


ullme_legacy_course_object_index_paths = function(course_dir, oid) {
  oid = ullme_clean_object_id(oid)
  file.path(course_dir, paste0(oid, c("_inst.yaml", "_inst.yml")))
}


ullme_existing_course_object_index_path = function(course_dir, oid) {
  canonical = ullme_course_object_index_path(course_dir, oid)
  if (file.exists(canonical)) return(canonical)
  legacy = ullme_legacy_course_object_index_paths(course_dir, oid)
  found = legacy[file.exists(legacy)]
  if (length(found) > 0) found[[1]] else canonical
}


ullme_object_index_instances = function(value, oid=NULL) {
  if (is.list(value) && !is.null(names(value)) && "objects" %in% names(value)) {
    return(value$objects %||% list())
  }
  value %||% list()
}


ullme_object_instance_id = function(instance, object_type) {
  if (!is.list(instance)) return("")
  paste0(
    instance$id %||%
      if (identical(object_type$type, "event")) instance$eventid else instance$docid %||%
      ""
  )[1]
}


ullme_object_instance_file_records = function(files) {
  if (is.null(files)) return(list())
  if (!is.list(files)) files = as.list(files)
  lapply(files, function(file) {
    if (is.list(file)) {
      list(
        path=paste0(file$path %||% "")[1],
        format=paste0(file$format %||% tools::file_ext(paste0(file$path %||% "")[1]))[1],
        role=paste0(file$role %||% "primary")[1]
      )
    } else {
      path = paste0(file)[1]
      list(path=path, format=tools::file_ext(path), role="primary")
    }
  })
}


ullme_safe_relative_material_path = function(path) {
  path = gsub("\\\\", "/", paste0(path)[1])
  !is.na(path) && nzchar(path) &&
    !grepl("^/|^[A-Za-z]:|(^|/)\\.\\.(/|$)", path)
}


ullme_validate_object_index_value = function(value, oid, course_dir=NULL,
                                              require_files=TRUE) {
  oid = ullme_clean_object_id(oid)
  object_type = tryCatch(ullme_read_object_type(oid), error=function(e) e)
  if (inherits(object_type, "error")) {
    return(ullme_validation_result(FALSE, conditionMessage(object_type), value=value))
  }
  errors = character(0)
  warnings = character(0)

  if (is.list(value) && !is.null(names(value)) && "objects" %in% names(value)) {
    declared_oid = paste0(value$oid %||% "")[1]
    if (!identical(declared_oid, oid)) errors = c(errors, "The index oid must match its filename.")
  }
  instances = ullme_object_index_instances(value, oid)
  if (!is.list(instances)) {
    errors = c(errors, "objects must be a list.")
    return(ullme_validation_result(FALSE, errors, warnings, value))
  }

  ids = character(0)
  for (i in seq_along(instances)) {
    instance = instances[[i]]
    label = paste0("objects[", i, "]")
    if (!is.list(instance)) {
      errors = c(errors, paste0(label, " must be a mapping."))
      next
    }
    id = ullme_object_instance_id(instance, object_type)
    if (!grepl("^[A-Za-z][A-Za-z0-9_.-]*$", id)) {
      errors = c(errors, paste0(label, " requires a valid id, docid, or eventid."))
    } else {
      ids = c(ids, id)
    }
    if (identical(object_type$type, "doc")) {
      records = ullme_object_instance_file_records(instance$files)
      if (length(records) == 0) errors = c(errors, paste0(label, " requires at least one file."))
      for (record in records) {
        if (!ullme_safe_relative_material_path(record$path)) {
          errors = c(errors, paste0(label, " contains an unsafe file path."))
          next
        }
        if (!nzchar(record$format)) warnings = c(warnings, paste0(label, " has a file without a format."))
        extension = tolower(tools::file_ext(record$path))
        if (nzchar(extension) && nzchar(record$format) &&
            !identical(extension, tolower(record$format))) {
          warnings = c(warnings, paste0(label, " declares format '", record$format,
                                        "' for a .", extension, " file."))
        }
        if (!is.null(course_dir) && isTRUE(require_files)) {
          path = record$path
          if (!grepl("/", path, fixed=TRUE)) path = file.path(object_type$doc_dir, path)
          full_path = file.path(course_dir, "materials", path)
          if (!file.exists(full_path) || dir.exists(full_path)) {
            errors = c(errors, paste0(label, " references missing material: ", gsub("\\\\", "/", path)))
          }
        }
      }
      extra = unlist(instance$extra_files %||% list(), use.names=FALSE)
      if (length(extra) > 0 && any(!vapply(extra, ullme_safe_relative_material_path, logical(1)))) {
        errors = c(errors, paste0(label, " contains an unsafe extra_files path."))
      }
      if (length(extra) > 0 && !is.null(course_dir) && isTRUE(require_files)) {
        for (path in extra[vapply(extra, ullme_safe_relative_material_path, logical(1))]) {
          if (!grepl("/", path, fixed=TRUE)) path = file.path(object_type$doc_dir, path)
          if (!file.exists(file.path(course_dir, "materials", path))) {
            errors = c(errors, paste0(label, " references missing extra material: ",
                                      gsub("\\\\", "/", path)))
          }
        }
      }
    } else {
      date = paste0(instance$date %||% "")[1]
      if (nzchar(date) && is.na(as.Date(date))) errors = c(errors, paste0(label, ".date must use YYYY-MM-DD."))
    }
  }
  duplicates = unique(ids[duplicated(ids)])
  if (length(duplicates) > 0) errors = c(errors, paste0("Duplicate object IDs: ", paste(duplicates, collapse=", "), "."))
  orders = vapply(instances, function(instance) {
    suppressWarnings(as.integer(instance$order %||% NA_integer_)[1])
  }, integer(1))
  if (any(!is.na(orders))) {
    if (any(is.na(orders)) || any(orders < 1L) || anyDuplicated(orders)) {
      errors = c(errors, "Explicit order values must be unique positive integers on every object.")
    } else if (is.unsorted(orders, strictly=TRUE)) {
      errors = c(errors, "Objects must appear in ascending order.")
    }
  }

  linked_oid = paste0(object_type$linked_to %||% "")[1]
  if (nzchar(linked_oid)) {
    linked_ids = character(0)
    if (!is.null(course_dir)) {
      linked = tryCatch(ullme_read_course_object_index(course_dir, linked_oid), error=function(e) NULL)
      if (!is.null(linked)) {
        linked_type = tryCatch(ullme_read_object_type(linked_oid), error=function(e) list(type="doc"))
        linked_ids = vapply(
          ullme_object_index_instances(linked, linked_oid),
          ullme_object_instance_id,
          character(1),
          object_type=linked_type
        )
      }
    }
    for (i in seq_along(instances)) {
      linked_to = paste0(instances[[i]]$linked_to %||% "")[1]
      if (!nzchar(linked_to)) {
        errors = c(errors, paste0("objects[", i, "] requires linked_to for object type ", linked_oid, "."))
      } else if (length(linked_ids) > 0 && !linked_to %in% linked_ids) {
        errors = c(errors, paste0("objects[", i, "].linked_to references unknown ", linked_oid, " object '", linked_to, "'."))
      }
    }
    mappings = vapply(instances, function(instance) {
      paste0(instance$linked_to %||% "")[1]
    }, character(1))
    duplicated_mappings = unique(mappings[nzchar(mappings) & duplicated(mappings)])
    if (length(duplicated_mappings) > 0) {
      warnings = c(warnings, paste0("Multiple ", oid, " objects map to ",
                                    linked_oid, " object", if (length(duplicated_mappings) > 1) "s " else " ",
                                    paste(duplicated_mappings, collapse=", "), "."))
    }
  }

  ullme_validation_result(length(errors) == 0, unique(errors), unique(warnings), value)
}


ullme_validate_object_index_yaml = function(content, oid, course_dir=NULL,
                                             require_files=TRUE) {
  parsed = ullme_parse_yaml_text(content, paste0(oid, ".yaml"))
  if (!parsed$ok) return(parsed)
  ullme_validate_object_index_value(
    value=parsed$value,
    oid=oid,
    course_dir=course_dir,
    require_files=require_files
  )
}


ullme_read_course_object_index = function(course_dir, oid) {
  path = ullme_existing_course_object_index_path(course_dir, oid)
  if (!file.exists(path)) return(NULL)
  result = ullme_parse_yaml_file(path)
  ullme_validation_stop(result)
  result$value
}


ullme_course_object_indexes = function(course_dir) {
  ids = ullme_object_type_ids()
  indexes = lapply(ids, function(oid) ullme_read_course_object_index(course_dir, oid))
  names(indexes) = ids
  indexes[!vapply(indexes, is.null, logical(1))]
}
