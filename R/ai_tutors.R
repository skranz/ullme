ullme_package_dir = function(subdir) {
  restore.point("ullme_package_dir")
  path = system.file(subdir, package="ullme")
  if (nzchar(path)) return(path)

  source_path = file.path(getwd(), "inst", subdir)
  if (dir.exists(source_path)) return(normalizePath(source_path, winslash="/"))
  source_path
}


ullme_definition_ids = function(root) {
  restore.point("ullme_definition_ids")
  if (length(root) == 0 || !dir.exists(root)) return(character(0))
  entries = list.files(root, full.names=TRUE, no..=TRUE)
  ids = basename(entries[dir.exists(entries)])
  sort(ids[grepl("^[A-Za-z][A-Za-z0-9_-]*$", ids)])
}


ullme_ai_tutor_definition_roots = function(app=getApp()) {
  restore.point("ullme_ai_tutor_definition_roots")
  course_dir = ullme_active_course_dir(app=app)
  list(
    course=if (is.null(course_dir)) character(0) else
      ullme_course_ai_tutors_dir(course_dir),
    package=ullme_package_dir("ai_tutors")
  )
}


ullme_ai_tutor_template_paths = function() {
  restore.point("ullme_ai_tutor_template_paths")
  root = ullme_package_dir("ai_tutors")
  if (!dir.exists(root)) return(character(0))
  paths = list.files(
    root,
    pattern="^[A-Za-z][A-Za-z0-9_-]*\\.ya?ml$",
    full.names=TRUE,
    ignore.case=TRUE,
    no..=TRUE
  )
  paths = paths[!grepl("_old\\.ya?ml$", basename(paths), ignore.case=TRUE)]
  sort(paths)
}


ullme_ai_tutor_template_path = function(tutorid) {
  restore.point("ullme_ai_tutor_template_path")
  tutorid = ullme_clean_definition_id(tutorid)
  paths = ullme_ai_tutor_template_paths()
  ids = tools::file_path_sans_ext(basename(paths))
  found = paths[ids == tutorid]
  if (length(found) == 0) return(NULL)
  found[[1]]
}


ullme_ai_tutor_definition = function(tutorid, app=getApp()) {
  restore.point("ullme_ai_tutor_definition")
  ullme_ai_tutor_definition_at(tutorid=tutorid, source="course", app=app)
}


ullme_ai_tutor_definition_at = function(tutorid, source, app=getApp()) {
  restore.point("ullme_ai_tutor_definition_at")
  tutorid = ullme_clean_definition_id(tutorid)
  source = paste0(source)[1]
  path = if (identical(source, "course")) {
    course_dir = ullme_active_course_dir(app=app)
    if (is.null(course_dir)) NULL else
      ullme_existing_course_ai_tutor_path(course_dir, tutorid)
  } else if (identical(source, "package")) {
    ullme_ai_tutor_template_path(tutorid)
  } else {
    NULL
  }
  if (is.null(path) || !file.exists(path)) return(NULL)
  content = paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n")
  ullme_normalize_ai_tutor_content(
    content=content,
    tutorid=tutorid,
    source=source
  )
}


ullme_ai_tutor_catalog = function(app=getApp()) {
  restore.point("ullme_ai_tutor_catalog")
  paths = ullme_ai_tutor_template_paths()
  definitions = lapply(paths, function(path) {
    tutorid = tools::file_path_sans_ext(basename(path))
    ullme_ai_tutor_definition_at(
      tutorid=tutorid,
      source="package",
      app=app
    )
  })
  definitions = definitions[!vapply(definitions, is.null, logical(1))]
  definitions[order(vapply(definitions, function(x) x$label, character(1)))]
}


ullme_ai_tutor_template_definition = function(tutorid, app=getApp()) {
  restore.point("ullme_ai_tutor_template_definition")
  ullme_ai_tutor_definition_at(tutorid=tutorid, source="package", app=app)
}


ullme_clean_definition_id = function(id) {
  restore.point("ullme_clean_definition_id")
  id = paste0(id)[1]
  if (is.na(id) || !grepl("^[A-Za-z][A-Za-z0-9_-]*$", id)) {
    stop("Definition IDs must start with a letter and contain only letters, numbers, underscores, or hyphens.")
  }
  id
}


ullme_clean_tutor_instance_id = function(id) {
  restore.point("ullme_clean_tutor_instance_id")
  id = paste0(id)[1]
  if (is.na(id) || !grepl("^[A-Za-z0-9][A-Za-z0-9_.-]*$", id)) {
    stop("Tutor instance IDs may contain letters, numbers, dots, underscores, or hyphens.")
  }
  id
}


ullme_normalize_tutor_doc_specs = function(value, allow_fixed_paths=FALSE) {
  restore.point("ullme_normalize_tutor_doc_specs")
  if (is.null(value) || length(value) == 0 || !is.list(value)) return(list())
  ids = names(value)
  if (is.null(ids)) return(list())
  specs = lapply(seq_along(value), function(i) {
    spec = value[[i]]
    fixed_path = ""
    if (isTRUE(allow_fixed_paths) &&
        is.character(spec) && length(spec) == 1L && !is.na(spec)) {
      fixed_path = gsub("\\\\", "/", trimws(spec))
      spec = list()
    }
    if (!is.list(spec)) spec = list()
    file_types = spec$file_types %||% spec$pref_format %||% list()
    list(
      docid=paste0(ids[[i]])[1],
      descr=paste0(spec$descr %||% "")[1],
      file_types=as.list(paste0(unlist(file_types, use.names=FALSE))),
      pref_doc_dir=paste0(spec$pref_doc_dir %||% "")[1],
      add_images=isTRUE(spec$add_images),
      fixed_path=fixed_path
    )
  })
  names(specs) = ids
  specs
}


ullme_tutor_doc_specs_for_js = function(specs) {
  restore.point("ullme_tutor_doc_specs_for_js")
  unname(specs)
}


