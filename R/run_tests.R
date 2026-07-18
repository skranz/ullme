# Run systematic tests outside the app with pre-specified inputs

example = function() {
  ullme_run_tests("C:/libraries/ullme/ullme_main/tests/umwelt", options=list(batch_size=3))
}

ullme_run_tests = function(test_dir, options=list()) {
  # Option priority, from lowest to highest: defaults, tests.yml, options.
  restore.point("ullme_run_tests")
  #stop()
  test_dir = normalizePath(test_dir, winslash="/", mustWork=TRUE)
  opts = ullme_tests_default_options()
  yml_file = file.path(test_dir, "tests.yml")
  if (file.exists(yml_file)) {
    yml_opts = ullme_tests_read_yaml(yml_file, "tests.yml")
    opts[names(yml_opts)] = yml_opts
  }
  if (!is.list(options)) stop("options must be a list.", call.=FALSE)
  opts[names(options)] = options

  # Relative material paths in tests.yml are resolved from the suite directory.
  # This keeps course-local suites portable while preserving support for the
  # absolute paths used by older command-line suites.
  if (!is.null(opts$materials_dir) && length(opts$materials_dir)) {
    materials_dir = paste0(opts$materials_dir)[1]
    is_absolute = grepl("^[A-Za-z]:[/\\\\]|^/|^\\\\\\\\", materials_dir)
    if (nzchar(materials_dir) && !is_absolute) {
      materials_dir = file.path(test_dir, materials_dir)
    }
    opts$materials_dir = normalizePath(
      materials_dir, winslash="/", mustWork=FALSE
    )
  }

  tutor_file = file.path(test_dir, "tutor.yml")
  instances_file = file.path(test_dir, "instances.yml")
  if (!file.exists(tutor_file)) stop("Missing tutor.yml.", call.=FALSE)
  if (!file.exists(instances_file)) stop("Missing instances.yml.", call.=FALSE)
  base_definition = ullme_tests_read_yaml(tutor_file, "tutor.yml")

  # The standard reader expects <course>/ai_tutors/<id>/instances.yml, while a
  # test specification intentionally keeps instances.yml directly in test_dir.
  raw_instances = ullme_tests_read_yaml(instances_file, "instances.yml")
  instances = lapply(raw_instances$instances %||% list(), function(instance) {
    docs = lapply(instance$docs %||% list(), ullme_tutor_document_paths)
    list(
      instanceid=paste0(instance$instanceid %||% instance$id %||% "")[1],
      label=paste0(instance$label %||% instance$instanceid %||%
                     instance$id %||% "")[1],
      docs=docs,
      source="test"
    )
  })
  instance_data = list(
    instances=instances,
    course_docs=lapply(
      raw_instances$course_docs %||% list(), ullme_tutor_document_paths
    )
  )
  variants = ullme_tests_variant_specs(test_dir, base_definition, opts)
  inputs = ullme_tests_input_specs(test_dir, instance_data)
  models = paste0(unlist(opts$models %||% list(), use.names=FALSE))
  models = models[nzchar(models)]
  if (!length(models)) stop("No models were selected.", call.=FALSE)
  timeout = suppressWarnings(as.numeric(opts$timeout_seconds)[1])
  if (is.na(timeout) || timeout <= 0) {
    stop("timeout_seconds must be positive.", call.=FALSE)
  }
  opts$timeout_seconds = timeout
  batch_size = suppressWarnings(as.numeric(opts$batch_size)[1])
  if (is.na(batch_size) || batch_size < 1 || batch_size != floor(batch_size)) {
    stop("batch_size must be a positive integer.", call.=FALSE)
  }
  opts$batch_size = as.integer(batch_size)
  results_root = file.path(test_dir, "results")
  if (!dir.exists(results_root) && !dir.create(
      results_root, recursive=TRUE, showWarnings=FALSE
  )) {
    stop("Could not create the results directory.", call.=FALSE)
  }
  run_folder = paste0(
    "results_", format(Sys.time(), "%Y-%m-%d_%H%M%S")
  )
  results_dir = file.path(results_root, run_folder)
  if (dir.exists(results_dir)) {
    stop(
      "A results directory already exists for the current second: ",
      results_dir,
      call.=FALSE
    )
  }
  if (!dir.create(results_dir, recursive=FALSE, showWarnings=FALSE)) {
    stop("Could not create results run directory: ", results_dir, call.=FALSE)
  }
  stage_main = file.path(test_dir, "ullme_tmp")
  ullme_remove_test_dir(stage_main, test_dir=test_dir)
  dir.create(stage_main, recursive=TRUE, showWarnings=FALSE)
  on.exit(
    ullme_remove_test_dir(stage_main, test_dir=test_dir),
    add=TRUE
  )
  course_dir = ullme_course_dir(
    main_dir=stage_main,
    userid="test_teacher",
    role="teacher",
    semester="SS00",
    courseid="test_course"
  )
  dir.create(course_dir, recursive=TRUE, showWarnings=FALSE)
  ullme_tests_copy_materials(instance_data, opts$materials_dir, course_dir)

  jobs = list()
  for (variant in variants) {
    tutor = ullme_normalize_ai_tutor_definition(
      variant$definition,
      tutorid=paste0(base_definition$tutorid %||% "test_tutor")[1],
      source="test"
    )
    tutor$instances = instance_data$instances
    tutor$course_docs = instance_data$course_docs
    for (model in models) for (input in inputs) {
      upload_dir = file.path(
        stage_main, "uploads", ullme_tests_safe_id(variant$id),
        ullme_tests_safe_id(model), ullme_tests_safe_id(input$instanceid),
        ullme_tests_safe_id(input$inputid)
      )
      app = ullme_tests_app(stage_main, course_dir, tutor, input, model, opts)
      app$uploads_dir = upload_dir
      uploads = ullme_tests_uploads(input, upload_dir)
      state = ullme_tutor_workflow_new(
        tutor=tutor,
        input=input$text,
        uploads=uploads,
        conversation=list(),
        model=model,
        app=app
      )
      filename = paste(
        ullme_tests_safe_id(variant$id),
        ullme_tests_safe_id(model),
        ullme_tests_safe_id(input$instanceid),
        ullme_tests_safe_id(input$inputid),
        sep="__"
      )
      path = file.path(results_dir, paste0(filename, ".yml"))
      jobs[[length(jobs) + 1L]] = list(
        variant=variant,
        model=model,
        input=input,
        app=app,
        state=state,
        result_path=path
      )
    }
  }
  run_started = Sys.time()
  ullme_tests_progress(
    "Starting ", length(jobs), " test case(s) with batch_size=",
    opts$batch_size, "."
  )
  ullme_tests_progress("Results directory: ", results_dir)
  batch_ids = split(
    seq_along(jobs),
    ceiling(seq_along(jobs) / opts$batch_size)
  )
  records = list()
  for (batch_index in seq_along(batch_ids)) {
    ids = batch_ids[[batch_index]]
    batch_jobs = jobs[ids]
    ullme_tests_progress(
      "Batch ", batch_index, "/", length(batch_ids), ": ",
      length(batch_jobs), " case(s)."
    )
    results = ullme_tests_run_batch(
      batch_jobs,
      timeout_seconds=timeout,
      batch_index=batch_index,
      batch_count=length(batch_ids),
      configured_batch_size=opts$batch_size
    )
    for (index in seq_along(batch_jobs)) {
      job = batch_jobs[[index]]
      result = results[[index]]
      writeLines(
        ullme_tests_as_yaml(ullme_tests_result_yaml(
          result, job$variant, job$input, job$model, opts
        )),
        job$result_path,
        useBytes=TRUE
      )
      records[[length(records) + 1L]] = list(
        variant=job$variant$id,
        model=job$model,
        instanceid=job$input$instanceid,
        inputid=job$input$inputid,
        status=result$status,
        result_file=normalizePath(
          job$result_path, winslash="/", mustWork=TRUE
        )
      )
      ullme_tests_progress(
        "  [", result$status, "] ", ullme_tests_job_label(job),
        " -> ", basename(job$result_path)
      )
    }
  }
  elapsed = as.numeric(difftime(Sys.time(), run_started, units="secs"))
  ullme_tests_progress(
    "Finished ", length(records), " test case(s) in ",
    format(round(elapsed, 1), nsmall=1), " seconds."
  )
  invisible(records)
}


