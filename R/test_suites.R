ullme_test_suites_root = function(course_dir) {
  file.path(course_dir, "tests")
}


ullme_clean_test_suite_id = function(id) {
  id = paste0(id %||% "")[1]
  if (is.na(id) || !grepl("^[A-Za-z][A-Za-z0-9_-]*$", id)) {
    stop("Test Suite IDs must start with a letter and contain only letters, numbers, underscores, or hyphens.")
  }
  id
}


ullme_clean_test_input_id = function(id, label="Input") {
  id = paste0(id %||% "")[1]
  if (is.na(id) || !grepl("^[A-Za-z0-9][A-Za-z0-9_.-]*$", id)) {
    stop(label, " IDs may contain letters, numbers, dots, underscores, or hyphens.")
  }
  id
}


ullme_test_suite_dir = function(course_dir, suiteid) {
  file.path(ullme_test_suites_root(course_dir), ullme_clean_test_suite_id(suiteid))
}


ullme_active_test_suite_dir = function(suiteid, app=getApp(), must_exist=TRUE) {
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) stop("Select a course first.")
  target = ullme_test_suite_dir(course_dir, suiteid)
  root = normalizePath(course_dir, winslash="/", mustWork=TRUE)
  normalized = normalizePath(target, winslash="/", mustWork=FALSE)
  if (!ullme_path_is_within(normalized, root, allow_root=FALSE)) {
    stop("The Test Suite is outside the active course.")
  }
  if (isTRUE(must_exist) && !dir.exists(target)) stop("The Test Suite does not exist.")
  target
}


ullme_test_suite_yaml = function(value) {
  trimws(yaml::as.yaml(value, unicode=TRUE))
}


ullme_test_suite_read_config = function(test_dir) {
  path = file.path(test_dir, "tests.yml")
  value = if (file.exists(path)) {
    tryCatch(yaml::read_yaml(path, eval.expr=FALSE), error=function(error) list())
  } else list()
  if (!is.list(value)) value = list()
  value
}


ullme_create_test_suite = function(suiteid, label, tutorid, app=getApp()) {
  if (!identical(app$role, "teacher")) stop("Only teachers can create Test Suites.")
  suiteid = ullme_clean_test_suite_id(suiteid)
  tutorid = ullme_clean_definition_id(tutorid)
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) stop("Select a course first.")
  target = ullme_test_suite_dir(course_dir, suiteid)
  if (file.exists(target) || dir.exists(target)) stop("A Test Suite with this ID already exists.")
  tutor_path = ullme_existing_course_ai_tutor_path(course_dir, tutorid)
  if (!file.exists(tutor_path)) stop("The selected course AI Tutor does not exist.")
  tutor_content = paste(readLines(tutor_path, warn=FALSE, encoding="UTF-8"), collapse="\n")
  validation = ullme_tutor_validation_state(tutorid, tutor_content)
  if (!isTRUE(validation$is_valid)) {
    stop("The selected AI Tutor is invalid: ", paste(unlist(validation$errors), collapse="; "))
  }
  instances_path = ullme_course_ai_tutor_instances_path(course_dir, tutorid)
  instances_content = if (file.exists(instances_path)) {
    paste(readLines(instances_path, warn=FALSE, encoding="UTF-8"), collapse="\n")
  } else {
    ullme_test_suite_yaml(list(course_docs=list(), instances=list()))
  }
  config = list(
    schema_version=1L,
    suite=list(id=suiteid, source_tutor=tutorid),
    materials_dir="../../materials",
    run_base=FALSE,
    models=as.list(app$api_models %||% app$api_config$model %||% character(0)),
    api=paste0(app$api_config$provider %||% "nvidia")[1],
    api_key_file=app$api_config$api_key_file %||% NULL,
    api_base_url=app$api_config$base_url %||% NULL,
    timeout_seconds=600,
    batch_size=1L,
    add_full_prompts_in_results=FALSE,
    results_by_node=TRUE
  )
  changes = list(
    ullme_change_write(file.path(target, "tutor.yml"), tutor_content),
    ullme_change_write(file.path(target, "instances.yml"), instances_content),
    ullme_change_write(file.path(target, "tests.yml"), ullme_test_suite_yaml(config)),
    ullme_change_write(
      file.path(target, "tutor_var_baseline.yml"),
      ullme_test_suite_yaml(list(test_variant=list(label="Baseline snapshot")))
    )
  )
  result = ullme_submit_change(ullme_new_change(
    action="test_suite_create",
    summary=paste0("Create Test Suite ", suiteid),
    origin="ui",
    details=list(kind="test_suite", suiteid=suiteid, tutorid=tutorid),
    changes=changes,
    app=app
  ), app=app)
  if (!isTRUE(result$ok)) stop(result$message %||% "Could not create the Test Suite.")
  invisible(result)
}