ullme_normalize_tutor_placeholder_documents = function(value) {
  restore.point("ullme_normalize_tutor_placeholder_documents")
  if (is.null(value) || !is.list(value) || is.null(names(value))) {
    return(list())
  }
  result = lapply(seq_along(value), function(i) {
    path = value[[i]]
    if (!is.character(path) || length(path) != 1L || is.na(path)) return(NULL)
    list(
      placeholder=paste0(names(value)[[i]])[1],
      path=gsub("\\\\", "/", trimws(path))
    )
  })
  result = Filter(Negate(is.null), result)
  names(result) = vapply(
    result,
    function(document) document$placeholder,
    character(1)
  )
  result
}


ullme_tutor_placeholder_documents_for_js = function(documents) {
  unname(documents)
}


ullme_normalize_tutor_file_permissions = function(value) {
  restore.point("ullme_normalize_tutor_file_permissions")
  if (is.null(value) || !is.list(value)) return(list())
  permissions = lapply(value, function(permission) {
    if (!is.list(permission)) return(NULL)
    type = tolower(trimws(paste0(permission$type %||% "")[1]))
    if (identical(type, "read_and_write")) type = "write_and_read"
    main_path = gsub(
      "\\\\", "/",
      trimws(paste0(permission$main_path %||% "")[1])
    )
    directories = unique(gsub(
      "\\\\", "/",
      trimws(paste0(unlist(
        permission$directories %||% list(),
        use.names=FALSE
      )))
    ))
    directories = gsub("^/+|/+$", "", directories[nzchar(directories)])
    extensions = unique(tolower(gsub(
      "^\\.+", "",
      trimws(paste0(unlist(
        permission$extensions %||% list(),
        use.names=FALSE
      )))
    )))
    list(
      type=type,
      main_path=gsub("^/+|/+$", "", main_path),
      directories=as.list(directories),
      recursive=isTRUE(permission$recursive),
      extensions=as.list(extensions[nzchar(extensions)])
    )
  })
  Filter(Negate(is.null), permissions)
}


ullme_normalize_ai_tutor_definition = function(definition, tutorid, source) {
  restore.point("ullme_normalize_ai_tutor_definition")
  if (!is.list(definition)) definition = list()
  per_instance = ullme_normalize_tutor_doc_specs(definition$docs_per_instance)
  per_course = ullme_normalize_tutor_doc_specs(definition$docs_per_course)
  placeholder_documents = ullme_normalize_tutor_placeholder_documents(
    definition$placeholder_documents
  )
  default_node_args = definition$default_node_args %||% list()
  if (!is.list(default_node_args) ||
      (length(default_node_args) && is.null(names(default_node_args)))) {
    default_node_args = list()
  }
  nodes = definition$nodes %||% list()
  if (!is.list(nodes) || is.null(names(nodes))) nodes = list()
  node_yaml = lapply(nodes, function(node) {
    trimws(yaml::as.yaml(node))
  })
  nodes = lapply(nodes, function(node) {
    if (!is.list(node)) return(list())
    inherited = default_node_args
    inherited[names(node)] = node
    node = inherited
    node$prompt = paste0(node$prompt %||% "", collapse="\n")
    node$waiting_message = paste0(
      node$waiting_message %||% "",
      collapse="\n"
    )
    node$show_before = paste0(node$show_before %||% "", collapse="\n")
    node$show_after = paste0(node$show_after %||% "", collapse="\n")
    node$show_text = paste0(node$show_text %||% "", collapse="\n")
    node[["next"]] = paste0(node[["next"]] %||% "")[1]
    node$switch_input = paste0(node$switch_input %||% "")[1]
    if (is.list(node$switch_to)) {
      names(node$switch_to) = paste0(names(node$switch_to))
      node$switch_to = lapply(node$switch_to, function(target) {
        paste0(target %||% "")[1]
      })
    }
    node$n_parallel = as.integer(node$n_parallel %||% 1L)[1]
    node$n_retries = as.integer(node$n_retries %||% 0L)[1]
    node$retries_if_empty = as.integer(node$retries_if_empty %||% 0L)[1]
    node$postfix_wait_retry_if_empty = paste0(
      node$postfix_wait_retry_if_empty %||% "",
      collapse="\n"
    )
    node$aggregate = paste0(node$aggregate %||% "")[1]
    node$ask_for_input = isTRUE(node$ask_for_input)
    node$add_to_history = !identical(node$add_to_history, FALSE)
    node
  })
  fragments = definition$prompt_fragments %||% list()
  if (!is.list(fragments) || is.null(names(fragments))) fragments = list()
  fragments = lapply(fragments, function(fragment) {
    paste0(fragment %||% "", collapse="\n")
  })
  list(
    tutorid=tutorid,
    lang=paste0(definition$lang %||% "")[1],
    label=paste0(definition$label %||% tutorid)[1],
    description=paste0(definition$description %||% "", collapse="\n"),
    instance_guidance=paste0(
      definition$instance_guidance %||% "",
      collapse="\n"
    ),
    source=source,
    enabled=!identical(definition$enabled, FALSE),
    is_valid=TRUE,
    validation_errors=list(),
    validation_warnings=list(),
    multiple_instances=!identical(definition$multiple_instances, FALSE),
    chat_history=isTRUE(definition$chat_history),
    show_final_output=!identical(definition$show_final_output, FALSE),
    default_node_args=default_node_args,
    start_node=paste0(definition$start_node %||% "")[1],
    nodes=nodes,
    node_yaml=node_yaml,
    prompt_fragments=fragments,
    shown_text=paste0(definition$shown_text %||% "", collapse="\n"),
    default_personality=paste0(
      definition$default_personality %||% "",
      collapse="\n"
    ),
    docs_per_instance=ullme_tutor_doc_specs_for_js(per_instance),
    docs_per_course=ullme_tutor_doc_specs_for_js(per_course),
    placeholder_documents=ullme_tutor_placeholder_documents_for_js(
      placeholder_documents
    ),
    doc_ids_per_instance=as.list(names(per_instance)),
    doc_ids_per_course=as.list(names(per_course)),
    placeholder_document_ids=as.list(names(placeholder_documents)),
    allowed_tools=as.list(paste0(unlist(
      definition$allowed_tools %||% list(),
      use.names=FALSE
    ))),
    allowed_student_customization=as.list(paste0(unlist(
      definition$allowed_student_customization %||% list(),
      use.names=FALSE
    ))),
    file_permissions=ullme_normalize_tutor_file_permissions(
      definition$file_permissions
    ),
    yaml_content=ullme_ai_tutor_yaml(definition)
  )
}