ullme_tests_default_options = function(
    run_base=FALSE,
    models="nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
    api="nvidia",
    just_variants=NULL,
    materials_dir=NULL,
    api_key_file=NULL,
    api_base_url=NULL,
    timeout_seconds=600,
    batch_size=1L,
    add_full_prompts_in_results=FALSE,
    results_by_node=TRUE) {
  as.list(environment())
}


ullme_tests_nonempty = function(value, fallback=NULL) {
  value = paste0(value %||% "")[1]
  if (is.na(value) || !nzchar(trimws(value))) fallback else value
}


ullme_tests_safe_id = function(value, fallback="value") {
  value = gsub("[^A-Za-z0-9._-]+", "-", paste0(value %||% "")[1])
  value = gsub("^-+|-+$", "", value)
  if (nzchar(value)) value else fallback
}


ullme_tests_progress = function(...) {
  message = paste0(...)
  cat(message, "\n", sep="")
  flush.console()
  callback = getOption("ullme.tests.progress_callback")
  if (is.function(callback)) {
    try(callback(message), silent=TRUE)
  }
  invisible(NULL)
}


ullme_tests_job_label = function(job) {
  paste0(
    job$variant$id, " / ", job$model, " / ",
    job$input$instanceid, "/", job$input$inputid
  )
}


