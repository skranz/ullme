example_studentApp = function() {
  library(ullme)
  restore.point.options(display.restore.point=TRUE)
  main_dir = "C:/libraries/ullme/ullme_main"
  app = studentApp(
    main_dir=main_dir,
    userid="seb",
    teacherid="skranz",
    courseid="Umwelt",
    api_key_file="C:/libraries/ullme/nvidia_api_key.txt",
    api_provider="nvidia"
  )
  viewApp(app, launch.browser=TRUE)
}


studentApp = function(main_dir, userid="student", teacherid=NULL,
                       courseid=NULL, semester=NULL, tutorid=NULL,
                       instanceid=NULL,
                       uses_fake_ai=NULL, max_upload_mb=100,
                       api_key_file=NULL,
                       api_provider=c("fake", "nvidia", "local"),
                       api_model=NULL, api_base_url=NULL,
                       render_chat_markdown=TRUE,
                       stream_chat=TRUE,
                       store_ai_interactions=TRUE,
                       never_save_chats=TRUE,
                       login_check=c("none", "sel"),
                       login_args=list(),
                       email2userid=ullme_email2userid) {
  restore.point("studentApp")
  .ullme_app(
    main_dir=main_dir,
    userid=userid,
    role="student",
    teacherid=teacherid,
    courseid=courseid,
    semester=semester,
    tutorid=tutorid,
    instanceid=instanceid,
    uses_fake_ai=uses_fake_ai,
    max_upload_mb=max_upload_mb,
    render_chat_markdown=render_chat_markdown,
    api_key_file=api_key_file,
    api_provider=api_provider,
    api_model=api_model,
    api_base_url=api_base_url,
    stream_chat=stream_chat,
    show_chat_thinking=FALSE,
    store_ai_interactions=store_ai_interactions,
    never_save_chats=never_save_chats,
    login_check=login_check,
    login_args=login_args,
    email2userid=email2userid
  )
}


ullme_optional_app_parameter = function(value, cleaner, name) {
  restore.point("ullme_optional_app_parameter")
  if (is.null(value) || length(value) == 0) return(NULL)
  value = paste0(value)[1]
  if (is.na(value) || !nzchar(trimws(value))) return(NULL)
  tryCatch(
    cleaner(value),
    error=function(e) stop(name, ": ", conditionMessage(e), call.=FALSE)
  )
}


ullme_student_url_parameters = function(session) {
  restore.point("ullme_student_url_parameters")
  search = tryCatch(session$clientData$url_search, error=function(e) "")
  query = shiny::parseQueryString(paste0(search %||% "")[1])
  specs = list(
    teacherid=c("teacherid", "teacher"),
    courseid=c("courseid", "course"),
    semester=c("sem", "semester"),
    tutorid=c("tutor", "tutorid"),
    instanceid=c("inst", "instance", "instanceid")
  )
  result = lapply(specs, function(keys) {
    value = NULL
    for (key in keys) {
      if (!is.null(query[[key]])) {
        value = query[[key]]
        break
      }
    }
    if (is.null(value) || length(value) == 0) return(NULL)
    value = paste0(value)[1]
    if (is.na(value) || !nzchar(trimws(value))) NULL else value
  })
  result
}


ullme_clean_semester_parameter = function(semester) {
  restore.point("ullme_clean_semester_parameter")
  semester = toupper(paste0(semester)[1])
  ullme_semester_index(semester)
  semester
}


ullme_student_available_semesters = function(app=getApp()) {
  restore.point("ullme_student_available_semesters")
  if (is.null(app$teacherid) || is.null(app$courseid)) return(character(0))
  ullme_course_semesters(
    main_dir=app$glob$main_dir,
    teacherid=app$teacherid,
    courseid=app$courseid,
    require_tutor=TRUE
  )
}