ullme_tutor_validation_state = function(tutorid, content) {
  restore.point("ullme_tutor_validation_state")
  validation = tryCatch(
    ullme_validate_tutor_yaml(tutorid=tutorid, content=content),
    error=function(error) ullme_validation_result(
      ok=FALSE,
      errors=conditionMessage(error)
    )
  )
  list(
    is_valid=isTRUE(validation$ok),
    errors=as.list(paste0(unlist(validation$errors, use.names=FALSE))),
    warnings=as.list(paste0(unlist(validation$warnings, use.names=FALSE)))
  )
}


ullme_normalize_ai_tutor_content = function(content, tutorid,
                                             source="course") {
  restore.point("ullme_normalize_ai_tutor_content")
  content = paste0(content %||% "", collapse="\n")
  value = tryCatch(
    yaml::yaml.load(content, eval.expr=FALSE),
    error=function(error) NULL
  )
  if (!is.list(value)) {
    value = list(
      tutorid=tutorid,
      label=tutorid,
      description="Invalid Tutor definition",
      enabled=TRUE,
      nodes=list()
    )
  }
  definition = ullme_normalize_ai_tutor_definition(
    definition=value,
    tutorid=tutorid,
    source=source
  )
  validity = ullme_tutor_validation_state(tutorid=tutorid, content=content)
  definition$is_valid = validity$is_valid
  definition$validation_errors = validity$errors
  definition$validation_warnings = validity$warnings
  definition$yaml_content = content
  definition
}


ullme_ai_tutor_yaml = function(value) {
  restore.point("ullme_ai_tutor_yaml")
  content = trimws(yaml::as.yaml(value))
  content = sub(
    "(?m)^docs_per_instance: \\[\\]$",
    "docs_per_instance: {}",
    content,
    perl=TRUE
  )
  content = sub(
    "(?m)^docs_per_course: \\[\\]$",
    "docs_per_course: {}",
    content,
    perl=TRUE
  )
  sub(
    "(?m)^placeholder_documents: \\[\\]$",
    "placeholder_documents: {}",
    content,
    perl=TRUE
  )
}


ullme_course_ai_tutors_dir = function(course_dir) {
  restore.point("ullme_course_ai_tutors_dir")
  file.path(course_dir, "ai_tutors")
}


ullme_course_ai_tutor_dir = function(course_dir, tutorid) {
  restore.point("ullme_course_ai_tutor_dir")
  file.path(
    ullme_course_ai_tutors_dir(course_dir),
    ullme_clean_definition_id(tutorid)
  )
}


ullme_course_ai_tutor_path = function(course_dir, tutorid) {
  restore.point("ullme_course_ai_tutor_path")
  file.path(ullme_course_ai_tutor_dir(course_dir, tutorid), "tutor.yml")
}


ullme_existing_course_ai_tutor_path = function(course_dir, tutorid) {
  restore.point("ullme_existing_course_ai_tutor_path")
  directory = ullme_course_ai_tutor_dir(course_dir, tutorid)
  candidates = file.path(directory, c("tutor.yml", "tutor.yaml"))
  found = candidates[file.exists(candidates)]
  if (length(found) > 0) found[[1]] else candidates[[1]]
}


ullme_course_ai_tutor_instances_path = function(course_dir, tutorid) {
  restore.point("ullme_course_ai_tutor_instances_path")
  file.path(ullme_course_ai_tutor_dir(course_dir, tutorid), "instances.yml")
}


ullme_tutor_document_paths = function(value) {
  restore.point("ullme_tutor_document_paths")
  paths = paste0(unlist(value %||% list(), use.names=FALSE))
  unique(gsub("\\\\", "/", paths[nzchar(paths)]))
}


ullme_read_course_ai_tutor_instances = function(course_dir, tutorid) {
  restore.point("ullme_read_course_ai_tutor_instances")
  path = ullme_course_ai_tutor_instances_path(course_dir, tutorid)
  if (!file.exists(path)) {
    return(list(instances=list(), course_docs=list(), exists=FALSE))
  }
  value = tryCatch(yaml::read_yaml(path), error=function(e) NULL)
  if (!is.list(value)) {
    return(list(instances=list(), course_docs=list(), exists=TRUE))
  }
  instances = value$instances %||% list()
  instances = lapply(instances, function(instance) {
    if (!is.list(instance)) return(NULL)
    docs = instance$docs %||% list()
    docs = lapply(docs, ullme_tutor_document_paths)
    list(
      instanceid=paste0(instance$instanceid %||% instance$id %||% "")[1],
      label=paste0(instance$label %||% instance$instanceid %||%
        instance$id %||% "")[1],
      docs=docs,
      source="saved"
    )
  })
  instances = instances[!vapply(instances, is.null, logical(1))]
  course_docs = lapply(value$course_docs %||% list(), ullme_tutor_document_paths)
  list(instances=instances, course_docs=course_docs, exists=TRUE)
}