ullme_test_suite_variant_records = function(test_dir) {
  paths = list.files(test_dir, "^tutor_var_.+[.]ya?ml$", full.names=TRUE,
                     ignore.case=TRUE, no..=TRUE)
  lapply(sort(paths), function(path) {
    value = tryCatch(yaml::read_yaml(path, eval.expr=FALSE), error=function(error) list())
    metadata = value$test_variant %||% list()
    modified_nodes = names(value$nodes %||% list())
    node_yaml = lapply(value$nodes %||% list(), function(node) {
      trimws(yaml::as.yaml(node, unicode=TRUE))
    })
    list(
      id=sub("[.]ya?ml$", "", sub("^tutor_var_", "", basename(path)), ignore.case=TRUE),
      label=paste0(metadata$label %||% basename(path))[1],
      yaml_content=paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n"),
      modified_nodes=as.list(modified_nodes),
      node_yaml=node_yaml
    )
  })
}


ullme_test_suite_input_records = function(test_dir) {
  root = file.path(test_dir, "instance_inputs")
  if (!dir.exists(root)) return(list())
  records = list()
  for (instance_dir in sort(list.dirs(root, recursive=FALSE, full.names=TRUE))) {
    for (input_dir in sort(list.dirs(instance_dir, recursive=FALSE, full.names=TRUE))) {
      files = list.files(input_dir, full.names=TRUE, no..=TRUE)
      files = files[file.exists(files) & !dir.exists(files)]
      text_files = files[tolower(tools::file_ext(files)) %in% c("txt", "md")]
      text = if (length(text_files)) paste(vapply(text_files, function(path) {
        paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n")
      }, character(1)), collapse="\n\n") else ""
      images = basename(files[tolower(tools::file_ext(files)) %in%
        c("png", "jpg", "jpeg", "gif", "webp")])
      records[[length(records) + 1L]] = list(
        instanceid=basename(instance_dir), inputid=basename(input_dir),
        text=text, images=as.list(images)
      )
    }
  }
  records
}


ullme_test_suite_result_runs = function(test_dir) {
  root = file.path(test_dir, "results")
  if (!dir.exists(root)) return(list())
  dirs = sort(list.dirs(root, recursive=FALSE, full.names=TRUE), decreasing=TRUE)
  lapply(dirs, function(path) {
    files = list.files(path, "[.]ya?ml$", full.names=TRUE, ignore.case=TRUE, no..=TRUE)
    statuses = vapply(files, function(file) {
      value = tryCatch(yaml::read_yaml(file, eval.expr=FALSE), error=function(error) list())
      paste0(value$test$status %||% "invalid")[1]
    }, character(1))
    counts = table(statuses)
    list(
      id=basename(path), case_count=length(files),
      completed=as.integer(counts[["completed"]] %||% 0L),
      errors=as.integer(sum(counts[names(counts) != "completed"])),
      modified=format(file.info(path)$mtime[[1]], "%Y-%m-%dT%H:%M:%OS%z")
    )
  })
}


ullme_test_suite_status = function(test_dir) {
  path = file.path(test_dir, ".ullme-run-status.yml")
  if (!file.exists(path)) return(list(state="idle", messages=list()))
  value = tryCatch(yaml::read_yaml(path, eval.expr=FALSE), error=function(error) NULL)
  # A reader can briefly overlap the worker's status-file replacement. Keep
  # polling in that case; the next read will see the complete YAML document.
  if (!is.list(value)) list(state="running", messages=list()) else value
}


ullme_test_suite_record = function(test_dir) {
  config = ullme_test_suite_read_config(test_dir)
  config_for_js = config
  config_for_js$api_key_file = NULL
  raw_instances = tryCatch(
    ullme_tests_read_yaml(file.path(test_dir, "instances.yml"), "instances.yml"),
    error=function(error) list(instances=list())
  )
  instances = lapply(raw_instances$instances %||% list(), function(instance) list(
    instanceid=paste0(instance$instanceid %||% instance$id %||% "")[1],
    label=paste0(instance$label %||% instance$instanceid %||% instance$id %||% "")[1]
  ))
  tutor_path = file.path(test_dir, "tutor.yml")
  tutor_content = if (file.exists(tutor_path)) {
    paste(readLines(tutor_path, warn=FALSE, encoding="UTF-8"), collapse="\n")
  } else ""
  tutor = ullme_normalize_ai_tutor_content(
    tutor_content,
    tutorid=paste0(config$suite$source_tutor %||% "test_tutor")[1],
    source="test"
  )
  list(
    id=basename(test_dir),
    label=basename(test_dir),
    source_tutor=paste0(config$suite$source_tutor %||% "")[1],
    tutor=tutor,
    config=config_for_js,
    instances=instances,
    variants=ullme_test_suite_variant_records(test_dir),
    inputs=ullme_test_suite_input_records(test_dir),
    runs=ullme_test_suite_result_runs(test_dir),
    status=ullme_test_suite_status(test_dir)
  )
}


