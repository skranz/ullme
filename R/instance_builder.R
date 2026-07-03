ullme_instance_builder_material_text = function(course_dir) {
  root = .ullme_material_root(file.path(course_dir, "materials"))
  relative = list.files(
    root, recursive=TRUE, full.names=FALSE, all.files=TRUE,
    no..=TRUE, include.dirs=FALSE
  )
  relative = sort(gsub("\\\\", "/", relative))
  if (!length(relative)) return("- No material files found.")
  paste(vapply(relative, function(path) {
    info = file.info(file.path(root, path))
    paste0(
      "- ", path,
      " (", tolower(tools::file_ext(path)),
      ", ", if (is.na(info$size[[1]])) "unknown size" else
        paste0(info$size[[1]], " bytes"), ")"
    )
  }, character(1)), collapse="\n")
}


ullme_instance_builder_prompt = function(course_dir, tutorid,
                                          user_guidance="") {
  tutorid = ullme_clean_definition_id(tutorid)
  tutor_path = ullme_existing_course_ai_tutor_path(course_dir, tutorid)
  if (!file.exists(tutor_path)) stop("The requested course AI Tutor does not exist.")
  definition = yaml::read_yaml(tutor_path, eval.expr=FALSE)
  if (!is.list(definition)) stop("The AI Tutor definition is invalid.")
  instance_data = ullme_read_course_ai_tutor_instances(course_dir, tutorid)
  tutor_yaml = paste(readLines(
    tutor_path, warn=FALSE, encoding="UTF-8"
  ), collapse="\n")
  instances_yaml = ullme_course_ai_tutor_instances_yaml(
    course_dir, tutorid,
    instances=instance_data$instances,
    course_docs=instance_data$course_docs
  )
  candidates = ullme_suggest_course_ai_tutor_instances(course_dir, definition)
  candidate_yaml = ullme_course_ai_tutor_instances_yaml(
    course_dir, tutorid,
    instances=candidates,
    course_docs=instance_data$course_docs
  )
  summary = paste0(
    "Label: ", definition$label %||% tutorid, "\n",
    "Description: ", paste0(definition$description %||% "", collapse="\n"), "\n",
    "Typical instances: ",
    paste0(definition$instance_guidance %||%
      "Infer instances carefully from document roles and filenames.", collapse="\n")
  )
  semester = basename(dirname(course_dir))
  ullme_prompt_with_literal_values("instance_builder", values=list(
    semester=semester,
    courseid=basename(course_dir),
    tutorid=tutorid,
    tutor_summary=summary,
    tutor_yaml=tutor_yaml,
    instances_yaml=instances_yaml,
    candidate_yaml=candidate_yaml,
    material_files=ullme_instance_builder_material_text(course_dir),
    user_guidance=if (nzchar(trimws(user_guidance))) user_guidance else
      "No additional guidance was supplied. Infer conservatively.",
    tools=paste(
      vapply(
        c(
          "list_material_files", "read_definition_yaml",
          "read_tutor_instances_yaml", "convert_material_files",
          "rewrite_tutor_instances_yaml", "change_status"
        ),
        function(name) paste0("- ", name, ": ",
          ullme_tool_registry()[[name]]$description),
        character(1)
      ),
      collapse="\n"
    )
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


ullme_test_instance_builder = function(main_dir, userid, semester, courseid,
                                        tutorid, guidance="",
                                        api_key_file=NULL,
                                        model="nvidia/nemotron-3-nano-30b-a3b",
                                        run=FALSE, allow_changes=FALSE,
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
  max_rounds = if (isTRUE(allow_changes)) 3L else 1L
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
    current_instances = if (file.exists(instances_path)) {
      paste(readLines(
        instances_path, warn=FALSE, encoding="UTF-8"
      ), collapse="\n")
    } else {
      NULL
    }
    changed = !identical(initial_instances, current_instances)
    if (changed || round >= max_rounds) break
    request = paste(
      "Continue the instance-builder task now.",
      "Your preceding turn ended without changing instances.yml.",
      "Do not repeat the plan or promise a future action.",
      "Call the required tools in this response, verify the saved YAML,",
      "and only then give the final summary."
    )
  }
  combined_answer = paste(answers, collapse="\n\n")
  ullme_ai_interaction_finish(
    interaction,
    status=if (isTRUE(allow_changes) && !changed) "incomplete" else "completed",
    text=combined_answer,
    thinking=paste(thinking, collapse="\n\n")
  )
  list(
    prompt=prompt,
    answer=combined_answer,
    changed=changed,
    rounds=length(answers),
    app=app
  )
}