ullme_tutor_spec_files = function(course_dir, spec) {
  restore.point("ullme_tutor_spec_files")
  directory = paste0(spec$pref_doc_dir %||% "")[1]
  if (!ullme_safe_relative_material_path(directory)) return(character(0))
  root = file.path(course_dir, "materials", directory)
  if (!dir.exists(root)) return(character(0))
  paths = list.files(
    root,
    recursive=TRUE,
    full.names=FALSE,
    no..=TRUE,
    include.dirs=FALSE
  )
  allowed = ullme_tutor_file_types(spec$file_types)
  keep = tolower(tools::file_ext(paths)) %in% allowed
  paths = paths[keep]
  sort(gsub("\\\\", "/", file.path(directory, paths)))
}


ullme_tutor_file_key = function(path, docid, directory="") {
  restore.point("ullme_tutor_file_key")
  path = gsub("\\\\", "/", paste0(path)[1])
  directory = gsub("\\\\", "/", paste0(directory %||% "")[1])
  relative = if (nzchar(directory) && startsWith(path, paste0(directory, "/"))) {
    substring(path, nchar(directory) + 2L)
  } else path
  parent = dirname(relative)
  stem = tolower(tools::file_path_sans_ext(basename(relative)))
  tokens = unique(c(
    tolower(docid),
    unlist(strsplit(tolower(docid), "[_-]+")),
    "solution", "solutions", "sol", "answer", "answers"
  ))
  tokens = tokens[nzchar(tokens)]
  suffix = paste0("([_-](", paste(ullme_regex_escape(tokens), collapse="|"), "))+$")
  stem = sub(suffix, "", stem, perl=TRUE)
  key = paste(if (!parent %in% c("", ".")) parent else "", stem, sep="_")
  key = gsub("[^a-z0-9]+", "_", key)
  gsub("^_+|_+$", "", key)
}


ullme_regex_escape = function(x) {
  restore.point("ullme_regex_escape")
  gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", paste0(x), perl=TRUE)
}


ullme_tutor_role_tokens = function(docid, spec=list()) {
  text = tolower(paste(
    docid,
    paste0(spec$descr %||% "", collapse=" "),
    paste0(spec$description %||% "", collapse=" ")
  ))
  tokens = unlist(strsplit(tolower(docid), "[_-]+"))
  if (grepl("solution|solutions|(^|[^a-z])sol([^a-z]|$)|answer|loesung|lösung",
            text, perl=TRUE)) {
    tokens = c(
      tokens,
      "solution", "solutions", "sol", "answer", "answers",
      "loesung", "loesungen"
    )
  }
  unique(tokens[nzchar(tokens) & nchar(tokens) > 1L])
}


ullme_tutor_files_with_role = function(files, tokens) {
  if (!length(files) || !length(tokens)) return(character(0))
  pattern = paste0(
    "(^|[_-])(",
    paste(ullme_regex_escape(tokens), collapse="|"),
    ")([_-]|$)"
  )
  files[grepl(
    pattern,
    tolower(tools::file_path_sans_ext(basename(files))),
    perl=TRUE
  )]
}


ullme_suggest_course_ai_tutor_instances = function(course_dir, definition) {
  restore.point("ullme_suggest_course_ai_tutor_instances")
  specs = ullme_normalize_tutor_doc_specs(definition$docs_per_instance)
  if (length(specs) == 0) return(list())
  docids = names(specs)
  files = lapply(specs, function(spec) ullme_tutor_spec_files(course_dir, spec))
  anchor = docids[[1]]
  anchor_files = files[[anchor]]
  if (length(anchor_files) == 0) return(list())

  other_tokens = unique(unlist(Map(
    ullme_tutor_role_tokens,
    docids[-1],
    specs[docids[-1]]
  )))
  if (length(other_tokens) > 0) {
    secondary_files = ullme_tutor_files_with_role(anchor_files, other_tokens)
    anchor_files = setdiff(anchor_files, secondary_files)
  }
  anchor_keys = vapply(
    anchor_files,
    ullme_tutor_file_key,
    character(1),
    docid=anchor,
    directory=specs[[anchor]]$pref_doc_dir
  )
  unique_keys = unique(anchor_keys[nzchar(anchor_keys)])
  lapply(unique_keys, function(key) {
    docs = list()
    docs[[anchor]] = as.list(ullme_preferred_document_file(
      anchor_files[anchor_keys == key],
      specs[[anchor]]$file_types
    ))
    for (docid in docids[-1]) {
      role_files = files[[docid]]
      marked_files = ullme_tutor_files_with_role(
        role_files,
        ullme_tutor_role_tokens(docid, specs[[docid]])
      )
      if (length(marked_files)) role_files = marked_files
      candidate_keys = vapply(
        role_files,
        ullme_tutor_file_key,
        character(1),
        docid=docid,
        directory=specs[[docid]]$pref_doc_dir
      )
      docs[[docid]] = as.list(ullme_preferred_document_file(
        role_files[candidate_keys == key],
        specs[[docid]]$file_types
      ))
    }
    list(instanceid=key, label=key, docs=docs, source="suggested")
  })
}


