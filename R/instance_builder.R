ullme_instance_builder_ps_files = function(course_dir) {
  root = file.path(
    .ullme_material_root(file.path(course_dir, "materials")),
    "ps"
  )
  if (!dir.exists(root)) return(character(0))
  relative = list.files(
    root, recursive=TRUE, full.names=FALSE, all.files=FALSE,
    no..=TRUE, include.dirs=FALSE
  )
  sort(paste0("ps/", gsub("\\\\", "/", relative)))
}


ullme_instance_builder_ps_text = function(course_dir) {
  files = ullme_instance_builder_ps_files(course_dir)
  if (!length(files)) return("- No files found in materials/ps.")
  paste0("- ", files, collapse="\n")
}


ullme_example_tutor_document_path = function(spec, docid,
                                              instanceid="example_1") {
  directory = trimws(paste0(spec$pref_doc_dir %||% "ps")[1])
  if (!nzchar(directory)) directory = "ps"
  directory = gsub("^/+|/+$", "", gsub("\\\\", "/", directory))
  formats = trimws(paste0(unlist(
    spec$file_types %||% list(),
    use.names=FALSE
  )))
  formats = formats[nzchar(formats)]
  extension = if (length(formats)) formats[[1]] else "md"
  extension = sub("^\\.+", "", tolower(extension))
  safe_docid = gsub("[^a-z0-9_-]+", "_", tolower(docid))
  paste0(directory, "/", instanceid, "_", safe_docid, ".", extension)
}


ullme_instance_builder_doc_roles_text = function(definition) {
  sections = list(
    per_instance=ullme_normalize_tutor_doc_specs(
      definition$docs_per_instance
    ),
    per_course=ullme_normalize_tutor_doc_specs(
      definition$docs_per_course
    )
  )
  lines = unlist(lapply(names(sections), function(scope) {
    specs = sections[[scope]]
    if (!length(specs)) return(NULL)
    vapply(names(specs), function(docid) {
      spec = specs[[docid]]
      types = paste0(unlist(spec$file_types, use.names=FALSE))
      paste0(
        "- ", docid, " (", gsub("_", " ", scope, fixed=TRUE), "): ",
        spec$descr, "; directory `", spec$pref_doc_dir,
        "`; allowed file types in preferred order: ",
        paste(types, collapse=", ")
      )
    }, character(1))
  }), use.names=FALSE)
  if (!length(lines)) "- No document roles defined." else
    paste(lines, collapse="\n")
}


ullme_example_tutor_instances_yaml = function(definition) {
  if (!is.list(definition)) stop("An AI Tutor definition is required.")
  instance_specs = ullme_normalize_tutor_doc_specs(
    definition$docs_per_instance
  )
  course_specs = ullme_normalize_tutor_doc_specs(
    definition$docs_per_course
  )
  instance_docs = lapply(names(instance_specs), function(docid) {
    as.list(ullme_example_tutor_document_path(
      instance_specs[[docid]],
      docid=docid,
      instanceid="example_1"
    ))
  })
  names(instance_docs) = names(instance_specs)
  course_docs = lapply(names(course_specs), function(docid) {
    as.list(ullme_example_tutor_document_path(
      course_specs[[docid]],
      docid=docid,
      instanceid="course"
    ))
  })
  names(course_docs) = names(course_specs)
  instances = if (length(instance_specs)) {
    list(list(
      instanceid="example_1",
      label="Example 1",
      docs=instance_docs
    ))
  } else {
    list()
  }
  ullme_tutor_instances_yaml(
    instances=instances,
    course_docs=course_docs
  )
}