ullme_student_resolve_parameters = function(session, app=getApp()) {
  restore.point("ullme_student_resolve_parameters")
  query = ullme_student_url_parameters(session)
  cleaners = list(
    teacherid=ullme_clean_user_name,
    courseid=ullme_clean_courseid,
    semester=ullme_clean_semester_parameter,
    tutorid=ullme_clean_definition_id,
    instanceid=ullme_clean_tutor_instance_id
  )
  for (name in names(cleaners)) {
    argument_value = app$global[[name]]
    value = if (is.null(argument_value)) query[[name]] else argument_value
    app[[name]] = ullme_optional_app_parameter(
      value=value,
      cleaner=cleaners[[name]],
      name=name
    )
  }
  missing = c("teacherid", "courseid")[
    vapply(c("teacherid", "courseid"), function(name) {
      is.null(app[[name]])
    }, logical(1))
  ]
  if (length(missing)) {
    stop(
      paste0(
        paste(missing, collapse=" and "),
        if (length(missing) == 1) " must" else " must",
        " be supplied to studentApp() or in the URL query string."
      ),
      call.=FALSE
    )
  }
  if (is.null(app$semester)) {
    app$semester = ullme_default_course_semester(
      main_dir=app$glob$main_dir,
      teacherid=app$teacherid,
      courseid=app$courseid
    ) %||% ullme_course_default_semester_for_date()
  } else if (!app$semester %in% ullme_course_semesters(
      main_dir=app$glob$main_dir,
      teacherid=app$teacherid,
      courseid=app$courseid,
      require_tutor=FALSE
    )) {
    default_semester = ullme_default_course_semester(
      main_dir=app$glob$main_dir,
      teacherid=app$teacherid,
      courseid=app$courseid
    )
    if (!is.null(default_semester)) app$semester = default_semester
  }
  app$allow_semester_switch = TRUE
  app$allow_tutor_switch = TRUE
  app$allow_instance_switch = TRUE
  invisible(app)
}


ullme_student_course_dir = function(app=getApp()) {
  restore.point("ullme_student_course_dir")
  if (is.null(app$teacherid) || is.null(app$courseid)) return(NULL)
  path = ullme_course_dir(
    main_dir=app$glob$main_dir,
    userid=app$teacherid,
    role="teacher",
    semester=app$semester,
    courseid=app$courseid
  )
  if (dir.exists(path)) path else NULL
}


ullme_student_tutor_definition = function(tutorid, app=getApp()) {
  restore.point("ullme_student_tutor_definition")
  course_dir = ullme_student_course_dir(app=app)
  if (is.null(course_dir)) return(NULL)
  path = ullme_existing_course_ai_tutor_path(course_dir, tutorid)
  if (!file.exists(path)) return(NULL)
  value = tryCatch(
    yaml::read_yaml(path, eval.expr=FALSE),
    error=function(e) NULL
  )
  if (!is.list(value) || identical(value$enabled, FALSE)) return(NULL)
  if (!identical(paste0(value$tutorid %||% "")[1], tutorid)) return(NULL)
  definition = ullme_normalize_ai_tutor_definition(
    definition=value,
    tutorid=tutorid,
    source="course"
  )
  has_instances = !identical(value$multiple_instances, FALSE)
  instance_data = if (has_instances) {
    ullme_read_course_ai_tutor_instances(course_dir, tutorid)
  } else {
    list(instances=list(), course_docs=list(), exists=FALSE)
  }
  instances = instance_data$instances
  if (has_instances && !isTRUE(instance_data$exists)) {
    instances = ullme_suggest_course_ai_tutor_instances(course_dir, value)
  }
  definition$instances = instances
  definition$course_docs = instance_data$course_docs
  definition
}


ullme_student_tutors = function(app=getApp()) {
  restore.point("ullme_student_tutors")
  course_dir = ullme_student_course_dir(app=app)
  if (is.null(course_dir)) return(list())
  ids = ullme_definition_ids(ullme_course_ai_tutors_dir(course_dir))
  tutors = lapply(ids, ullme_student_tutor_definition, app=app)
  tutors = tutors[!vapply(tutors, is.null, logical(1))]
  tutors[order(vapply(tutors, function(tutor) tutor$label, character(1)))]
}