ullme_course_ai_tutors = function(app=getApp()) {
  restore.point("ullme_course_ai_tutors")
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) return(list())
  instance_builder_inputs = ullme_form_input_choices(
    "instance_builder",
    course_dir=course_dir,
    app=app
  )
  root = ullme_course_ai_tutors_dir(course_dir)
  ids = ullme_definition_ids(root)
  tutors = lapply(ids, function(tutorid) {
    path = ullme_existing_course_ai_tutor_path(course_dir, tutorid)
    if (!file.exists(path)) return(NULL)
    content = paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n")
    value = tryCatch(yaml::yaml.load(content, eval.expr=FALSE), error=function(e) NULL)
    if (is.list(value)) {
      value = ullme_materialize_course_ai_tutor(
        tutorid=tutorid,
        course_tutor=value,
        path=path,
        app=app
      )
      content = ullme_ai_tutor_yaml(value)
    } else {
      value = list(tutorid=tutorid, enabled=TRUE)
    }
    definition = ullme_normalize_ai_tutor_content(
      content=content,
      tutorid=tutorid,
      source="course"
    )
    has_instances = !identical(value$multiple_instances, FALSE)
    instance_data = if (has_instances) {
      ullme_read_course_ai_tutor_instances(course_dir, tutorid)
    } else {
      list(instances=list(), course_docs=list(), exists=FALSE)
    }
    suggestions = if (has_instances) {
      ullme_suggest_course_ai_tutor_instances(course_dir, value)
    } else {
      list()
    }
    instances = instance_data$instances
    if (has_instances && !isTRUE(instance_data$exists)) instances = suggestions
    definition$instances = instances
    definition$suggested_instances = suggestions
    definition$course_docs = instance_data$course_docs
    definition$instance_count = length(instances)
    definition$instance_assignments_saved =
      has_instances && isTRUE(instance_data$exists)
    definition$instances_yaml_content = if (has_instances) {
      ullme_course_ai_tutor_instances_yaml(
        course_dir=course_dir,
        tutorid=tutorid,
        instances=instances,
        course_docs=instance_data$course_docs
      )
    } else {
      ""
    }
    definition$instance_builder_inputs =
      if (has_instances) instance_builder_inputs else list()
    definition$edit_history = list(
      definition=ullme_edit_history_state(
        scope="tutor_definition",
        tutorid=tutorid,
        app=app
      ),
      instances=ullme_edit_history_state(
        scope="tutor_instances",
        tutorid=tutorid,
        app=app
      )
    )
    conversion_specs = c(
      ullme_normalize_tutor_doc_specs(value$docs_per_instance),
      ullme_normalize_tutor_doc_specs(value$docs_per_course)
    )
    conversion_files = unique(unlist(lapply(
      conversion_specs,
      function(spec) ullme_tutor_spec_files(course_dir, spec)
    ), use.names=FALSE))
    definition$conversion_files = as.list(sort(conversion_files))
    definition$conversion_input_formats = as.list(ullme_document_input_formats())
    definition$conversion_output_formats = as.list(ullme_document_output_formats())
    definition
  })
  tutors = tutors[!vapply(tutors, is.null, logical(1))]
  tutors[order(vapply(tutors, function(x) x$label, character(1)))]
}


ullme_tutor_instances_yaml = function(instances=list(), course_docs=list()) {
  trimws(yaml::as.yaml(list(
    course_docs=course_docs %||% list(),
    instances=instances %||% list()
  )))
}