ullme_instance_builder_prompt = function(course_dir, tutorid,
                                          user_guidance="") {
  tutorid = ullme_clean_definition_id(tutorid)
  tutor_path = ullme_existing_course_ai_tutor_path(course_dir, tutorid)
  if (!file.exists(tutor_path)) stop("The requested course AI Tutor does not exist.")
  definition = yaml::read_yaml(tutor_path, eval.expr=FALSE)
  if (!is.list(definition)) stop("The AI Tutor definition is invalid.")
  semester = basename(dirname(course_dir))
  ullme_prompt_with_literal_values("instance_builder", values=list(
    semester=semester,
    courseid=basename(course_dir),
    tutorid=tutorid,
    tutor_label=paste0(definition$label %||% tutorid)[1],
    tutor_guidance=paste0(
      definition$instance_guidance %||%
        "Group matching problem and solution filenames.",
      collapse="\n"
    ),
    document_roles=ullme_instance_builder_doc_roles_text(definition),
    example_yaml=ullme_example_tutor_instances_yaml(definition),
    ps_files=ullme_instance_builder_ps_text(course_dir),
    user_guidance=if (nzchar(trimws(user_guidance))) user_guidance else
      "No additional instruction."
  ))
}


ullme_instance_builder_request = function(tutorid, guidance="",
                                           app=getApp()) {
  if (!identical(app$role, "teacher")) {
    stop("Only teachers can build AI Tutor instances.")
  }
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) stop("Select a course first.")
  ullme_instance_builder_prompt(
    course_dir=course_dir,
    tutorid=tutorid,
    user_guidance=guidance
  )
}


ullme_instance_builder_yaml_header = function() {
  "BEGIN_ULLME_INSTANCES_YAML"
}


ullme_instance_builder_yaml_footer = function() {
  "END_ULLME_INSTANCES_YAML"
}


ullme_parse_instance_builder_response = function(text) {
  parsed = ullme_parse_yaml_reply(
    text=text,
    required_fields=c("course_docs", "instances"),
    header_line=ullme_instance_builder_yaml_header(),
    footer_line=ullme_instance_builder_yaml_footer(),
    label="Instance Builder response"
  )
  if (!isTRUE(parsed$ok)) return(parsed)
  unknown = setdiff(names(parsed$value), c("course_docs", "instances"))
  if (length(unknown)) {
    message = paste0(
      "Instance Builder response contains unknown top-level field",
      if (length(unknown) > 1L) "s" else "",
      ": ", paste(unknown, collapse=", "), "."
    )
    return(list(
      ok=FALSE, value=NULL, yaml="", source=parsed$source,
      errors=message, message=message
    ))
  }
  parsed
}


ullme_apply_instance_builder_response = function(tutorid, text,
                                                  app=getApp()) {
  parsed = ullme_parse_instance_builder_response(text)
  if (!isTRUE(parsed$ok)) {
    return(list(
      ok=FALSE,
      applied=FALSE,
      message=parsed$message,
      parse=parsed
    ))
  }
  result = tryCatch(
    ullme_save_course_ai_tutor_instances_yaml(
      tutorid=tutorid,
      yaml_content=parsed$yaml,
      origin="instance_builder",
      app=app
    ),
    error=function(e) e
  )
  if (!inherits(result, "error") && isTRUE(result$ok) &&
      identical(result$status, "committed")) {
    if (!isTRUE(app$headless)) ullme_send_course_state(app=app)
    return(list(
      ok=TRUE, applied=TRUE, message="Instances updated.", parse=parsed
    ))
  }
  message = if (inherits(result, "error")) {
    conditionMessage(result)
  } else {
    result$message %||% "The returned assignments could not be saved."
  }
  list(
    ok=FALSE,
    applied=FALSE,
    message=message,
    parse=parsed
  )
}


ullme_instance_builder_retry_prompt = function(previous_output, error) {
  paste0(
    "Your previous Instance Builder response could not be accepted.\n\n",
    "PARSING OR VALIDATION ERROR\n", paste0(error)[1], "\n\n",
    "PREVIOUS RESPONSE\n", paste0(previous_output, collapse="\n"), "\n\n",
    "Return a corrected complete instances.yml now. Output exactly these ",
    "three parts and nothing else:\n",
    ullme_instance_builder_yaml_header(), "\n",
    "<valid YAML mapping with course_docs and instances>\n",
    ullme_instance_builder_yaml_footer()
  )
}