ullme_student_select_context = function(tutorid=app$tutorid,
                                         instanceid=app$instanceid,
                                         app=getApp()) {
  restore.point("ullme_student_select_context")
  course_dir = ullme_student_course_dir(app=app)
  if (is.null(course_dir)) {
    stop(
      "Course ", app$courseid, " was not found for teacher ",
      app$teacherid, " in semester ", app$semester, ".",
      call.=FALSE
    )
  }
  tutors = ullme_student_tutors(app=app)
  if (length(tutors) == 0) {
    stop("This course has no enabled AI Tutors.", call.=FALSE)
  }
  tutorids = vapply(tutors, function(tutor) tutor$tutorid, character(1))
  if (is.null(tutorid) && !is.null(instanceid)) {
    compatible = vapply(tutors, function(tutor) {
      instanceid %in% vapply(
        tutor$instances,
        function(instance) paste0(instance$instanceid %||% "")[1],
        character(1)
      )
    }, logical(1))
    if (any(compatible)) tutorid = tutorids[[which(compatible)[[1]]]]
  }
  if (is.null(tutorid)) tutorid = tutorids[[1]]
  if (!tutorid %in% tutorids) {
    stop("AI Tutor '", tutorid, "' is not available in this course.", call.=FALSE)
  }
  tutor = tutors[[match(tutorid, tutorids)]]
  if (!isTRUE(tutor$multiple_instances)) instanceid = NULL
  instanceids = vapply(
    tutor$instances,
    function(instance) paste0(instance$instanceid %||% "")[1],
    character(1)
  )
  instanceids = instanceids[nzchar(instanceids)]
  if (isTRUE(tutor$multiple_instances) &&
      is.null(instanceid) && length(instanceids)) {
    instanceid = instanceids[[1]]
  }
  if (!is.null(instanceid) && !instanceid %in% instanceids) {
    stop(
      "Tutor instance '", instanceid, "' is not available for AI Tutor '",
      tutorid, "'.",
      call.=FALSE
    )
  }
  app$tutorid = tutorid
  app$instanceid = instanceid
  app$student_tutors = tutors
  invisible(tutor)
}


ullme_student_context_for_js = function(error="", app=getApp()) {
  restore.point("ullme_student_context_for_js")
  tutors = app$student_tutors %||% list()
  list(
    teacherid=app$teacherid %||% "",
    courseid=app$courseid %||% "",
    semester=app$semester %||% "",
    semesters=as.list(ullme_student_available_semesters(app=app)),
    tutorid=app$tutorid %||% "",
    instanceid=app$instanceid %||% "",
    allow_semester_switch=isTRUE(app$allow_semester_switch),
    allow_tutor_switch=isTRUE(app$allow_tutor_switch),
    allow_instance_switch=isTRUE(app$allow_instance_switch),
    tutors=lapply(tutors, function(tutor) {
      shown_text = ullme_student_shown_text(
        tutor=tutor,
        instanceid=if (identical(tutor$tutorid, app$tutorid)) {
          app$instanceid
        } else {
          NULL
        },
        app=app
      )
      list(
        tutorid=tutor$tutorid,
        label=tutor$label,
        description=tutor$description,
        shown_text=shown_text,
        shown_html=ullme_chat_output_html(
          shown_text,
          app=app
        ),
        multiple_instances=isTRUE(tutor$multiple_instances),
        chat_history=isTRUE(tutor$chat_history),
        instances=lapply(tutor$instances, function(instance) {
          list(
            instanceid=instance$instanceid,
            label=instance$label %||% instance$instanceid
          )
        })
      )
    }),
    chat_history=ullme_student_chat_history_state(app=app),
    error=paste0(error %||% "")[1]
  )
}


ullme_send_student_context = function(error="", app=getApp()) {
  restore.point("ullme_send_student_context")
  callJS(
    .fun="window.ullme.updateStudentContext",
    .args=list(ullme_student_context_for_js(error=error, app=app)),
    .app=app
  )
  invisible(TRUE)
}


ullme_init_student_app = function(session, app=getApp()) {
  restore.point("ullme_init_student_app")
  result = tryCatch({
    ullme_student_resolve_parameters(session=session, app=app)
    ullme_student_select_context(app=app)
    ullme_student_chat_history_init(app=app)
    list(ok=TRUE, error="")
  }, error=function(e) {
    list(ok=FALSE, error=conditionMessage(e))
  })
  ullme_send_student_context(error=result$error, app=app)
  invisible(result)
}