ullme_course_ai_tutor_instances_yaml = function(course_dir, tutorid,
                                                 instances=list(),
                                                 course_docs=list()) {
  path = ullme_course_ai_tutor_instances_path(course_dir, tutorid)
  if (file.exists(path)) {
    return(paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n"))
  }
  ullme_tutor_instances_yaml(instances=instances, course_docs=course_docs)
}


ullme_materialize_course_ai_tutor = function(tutorid, course_tutor, path,
                                              app=getApp()) {
  restore.point("ullme_materialize_course_ai_tutor")
  fields = setdiff(names(course_tutor), c("tutorid", "enabled"))
  if (length(fields) > 0) return(course_tutor)
  template_path = ullme_ai_tutor_template_path(tutorid)
  if (is.null(template_path)) return(course_tutor)
  value = tryCatch(yaml::read_yaml(template_path), error=function(e) NULL)
  if (!is.list(value)) return(course_tutor)
  value$tutorid = tutorid
  value$enabled = !identical(course_tutor$enabled, FALSE)
  writeLines(ullme_ai_tutor_yaml(value), path, useBytes=TRUE)
  value
}


ullme_add_course_ai_tutor = function(templateid=NULL, tutorid=NULL,
                                      app=getApp()) {
  restore.point("ullme_add_course_ai_tutor")
  if (!identical(app$role, "teacher")) stop("Only teachers can add AI Tutors.")
  if (is.null(templateid)) templateid = tutorid
  if (is.null(tutorid)) tutorid = templateid
  templateid = ullme_clean_definition_id(templateid)
  tutorid = ullme_clean_definition_id(tutorid)
  template_path = ullme_ai_tutor_template_path(templateid)
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(template_path)) stop("The selected AI Tutor template was not found.")
  if (is.null(course_dir)) stop("Select a course first.")
  tutor_dir = ullme_course_ai_tutor_dir(course_dir, tutorid)
  if (dir.exists(tutor_dir)) stop("An AI Tutor with this Tutor ID already exists.")

  value = yaml::read_yaml(template_path)
  value$tutorid = tutorid
  value$enabled = TRUE
  stage = ullme_tempdir(pattern=".ullme-course-tutor-", app=app)
  on.exit(ullme_remove_tempdir(stage, app=app), add=TRUE)
  writeLines(ullme_ai_tutor_yaml(value), file.path(stage, "tutor.yml"), useBytes=TRUE)
  operation = ullme_new_change(
    action="course_tutor_add",
    summary=paste0("Add AI Tutor ", tutorid, " to course ", app$courseid),
    origin="ui",
    details=list(courseid=app$courseid, tutorid=tutorid),
    changes=list(ullme_change_copy(stage, tutor_dir, overwrite=FALSE)),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  isTRUE(result$ok)
}


ullme_delete_course_ai_tutor = function(tutorid, app=getApp()) {
  restore.point("ullme_delete_course_ai_tutor")
  if (!identical(app$role, "teacher")) stop("Only teachers can delete AI Tutors.")
  tutorid = ullme_clean_definition_id(tutorid)
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) stop("Select a course first.")
  tutor_dir = ullme_course_ai_tutor_dir(course_dir, tutorid)
  if (!dir.exists(tutor_dir)) stop("The selected AI Tutor no longer exists.")
  operation = ullme_new_change(
    action="course_tutor_delete",
    summary=paste0("Delete AI Tutor ", tutorid, " from course ", app$courseid),
    origin="ui",
    details=list(courseid=app$courseid, tutorid=tutorid),
    changes=list(ullme_change_delete(tutor_dir)),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  isTRUE(result$ok)
}


ullme_set_course_ai_tutor_enabled = function(tutorid, enabled, app=getApp()) {
  restore.point("ullme_set_course_ai_tutor_enabled")
  if (!identical(app$role, "teacher")) return(FALSE)
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) return(FALSE)
  path = ullme_existing_course_ai_tutor_path(course_dir, tutorid)
  if (!file.exists(path)) return(FALSE)
  value = yaml::read_yaml(path)
  if (!is.list(value)) value = list()
  value$tutorid = ullme_clean_definition_id(tutorid)
  value$enabled = isTRUE(enabled)
  operation = ullme_new_change(
    action="course_tutor_toggle",
    summary=paste0(if (isTRUE(enabled)) "Enable" else "Disable",
                   " AI Tutor ", tutorid, " for course ", app$courseid),
    origin="ui",
    details=list(courseid=app$courseid, tutorid=tutorid, enabled=isTRUE(enabled)),
    changes=list(ullme_change_write(path, ullme_ai_tutor_yaml(value))),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  isTRUE(result$ok)
}


ullme_tutor_doc_specs_from_rows = function(rows, allow_fixed_paths=FALSE) {
  restore.point("ullme_tutor_doc_specs_from_rows")
  if (!is.list(rows)) return(list())
  result = list()
  for (row in rows) {
    if (!is.list(row)) next
    docid = ullme_clean_definition_id(row$docid)
    fixed_path = gsub(
      "\\\\", "/",
      trimws(paste0(row$fixed_path %||% "")[1])
    )
    if (isTRUE(allow_fixed_paths) && nzchar(fixed_path)) {
      if (!ullme_safe_relative_material_path(fixed_path)) {
        stop("Fixed course document paths must be relative material paths.")
      }
      result[[docid]] = fixed_path
      next
    }
    file_types = unique(trimws(paste0(unlist(
      row$file_types %||% list(),
      use.names=FALSE
    ))))
    result[[docid]] = list(
      descr=paste0(row$descr %||% "")[1],
      file_types=as.list(file_types[nzchar(file_types)]),
      pref_doc_dir=paste0(row$pref_doc_dir %||% "")[1],
      add_images=isTRUE(row$add_images)
    )
  }
  result
}


ullme_tutor_placeholder_documents_from_rows = function(rows) {
  restore.point("ullme_tutor_placeholder_documents_from_rows")
  if (!is.list(rows)) return(list())
  result = list()
  for (row in rows) {
    if (!is.list(row)) next
    placeholder = ullme_clean_definition_id(row$placeholder)
    path = gsub("\\\\", "/", trimws(paste0(row$path %||% "")[1]))
    if (!ullme_safe_relative_material_path(path)) {
      stop("Placeholder document paths must be relative material paths.")
    }
    result[[placeholder]] = path
  }
  result
}


ullme_tutor_file_permissions_from_rows = function(rows) {
  restore.point("ullme_tutor_file_permissions_from_rows")
  permissions = ullme_normalize_tutor_file_permissions(rows)
  lapply(permissions, function(permission) {
    list(
      type=permission$type,
      main_path=permission$main_path,
      directories=permission$directories,
      recursive=permission$recursive,
      extensions=permission$extensions
    )
  })
}


ullme_save_course_ai_tutor = function(tutorid, mode=c("ui", "yaml"),
                                       yaml_content=NULL, fields=NULL,
                                       app=getApp()) {
  restore.point("ullme_save_course_ai_tutor")
  if (!identical(app$role, "teacher")) stop("Only teachers can edit AI Tutors.")
  tutorid = ullme_clean_definition_id(tutorid)
  mode = match.arg(mode)
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) stop("Select a course first.")
  path = ullme_existing_course_ai_tutor_path(course_dir, tutorid)
  if (!file.exists(path)) stop("This AI Tutor is not part of the course.")

  if (identical(mode, "yaml")) {
    content = paste0(yaml_content %||% "", collapse="\n")
  } else {
    current = tryCatch(
      yaml::read_yaml(path, eval.expr=FALSE),
      error=function(error) NULL
    )
    if (!is.list(current)) {
      stop("Use Tutor YAML to repair the invalid Tutor definition.")
    }
    if (!is.list(fields)) fields = list()
    current$tutorid = tutorid
    has_field = function(name) name %in% names(fields)
    if (has_field("lang")) current$lang = paste0(fields$lang)[1]
    if (has_field("label")) current$label = paste0(fields$label)[1]
    if (has_field("description")) {
      current$description = paste0(fields$description, collapse="\n")
    }
    if (has_field("instance_guidance")) {
      current$instance_guidance = paste0(
        fields$instance_guidance,
        collapse="\n"
      )
    }
    if (has_field("shown_text")) {
      current$shown_text = paste0(fields$shown_text, collapse="\n")
    }
    if (has_field("default_personality")) {
      current$default_personality = paste0(
        fields$default_personality,
        collapse="\n"
      )
    }
    if (has_field("multiple_instances")) {
      current$multiple_instances = isTRUE(fields$multiple_instances)
    }
    if (has_field("chat_history")) {
      current$chat_history = isTRUE(fields$chat_history)
    }
    if (has_field("show_final_output")) {
      current$show_final_output = isTRUE(fields$show_final_output)
    }
    if (has_field("file_permissions")) {
      current$file_permissions = ullme_tutor_file_permissions_from_rows(
        fields$file_permissions %||% list()
      )
    }
    if (has_field("docs_per_instance")) {
      current$docs_per_instance = ullme_tutor_doc_specs_from_rows(
        fields$docs_per_instance %||% list()
      )
    }
    if (has_field("docs_per_course")) {
      current$docs_per_course = ullme_tutor_doc_specs_from_rows(
        fields$docs_per_course %||% list()
      )
    }
    if (has_field("placeholder_documents")) {
      current$placeholder_documents =
        ullme_tutor_placeholder_documents_from_rows(
          fields$placeholder_documents %||% list()
        )
    }
    if (has_field("allowed_tools")) {
      current$allowed_tools = as.list(unique(trimws(paste0(unlist(
        fields$allowed_tools %||% list(),
        use.names=FALSE
      )))))
      current$allowed_tools =
        current$allowed_tools[nzchar(unlist(current$allowed_tools))]
    }
    if (has_field("allowed_student_customization")) {
      current$allowed_student_customization = as.list(unique(trimws(paste0(unlist(
        fields$allowed_student_customization %||% list(),
        use.names=FALSE
      )))))
      current$allowed_student_customization =
        current$allowed_student_customization[
          nzchar(unlist(current$allowed_student_customization))
        ]
    }
    content = ullme_ai_tutor_yaml(current)
  }
  syntax = ullme_parse_yaml_text(content, label="Tutor YAML")
  ullme_validation_stop(syntax, prefix="Tutor YAML syntax is invalid")
  validity = ullme_tutor_validation_state(tutorid=tutorid, content=content)
  operation = ullme_new_change(
    action="definition_edit",
    summary=paste0("Save course AI Tutor ", tutorid),
    origin="ui",
    details=list(kind="tutor", definitionid=tutorid, source="course"),
    changes=list(ullme_change_write(path, content)),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  if (!isTRUE(result$ok)) stop(result$message %||% "Could not save the AI Tutor.")
  result$validation = validity
  result
}


ullme_validate_tutor_document_assignment = function(path, course_dir) {
  restore.point("ullme_validate_tutor_document_assignment")
  path = gsub("\\\\", "/", paste0(path)[1])
  if (!ullme_safe_relative_material_path(path)) {
    stop("Tutor document paths must be relative material paths.")
  }
  target = normalizePath(
    file.path(course_dir, "materials", path),
    winslash="/",
    mustWork=FALSE
  )
  root = normalizePath(
    file.path(course_dir, "materials"),
    winslash="/",
    mustWork=TRUE
  )
  if (!ullme_path_is_within(target, root, allow_root=FALSE) ||
      !file.exists(target) || dir.exists(target)) {
    stop("Tutor document does not exist: ", path)
  }
  path
}


ullme_save_course_ai_tutor_instances = function(tutorid, instances,
                                                 course_docs=NULL,
                                                 origin="ui",
                                                 app=getApp()) {
  restore.point("ullme_save_course_ai_tutor_instances")
  if (!identical(app$role, "teacher")) stop("Only teachers can edit AI Tutors.")
  tutorid = ullme_clean_definition_id(tutorid)
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) stop("Select a course first.")
  tutor_path = ullme_existing_course_ai_tutor_path(course_dir, tutorid)
  if (!file.exists(tutor_path)) stop("This AI Tutor is not part of the course.")
  definition = yaml::read_yaml(tutor_path)
  if (!is.list(definition)) stop("The course AI Tutor YAML is invalid.")
  if (identical(definition$multiple_instances, FALSE)) {
    stop("This AI Tutor is course-wide and does not use instances.")
  }
  instance_docids = names(
    ullme_normalize_tutor_doc_specs(definition$docs_per_instance)
  )
  course_docids = names(
    ullme_normalize_tutor_doc_specs(definition$docs_per_course)
  )

  clean_instances = list()
  seen_instanceids = character(0)
  for (instance in instances %||% list()) {
    if (!is.list(instance)) next
    instanceid = ullme_clean_tutor_instance_id(instance$instanceid)
    label = trimws(paste0(instance$label %||% instanceid)[1])
    if (!nzchar(label)) label = instanceid
    if (instanceid %in% seen_instanceids) {
      stop("Tutor instance IDs must be unique: ", instanceid)
    }
    seen_instanceids = c(seen_instanceids, instanceid)
    unknown_docids = setdiff(names(instance$docs %||% list()), instance_docids)
    if (length(unknown_docids) > 0) {
      stop(
        "Unknown per-instance document role",
        if (length(unknown_docids) > 1) "s" else "",
        ": ",
        paste(unknown_docids, collapse=", ")
      )
    }
    docs = lapply(instance$docs %||% list(), function(paths) {
      as.list(vapply(
        ullme_tutor_document_paths(paths),
        ullme_validate_tutor_document_assignment,
        character(1),
        course_dir=course_dir
      ))
    })
    clean_instances[[length(clean_instances) + 1L]] = list(
      instanceid=instanceid,
      label=label,
      docs=docs
    )
  }
  unknown_course_docids = setdiff(
    names(course_docs %||% list()),
    course_docids
  )
  if (length(unknown_course_docids) > 0) {
    stop(
      "Unknown course document role",
      if (length(unknown_course_docids) > 1) "s" else "",
      ": ",
      paste(unknown_course_docids, collapse=", ")
    )
  }
  clean_course_docs = lapply(course_docs %||% list(), function(paths) {
    as.list(vapply(
      ullme_tutor_document_paths(paths),
      ullme_validate_tutor_document_assignment,
      character(1),
      course_dir=course_dir
    ))
  })
  content = trimws(yaml::as.yaml(list(
    course_docs=clean_course_docs,
    instances=clean_instances
  )))
  path = ullme_course_ai_tutor_instances_path(course_dir, tutorid)
  operation = ullme_new_change(
    action="definition_edit",
    summary=paste0("Save AI Tutor instances for ", tutorid),
    origin=origin,
    details=list(kind="tutor_instances", tutorid=tutorid),
    changes=list(ullme_change_write(path, content)),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  if (!isTRUE(result$ok)) stop(result$message %||% "Could not save Tutor instances.")
  result
}


ullme_save_course_ai_tutor_instances_yaml = function(tutorid, yaml_content,
                                                      origin="ui",
                                                      app=getApp()) {
  parsed = ullme_parse_yaml_text(
    paste0(yaml_content %||% "", collapse="\n"),
    "instances.yml"
  )
  ullme_validation_stop(parsed)
  value = parsed$value
  if (!is.list(value)) stop("instances.yml must contain a YAML mapping.")
  unknown = setdiff(names(value), c("course_docs", "instances"))
  if (length(unknown)) {
    stop("Unknown instances.yml field", if (length(unknown) > 1) "s" else "",
         ": ", paste(unknown, collapse=", "))
  }
  ullme_save_course_ai_tutor_instances(
    tutorid=tutorid,
    instances=value$instances %||% list(),
    course_docs=value$course_docs %||% list(),
    origin=origin,
    app=app
  )
}


ullme_handle_ai_tutor_add = function(templateid=NULL, tutorid=NULL,
                                      app=getApp(), ...) {
  restore.point("ullme_handle_ai_tutor_add")
  result = tryCatch({
    added = ullme_add_course_ai_tutor(
      templateid=templateid,
      tutorid=tutorid,
      app=app
    )
    if (!isTRUE(added)) stop("The AI Tutor could not be added.")
    ullme_send_course_state(app=app)
    list(ok=TRUE, message="AI Tutor added.")
  }, error=function(e) {
    list(ok=FALSE, status="error", message=conditionMessage(e))
  })
  callJS(
    .fun="window.ullme.aiTutorAddComplete",
    .args=list(result),
    .app=app
  )
  invisible(result)
}


ullme_handle_ai_tutor_delete = function(tutorid=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_ai_tutor_delete")
  result = tryCatch({
    deleted = ullme_delete_course_ai_tutor(tutorid=tutorid, app=app)
    if (!isTRUE(deleted)) stop("The AI Tutor could not be deleted.")
    ullme_send_course_state(app=app)
    list(ok=TRUE, message="AI Tutor deleted.")
  }, error=function(e) {
    list(ok=FALSE, status="error", message=conditionMessage(e))
  })
  callJS(
    .fun="window.ullme.aiTutorDeleteComplete",
    .args=list(result),
    .app=app
  )
  invisible(result)
}


ullme_handle_ai_tutor_toggle = function(tutorid=NULL, enabled=FALSE,
                                         app=getApp(), ...) {
  restore.point("ullme_handle_ai_tutor_toggle")
  changed = tryCatch(
    ullme_set_course_ai_tutor_enabled(
      tutorid=tutorid,
      enabled=enabled,
      app=app
    ),
    error=function(e) FALSE
  )
  if (changed) ullme_send_course_state(app=app)
  invisible(changed)
}


ullme_handle_ai_tutor_save = function(tutorid=NULL, mode="ui",
                                       yaml_content=NULL, fields=NULL,
                                       app=getApp(), ...) {
  restore.point("ullme_handle_ai_tutor_save")
  result = tryCatch({
    saved = ullme_save_course_ai_tutor(
      tutorid=tutorid,
      mode=mode,
      yaml_content=yaml_content,
      fields=fields,
      app=app
    )
    ullme_send_course_state(app=app)
    list(
      ok=TRUE,
      message="AI Tutor saved.",
      validation=saved$validation
    )
  }, error=function(e) {
    list(ok=FALSE, message=conditionMessage(e))
  })
  callJS(
    .fun="window.ullme.aiTutorSaveComplete",
    .args=list(result),
    .app=app
  )
  invisible(result)
}


ullme_handle_ai_tutor_instances_save = function(tutorid=NULL, instances=NULL,
                                                 course_docs=NULL,
                                                 app=getApp(), ...) {
  restore.point("ullme_handle_ai_tutor_instances_save")
  result = tryCatch({
    ullme_save_course_ai_tutor_instances(
      tutorid=tutorid,
      instances=instances,
      course_docs=course_docs,
      app=app
    )
    ullme_send_course_state(app=app)
    list(
      ok=TRUE,
      kind="instances",
      tutorid=tutorid,
      message="Tutor instances saved."
    )
  }, error=function(e) {
    list(
      ok=FALSE,
      kind="instances",
      tutorid=tutorid,
      message=conditionMessage(e)
    )
  })
  callJS(
    .fun="window.ullme.aiTutorInstancesSaveComplete",
    .args=list(result),
    .app=app
  )
  invisible(result)
}


ullme_handle_ai_tutor_instances_yaml_save = function(tutorid=NULL,
                                                      yaml_content=NULL,
                                                      app=getApp(), ...) {
  result = tryCatch({
    ullme_save_course_ai_tutor_instances_yaml(
      tutorid=tutorid,
      yaml_content=yaml_content,
      app=app
    )
    ullme_send_course_state(app=app)
    list(ok=TRUE, message="Tutor instance YAML saved.")
  }, error=function(e) list(ok=FALSE, message=conditionMessage(e)))
  callJS(
    .fun="window.ullme.aiTutorInstancesSaveComplete",
    .args=list(result),
    .app=app
  )
  invisible(result)
}


ullme_handle_ai_tutor_convert = function(tutorid=NULL, paths=NULL, to="",
                                          from="", overwrite=FALSE,
                                          app=getApp(), ...) {
  result = tryCatch(
    ullme_convert_material_files(
      paths=paths,
      to=to,
      from=from,
      tutorid=tutorid,
      overwrite=isTRUE(overwrite),
      origin="ui",
      app=app
    ),
    error=function(e) list(ok=FALSE, status="error", message=conditionMessage(e))
  )
  if (isTRUE(result$ok) && identical(result$status, "committed")) {
    ullme_send_course_state(app=app)
  }
  callJS(
    .fun="window.ullme.aiTutorConversionComplete",
    .args=list(result),
    .app=app
  )
  invisible(result)
}