ullme_tests_promise_value = function(value) {
  promises::promise(function(resolve, reject) resolve(value))
}


ullme_tests_error_result = function(job, error) {
  ullme_tutor_workflow_cancel(job$state, reason="Test run failed")
  list(
    status="error",
    text=paste0(
      "Test run failed: ", ullme_safe_ai_error(error, job$app$api_config)
    ),
    state=job$state,
    error=error
  )
}


ullme_tests_finish_result = function(result, job, batch_index, batch_count,
                                      configured_batch_size,
                                      actual_batch_size) {
  finished_at = Sys.time()
  started_at = job$state$test_started_at %||% finished_at
  result$execution = list(
    started_at=format(started_at, "%Y-%m-%dT%H:%M:%OS3%z"),
    finished_at=format(finished_at, "%Y-%m-%dT%H:%M:%OS3%z"),
    duration_seconds=unname(as.numeric(difftime(
      finished_at, started_at, units="secs"
    ))),
    batched=actual_batch_size > 1L,
    batch_size=as.integer(configured_batch_size),
    batch_case_count=as.integer(actual_batch_size),
    batch_index=as.integer(batch_index),
    batch_count=as.integer(batch_count),
    waves=as.integer(job$state$test_wave_count %||% 0L)
  )
  result
}


ullme_tests_step_promise = function(job) {
  started = tryCatch(
    ullme_tutor_workflow_advance(
      job$state,
      single_model_step=TRUE
    ),
    error=function(error) error
  )
  if (inherits(started, "error")) {
    return(ullme_tests_promise_value(list(ok=FALSE, error=started)))
  }
  if (!inherits(started, "promise")) {
    return(ullme_tests_promise_value(list(ok=TRUE, result=started)))
  }
  promises::then(
    started,
    onFulfilled=function(result) list(ok=TRUE, result=result),
    onRejected=function(error) list(ok=FALSE, error=error)
  )
}