ullme_handle_student_context = function(semester=NULL, tutorid=NULL,
                                         instanceid=NULL,
                                         app=getApp(), ...) {
  restore.point("ullme_handle_student_context")
  old_semester = app$semester
  old_tutorid = app$tutorid
  old_instanceid = app$instanceid
  result = tryCatch({
    semester = ullme_optional_app_parameter(
      semester, ullme_clean_semester_parameter, "semester"
    )
    tutorid = ullme_optional_app_parameter(
      tutorid, ullme_clean_definition_id, "tutorid"
    )
    instanceid = ullme_optional_app_parameter(
      instanceid, ullme_clean_tutor_instance_id, "instanceid"
    )
    if (!is.null(semester)) app$semester = semester
    semester_changed = !identical(app$semester, old_semester)
    if (isTRUE(semester_changed) && is.null(tutorid)) {
      app$tutorid = NULL
      app$instanceid = NULL
    }
    if ((!identical(tutorid, old_tutorid) || isTRUE(semester_changed)) &&
        isTRUE(app$allow_instance_switch)) {
      instanceid = NULL
    }
    ullme_student_select_context(
      tutorid=tutorid,
      instanceid=instanceid,
      app=app
    )
    context_changed =
      !identical(app$semester, old_semester) ||
      !identical(app$tutorid, old_tutorid) ||
      !identical(app$instanceid, old_instanceid)
    if (isTRUE(context_changed)) {
      ullme_student_session_stats_init(app=app)
    }
    if (!identical(app$semester, old_semester) ||
        !identical(app$tutorid, old_tutorid)) {
      ullme_student_chat_history_init(app=app)
    }
    ""
  }, error=function(e) {
    app$semester = old_semester
    app$tutorid = old_tutorid
    app$instanceid = old_instanceid
    conditionMessage(e)
  })
  ullme_send_student_context(error=result, app=app)
  invisible(!nzchar(result))
}


ullme_student_selected_tutor = function(app=getApp()) {
  restore.point("ullme_student_selected_tutor")
  tutors = app$student_tutors %||% ullme_student_tutors(app=app)
  matches = vapply(tutors, function(tutor) {
    identical(tutor$tutorid, app$tutorid)
  }, logical(1))
  if (!any(matches)) return(NULL)
  tutors[[which(matches)[[1]]]]
}


ullme_student_document_text = function(paths, course_dir,
                                        missing="[content missing]") {
  restore.point("ullme_student_document_text")
  paths = ullme_tutor_document_paths(paths)
  if (length(paths) == 0) return(missing)
  text = vapply(paths, function(path) {
    if (!ullme_safe_relative_material_path(path)) return("")
    target = file.path(course_dir, "materials", path)
    extension = tolower(tools::file_ext(target))
    if (!file.exists(target)) return("")
    if (!extension %in% c("md", "txt", "tex", "csv", "json", "yaml", "yml")) {
      return(paste0("[Document available as ", path, "]"))
    }
    content = paste(readLines(
      target, warn=FALSE, encoding="UTF-8"
    ), collapse="\n")
    paste0("### ", path, "\n\n", content)
  }, character(1))
  text = paste(text[nzchar(text)], collapse="\n\n")
  if (nzchar(text)) text else missing
}