ullme_test_suites_for_js = function(app=getApp()) {
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) return(list())
  root = ullme_test_suites_root(course_dir)
  if (!dir.exists(root)) return(list())
  dirs = list.dirs(root, recursive=FALSE, full.names=TRUE)
  dirs = dirs[grepl("^[A-Za-z][A-Za-z0-9_-]*$", basename(dirs))]
  records = lapply(sort(dirs), ullme_test_suite_record)
  lapply(records, function(record) {
    record$courseid = app$courseid %||% ""
    record
  })
}


ullme_save_test_suite_config = function(suiteid, fields, app=getApp()) {
  test_dir = ullme_active_test_suite_dir(suiteid, app=app)
  config = ullme_test_suite_read_config(test_dir)
  suite = config$suite %||% list(id=suiteid)
  suite$label = NULL
  models = trimws(paste0(unlist(fields$models %||% list(), use.names=FALSE)))
  models = unique(models[nzchar(models)])
  if (!length(models)) stop("Select at least one model.")
  batch_size = suppressWarnings(as.integer(fields$batch_size)[1])
  timeout = suppressWarnings(as.numeric(fields$timeout_seconds)[1])
  if (is.na(batch_size) || batch_size < 1) stop("Batch size must be a positive integer.")
  if (is.na(timeout) || timeout <= 0) stop("Timeout must be positive.")
  config$suite = suite
  config$models = as.list(models)
  config$api = paste0(fields$api %||% config$api %||% "nvidia")[1]
  config$batch_size = batch_size
  config$timeout_seconds = timeout
  config$run_base = isTRUE(fields$run_base)
  config$add_full_prompts_in_results = isTRUE(fields$add_full_prompts_in_results)
  config$results_by_node = isTRUE(fields$results_by_node)
  result = ullme_submit_change(ullme_new_change(
    action="test_suite_config", summary=paste0("Update Test Suite ", suiteid),
    origin="ui", details=list(kind="test_suite", suiteid=suiteid),
    changes=list(ullme_change_write(file.path(test_dir, "tests.yml"), ullme_test_suite_yaml(config))),
    app=app
  ), app=app)
  if (!isTRUE(result$ok)) stop(result$message %||% "Could not save Test Suite settings.")
  invisible(result)
}


ullme_delete_test_suite = function(suiteid, app=getApp()) {
  test_dir = ullme_active_test_suite_dir(suiteid, app=app)
  status = ullme_test_suite_status(test_dir)
  if (status$state %in% c("starting", "running")) {
    stop("Stop the active Test Suite run before deleting the suite.")
  }
  result = ullme_submit_change(ullme_new_change(
    action="test_suite_delete", summary=paste0("Delete Test Suite ", suiteid),
    origin="ui", details=list(kind="test_suite", suiteid=suiteid),
    changes=list(ullme_change_delete(test_dir)), app=app
  ), app=app)
  if (!isTRUE(result$ok)) stop(result$message %||% "Could not delete the Test Suite.")
  invisible(result)
}


ullme_refresh_test_suite_tutor = function(suiteid, app=getApp()) {
  test_dir = ullme_active_test_suite_dir(suiteid, app=app)
  config = ullme_test_suite_read_config(test_dir)
  tutorid = ullme_clean_definition_id(config$suite$source_tutor %||% "")
  course_dir = ullme_active_course_dir(app=app)
  tutor_path = ullme_existing_course_ai_tutor_path(course_dir, tutorid)
  instances_path = ullme_course_ai_tutor_instances_path(course_dir, tutorid)
  if (!file.exists(tutor_path)) stop("The source AI Tutor no longer exists in this course.")
  tutor_content = paste(readLines(tutor_path, warn=FALSE, encoding="UTF-8"), collapse="\n")
  validation = ullme_tutor_validation_state(tutorid, tutor_content)
  if (!isTRUE(validation$is_valid)) stop("The source AI Tutor is currently invalid.")
  instances_content = if (file.exists(instances_path)) {
    paste(readLines(instances_path, warn=FALSE, encoding="UTF-8"), collapse="\n")
  } else ullme_test_suite_yaml(list(course_docs=list(), instances=list()))
  result = ullme_submit_change(ullme_new_change(
    action="test_suite_refresh", summary=paste0("Refresh Test Suite ", suiteid,
      " from AI Tutor ", tutorid), origin="ui",
    details=list(kind="test_suite", suiteid=suiteid, tutorid=tutorid),
    changes=list(
      ullme_change_write(file.path(test_dir, "tutor.yml"), tutor_content),
      ullme_change_write(file.path(test_dir, "instances.yml"), instances_content)
    ), app=app
  ), app=app)
  if (!isTRUE(result$ok)) stop(result$message %||% "Could not refresh the Tutor snapshot.")
  invisible(result)
}