ullme_test_instance_builder = function(main_dir, userid, semester, courseid,
                                        tutorid, guidance="",
                                        api_key_file=NULL,
                                        model="nvidia/nemotron-3-nano-30b-a3b",
                                        run=FALSE, allow_changes=FALSE,
                                        retries=1L,
                                        timeout_seconds=180) {
  course_dir = ullme_course_dir(
    main_dir=main_dir, userid=userid, role="teacher",
    semester=semester, courseid=courseid
  )
  if (!dir.exists(course_dir)) stop("The requested course does not exist.")
  prompt = ullme_instance_builder_prompt(course_dir, tutorid, guidance)
  if (!isTRUE(run)) return(prompt)
  app = teacherApp(
    main_dir=main_dir,
    userid=userid,
    api_provider="nvidia",
    api_key_file=api_key_file,
    api_model=model,
    store_ai_interactions=TRUE
  )
  app$semester = semester
  app$courseid = courseid
  app$api_models = model
  app$headless = TRUE
  app$agent_approval_override = if (isTRUE(allow_changes)) "allow" else "deny"
  instances_path = ullme_course_ai_tutor_instances_path(course_dir, tutorid)
  initial_instances = if (file.exists(instances_path)) {
    paste(readLines(instances_path, warn=FALSE, encoding="UTF-8"), collapse="\n")
  } else {
    NULL
  }
  interaction = ullme_ai_interaction_start(
    prompt, guidance, model, "instance_builder_headless", app=app
  )
  answers = character(0)
  thinking = character(0)
  request = prompt
  changed = FALSE
  retries = suppressWarnings(as.integer(retries)[1])
  if (is.na(retries) || retries < 0L) stop("retries must be non-negative.")
  max_rounds = retries + 1L
  builder_result = NULL
  deadline = as.numeric(Sys.time()) + as.numeric(timeout_seconds)[1]
  for (round in seq_len(max_rounds)) {
    remaining = deadline - as.numeric(Sys.time())
    if (is.na(remaining) || remaining <= 0) {
      error = paste0(
        "The instance-builder test timed out after ",
        timeout_seconds,
        " seconds."
      )
      ullme_ai_interaction_finish(
        interaction,
        status="error",
        text=paste(answers, collapse="\n\n"),
        thinking=paste(thinking, collapse="\n\n"),
        error=error
      )
      stop(error)
    }
    job = ullme_start_ai_stream(
      input=request,
      model=model,
      context=list(studio_view="ai-tutors"),
      include_thinking=TRUE,
      task_profile="instance_builder",
      app=app
    )
    round_result = tryCatch(
      ullme_await_promise(
        job$promise,
        seconds=remaining,
        on_timeout=function() {
          job$controller$cancel("Instance-builder test timed out")
        }
      ),
      error=function(e) {
        ullme_ai_interaction_finish(
          interaction,
          status="error",
          text=paste(answers, collapse="\n\n"),
          thinking=paste(thinking, collapse="\n\n"),
          error=conditionMessage(e)
        )
        stop(e)
      }
    )
    answer = round_result$text
    answers = c(answers, answer)
    thinking = c(thinking, round_result$thinking)
    builder_result = if (isTRUE(allow_changes)) {
      ullme_apply_instance_builder_response(tutorid, answer, app=app)
    } else {
      parsed = ullme_parse_instance_builder_response(answer)
      list(
        ok=isTRUE(parsed$ok),
        applied=FALSE,
        message=parsed$message,
        parse=parsed
      )
    }
    current_instances = if (file.exists(instances_path)) {
      paste(readLines(
        instances_path, warn=FALSE, encoding="UTF-8"
      ), collapse="\n")
    } else {
      NULL
    }
    changed = !identical(initial_instances, current_instances)
    if (isTRUE(builder_result$ok) || round >= max_rounds) break
    request = ullme_instance_builder_retry_prompt(
      previous_output=answer,
      error=builder_result$message
    )
  }
  combined_answer = paste(answers, collapse="\n\n")
  ullme_ai_interaction_finish(
    interaction,
    status=if (!isTRUE(builder_result$ok)) "incomplete" else "completed",
    text=combined_answer,
    thinking=paste(thinking, collapse="\n\n")
  )
  list(
    prompt=prompt,
    answer=combined_answer,
    changed=changed,
    rounds=length(answers),
    result=builder_result,
    app=app
  )
}