ullme_tests_run_batch = function(jobs, timeout_seconds,
                                  batch_index=1L, batch_count=1L,
                                  configured_batch_size=1L) {
  results = vector("list", length(jobs))
  active = seq_along(jobs)
  wave = 0L
  while (length(active)) {
    wave = wave + 1L
    wave_started_at = Sys.time()
    for (index in active) {
      if (is.null(jobs[[index]]$state$test_started_at)) {
        jobs[[index]]$state$test_started_at = wave_started_at
        jobs[[index]]$state$test_wave_count = 0L
      }
      jobs[[index]]$state$test_wave_count =
        jobs[[index]]$state$test_wave_count + 1L
    }
    nodes = vapply(active, function(index) {
      paste0(jobs[[index]]$state$node %||% "unknown")[1]
    }, character(1))
    node_counts = table(nodes)
    node_summary = paste0(
      names(node_counts), "=", as.integer(node_counts), collapse=", "
    )
    ullme_tests_progress(
      "  Batch ", batch_index, "/", batch_count, ", wave ", wave,
      ": sending ", length(active), " request(s) [", node_summary, "]."
    )

    calls = lapply(active, function(index) {
      ullme_tests_step_promise(jobs[[index]])
    })
    combined = promises::promise_all(.list=calls)
    wave_values = tryCatch(
      ullme_await_promise(
        combined,
        seconds=timeout_seconds,
        on_timeout=function() {
          for (index in active) {
            ullme_tutor_workflow_cancel(
              jobs[[index]]$state, reason="Test batch timed out"
            )
          }
        }
      ),
      error=function(error) error
    )
    if (inherits(wave_values, "error")) {
      for (index in active) {
        results[[index]] = ullme_tests_finish_result(
          ullme_tests_error_result(jobs[[index]], wave_values),
          jobs[[index]],
          batch_index=batch_index,
          batch_count=batch_count,
          configured_batch_size=configured_batch_size,
          actual_batch_size=length(jobs)
        )
      }
      ullme_tests_progress(
        "  Batch ", batch_index, " stopped in wave ", wave, ": ",
        conditionMessage(wave_values)
      )
      break
    }

    still_active = integer(0)
    for (position in seq_along(active)) {
      index = active[[position]]
      value = wave_values[[position]]
      if (!isTRUE(value$ok)) {
        results[[index]] = ullme_tests_finish_result(
          ullme_tests_error_result(jobs[[index]], value$error),
          jobs[[index]],
          batch_index=batch_index,
          batch_count=batch_count,
          configured_batch_size=configured_batch_size,
          actual_batch_size=length(jobs)
        )
      } else if (identical(value$result$status %||% "", "advanced")) {
        still_active = c(still_active, index)
      } else {
        results[[index]] = ullme_tests_finish_result(
          value$result,
          jobs[[index]],
          batch_index=batch_index,
          batch_count=batch_count,
          configured_batch_size=configured_batch_size,
          actual_batch_size=length(jobs)
        )
      }
    }
    ullme_tests_progress(
      "  Wave ", wave, " complete: ",
      length(active) - length(still_active), " finished, ",
      length(still_active), " continuing."
    )
    active = still_active
  }
  results
}


ullme_tests_read_yaml = function(path, label=basename(path)) {
  value = tryCatch(
    yaml::read_yaml(path, eval.expr=FALSE),
    error=function(error) stop(
      "Could not read ", label, ": ", conditionMessage(error),
      call.=FALSE
    )
  )
  if (!is.list(value)) stop(label, " must contain a YAML mapping.", call.=FALSE)
  value
}