ullme_save_test_suite_variant = function(suiteid, variantid, label, yaml_content,
                                          app=getApp()) {
  test_dir = ullme_active_test_suite_dir(suiteid, app=app)
  variantid = ullme_clean_test_input_id(variantid, "Variant")
  value = ullme_tests_read_yaml_text(paste0(yaml_content %||% "", collapse="\n"), "Variant YAML")
  value$test_variant = list(label=trimws(paste0(label %||% variantid)[1]))
  base = ullme_tests_read_yaml(file.path(test_dir, "tutor.yml"), "tutor.yml")
  modification = value
  modification$test_variant = NULL
  merged = utils::modifyList(base, modification, keep.null=TRUE)
  validation = ullme_tutor_validation_state(
    paste0(base$tutorid %||% "test_tutor")[1], ullme_ai_tutor_yaml(merged)
  )
  if (!isTRUE(validation$is_valid)) {
    stop("The merged Tutor is invalid: ", paste(unlist(validation$errors), collapse="; "))
  }
  path = file.path(test_dir, paste0("tutor_var_", variantid, ".yml"))
  result = ullme_submit_change(ullme_new_change(
    action="test_suite_variant", summary=paste0("Save Test Suite variant ", variantid),
    origin="ui", details=list(kind="test_variant", suiteid=suiteid, variantid=variantid),
    changes=list(ullme_change_write(path, ullme_test_suite_yaml(value))), app=app
  ), app=app)
  if (!isTRUE(result$ok)) stop(result$message %||% "Could not save the variant.")
  invisible(result)
}


ullme_save_test_suite_variant_node = function(suiteid, variantid, nodeid,
                                               yaml_content="",
                                               action=c("save", "revert"),
                                               app=getApp()) {
  test_dir = ullme_active_test_suite_dir(suiteid, app=app)
  variantid = ullme_clean_test_input_id(variantid, "Variant")
  nodeid = ullme_clean_tutor_node_id(nodeid)
  action = match.arg(action)
  path = file.path(test_dir, paste0("tutor_var_", variantid, ".yml"))
  if (!file.exists(path)) stop("The selected Tutor variant does not exist.")
  value = ullme_tests_read_yaml(path, basename(path))
  nodes = value$nodes %||% list()
  if (!is.list(nodes)) nodes = list()
  if (identical(action, "revert")) {
    nodes[[nodeid]] = NULL
  } else {
    parsed = ullme_tests_read_yaml_text(
      paste0(yaml_content %||% "", collapse="\n"),
      paste0("Variant node ", nodeid)
    )
    if (!length(parsed) || is.null(names(parsed))) {
      stop("Variant node YAML must be a non-empty mapping.")
    }
    nodes[[nodeid]] = parsed
  }
  value$nodes = if (length(nodes)) nodes else NULL
  metadata = value$test_variant %||% list(label=variantid)
  value$test_variant = NULL
  base = ullme_tests_read_yaml(file.path(test_dir, "tutor.yml"), "tutor.yml")
  merged = utils::modifyList(base, value, keep.null=TRUE)
  validation = ullme_tutor_validation_state(
    paste0(base$tutorid %||% "test_tutor")[1], ullme_ai_tutor_yaml(merged)
  )
  if (!isTRUE(validation$is_valid)) {
    stop("The merged Tutor is invalid: ", paste(unlist(validation$errors), collapse="; "))
  }
  value = c(list(test_variant=metadata), value)
  result = ullme_submit_change(ullme_new_change(
    action="test_suite_variant_node",
    summary=paste0(if (identical(action, "revert")) "Revert" else "Save",
      " Test Suite variant node ", nodeid),
    origin="ui",
    details=list(kind="test_variant_node", suiteid=suiteid,
                 variantid=variantid, nodeid=nodeid, action=action),
    changes=list(ullme_change_write(path, ullme_test_suite_yaml(value))),
    app=app
  ), app=app)
  if (!isTRUE(result$ok)) stop(result$message %||% "Could not save the variant node.")
  invisible(result)
}


ullme_tests_read_yaml_text = function(content, label="YAML") {
  value = tryCatch(yaml::yaml.load(content, eval.expr=FALSE), error=function(error) {
    stop(label, " is invalid: ", conditionMessage(error), call.=FALSE)
  })
  if (is.null(value)) value = list()
  if (!is.list(value)) stop(label, " must contain a YAML mapping.")
  value
}


ullme_save_test_suite_input = function(suiteid, instanceid, inputid, text,
                                        app=getApp()) {
  test_dir = ullme_active_test_suite_dir(suiteid, app=app)
  instanceid = ullme_clean_test_input_id(instanceid, "Instance")
  inputid = ullme_clean_test_input_id(inputid, "Input")
  instances = ullme_test_suite_record(test_dir)$instances
  known = vapply(instances, `[[`, character(1), "instanceid")
  if (length(known) && !instanceid %in% known) stop("Select a known Tutor instance.")
  path = file.path(test_dir, "instance_inputs", instanceid, inputid, "input.md")
  result = ullme_submit_change(ullme_new_change(
    action="test_suite_input", summary=paste0("Save Test Suite input ", inputid),
    origin="ui", details=list(kind="test_input", suiteid=suiteid,
                               instanceid=instanceid, inputid=inputid),
    changes=list(ullme_change_write(path, paste0(text %||% "", collapse="\n"))), app=app
  ), app=app)
  if (!isTRUE(result$ok)) stop(result$message %||% "Could not save the input.")
  invisible(result)
}


