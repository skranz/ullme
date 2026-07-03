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
  summary = paste0(
    "Label: ", definition$label %||% tutorid, "\n",
    "Description: ", paste0(definition$description %||% "", collapse="\n"), "\n",
    "Typical instances: ",
    paste0(definition$instance_guidance %||%
      "Infer instances carefully from document roles and filenames.", collapse="\n")
  )
  semester = basename(dirname(course_dir))
  ullme_prompt("instance_builder", values=list(
    semester=semester,
    courseid=basename(course_dir),
    tutorid=tutorid,
    tutor_summary=summary,
    tutor_yaml=tutor_yaml,
    instances_yaml=instances_yaml,
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
                                        run=FALSE, allow_changes=FALSE) {
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
  app$agent_approval_override = if (isTRUE(allow_changes)) "allow" else "deny"
  chat = ullme_ai_request_chat(
    model=model,
    context=list(studio_view="ai-tutors"),
    app=app
  )
  answer = chat$chat(prompt, echo="none")
  list(prompt=prompt, answer=answer, app=app)
}