ullme_tests_variant_specs = function(test_dir, base_definition, opts) {
  files = list.files(
    test_dir,
    pattern="^tutor_var_.+[.]ya?ml$",
    full.names=TRUE,
    ignore.case=TRUE,
    no..=TRUE
  )
  files = sort(files)
  variants = lapply(files, function(path) {
    modification = ullme_tests_read_yaml(path, basename(path))
    metadata = modification$test_variant %||% list()
    modification$test_variant = NULL
    id = sub("[.]ya?ml$", "", sub("^tutor_var_", "", basename(path)),
             ignore.case=TRUE)
    label = ullme_tests_nonempty(metadata$label, id)
    list(
      id=id,
      label=label,
      path=path,
      metadata=metadata,
      definition=utils::modifyList(
        base_definition, modification, keep.null=TRUE
      )
    )
  })
  if (isTRUE(opts$run_base)) {
    variants = c(list(list(
      id="base",
      label="Base tutor.yml",
      path=file.path(test_dir, "tutor.yml"),
      metadata=list(),
      definition=base_definition
    )), variants)
  }
  wanted = paste0(unlist(opts$just_variants %||% list(), use.names=FALSE))
  wanted = wanted[nzchar(wanted)]
  if (length(wanted)) {
    variants = Filter(function(variant) {
      candidates = c(
        variant$id,
        variant$label,
        basename(variant$path),
        tools::file_path_sans_ext(basename(variant$path))
      )
      any(tolower(candidates) %in% tolower(wanted))
    }, variants)
  }
  if (!length(variants)) stop("No test variants were selected.", call.=FALSE)
  variants
}


ullme_tests_input_specs = function(test_dir, instance_data) {
  root = file.path(test_dir, "instance_inputs")
  if (!dir.exists(root)) stop("Missing instance_inputs directory.", call.=FALSE)
  instance_dirs = list.dirs(root, recursive=FALSE, full.names=TRUE)
  specs = list()
  for (instance_dir in sort(instance_dirs)) {
    instanceid = basename(instance_dir)
    input_dirs = list.dirs(instance_dir, recursive=FALSE, full.names=TRUE)
    for (input_dir in sort(input_dirs)) {
      files = list.files(
        input_dir, full.names=TRUE, recursive=FALSE, no..=TRUE
      )
      files = files[file.exists(files) & !dir.exists(files)]
      text_files = files[tolower(tools::file_ext(files)) %in% c("txt", "md")]
      image_files = files[tolower(tools::file_ext(files)) %in%
        c("png", "jpg", "jpeg", "gif", "webp")]
      text = if (length(text_files)) {
        paste(vapply(text_files, function(path) paste(
          readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n"
        ), character(1)), collapse="\n\n")
      } else if (length(image_files)) {
        "[uploaded image]"
      } else {
        ""
      }
      if (!nzchar(trimws(text)) && !length(image_files)) {
        warning("Skipping empty test input directory: ", input_dir)
        next
      }
      specs[[length(specs) + 1L]] = list(
        instanceid=instanceid,
        inputid=basename(input_dir),
        directory=input_dir,
        text=text,
        images=image_files
      )
    }
  }
  known = vapply(instance_data$instances %||% list(), function(instance) {
    paste0(instance$instanceid %||% "")[1]
  }, character(1))
  unknown = setdiff(unique(vapply(specs, `[[`, character(1), "instanceid")), known)
  if (length(known) && length(unknown)) {
    stop("Input directories name unknown instances: ",
         paste(unknown, collapse=", "), call.=FALSE)
  }
  if (!length(specs)) stop("No test inputs were found.", call.=FALSE)
  specs
}


ullme_tests_copy_materials = function(instance_data, materials_dir,
                                       course_dir) {
  material_target = file.path(course_dir, "materials")
  dir.create(material_target, recursive=TRUE, showWarnings=FALSE)
  documents = c(
    unlist(instance_data$course_docs %||% list(), use.names=FALSE),
    unlist(lapply(instance_data$instances %||% list(), function(instance) {
      unlist(instance$docs %||% list(), use.names=FALSE)
    }), use.names=FALSE)
  )
  documents = unique(gsub("\\\\", "/", paste0(documents)))
  documents = documents[nzchar(documents)]
  if (!length(documents)) return(invisible(material_target))
  if (is.null(materials_dir) || !dir.exists(materials_dir)) {
    stop("materials_dir does not exist, but instances.yml references documents.",
         call.=FALSE)
  }
  for (relative in documents) {
    if (!ullme_safe_relative_material_path(relative)) {
      stop("Unsafe material path in instances.yml: ", relative, call.=FALSE)
    }
    source = file.path(materials_dir, relative)
    if (!file.exists(source) || dir.exists(source)) {
      stop("Material file not found: ", source, call.=FALSE)
    }
    target = file.path(material_target, relative)
    dir.create(dirname(target), recursive=TRUE, showWarnings=FALSE)
    if (!file.copy(source, target, overwrite=TRUE, copy.date=TRUE)) {
      stop("Could not stage material file: ", source, call.=FALSE)
    }
  }
  invisible(material_target)
}