ullme_test_suite_preflight = function(test_dir, options=list()) {
  config = ullme_test_suite_read_config(test_dir)
  opts = ullme_tests_default_options()
  opts[names(config)] = config
  opts[names(options)] = options
  base = ullme_tests_read_yaml(file.path(test_dir, "tutor.yml"), "tutor.yml")
  raw_instances = ullme_tests_read_yaml(file.path(test_dir, "instances.yml"), "instances.yml")
  instance_data = list(instances=lapply(raw_instances$instances %||% list(), function(instance) list(
    instanceid=paste0(instance$instanceid %||% instance$id %||% "")[1]
  )))
  variants = ullme_tests_variant_specs(test_dir, base, opts)
  inputs = ullme_tests_input_specs(test_dir, instance_data)
  models = paste0(unlist(opts$models %||% list(), use.names=FALSE))
  models = models[nzchar(models)]
  if (!length(models)) stop("No models were selected.")
  ullme_api_config(
    api_provider=paste0(opts$api)[1],
    api_key_file=opts$api_key_file,
    api_model=models[[1]],
    api_base_url=opts$api_base_url
  )
  list(case_count=length(variants) * length(inputs) * length(models),
       variants=length(variants), inputs=length(inputs), models=length(models))
}


ullme_test_suite_write_status = function(path, state, messages=list(), error="",
                                          result_dir="") {
  value = list(
    state=state,
    updated_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS%z"),
    messages=as.list(tail(paste0(unlist(messages, use.names=FALSE)), 100L)),
    error=paste0(error %||% "")[1], result_dir=paste0(result_dir %||% "")[1]
  )
  temporary = tempfile(pattern=".ullme-status-", tmpdir=dirname(path), fileext=".yml")
  writeLines(ullme_test_suite_yaml(value), temporary, useBytes=TRUE)
  copied = file.copy(temporary, path, overwrite=TRUE, copy.date=FALSE)
  unlink(temporary, force=TRUE)
  if (!isTRUE(copied)) stop("Could not update Test Suite status.")
  invisible(value)
}


ullme_test_suite_worker_entry = function(test_dir, options, status_path) {
  messages = character(0)
  result_dir = ""
  progress = function(message) {
    messages <<- c(messages, message)
    if (startsWith(message, "Results directory: ")) {
      result_dir <<- sub("^Results directory: ", "", message)
    }
    ullme_test_suite_write_status(status_path, "running", messages,
                                  result_dir=result_dir)
  }
  options(ullme.tests.progress_callback=progress)
  ullme_test_suite_write_status(status_path, "running", "Starting Test Suite.")
  tryCatch({
    records = ullme_run_tests(test_dir, options=options)
    ullme_test_suite_write_status(status_path, "completed", messages,
                                  result_dir=result_dir)
    records
  }, error=function(error) {
    ullme_test_suite_write_status(status_path, "error", messages,
                                  error=conditionMessage(error), result_dir=result_dir)
    stop(error)
  })
}


ullme_test_suite_development_root = function() {
  candidates = unique(c(
    normalizePath(getwd(), winslash="/", mustWork=FALSE),
    normalizePath(system.file(package="ullme"), winslash="/", mustWork=FALSE)
  ))
  found = candidates[file.exists(file.path(candidates, "R", "test_suites.R"))]
  if (length(found)) found[[1]] else ""
}


ullme_test_suite_worker_bootstrap = function(test_dir, options, status_path,
                                              development_root="") {
  suppressPackageStartupMessages(library(ullme))
  if (nzchar(development_root) &&
      file.exists(file.path(development_root, "R", "test_suites.R"))) {
    sys.source(file.path(development_root, "R", "run_tests.R"), envir=.GlobalEnv)
    sys.source(file.path(development_root, "R", "test_suites.R"), envir=.GlobalEnv)
    worker = get("ullme_test_suite_worker_entry", envir=.GlobalEnv)
  } else {
    worker = getFromNamespace("ullme_test_suite_worker_entry", "ullme")
  }
  worker(test_dir=test_dir, options=options, status_path=status_path)
}