ullme_student_tutor_values = function(tutor=ullme_student_selected_tutor(app),
                                       instanceid=app$instanceid,
                                       app=getApp()) {
  restore.point("ullme_student_tutor_values")
  if (is.null(tutor)) return(list())
  course_dir = ullme_student_course_dir(app=app)
  instances = tutor$instances %||% list()
  selected = instances[vapply(instances, function(instance) {
    identical(paste0(instance$instanceid %||% "")[1], instanceid %||% "")
  }, logical(1))]
  instance_docs = if (length(selected)) selected[[1]]$docs else list()
  placeholder_documents = ullme_normalize_tutor_placeholder_documents(
    setNames(
      lapply(tutor$placeholder_documents %||% list(), function(document) {
        document$path
      }),
      vapply(
        tutor$placeholder_documents %||% list(),
        function(document) document$placeholder,
        character(1)
      )
    )
  )
  docids = unique(c(
    paste0(unlist(
      tutor$placeholder_document_ids %||% list(),
      use.names=FALSE
    )),
    paste0(unlist(tutor$doc_ids_per_course %||% list(), use.names=FALSE)),
    paste0(unlist(tutor$doc_ids_per_instance %||% list(), use.names=FALSE)),
    names(tutor$course_docs %||% list()),
    names(instance_docs %||% list())
  ))
  docids = docids[nzchar(docids)]
  values = lapply(docids, function(docid) {
    placeholder_path = placeholder_documents[[docid]]$path %||% ""
    if (nzchar(placeholder_path)) {
      return(ullme_student_document_text(
        placeholder_path,
        course_dir=course_dir,
        missing="[content missing]"
      ))
    }
    ullme_student_document_text(
      c(
        tutor$course_docs[[docid]] %||% list(),
        instance_docs[[docid]] %||% list()
      ),
      course_dir=course_dir,
      missing=""
    )
  })
  names(values) = docids
  values$personality = tutor$default_personality %||% ""
  customization_ids = paste0(unlist(
    tutor$allowed_student_customization %||% list(),
    use.names=FALSE
  ))
  for (customization_id in customization_ids[nzchar(customization_ids)]) {
    if (is.null(values[[customization_id]])) {
      values[[customization_id]] = ""
    }
  }
  values
}


ullme_student_shown_text = function(tutor=ullme_student_selected_tutor(app),
                                     instanceid=app$instanceid,
                                     app=getApp()) {
  restore.point("ullme_student_shown_text")
  if (is.null(tutor)) return("")
  ullme_render_prompt(
    text=tutor$shown_text %||% "",
    values=ullme_student_tutor_values(
      tutor=tutor,
      instanceid=instanceid,
      app=app
    ),
    strict=FALSE
  )
}


ullme_student_system_prompt = function(app=getApp()) {
  restore.point("ullme_student_system_prompt")
  tutor = ullme_student_selected_tutor(app=app)
  if (is.null(tutor)) stop("No AI Tutor is selected.")
  prompt = ullme_render_ai_tutor_system_prompt(
    definition=tutor,
    documents=ullme_student_tutor_values(tutor=tutor, app=app),
    customization=list()
  )
  transcript = ullme_student_chat_history_transcript(app=app)
  if (nzchar(transcript)) paste(prompt, transcript, sep="\n\n") else prompt
}


ullme_student_chat = function(model=NULL, app=getApp()) {
  model = ullme_model_id(model, app=app)
  prompt = ullme_student_system_prompt(app=app)
  key = ullme_chat_key(model, task_profile="student_tutor", app=app)
  chat = app$teacher_chats[[key]]
  if (is.null(chat)) {
    chat = ullme_api_chat(
      app$api_config,
      model=model,
      system_prompt=prompt,
      task_profile="student_tutor"
    )
    if (!is.null(chat)) {
      tool_names = paste0(unlist(
        ullme_student_selected_tutor(app=app)$allowed_tools %||% list(),
        use.names=FALSE
      ))
      tool_names = intersect(tool_names, names(ullme_student_tool_registry()))
      if (length(tool_names)) {
        tools = lapply(tool_names, ullme_student_tool, app=app)
        names(tools) = tool_names
        chat$register_tools(tools)
        chat$on_tool_request(function(request) {
          ullme_handle_tool_lifecycle_event("request", request, app=app)
        })
        chat$on_tool_result(function(result) {
          ullme_handle_tool_lifecycle_event("result", result, app=app)
        })
      }
    }
    app$teacher_chats[[key]] = chat
  } else {
    chat$set_system_prompt(prompt)
  }
  chat
}