ullme_tests_uploads = function(input, upload_dir) {
  if (!length(input$images)) return(list())
  dir.create(upload_dir, recursive=TRUE, showWarnings=FALSE)
  lapply(seq_along(input$images), function(index) {
    source = input$images[[index]]
    id = sprintf("test%03d", index)
    target = file.path(upload_dir, paste0(id, "_", basename(source)))
    if (!file.copy(source, target, overwrite=TRUE, copy.date=TRUE)) {
      stop("Could not stage input image: ", source, call.=FALSE)
    }
    extension = tolower(tools::file_ext(source))
    mime = switch(extension, jpg="image/jpeg", jpeg="image/jpeg",
                  png="image/png", gif="image/gif", webp="image/webp",
                  "application/octet-stream")
    list(id=id, name=basename(source), type=mime,
         size=unname(file.info(target)$size))
  })
}


ullme_tests_app = function(main_dir, course_dir, tutor, input, model, opts) {
  key_file = ullme_tests_nonempty(
    opts$api_key_file,
    ullme_tests_nonempty(
      Sys.getenv("NVIDIA_API_KEY_FILE", unset=""),
      "C:/libraries/ullme/nvidia_api_key.txt"
    )
  )
  config = ullme_api_config(
    api_provider=paste0(opts$api)[1],
    api_key_file=key_file,
    api_model=model,
    api_base_url=opts$api_base_url
  )
  app = new.env(parent=emptyenv())
  app$glob = new.env(parent=emptyenv())
  app$glob$main_dir = main_dir
  app$role = "student"
  app$userid = "test_student"
  app$teacherid = "test_teacher"
  app$courseid = "test_course"
  app$semester = "SS00"
  app$tutorid = tutor$tutorid
  app$instanceid = input$instanceid
  app$student_tutors = list(tutor)
  app$api_config = config
  app$api_models = model
  app$uses_fake_ai = identical(config$provider, "fake")
  app$chat_debug = FALSE
  app$enable_ai_tools = FALSE
  app$chat_connect_timeout_seconds = min(60, as.numeric(opts$timeout_seconds))
  app$chat_timeout_seconds = as.numeric(opts$timeout_seconds)
  app$uploads_dir = file.path(main_dir, "uploads")
  app
}


ullme_tests_media_metadata = function(input) {
  lapply(input$images %||% character(0), function(path) {
    extension = tolower(tools::file_ext(path))
    mime = switch(
      extension,
      jpg="image/jpeg",
      jpeg="image/jpeg",
      png="image/png",
      gif="image/gif",
      webp="image/webp",
      "application/octet-stream"
    )
    size = suppressWarnings(as.numeric(file.info(path)$size)[1])
    list(
      filename=basename(path),
      mime_type=mime,
      size_bytes=if (is.na(size)) 0 else size
    )
  })
}


ullme_tests_yaml_text = function(text, always=FALSE) {
  text = paste0(text %||% "", collapse="\n")
  if (nzchar(text) && (isTRUE(always) || grepl("\n", text, fixed=TRUE))) {
    class(text) = c("ullme_yaml_literal", "character")
  }
  text
}