ullme_start_test_suite_run = function(suiteid, options=list(), app=getApp()) {
  if (!requireNamespace("callr", quietly=TRUE)) {
    stop("Package 'callr' is required to run Test Suites in the background.")
  }
  test_dir = ullme_active_test_suite_dir(suiteid, app=app)
  preflight = ullme_test_suite_preflight(test_dir, options=options)
  current_status = ullme_test_suite_status(test_dir)
  status_path = file.path(test_dir, ".ullme-run-status.yml")
  status_age = if (file.exists(status_path)) {
    as.numeric(difftime(Sys.time(), file.info(status_path)$mtime[[1]], units="secs"))
  } else Inf
  stale_after = max(120, 2 * as.numeric(
    ullme_test_suite_read_config(test_dir)$timeout_seconds %||% 600
  ))
  if (current_status$state %in% c("starting", "running") &&
      is.finite(status_age) && status_age < stale_after) {
    stop("This Test Suite is already running in another teacher session.")
  }
  processes = app$test_suite_processes %||% list()
  existing = processes[[suiteid]]
  if (!is.null(existing) && isTRUE(tryCatch(existing$is_alive(), error=function(error) FALSE))) {
    stop("This Test Suite is already running.")
  }
  ullme_test_suite_write_status(status_path, "starting", list(
    paste0("Validated ", preflight$case_count, " test case(s).")
  ))
  process = callr::r_bg(
    func=ullme_test_suite_worker_bootstrap,
    args=list(
      test_dir=test_dir, options=options, status_path=status_path,
      development_root=ullme_test_suite_development_root()
    ),
    package=FALSE, supervise=TRUE,
    stdout=file.path(test_dir, ".ullme-run.log"),
    stderr=file.path(test_dir, ".ullme-run-error.log")
  )
  processes[[suiteid]] = process
  app$test_suite_processes = processes
  preflight
}


ullme_test_suite_result_payload = function(suiteid, runid, filename=NULL,
                                            app=getApp()) {
  test_dir = ullme_active_test_suite_dir(suiteid, app=app)
  runid = basename(paste0(runid %||% "")[1])
  if (!grepl("^results_[0-9_-]+$", runid)) stop("Invalid result run ID.")
  run_dir = file.path(test_dir, "results", runid)
  if (!dir.exists(run_dir)) stop("The result run does not exist.")
  paths = list.files(run_dir, "[.]ya?ml$", full.names=TRUE, ignore.case=TRUE, no..=TRUE)
  cases = lapply(paths, function(path) {
    value = ullme_tests_read_yaml(path, basename(path))
    list(
      file=basename(path), test=value$test %||% list(), execution=value$execution %||% list()
    )
  })
  detail = NULL
  if (!is.null(filename) && nzchar(paste0(filename)[1])) {
    wanted = basename(paste0(filename)[1])
    found = which(vapply(cases, `[[`, character(1), "file") == wanted)
    if (length(found)) {
      path = paths[[found[[1]]]]
      value = ullme_tests_read_yaml(path, basename(path))
      detail = list(
        file=basename(path), test=value$test %||% list(),
        execution=value$execution %||% list(), input=value$input %||% list(),
        response=value$response %||% list(),
        raw_yaml=paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n")
      )
    }
  }
  list(suiteid=suiteid, runid=runid, cases=cases, detail=detail)
}


ullme_send_test_suite_state = function(app=getApp()) {
  callJS(.fun="window.ullmeTests.update", .args=list(ullme_test_suites_for_js(app=app)), .app=app)
  invisible(TRUE)
}


ullme_test_suites_ui = function(app=getApp()) {
  tags$section(
    id="ullme_test_suites_panel",
    class="ullme-test-suites ullme-course-content-panel",
    `data-course-panel`="tests",
    tags$div(
      class="ullme-panel-inner ullme-tests-shell",
      tags$div(id="ullme_tests_workspace")
    ),
    tags$input(
      id="ullme_test_input_upload", class="ullme-file-input", type="file",
      accept="image/png,image/jpeg,image/gif,image/webp", multiple="multiple"
    )
  )
}


ullme_test_variant_node_editor_ui = function() {
  tags$section(
    id="ullme_test_variant_node_panel",
    class="ullme-assistant-panel ullme-node-editor-panel ullme-test-variant-node-panel",
    role="tabpanel",
    `aria-labelledby`="ullme_test_variant_node_tab",
    tags$div(
      class="ullme-node-editor-head",
      tags$strong(id="ullme_test_variant_node_title", "Variant node")
    ),
    tags$label(
      class="ullme-node-editor-field",
      tags$span("Node ID"),
      tags$input(id="ullme_test_variant_node_id", type="text", readonly="readonly")
    ),
    tags$label(
      class="ullme-node-editor-field ullme-node-editor-yaml-field",
      tags$span("Node YAML override"),
      tags$textarea(id="ullme_test_variant_node_yaml", spellcheck="false")
    ),
    tags$div(
      id="ullme_test_variant_node_status",
      class="ullme-node-editor-status", role="status", `aria-live`="polite",
      "Select a node in the variant diagram."
    ),
    tags$div(
      class="ullme-node-editor-actions",
      tags$button(
        id="ullme_test_variant_node_revert", class="ullme-secondary-action",
        type="button", "Use base node"
      ),
      tags$button(
        id="ullme_test_variant_node_save", class="ullme-primary-action",
        type="button", "Save override"
      )
    )
  )
}