ullme_student_context_controls_ui = function(app=getApp()) {
  restore.point("ullme_student_context_controls_ui")
  tags$div(
    class="ullme-context-controls ullme-student-context-summary",
    if (!isTRUE(app$never_save_chats)) {
      tags$button(
        id="ullme_student_history_open_btn",
        class="ullme-icon-button ullme-student-history-open-button",
        type="button",
        `aria-label`="Open chat history",
        title="Open chat history",
        style="display: none;",
        HTML('<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h16v16H4z"></path><path d="M9 4v16"></path><path d="M13 9l3 3-3 3"></path></svg>')
      )
    },
    tags$span(
      id="ullme_student_course_summary",
      class="ullme-student-course-summary",
      app$courseid %||% "Course"
    ),
    tags$div(
      class="ullme-student-header-select-wrap",
      tags$span(
        id="ullme_student_semester_text",
        class="ullme-student-header-text",
        app$semester %||% "Semester"
      ),
      tags$select(
        id="ullme_student_semester_select",
        class="ullme-student-header-select",
        style="display: none;"
      )
    ),
    tags$div(
      class="ullme-student-header-select-wrap",
      tags$span(id="ullme_student_tutor_text", class="ullme-student-header-text", "Loading..."),
      tags$select(
        id="ullme_student_tutor_select",
        class="ullme-student-header-select",
        style="display: none;"
      )
    ),
    tags$div(
      class="ullme-student-header-select-wrap",
      tags$span(id="ullme_student_instance_text", class="ullme-student-header-text", "Loading..."),
      tags$select(
        id="ullme_student_instance_select",
        class="ullme-student-header-select",
        style="display: none;"
      )
    ),
    tags$button(
      id="ullme_student_new_chat_btn",
      class="ullme-icon-button ullme-new-chat-btn",
      type="button",
      `aria-label`="New Chat",
      title="New Chat",
      HTML('<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path><path d="M9 10h6"></path><path d="M12 7v6"></path></svg>')
    ),
    tags$span(
      id="ullme_student_context_error",
      class="ullme-student-context-error",
      role="alert"
    )
  )
}


ullme_student_sidebar_ui = function(app=getApp()) {
  restore.point("ullme_student_sidebar_ui")
  if (isTRUE(app$never_save_chats)) return(NULL)
  tags$aside(
    id="ullme_student_chat_history",
    class="ullme-student-chat-history",
    `aria-label`="Chat history",
    tags$div(
      class="ullme-student-chat-history-head",
      tags$span("Chats"),
      tags$div(
        class="ullme-student-chat-history-actions",
        tags$button(
          id="ullme_student_history_new_btn",
          class="ullme-icon-button",
          type="button",
          `aria-label`="New chat",
          title="New chat",
          HTML('<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14"></path><path d="M5 12h14"></path></svg>')
        ),
        tags$button(
          id="ullme_student_history_close_btn",
          class="ullme-icon-button",
          type="button",
          `aria-label`="Close chat history",
          title="Close chat history",
          HTML('<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h16v16H4z"></path><path d="M9 4v16"></path><path d="M16 9l-3 3 3 3"></path></svg>')
        )
      )
    ),
    tags$nav(
      id="ullme_student_chat_history_recent",
      class="ullme-student-chat-history-list",
      `aria-label`="Recent chats"
    ),
    tags$details(
      id="ullme_student_chat_history_more",
      class="ullme-student-chat-history-more",
      tags$summary("More"),
      tags$nav(
        id="ullme_student_chat_history_older",
        class="ullme-student-chat-history-list",
        `aria-label`="Older chats"
      )
    )
  )
}


ullme_student_workspace_ui = function(app=getApp()) {
  restore.point("ullme_student_workspace_ui")
  tags$div(
    class="ullme-workspace ullme-student-workspace",
    ullme_student_sidebar_ui(app=app),
    ullme_chat_pane_ui(app=app, show_header=FALSE)
  )
}

ullme_handle_student_chat_clear = function(app=getApp(), ...) {
  restore.point("ullme_handle_student_chat_clear")
  ullme_student_session_stats_init(app=app)
  model = ullme_model_id(NULL, app=app)
  key = ullme_chat_key(model, task_profile="student_tutor", app=app)
  app$teacher_chats[[key]] = NULL
  if (ullme_student_chat_history_enabled(app=app)) {
    ullme_student_chat_history_new(app=app)
    ullme_send_student_chat_history(app=app)
  }
  invisible(TRUE)
}