ullme_tests_as_yaml = function(value) {
  blocks = list()
  replace_blocks = function(item) {
    if (inherits(item, "ullme_yaml_literal")) {
      token = sprintf("ULLMEYAMLBLOCK%06d", length(blocks) + 1L)
      blocks[[token]] <<- paste0(item)[1]
      return(token)
    }
    if (is.list(item)) return(lapply(item, replace_blocks))
    item
  }
  yaml_text = yaml::as.yaml(replace_blocks(value), unicode=TRUE)
  if (!length(blocks)) return(yaml_text)

  lines = strsplit(yaml_text, "\n", fixed=TRUE)[[1]]
  output = character(0)
  for (line in lines) {
    found = names(blocks)[vapply(
      names(blocks),
      function(token) endsWith(line, token),
      logical(1)
    )]
    if (!length(found)) {
      output = c(output, line)
      next
    }
    if (length(found) != 1L) {
      stop("Could not identify a unique YAML literal placeholder.", call.=FALSE)
    }
    token = found[[1]]
    leading = regexpr("[^ ]", line)[[1]] - 1L
    if (leading < 0L) leading = 0L
    output = c(output, sub(token, "|-", line, fixed=TRUE))
    text_lines = strsplit(
      paste0(blocks[[token]], "\nULLMEYAMLBLOCKEND"),
      "\n",
      fixed=TRUE
    )[[1]]
    text_lines = text_lines[-length(text_lines)]
    while (length(text_lines) && !nzchar(text_lines[[length(text_lines)]])) {
      text_lines = text_lines[-length(text_lines)]
    }
    if (length(text_lines)) {
      output = c(
        output,
        paste0(strrep(" ", leading + 2L), text_lines)
      )
    }
  }
  paste(output, collapse="\n")
}


ullme_tests_result_yaml = function(result, variant, input, model, opts) {
  trace = result$state$trace %||% list()
  media = ullme_tests_media_metadata(input)
  nodes = list()
  if (isTRUE(opts$results_by_node)) {
    for (item in trace) {
      node = list(
        node_id=paste0(item$node %||% "unknown")[1],
        skipped=isTRUE(item$skipped),
        started_at=paste0(item$started_at %||% "")[1],
        finished_at=paste0(item$finished_at %||% "")[1],
        duration_seconds=as.numeric(item$duration_seconds %||% 0)[1],
        output=if (isTRUE(item$skipped)) "" else
          ullme_tests_yaml_text(item$output, always=TRUE)
      )
      if (isTRUE(opts$add_full_prompts_in_results) && !isTRUE(item$skipped)) {
        node$system_prompt = ullme_tests_yaml_text(
          item$system_prompt, always=TRUE
        )
        node$prompt = ullme_tests_yaml_text(item$prompt, always=TRUE)
      }
      nodes[[length(nodes) + 1L]] = node
    }
  } else if (isTRUE(opts$add_full_prompts_in_results)) {
    for (item in trace) {
      if (isTRUE(item$skipped)) next
      nodes[[length(nodes) + 1L]] = list(
        node_id=paste0(item$node %||% "unknown")[1],
        system_prompt=ullme_tests_yaml_text(item$system_prompt, always=TRUE),
        prompt=ullme_tests_yaml_text(item$prompt, always=TRUE)
      )
    }
  }
  error_message = if (identical(result$status %||% "", "error")) {
    sub(
      "^Test run failed: ", "",
      paste0(result$text %||% "", collapse="\n")
    )
  } else {
    ""
  }
  list(
    schema_version=1L,
    test=list(
      variant_id=variant$id,
      variant_label=variant$label,
      model=model,
      api=paste0(opts$api)[1],
      instance_id=input$instanceid,
      input_id=input$inputid,
      status=paste0(result$status %||% "unknown")[1]
    ),
    execution=result$execution %||% list(),
    input=list(
      text=ullme_tests_yaml_text(input$text),
      media_count=length(media),
      media_total_bytes=sum(vapply(
        media, function(item) item$size_bytes, numeric(1)
      )),
      media=media
    ),
    response=list(
      final_output=ullme_tests_yaml_text(result$text, always=TRUE),
      error_message=error_message,
      node_count=length(nodes),
      nodes=nodes
    )
  )
}