ullme_handle_test_suite_create = function(suiteid=NULL, label=NULL, tutorid=NULL,
                                           app=getApp(), ...) {
  result = tryCatch({
    ullme_create_test_suite(suiteid, label, tutorid, app=app)
    ullme_send_test_suite_state(app=app)
    list(ok=TRUE, suiteid=suiteid, message="Test Suite created.")
  }, error=function(error) list(ok=FALSE, message=conditionMessage(error)))
  callJS(.fun="window.ullmeTests.actionComplete", .args=list(result), .app=app)
  invisible(result)
}


ullme_handle_test_suite_delete = function(suiteid=NULL, app=getApp(), ...) {
  result = tryCatch({
    ullme_delete_test_suite(suiteid, app=app)
    ullme_send_test_suite_state(app=app)
    list(ok=TRUE, kind="suite_delete", suiteid=suiteid,
         message="Test Suite deleted.")
  }, error=function(error) list(
    ok=FALSE, kind="suite_delete", message=conditionMessage(error)
  ))
  callJS(.fun="window.ullmeTests.actionComplete", .args=list(result), .app=app)
  invisible(result)
}


ullme_handle_test_suite_config_save = function(suiteid=NULL, fields=list(), app=getApp(), ...) {
  result = tryCatch({
    ullme_save_test_suite_config(suiteid, fields, app=app)
    ullme_send_test_suite_state(app=app)
    list(ok=TRUE, message="Test Suite settings saved.")
  }, error=function(error) list(ok=FALSE, message=conditionMessage(error)))
  callJS(.fun="window.ullmeTests.actionComplete", .args=list(result), .app=app)
  invisible(result)
}


ullme_handle_test_suite_refresh = function(suiteid=NULL, app=getApp(), ...) {
  result = tryCatch({
    ullme_refresh_test_suite_tutor(suiteid, app=app)
    ullme_send_test_suite_state(app=app)
    list(ok=TRUE, message="Tutor snapshot refreshed.")
  }, error=function(error) list(ok=FALSE, message=conditionMessage(error)))
  callJS(.fun="window.ullmeTests.actionComplete", .args=list(result), .app=app)
  invisible(result)
}


ullme_handle_test_suite_variant_save = function(suiteid=NULL, variantid=NULL,
                                                 label=NULL, yaml_content="",
                                                 app=getApp(), ...) {
  result = tryCatch({
    ullme_save_test_suite_variant(suiteid, variantid, label, yaml_content, app=app)
    ullme_send_test_suite_state(app=app)
    list(ok=TRUE, kind="variant", variantid=variantid, message="Variant saved.")
  }, error=function(error) list(ok=FALSE, message=conditionMessage(error)))
  callJS(.fun="window.ullmeTests.actionComplete", .args=list(result), .app=app)
  invisible(result)
}


ullme_handle_test_suite_variant_node_save = function(
    suiteid=NULL, variantid=NULL, nodeid=NULL, yaml_content="", action="save",
    app=getApp(), ...) {
  result = tryCatch({
    ullme_save_test_suite_variant_node(
      suiteid=suiteid, variantid=variantid, nodeid=nodeid,
      yaml_content=yaml_content, action=action, app=app
    )
    ullme_send_test_suite_state(app=app)
    list(ok=TRUE, kind="variant_node", suiteid=suiteid, variantid=variantid,
         nodeid=nodeid, action=action,
         message=if (identical(action, "revert"))
           "The variant uses the base node again." else "Variant node override saved.")
  }, error=function(error) list(
    ok=FALSE, kind="variant_node", message=conditionMessage(error)
  ))
  callJS(.fun="window.ullmeTests.actionComplete", .args=list(result), .app=app)
  invisible(result)
}


ullme_handle_test_suite_input_save = function(suiteid=NULL, instanceid=NULL,
                                               inputid=NULL, text="", app=getApp(), ...) {
  result = tryCatch({
    ullme_save_test_suite_input(suiteid, instanceid, inputid, text, app=app)
    ullme_send_test_suite_state(app=app)
    list(ok=TRUE, message="Test input saved.")
  }, error=function(error) list(ok=FALSE, message=conditionMessage(error)))
  callJS(.fun="window.ullmeTests.actionComplete", .args=list(result), .app=app)
  invisible(result)
}