ullme_tests_fence = function(text) {
  text = paste0(text %||% "", collapse="\n")
  hits = gregexpr("`+", text, perl=TRUE)[[1]]
  longest = if (length(hits) == 1L && hits[[1]] < 0L) 0L else
    max(attr(hits, "match.length"))
  fence = paste(rep("`", max(3L, longest + 1L)), collapse="")
  c(paste0(fence, "text"), text, fence)
}


ullme_tests_result_markdown = function(result, variant, input, model, opts) {
  state = result$state
  trace = state$trace %||% list()
  lines = c(
    paste0("# ", variant$label, " — ", input$instanceid, "/", input$inputid),
    "",
    paste0("- Variant: `", variant$id, "`"),
    paste0("- Model: `", model, "`"),
    paste0("- Instance: `", input$instanceid, "`"),
    paste0("- Input: `", input$inputid, "`"),
    paste0("- Status: `", result$status %||% "unknown", "`"),
    paste0("- Created: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %z")),
    "", "## Final output", "", paste0(result$text %||% "", collapse="\n")
  )
  if (isTRUE(opts$results_by_node)) {
    lines = c(lines, "", "## Results by node")
    for (item in trace) {
      lines = c(lines, "", paste0("### ", item$node), "")
      if (isTRUE(item$skipped)) {
        lines = c(lines, "_Skipped._")
      } else {
        lines = c(lines, paste0(item$output %||% "", collapse="\n"))
      }
      if (isTRUE(opts$add_full_prompts_in_results) && !isTRUE(item$skipped)) {
        lines = c(
          lines, "", "#### System prompt", "",
          ullme_tests_fence(item$system_prompt), "", "#### Node prompt", "",
          ullme_tests_fence(item$prompt)
        )
      }
    }
  } else if (isTRUE(opts$add_full_prompts_in_results)) {
    lines = c(lines, "", "## Full prompts")
    for (item in trace) {
      if (isTRUE(item$skipped)) next
      lines = c(
        lines, "", paste0("### ", item$node), "", "#### System prompt", "",
        ullme_tests_fence(item$system_prompt), "", "#### Node prompt", "",
        ullme_tests_fence(item$prompt)
      )
    }
  }
  lines
}


ullme_remove_test_dir = function(dir_to_be_removed, test_dir=NULL) {
  if (length(dir_to_be_removed) != 1L || is.na(dir_to_be_removed) ||
      !nzchar(trimws(dir_to_be_removed))) {
    stop("dir_to_be_removed must be one non-empty path.", call.=FALSE)
  }
  dir_to_be_removed = normalizePath(
    dir_to_be_removed, winslash="/", mustWork=FALSE
  )
  path_to_check = if (identical(.Platform$OS.type, "windows")) {
    tolower(dir_to_be_removed)
  } else {
    dir_to_be_removed
  }

  # Require at least <main_dir>/tests/<test_name>/<subdirectory>. In
  # particular, never allow removal of tests/ or of the test directory itself.
  if (!grepl("/tests/[^/]+/.+$", path_to_check)) {
    stop(
      "Only subdirectories of main_dir/tests/<test_name>/ can be removed ",
      "by ullme_remove_test_dir.",
      call.=FALSE
    )
  }
  if (!is.null(test_dir)) {
    test_dir = normalizePath(test_dir, winslash="/", mustWork=TRUE)
    root_to_check = if (identical(.Platform$OS.type, "windows")) {
      tolower(test_dir)
    } else {
      test_dir
    }
    if (!startsWith(path_to_check, paste0(root_to_check, "/"))) {
      stop(
        "The directory to remove is not a subdirectory of test_dir.",
        call.=FALSE
      )
    }
  }
  unlink(dir_to_be_removed, recursive=TRUE)
  invisible(!file.exists(dir_to_be_removed))
}