ullme_handle_test_suite_upload_prepare = function(suiteid=NULL, instanceid=NULL,
                                                   inputid=NULL, split=FALSE,
                                                   app=getApp(), ...) {
  result = tryCatch({
    test_dir = ullme_active_test_suite_dir(suiteid, app=app)
    instanceid = ullme_clean_test_input_id(instanceid, "Instance")
    inputid = ullme_clean_test_input_id(inputid, "Input")
    app$test_suite_upload_target = list(suiteid=suiteid, instanceid=instanceid,
      inputid=inputid, split=isTRUE(split),
      directory=file.path(test_dir, "instance_inputs", instanceid, inputid))
    list(ok=TRUE)
  }, error=function(error) list(ok=FALSE, message=conditionMessage(error)))
  callJS(.fun="window.ullmeTests.uploadReady", .args=list(result), .app=app)
  invisible(result)
}


ullme_handle_test_suite_upload = function(app=getApp(), value, ...) {
  target = app$test_suite_upload_target
  app$test_suite_upload_target = NULL
  result = tryCatch({
    if (is.null(target)) stop("Choose a Test Suite input before uploading images.")
    if (is.null(value) || NROW(value) == 0) stop("No images were uploaded.")
    changes = list()
    for (i in seq_len(NROW(value))) {
      name = ullme_clean_file_name(basename(value$name[[i]]))
      extension = tolower(tools::file_ext(name))
      if (!extension %in% c("png", "jpg", "jpeg", "gif", "webp")) {
        stop("Test input uploads must be supported image files.")
      }
      directory = if (isTRUE(target$split) && NROW(value) > 1L) {
        file.path(dirname(target$directory), paste0(target$inputid, "_", i))
      } else target$directory
      changes[[length(changes) + 1L]] = ullme_change_copy(
        value$datapath[[i]], file.path(directory, name), overwrite=TRUE
      )
    }
    committed = ullme_submit_change(ullme_new_change(
      action="test_suite_upload", summary=paste0("Upload Test Suite input images"),
      origin="ui", details=target, changes=changes, app=app
    ), app=app)
    if (!isTRUE(committed$ok)) stop(committed$message %||% "Could not store test images.")
    ullme_send_test_suite_state(app=app)
    list(
      ok=TRUE,
      message=if (isTRUE(target$split) && NROW(value) > 1L)
        paste0("Created ", NROW(value), " separate image inputs.") else
        "Test images uploaded."
    )
  }, error=function(error) list(ok=FALSE, message=conditionMessage(error)))
  callJS(.fun="window.ullmeTests.uploadComplete", .args=list(result), .app=app)
  invisible(result)
}


ullme_handle_test_suite_run = function(suiteid=NULL, variants=NULL, app=getApp(), ...) {
  result = tryCatch({
    selected = paste0(unlist(variants %||% list(), use.names=FALSE))
    test_dir = ullme_active_test_suite_dir(suiteid, app=app)
    run_base = isTRUE(ullme_test_suite_read_config(test_dir)$run_base)
    if (!length(selected) && !run_base) stop("Select at least one Tutor variant.")
    if (run_base) {
      selected = c("base", selected)
    }
    options = if (length(selected)) list(just_variants=as.list(selected)) else list()
    preflight = ullme_start_test_suite_run(suiteid, options=options, app=app)
    ullme_send_test_suite_state(app=app)
    list(ok=TRUE, message=paste0("Started ", preflight$case_count, " test case(s)."))
  }, error=function(error) list(ok=FALSE, message=conditionMessage(error)))
  callJS(.fun="window.ullmeTests.actionComplete", .args=list(result), .app=app)
  invisible(result)
}


ullme_handle_test_suite_poll = function(app=getApp(), ...) {
  processes = app$test_suite_processes %||% list()
  for (suiteid in names(processes)) {
    process = processes[[suiteid]]
    alive = isTRUE(tryCatch(process$is_alive(), error=function(error) FALSE))
    if (alive) next
    test_dir = tryCatch(
      ullme_active_test_suite_dir(suiteid, app=app),
      error=function(error) NULL
    )
    if (!is.null(test_dir)) {
      status = ullme_test_suite_status(test_dir)
      if (status$state %in% c("starting", "running")) {
        errors = tryCatch(process$read_error_lines(), error=function(error) character(0))
        message = paste(tail(errors[nzchar(errors)], 8L), collapse="\n")
        if (!nzchar(message)) message = "The background Test Suite process stopped unexpectedly."
        ullme_test_suite_write_status(
          file.path(test_dir, ".ullme-run-status.yml"), "error",
          status$messages %||% list(), error=message,
          result_dir=status$result_dir %||% ""
        )
      }
    }
    processes[[suiteid]] = NULL
  }
  app$test_suite_processes = processes
  ullme_send_test_suite_state(app=app)
  invisible(TRUE)
}


ullme_handle_test_suite_results = function(suiteid=NULL, runid=NULL, filename=NULL,
                                            app=getApp(), ...) {
  result = tryCatch(
    c(list(ok=TRUE), ullme_test_suite_result_payload(suiteid, runid, filename, app=app)),
    error=function(error) list(ok=FALSE, message=conditionMessage(error))
  )
  callJS(.fun="window.ullmeTests.receiveResults", .args=list(result), .app=app)
  invisible(result)
}
