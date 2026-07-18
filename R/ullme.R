

ullme_main_dir = function(app=getApp()) {
  main_dir = app$glob$main_dir
  if (is.null(main_dir)) {
    main_dir ="C:/libraries/ullme/ullme_main"
  }
  if (!dir.exists(main_dir)) {
    stop(paste0("main_dir = ", main_dir, " does not exist."))
  }
  main_dir
}

ullme_user_role = function(app=getApp()) {
  app$role
}

ullme_user_allowed_roles = function(app=getApp()) {
  app$allowed_roles
}


ullme_userid = function(app=getApp()) {
  app$userid
}

ullme_teacherid = function(app=getApp()) {
  app$teacherid
}


.ullme_app = function(main_dir, userid="skranz",
                      role=c("teacher", "student"), teacherid=NULL,
                      courseid=NULL, semester=NULL, tutorid=NULL,
                      instanceid=NULL,
                      uses_fake_ai=NULL, max_upload_mb=100,
                      api_key_file=NULL,
                      api_provider=c("fake", "nvidia", "local"),
                      api_model=NULL, api_base_url=NULL,
                      render_chat_markdown=TRUE,
                      catch_chat_errors=TRUE,
                      chat_debug=FALSE,
                      enable_ai_tools=TRUE,
                      instance_builder_retries=1L,
                      show_chat_thinking=FALSE,
                      store_ai_interactions=TRUE,
                      never_save_chats=TRUE,
                      base_url_student="",
                      login_check=c("none", "sel"),
                      login_args=list(),
                      email2userid=ullme_email2userid,
                      adapt_mathjax=TRUE) {
  restore.point(".ullme_app")
  app = eventsApp()
  glob = app$glob
  # shinyEvents calls this shared environment `glob`; expose the clearer
  # `global` alias used by the app constructors as well.
  app$global = glob

  role = match.arg(role)
  login_check = ullme_login_check(login_check)
  if (!is.list(login_args)) stop("login_args must be a list.")
  if (!is.function(email2userid)) {
    stop("email2userid must be a function.", call.=FALSE)
  }
  api_provider = match.arg(api_provider)
  if (!is.null(uses_fake_ai)) {
    if (isTRUE(uses_fake_ai)) {
      api_provider = "fake"
    } else if (identical(api_provider, "fake")) {
      api_provider = "local"
    }
  }
  app$api_config = ullme_api_config(
    api_provider=api_provider,
    api_key_file=api_key_file,
    api_model=api_model,
    api_base_url=api_base_url
  )

  max_upload_mb = as.numeric(max_upload_mb)[1]
  if (is.na(max_upload_mb) || max_upload_mb <= 0) {
    stop("max_upload_mb must be a positive number.")
  }
  if (!is.logical(render_chat_markdown) ||
      length(render_chat_markdown) != 1L ||
      is.na(render_chat_markdown)) {
    stop("render_chat_markdown must be TRUE or FALSE.")
  }
  if (!is.logical(adapt_mathjax) ||
      length(adapt_mathjax) != 1L ||
      is.na(adapt_mathjax)) {
    stop("adapt_mathjax must be TRUE or FALSE.")
  }
  if (!is.logical(catch_chat_errors) ||
      length(catch_chat_errors) != 1L ||
      is.na(catch_chat_errors)) {
    stop("catch_chat_errors must be TRUE or FALSE.")
  }
  if (!is.logical(chat_debug) ||
      length(chat_debug) != 1L ||
      is.na(chat_debug)) {
    stop("chat_debug must be TRUE or FALSE.")
  }
  if (!is.logical(enable_ai_tools) ||
      length(enable_ai_tools) != 1L ||
      is.na(enable_ai_tools)) {
    stop("enable_ai_tools must be TRUE or FALSE.")
  }
  retry_value = suppressWarnings(as.numeric(instance_builder_retries)[1])
  if (length(instance_builder_retries) != 1L || is.na(retry_value) ||
      !is.finite(retry_value) || retry_value < 0 ||
      retry_value != floor(retry_value)) {
    stop("instance_builder_retries must be a non-negative integer.")
  }
  instance_builder_retries = as.integer(retry_value)
  if (!is.logical(show_chat_thinking) ||
      length(show_chat_thinking) != 1L ||
      is.na(show_chat_thinking)) {
    stop("show_chat_thinking must be TRUE or FALSE.")
  }
  if (!is.logical(store_ai_interactions) ||
      length(store_ai_interactions) != 1L ||
      is.na(store_ai_interactions)) {
    stop("store_ai_interactions must be TRUE or FALSE.")
  }
  if (!is.logical(never_save_chats) ||
      length(never_save_chats) != 1L ||
      is.na(never_save_chats)) {
    stop("never_save_chats must be TRUE or FALSE.")
  }
  # Shiny's upload limit is process-wide, even though upload state is per app.
  current_upload_limit = getOption("shiny.maxRequestSize", 5 * 1024^2)
  options(shiny.maxRequestSize=max(current_upload_limit, max_upload_mb * 1024^2))

  # app is per Shiny app instance; app$glob is shared across all instances.
  # Store only truly shared values in glob and keep user-specific state on app.
  glob$main_dir = main_dir
  glob$userid = if (identical(login_check, "sel")) {
    "login_pending"
  } else {
    ullme_clean_user_name(userid)
  }
  glob$teacherid = if (identical(login_check, "sel") &&
                       identical(role, "teacher")) {
    NULL
  } else {
    ullme_optional_app_parameter(
      teacherid, ullme_clean_user_name, "teacherid"
    )
  }
  glob$courseid = ullme_optional_app_parameter(
    courseid, ullme_clean_courseid, "courseid"
  )
  glob$semester = ullme_optional_app_parameter(
    semester,
    function(value) {
      value = toupper(paste0(value)[1])
      ullme_semester_index(value)
      value
    },
    "semester"
  )
  glob$tutorid = ullme_optional_app_parameter(
    tutorid, ullme_clean_definition_id, "tutorid"
  )
  glob$instanceid = ullme_optional_app_parameter(
    instanceid, ullme_clean_tutor_instance_id, "instanceid"
  )
  app$userid = glob$userid
  app$teacherid = if (identical(role, "teacher")) {
    if (identical(login_check, "sel")) "login_pending" else glob$teacherid
  } else {
    glob$teacherid
  }
  app$courseid = glob$courseid
  app$semester = glob$semester %||% ullme_semester()
  app$tutorid = glob$tutorid
  app$instanceid = glob$instanceid
  app$role = role
  app$app_kind = role
  app$allowed_roles = role
  app$login_check = login_check
  app$login_args = login_args
  app$email2userid = email2userid
  app$login_email = NULL
  app$studentid = NULL
  app$is.authenticated = identical(login_check, "none")
  app$uses_fake_ai = identical(app$api_config$provider, "fake")
  app$render_chat_markdown = isTRUE(render_chat_markdown)
  app$adapt_mathjax = isTRUE(adapt_mathjax)
  app$catch_chat_errors = isTRUE(catch_chat_errors)
  app$chat_debug = isTRUE(chat_debug)
  app$enable_ai_tools = isTRUE(enable_ai_tools)
  app$instance_builder_retries = instance_builder_retries
  app$show_chat_thinking = isTRUE(show_chat_thinking)
  app$store_ai_interactions = isTRUE(store_ai_interactions)
  app$never_save_chats =
    identical(role, "student") && isTRUE(never_save_chats)
  app$chat_response_active = FALSE
  app$chat_tasks = list()
  app$chat_requests = list()
  app$active_chat_request = NULL
  app$chat_timeout_seconds = 180
  app$chat_connect_timeout_seconds = 60
  app$tutor_workflow_timeout_seconds = 600
  app$api_models = app$api_config$model
  app$api_models_error = NULL
  app$base_url_student = ullme_normalize_base_url(base_url_student)
  ullme_set_app_user_paths(app=app)
  app$pending_changes = list()
  app$change_results = list()
  app$change_waiters = list()
  if (identical(role, "teacher")) {
    if (identical(login_check, "sel")) {
      app$courseids = character()
    } else {
      app$courseids = ullme_user_courseids(
        main_dir=main_dir,
        userid=app$teacherid,
        role=app$role,
        semester=app$semester
      )
      app$courseid = ullme_selected_courseid(
        app$courseids,
        preferred=app$courseid
      )
    }
  } else {
    app$courseids = if (is.null(app$courseid)) character(0) else app$courseid
  }
  app$material_category = "root"
  app$material_upload_directory = ""
  app$material_upload_tree = NULL

  if (identical(login_check, "sel")) {
    app$login_args = ullme_validate_sel_login_args(login_args)
    if (identical(role, "teacher")) {
      app$teachers = ullme_allowed_teachers(main_dir)
    }
    app$login_module = ullme_make_login_module(app=app)
    app$ui = ullme_login_shell_ui()
  } else {
    ullme_add_resource_paths(app=app)
    app$ui = ullme_app_ui(app=app)
  }
  ullme_register_handlers(app=app)

  appInitHandler(function(session, app, ...) {
    restore.point("ullme_init")
    if (identical(app$login_check, "sel")) {
      ullme_init_login(app=app)
    } else {
      ullme_init_app(session=session, app=app)
    }
  })
  app
}


ullme_add_resource_paths = function(app=getApp()) {
  restore.point("ullme_add_resource_paths")
  if (isTRUE(app$resource_paths_registered)) return(invisible(TRUE))
  www_dir = ullme_www_dir()
  dir.create(app$uploads_dir, recursive=TRUE, showWarnings=FALSE)
  dir.create(app$audio_dir, recursive=TRUE, showWarnings=FALSE)

  existing = shiny::resourcePaths()
  add_path = function(prefix, directory) {
    # Don't make these checks throws error if add is started
    # multiple times

    # if (prefix %in% names(existing)) {
    #   existing_path = normalizePath(
    #     existing[[prefix]],
    #     winslash="/",
    #     mustWork=FALSE
    #   )
    #   requested_path = normalizePath(
    #     directory,
    #     winslash="/",
    #     mustWork=FALSE
    #   )
    #
    #   #if (!identical(existing_path, requested_path)) {
    #   #  stop("The resource prefix ", prefix, " is already in use.")
    #   #}
    #   return(invisible(FALSE))
    # }
    shiny::addResourcePath(prefix=prefix, directoryPath=directory)
    existing[[prefix]] <<- directory
    invisible(TRUE)
  }
  add_path("ullme", www_dir)
  add_path(app$uploads_resource_prefix, app$uploads_dir)
  add_path(app$audio_resource_prefix, app$audio_dir)
  app$resource_paths_registered = TRUE
  if (identical(app$login_check, "sel") &&
      !is.null(app$session) &&
      is.function(app$session$onSessionEnded)) {
    prefixes = c(
      app$uploads_resource_prefix,
      app$audio_resource_prefix
    )
    app$session$onSessionEnded(function() {
      for (prefix in prefixes) {
        try(shiny::removeResourcePath(prefix), silent=TRUE)
      }
    })
  }
  invisible(TRUE)
}


ullme_www_dir = function() {
  restore.point("ullme_www_dir")
  www_dir = system.file("www", package="ullme")
  if (nzchar(www_dir)) return(www_dir)

  src_dir = file.path(getwd(), "inst", "www")
  if (dir.exists(src_dir)) return(normalizePath(src_dir, winslash="/"))

  stop("Cannot find ullme www assets.")
}


ullme_init_storage = function(main_dir, app=getApp()) {
  restore.point("ullme_init_storage")
  dir.create(main_dir, recursive=TRUE, showWarnings=FALSE)
  dir.create(app$cur_session_dir, recursive=TRUE, showWarnings=FALSE)
  dir.create(app$uploads_dir, recursive=TRUE, showWarnings=FALSE)
  dir.create(app$audio_dir, recursive=TRUE, showWarnings=FALSE)
  ullme_init_teacher_info(main_dir=main_dir)
  ullme_init_user_dirs(app=app)
  invisible(TRUE)
}


ullme_register_handlers = function(app=getApp()) {
  restore.point("ullme_register_handlers")
  eventHandler(
    eventId = "ullme_submit_chat_event",
    id = NULL,
    fun = ullme_handle_chat_submit_safe,
    app = app
  )
  changeHandler(
    id = "ullme_image_upload",
    fun = ullme_handle_image_upload,
    app = app
  )
  if (identical(app$role, "student")) {
    changeHandler(
      id = "ullme_camera_upload",
      fun = ullme_handle_image_upload,
      app = app
    )
    eventHandler(
      eventId="ullme_cancel_chat_event",
      id=NULL,
      fun=ullme_handle_chat_cancel,
      app=app
    )
    eventHandler(
      eventId="ullme_student_context_event",
      id=NULL,
      fun=ullme_handle_student_context,
      app=app
    )
    eventHandler(
      eventId="ullme_student_chat_clear_event",
      id=NULL,
      fun=ullme_handle_student_chat_clear,
      app=app
    )
    eventHandler(
      eventId="ullme_student_chat_history_event",
      id=NULL,
      fun=ullme_handle_student_chat_history,
      app=app
    )
    ullme_register_audio_handlers(app=app)
    return(invisible(TRUE))
  }
  lapply(c("root", ullme_course_material_categories()), function(category) {
    changeHandler(
      id = paste0("ullme_material_upload_", category),
      fun = ullme_handle_material_upload,
      app = app
    )
  })
  eventHandler(
    eventId = "ullme_semester_select_event",
    id = NULL,
    fun = ullme_handle_semester_select,
    app = app
  )
  eventHandler(
    eventId = "ullme_course_select_event",
    id = NULL,
    fun = ullme_handle_course_select,
    app = app
  )
  eventHandler(
    eventId = "ullme_add_course_event",
    id = NULL,
    fun = ullme_handle_add_course,
    app = app
  )
  eventHandler(
    eventId = "ullme_course_settings_save_event",
    id = NULL,
    fun = ullme_handle_course_settings_save,
    app = app
  )
  eventHandler(
    eventId = "ullme_allowed_users_save_event",
    id = NULL,
    fun = ullme_handle_allowed_users_save,
    app = app
  )
  eventHandler(
    eventId = "ullme_teacher_select_event",
    id = NULL,
    fun = ullme_handle_teacher_select,
    app = app
  )
  eventHandler(
    eventId = "ullme_usage_statistics_refresh_event",
    id = NULL,
    fun = ullme_handle_usage_statistics_refresh,
    app = app
  )
  eventHandler(
    eventId = "ullme_material_category_event",
    id = NULL,
    fun = ullme_handle_material_category,
    app = app
  )
  eventHandler(
    eventId = "ullme_material_upload_destination_event",
    id = NULL,
    fun = ullme_handle_material_upload_destination,
    app = app
  )
  eventHandler(
    eventId = "ullme_material_delete_event",
    id = NULL,
    fun = ullme_handle_material_delete,
    app = app
  )
  eventHandler(
    eventId = "ullme_material_operation_event",
    id = NULL,
    fun = ullme_handle_material_operation,
    app = app
  )
  eventHandler(
    eventId = "ullme_material_convert_event",
    id = NULL,
    fun = ullme_handle_material_convert,
    app = app
  )
  eventHandler(
    eventId = "ullme_material_create_directory_event",
    id = NULL,
    fun = ullme_handle_material_create_directory,
    app = app
  )
  eventHandler(
    eventId = "ullme_ai_tutor_add_event",
    id = NULL,
    fun = ullme_handle_ai_tutor_add,
    app = app
  )
  eventHandler(
    eventId = "ullme_ai_tutor_delete_event",
    id = NULL,
    fun = ullme_handle_ai_tutor_delete,
    app = app
  )
  eventHandler(
    eventId = "ullme_ai_tutor_toggle_event",
    id = NULL,
    fun = ullme_handle_ai_tutor_toggle,
    app = app
  )
  eventHandler(
    eventId = "ullme_cancel_chat_event",
    id = NULL,
    fun = ullme_handle_chat_cancel,
    app = app
  )
  eventHandler(
    eventId = "ullme_ai_tutor_save_event",
    id = NULL,
    fun = ullme_handle_ai_tutor_save,
    app = app
  )
  eventHandler(
    eventId = "ullme_ai_tutor_node_event",
    id = NULL,
    fun = ullme_handle_ai_tutor_node,
    app = app
  )
  eventHandler(
    eventId = "ullme_ai_tutor_instances_save_event",
    id = NULL,
    fun = ullme_handle_ai_tutor_instances_save,
    app = app
  )
  eventHandler(
    eventId = "ullme_ai_tutor_instances_yaml_save_event",
    id = NULL,
    fun = ullme_handle_ai_tutor_instances_yaml_save,
    app = app
  )
  eventHandler(
    eventId = "ullme_ai_tutor_convert_event",
    id = NULL,
    fun = ullme_handle_ai_tutor_convert,
    app = app
  )
  eventHandler(
    eventId = "ullme_change_approval_event",
    id = NULL,
    fun = ullme_handle_change_approval,
    app = app
  )
  eventHandler(
    eventId = "ullme_edit_history_event",
    id = NULL,
    fun = ullme_handle_edit_history,
    app = app
  )
  eventHandler(
    eventId = "ullme_course_file_open_event",
    id = NULL,
    fun = ullme_handle_course_file_open,
    app = app
  )
  eventHandler(
    eventId = "ullme_course_file_save_event",
    id = NULL,
    fun = ullme_handle_course_file_save,
    app = app
  )
  ullme_register_audio_handlers(app=app)
  invisible(TRUE)
}


ullme_app_ui = function(app=getApp()) {
  restore.point("ullme_app_ui")
  is_teacher = identical(app$app_kind, "teacher")
  tagList(
  tags$head(
      tags$meta(name="viewport", content="width=device-width, initial-scale=1"),
      if (!is_teacher) tags$script(HTML(
        "try{var t=localStorage.getItem('ullme-color-theme')||'system';var d=t==='dark'||(t==='system'&&window.matchMedia('(prefers-color-scheme: dark)').matches);document.documentElement.dataset.ullmeTheme=d?'dark':'light';document.documentElement.style.colorScheme=d?'dark':'light'}catch(e){}"
      )),
      tags$link(
        rel="stylesheet",
        type="text/css",
        href=if (is_teacher) "ullme/ullme-teacher.css" else
          "ullme/ullme-student.css"
      ),
      if (is_teacher) tags$link(
        rel="stylesheet",
        type="text/css",
        href="ullme/ullme-tutor-flow.css"
      ),
      if (is_teacher) tags$link(
        rel="stylesheet",
        type="text/css",
        href="ullme/ullme-tutor-validation.css"
      ),
      if (is_teacher) tags$script(src="ullme/ullme-materials.js"),
      tags$script(src="ullme/ullme-chat.js"),
      if (is_teacher) tags$script(src="ullme/ullme-usage.js"),
      tags$script(
        src=if (is_teacher) "ullme/ullme-teacher.js" else
          "ullme/ullme-student.js"
      ),
      if (is_teacher) tags$script(src="ullme/ullme-tutor-flow.js"),
      if (is_teacher) tags$script(src="ullme/ullme-tutor-validation.js"),
      if (is_teacher) tags$script(src="ullme/ullme-tutors.js"),
      tags$script(src="ullme/ullme-audio.js"),
      tags$script(
        src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js",
        defer="defer"
      )
    ),
    tags$div(
      class = "ullme-fluid",
      tags$div(
        id = "ullme_app",
        class = paste("ullme-app", paste0("ullme-role-", app$role)),
        ullme_appbar_ui(app=app),
        tags$main(
          class = "ullme-main",
          ullme_role_workspace_ui(app=app)
        ),
        tags$input(
          id = "ullme_image_upload",
          class = "ullme-file-input",
          type = "file",
          accept = "image/*",
          multiple = "multiple"
        ),
        if (identical(app$app_kind, "student")) tags$input(
          id = "ullme_camera_upload",
          class = "ullme-file-input",
          type = "file",
          accept = "image/*",
          capture = "environment"
        ),
        if (identical(app$app_kind, "student")) tags$div(
          id = "ullme_camera_dialog",
          class = "ullme-camera-dialog",
          role = "dialog",
          `aria-modal` = "true",
          `aria-label` = "Take a photo",
          hidden = "hidden",
          tags$div(
            class = "ullme-camera-panel",
            tags$video(
              id = "ullme_camera_video",
              class = "ullme-camera-video",
              autoplay = "autoplay",
              muted = "muted",
              playsinline = "playsinline"
            ),
            tags$div(
              class = "ullme-camera-actions",
              tags$button(
                id = "ullme_camera_cancel",
                class = "ullme-camera-cancel",
                type = "button",
                "Cancel"
              ),
              tags$button(
                id = "ullme_camera_capture",
                class = "ullme-camera-capture",
                type = "button",
                `aria-label` = "Capture photo",
                HTML(ullme_icon_svg("camera")),
                tags$span("Take photo")
              )
            )
          )
        ),
        tags$input(
          id = "ullme_audio_upload",
          class = "ullme-file-input",
          type = "file",
          accept = "audio/*"
        ),
        if (identical(app$app_kind, "teacher")) tagList(
          lapply(c("root", ullme_course_material_categories()), function(category) {
            tags$input(
              id = paste0("ullme_material_upload_", category),
              class = "ullme-file-input ullme-material-file-input",
              type = "file",
              multiple = "multiple",
              `data-category` = category
            )
          })
        )
      )
    )
  )
}


ullme_role_workspace_ui = function(app=getApp()) {
  restore.point("ullme_role_workspace_ui")
  if (identical(app$app_kind, "teacher")) {
    return(ullme_teacher_workspace_ui(app=app))
  }
  ullme_student_workspace_ui(app=app)
}


ullme_chat_pane_ui = function(app=getApp(), show_header=FALSE,
                               show_help=FALSE) {
  restore.point("ullme_chat_pane_ui")
  intro = ullme_intro_msg()
  intro_html = ullme_chat_output_html(intro$text, app=app)
  chat_contents = tagList(
    tags$section(
      id = "ullme_chat_messages",
      class = "ullme-chat-messages",
      `data-intro-role` = intro$role,
      `data-intro-text` = intro$text,
      `data-intro-meta` = intro$meta,
      `data-intro-html` = intro_html,
      if (identical(app$app_kind, "student")) tags$div(
        id="ullme_student_tutor_warning",
        class="ullme-student-tutor-warning",
        role="alert"
      )
    ),
    ullme_composer_ui(app=app)
  )
  tags$section(
    class = "ullme-chat-pane",
    if (isTRUE(show_header)) tags$header(
      class="ullme-ai-pane-header",
      if (isTRUE(show_help)) tags$nav(
        class="ullme-assistant-tabs",
        role="tablist",
        `aria-label`="Right pane",
        tags$button(
          id="ullme_help_tab",
          class="ullme-assistant-tab ullme-assistant-tab-active",
          type="button",
          role="tab",
          `data-assistant-tab`="help",
          `aria-controls`="ullme_help_panel",
          `aria-selected`="true",
          "Help"
        ),
        tags$button(
          id="ullme_ai_chat_tab",
          class="ullme-assistant-tab",
          type="button",
          role="tab",
          `data-assistant-tab`="chat",
          `aria-controls`="ullme_ai_chat_panel",
          `aria-selected`="false",
          "AI chat"
        ),
        tags$button(
          id="ullme_tutor_validation_tab",
          class="ullme-assistant-tab ullme-tutor-validation-tab",
          type="button",
          role="tab",
          `data-assistant-tab`="validation",
          `aria-controls`="ullme_tutor_validation_panel",
          `aria-selected`="false",
          tabindex="-1",
          hidden="hidden",
          "Invalid Tutor"
        ),
        tags$button(
          id="ullme_node_editor_tab",
          class="ullme-assistant-tab ullme-node-editor-tab",
          type="button",
          role="tab",
          `data-assistant-tab`="node",
          `aria-controls`="ullme_node_editor_panel",
          `aria-selected`="false",
          tabindex="-1",
          hidden="hidden",
          "Node editor"
        )
      ) else tags$div(
          class="ullme-ai-pane-heading",
          tags$span(class="ullme-ai-pane-title", "AI assistant")
        ),
      tags$button(
        id="ullme_ai_pane_toggle",
        class="ullme-icon-button",
        type="button",
        `aria-label`="Collapse right pane",
        title="Collapse right pane",
        HTML(ullme_icon_svg("panel"))
      )
    ),
    if (isTRUE(show_help)) ullme_teacher_help_ui(app=app),
    if (isTRUE(show_help)) ullme_tutor_validation_ui(),
    if (isTRUE(show_help)) ullme_tutor_node_editor_ui(),
    if (isTRUE(show_help)) tags$section(
      id="ullme_ai_chat_panel",
      class="ullme-assistant-panel ullme-ai-chat-panel",
      role="tabpanel",
      `aria-labelledby`="ullme_ai_chat_tab",
      chat_contents
    ) else chat_contents
  )
}


ullme_appbar_ui = function(app=getApp()) {
  restore.point("ullme_appbar_ui")
  tags$header(
    class = "ullme-appbar",
    tags$div(
      class = "ullme-appbar-brand",
      title = "created by Sebastian Kranz (Ulm University)",
      "uLLMe"
    ),
    ullme_context_controls_ui(app=app),
    tags$div(class="ullme-appbar-spacer"),
    tags$button(
      id = "ullme_user_settings_btn",
      class = "ullme-icon-button ullme-user-settings-button",
      type = "button",
      `aria-label` = "Personal settings",
      title = "Personal settings",
      HTML(ullme_icon_svg("user"))
    ),
    tags$div(
      id = "ullme_user_settings",
      class = "ullme-user-settings",
      role = "dialog",
      `aria-label` = "Personal settings",
      tags$div(class="ullme-user-settings-title", "Personal settings"),
      tags$label(
        class = "ullme-user-settings-field",
        tags$span("Username"),
        tags$input(
          type="text",
          value=app$login_email %||% app$userid,
          readonly="readonly"
        )
      ),
      if (identical(app$app_kind, "student")) tags$label(
        class = "ullme-user-settings-field",
        tags$span("Appearance"),
        tags$select(
          id = "ullme_student_theme_select",
          tags$option(value="system", "System"),
          tags$option(value="light", "Light"),
          tags$option(value="dark", "Dark")
        )
      )
    )
  )
}


ullme_context_controls_ui = function(app=getApp()) {
  restore.point("ullme_context_controls_ui")
  if (identical(app$app_kind, "teacher")) {
    return(ullme_teacher_context_controls_ui(app=app))
  }
  ullme_student_context_controls_ui(app=app)
}


ullme_fixed_context_controls_ui = function(app, role_label,
                                            allow_add_course=FALSE) {
  semesters = ullme_semester_sequence(center=app$semester)
  tags$div(
    class = "ullme-context-controls",
    tags$div(
      class = "ullme-sidebar-context",
      tags$span(class="ullme-fixed-role", role_label),
      tags$button(
        id = "ullme_semester_select",
        class = "ullme-sidebar-value",
        type = "button",
        `data-value` = app$semester,
        `data-options` = paste(semesters, collapse="|"),
        `data-kind` = "semester",
        `aria-label` = "Semester",
        app$semester,
        tags$span(class = "ullme-sidebar-value-arrow", HTML("&#9662;"))
      ),
      tags$button(
        id = "ullme_course_select",
        class = "ullme-sidebar-value ullme-course-select",
        type = "button",
        `data-value` = app$courseid,
        `data-options` = paste(app$courseids, collapse="|"),
        `data-kind` = "course",
        `aria-label` = "Course",
        if (nzchar(app$courseid)) app$courseid else "Course",
        tags$span(class = "ullme-sidebar-value-arrow", HTML("&#9662;"))
      )
    ),
    if (isTRUE(allow_add_course)) tags$button(
        id = "ullme_add_course_btn",
        class = "ullme-icon-button ullme-add-course-button",
        type = "button",
        `aria-label` = "Add course",
        title = "Add course",
        HTML(ullme_icon_svg("plus"))
      )
  )
}


ullme_title_case = function(x) {
  restore.point("ullme_title_case")
  x = paste0(x)[1]
  if (is.na(x) || !nzchar(x)) return("")
  paste0(toupper(substr(x, 1, 1)), substr(x, 2, nchar(x)))
}


ullme_course_workspace_ui = function(app=getApp()) {
  restore.point("ullme_course_workspace_ui")
  tags$section(
    id = "ullme_course_workspace",
    class = paste("ullme-course-workspace", if (!nzchar(app$courseid)) "ullme-course-workspace-empty" else ""),
    ullme_usage_statistics_ui(app=app),
    ullme_ai_tutors_ui(app=app),
    ullme_material_ui(app=app),
    ullme_course_file_ui(app=app),
    ullme_course_settings_ui(app=app),
    ullme_allowed_users_ui(app=app)
  )
}


ullme_course_tabs_ui = function(app=getApp()) {
  restore.point("ullme_course_tabs_ui")
  active = !is.null(app$courseid) && nzchar(app$courseid)
  tags$nav(
    id = "ullme_course_tabs",
    class = paste("ullme-course-tabs", if (!active) "ullme-course-tabs-hidden" else ""),
    tags$button(class="ullme-course-tab ullme-course-tab-active", type="button", `data-course-panel`="ai-tutors", "AI Tutors"),
    tags$button(class="ullme-course-tab", type="button", `data-course-panel`="materials", "Materials"),
    tags$button(class="ullme-course-tab", type="button", `data-course-panel`="settings", "Settings"),
    tags$button(
      id = "ullme_material_upload_btn",
      class = "ullme-icon-button ullme-material-tab-upload",
      type = "button",
      `aria-label` = "Upload material",
      title = "Upload material",
      HTML(ullme_icon_svg("upload"))
    )
  )
}


ullme_studio_navigation_ui = function(app=getApp()) {
  items = list(
    list(view="usage", label="Usage", icon="analytics"),
    list(view="materials", label="Materials", icon="folder"),
    list(view="settings", label="Settings", icon="settings")
  )
  tags$nav(
    id="ullme_studio_nav",
    class="ullme-studio-nav",
    `aria-label`="Teacher workspace",
    tags$div(
      class="ullme-add-nav-wrap",
      tags$button(
        id="ullme_add_menu_btn",
        class="ullme-studio-nav-item ullme-studio-nav-add",
        type="button",
        `aria-haspopup`="menu",
        `aria-expanded`="false",
        title="Add",
        HTML(ullme_icon_svg("plus")),
        tags$span("Add")
      ),
      tags$div(
        id="ullme_add_menu",
        class="ullme-add-menu",
        role="menu",
        tags$button(
          type="button",
          role="menuitem",
          `data-add-kind`="tutors",
          HTML(ullme_icon_svg("tutor")),
          tags$span("Add Tutor")
        ),
        tags$button(
          type="button",
          role="menuitem",
          `data-add-kind`="course",
          HTML(ullme_icon_svg("plus")),
          tags$span("New Course")
        )
      )
    ),
    lapply(seq_along(items), function(i) {
      item = items[[i]]
      tagList(
        if (i == 3) tags$div(
          id="ullme_tutor_nav_items",
          class="ullme-dynamic-nav-items",
          `aria-label`="Course AI Tutors"
        ),
        tags$button(
        class=paste(
          "ullme-studio-nav-item",
          if (i == 1) "ullme-studio-nav-item-active" else ""
        ),
        type="button",
        `data-studio-view`=item$view,
        title=item$label,
        HTML(ullme_icon_svg(item$icon)),
        tags$span(item$label)
        )
      )
    }),
    tags$div(class="ullme-studio-nav-spacer"),
    tags$div(
      class="ullme-studio-settings-nav",
      tags$button(
        class="ullme-studio-nav-item",
        type="button",
        `data-studio-view`="allowed-users",
        title="Allowed users",
        HTML(ullme_icon_svg("users")),
        tags$span("Users")
      )
    )
  )
}


ullme_ai_tutors_ui = function(app=getApp()) {
  restore.point("ullme_ai_tutors_ui")
  tags$section(
    id = "ullme_ai_tutors_panel",
    class = "ullme-ai-tutors ullme-course-content-panel",
    `data-course-panel` = "ai-tutors",
    tags$div(
      class = "ullme-panel-inner ullme-ai-tutor-detail-shell",
      tags$div(
        id="ullme_ai_tutor_detail",
        class="ullme-ai-tutor-detail",
        tags$div(
          class="ullme-feature-empty",
          tags$strong("No AI Tutor selected"),
          tags$span("Use Add to create an editable course copy.")
        )
      )
    )
  )
}


ullme_course_settings_ui = function(app=getApp()) {
  restore.point("ullme_course_settings_ui")
  tags$section(
    id = "ullme_course_settings_panel",
    class = "ullme-course-settings ullme-course-content-panel",
    `data-course-panel` = "settings",
    tags$div(
      class = "ullme-panel-inner",
      tags$div(
        class="ullme-panel-head ullme-settings-panel-head",
        tags$div(class="ullme-panel-title", "Course Settings"),
        tags$div(
          class="ullme-edit-history-controls",
          `data-edit-history-scope`="course_settings",
          tags$button(
            class="ullme-icon-button ullme-edit-history-button",
            type="button",
            `data-edit-history-direction`="undo",
            `aria-label`="Undo course settings change",
            title="Undo",
            disabled="disabled",
            HTML(ullme_icon_svg("undo"))
          ),
          tags$button(
            class="ullme-icon-button ullme-edit-history-button",
            type="button",
            `data-edit-history-direction`="redo",
            `aria-label`="Redo course settings change",
            title="Redo",
            disabled="disabled",
            HTML(ullme_icon_svg("redo"))
          )
        )
      ),
      tags$div(
        class = "ullme-settings-grid",
        tags$label(
          class = "ullme-field",
          tags$span("Course ID"),
          tags$input(id="ullme_settings_courseid", type="text", readonly="readonly")
        ),
        tags$label(
          class = "ullme-field",
          tags$span("Course name"),
          tags$input(id="ullme_settings_coursename", type="text")
        )
      ),
      tags$button(
        id = "ullme_course_settings_save",
        class = "ullme-primary-action",
        type = "button",
        "Save"
      ),
      tags$div(
        class="ullme-student-url-settings",
        tags$label(
          class="ullme-field",
          tags$span("Student app base URL"),
          tags$input(
            id="ullme_settings_student_base_url",
            type="text",
            readonly="readonly"
          )
        ),
        tags$label(
          class="ullme-field",
          tags$span("Tutor and instance URLs"),
          tags$textarea(
            id="ullme_settings_student_urls",
            readonly="readonly",
            rows="8"
          )
        )
      )
    )
  )
}


ullme_allowed_users_ui = function(app=getApp()) {
  restore.point("ullme_allowed_users_ui")
  tags$section(
    id = "ullme_allowed_users_panel",
    class = "ullme-allowed-users ullme-course-content-panel",
    `data-course-panel` = "allowed-users",
    tags$div(
      class = "ullme-panel-inner",
      tags$div(
        class="ullme-panel-head ullme-settings-panel-head",
        tags$div(
          class="ullme-panel-title",
          tags$span("Allowed Users"),
          tags$small(
            id="ullme_allowed_users_teacher",
            class="ullme-panel-subtitle"
          )
        )
      ),
      tags$div(
        id="ullme_allowed_users_notice",
        class="ullme-settings-note"
      ),
      tags$div(
        class="ullme-allowed-users-table-wrap",
        tags$table(
          tags$thead(
            tags$tr(
              tags$th("Email or userid"),
              tags$th("Userid"),
              tags$th("Can edit users"),
              tags$th("")
            )
          ),
          tags$tbody(id="ullme_allowed_user_rows")
        )
      ),
      tags$div(
        class="ullme-tutor-form-actions ullme-allowed-users-actions",
        tags$button(
          id="ullme_allowed_users_add",
          class="ullme-secondary-action",
          type="button",
          "Add user"
        ),
        tags$button(
          id="ullme_allowed_users_save",
          class="ullme-primary-action",
          type="button",
          "Save users"
        )
      )
    )
  )
}


ullme_material_ui = function(app=getApp()) {
  restore.point("ullme_material_ui")
  tags$section(
    id = "ullme_material_panel",
    class = "ullme-material ullme-course-content-panel",
    `data-course-panel` = "materials",
    tags$div(
      class = "ullme-panel-inner",
      tags$div(
        class="ullme-material-view-toggle",
        tags$button(
          class="ullme-material-view-button ullme-material-view-button-active",
          type="button",
          `data-material-view`="materials",
          "Material folders"
        ),
        tags$button(
          class="ullme-material-view-button",
          type="button",
          `data-material-view`="files",
          "All course files"
        )
      ),
      tags$div(
        id="ullme_material_folder_view",
        class="ullme-material-folder-view",
        tags$div(
          class="ullme-material-toolbar",
          tags$button(
            id="ullme_material_select_all",
            class="ullme-secondary-action",
            type="button",
            "Select all"
          ),
          tags$button(
            id="ullme_material_clear_selection",
            class="ullme-secondary-action",
            type="button",
            "Clear"
          ),
          tags$span(
            id="ullme_material_selection_count",
            class="ullme-material-selection-count",
            "0 selected"
          ),
          tags$span(
            class="ullme-material-drag-hint",
            "Drag files to move \u00b7 drag across rows to select"
          ),
          tags$button(
            id="ullme_material_inline_upload",
            class="ullme-secondary-action",
            type="button",
            "Upload files"
          ),
          tags$button(
            id="ullme_material_create_directory",
            class="ullme-secondary-action ullme-material-new-folder",
            type="button",
            "New folder"
          )
        ),
        tags$div(
          id="ullme_material_upload_status",
          class="ullme-material-upload-status",
          role="status",
          `aria-live`="polite",
          tags$div(class="ullme-material-upload-track", tags$div(class="ullme-material-upload-bar")),
          tags$span(id="ullme_material_upload_status_text", "Uploading materials...")
        ),
        tags$div(
          id="ullme_material_batch_bar",
          class="ullme-material-batch-bar",
          tags$select(
            id="ullme_material_operation",
            `aria-label`="File operation",
            tags$option(value="move", "Move"),
            tags$option(value="copy", "Copy")
          ),
          tags$span("to"),
          tags$select(
            id="ullme_material_destination",
            `aria-label`="Destination folder"
          ),
          tags$button(
            id="ullme_material_apply_operation",
            class="ullme-primary-action",
            type="button",
            disabled="disabled",
            "Apply"
          ),
          tags$div(
            class="ullme-material-convert-control",
            tags$button(
              id="ullme_material_convert",
              class="ullme-secondary-action",
              type="button",
              disabled="disabled",
              `data-options`="docx-md|tex-md|all-md|pdf-txt|all-md-txt|all-overwrite",
              `data-kind`="conversion",
              `data-action-menu`="true",
              `aria-haspopup`="menu",
              `aria-expanded`="false",
              "Convert",
              tags$span(class="ullme-sidebar-value-arrow", HTML("&#9662;"))
            )
          ),
          tags$button(
            id="ullme_material_delete_selected",
            class="ullme-danger-action",
            type="button",
            disabled="disabled",
            "Delete selected"
          )
        ),
        tags$div(
          class="ullme-material-files",
          tags$div(
            class="ullme-material-tree-header",
            tags$button(
              id="ullme_material_sort_name",
              class="ullme-material-sort-heading ullme-material-sort-heading-active",
              type="button",
              `data-material-sort`="name",
              `aria-label`="Sort by name",
              tags$span("Name"),
              tags$span(class="ullme-material-sort-arrow", "\u2191")
            ),
            tags$button(
              id="ullme_material_sort_date",
              class="ullme-material-sort-heading",
              type="button",
              `data-material-sort`="date",
              `aria-label`="Sort by modification date",
              tags$span("Modified"),
              tags$span(class="ullme-material-sort-arrow", "")
            )
          ),
          tags$div(
            id="ullme_material_files",
            class="ullme-material-tree-rows",
            role="tree",
            `aria-label`="Course material files"
          )
        )
      ),
      tags$div(
        id="ullme_course_file_tree",
        class="ullme-course-file-tree",
        `aria-label`="Course files"
      )
    )
  )
}


ullme_course_file_ui = function(app=getApp()) {
  tags$section(
    id="ullme_course_file_panel",
    class="ullme-course-file-panel ullme-course-content-panel",
    `data-course-panel`="file",
    tags$header(
      class="ullme-course-file-head",
      tags$button(
        id="ullme_course_file_back",
        class="ullme-secondary-action",
        type="button",
        "Back"
      ),
      tags$div(
        class="ullme-course-file-identity",
        tags$strong(id="ullme_course_file_name", "File"),
        tags$code(id="ullme_course_file_path", "")
      ),
      tags$button(
        id="ullme_course_file_save",
        class="ullme-primary-action",
        type="button",
        "Save"
      )
    ),
    tags$textarea(
      id="ullme_course_file_editor",
      class="ullme-course-file-editor",
      spellcheck="false",
      `aria-label`="Course file editor"
    ),
    tags$footer(
      class="ullme-course-file-footer",
      tags$span(id="ullme_course_file_status", "Open a text file to edit it."),
      tags$span("Ctrl+S to save")
    )
  )
}


ullme_material_category_label = function(category) {
  restore.point("ullme_material_category_label")
  labels = c(general="General", slides="Slides", ps="Problem Sets", quiz="Quiz", background="Background")
  label = labels[[category]]
  if (is.null(label)) ullme_title_case(category) else label
}


ullme_intro_msg = function() {
  restore.point("ullme_intro_msg")
  list(
    role = "assistant",
    meta = "",
    text = paste(
      "Hi! I am uLLMe.",
      "Shall I explain what you can do with uLLMe,",
      "or do you have something specific in mind?"
    )
  )
}


ullme_chat_output_html = function(text, app=getApp()) {
  restore.point("ullme_chat_output_html")
  text = paste0(text %||% "", collapse="\n")
  if (!isTRUE(app$render_chat_markdown) || !nzchar(text)) return("")

  if (isTRUE(app$adapt_mathjax)) {
    text = replace_math_delimiters(text)
  }

  # Protect common LaTeX delimiters and escaped braces from CommonMark
  # so that MathJax can still find \[ \], \( \), \{ \}
  # In R string literals, "\\" represents a single backslash.
  text = gsub("\\[", "\\\\[", text, fixed=TRUE)
  text = gsub("\\]", "\\\\]", text, fixed=TRUE)
  text = gsub("\\(", "\\\\(", text, fixed=TRUE)
  text = gsub("\\)", "\\\\)", text, fixed=TRUE)
  text = gsub("\\{", "\\\\{", text, fixed=TRUE)
  text = gsub("\\}", "\\\\}", text, fixed=TRUE)

  paste0(
    commonmark::markdown_html(text, extensions=TRUE),
    collapse="\n"
  )
}


ullme_composer_ui = function(app=getApp()) {
  restore.point("ullme_composer_ui")
  tags$footer(
    class = "ullme-composer-wrap",
    tags$div(
      class = "ullme-composer",
      ullme_audio_recording_ui(),
      tags$div(
        id = "ullme_upload_preview",
        class = "ullme-upload-preview",
        `aria-live` = "polite"
      ),
      if (identical(app$app_kind, "student")) tags$button(
        id = "ullme_camera_btn",
        class = "ullme-icon-button",
        type = "button",
        `aria-label` = "Take a photo",
        title = "Take a photo",
        HTML(ullme_icon_svg("camera"))
      ),
      tags$button(
        id = "ullme_upload_btn",
        class = "ullme-icon-button",
        type = "button",
        `aria-label` = "Upload image",
        title = "Upload image",
        HTML(ullme_icon_svg("image"))
      ),
      tags$textarea(
        id = "ullme_chat_input",
        class = "ullme-chat-input",
        rows = "1",
        placeholder = "Ask anything",
        `aria-label` = "Chat message"
      ),
      tags$select(
        id = "ullme_model_select",
        class = "ullme-model-select",
        `aria-label` = "Model",
        title = "Choose model",
        tags$option(value="loading", selected="selected", "Loading…")
      ),
      tags$button(
        id = "ullme_voice_btn",
        class = "ullme-icon-button",
        type = "button",
        `aria-label` = "Voice recording",
        title = "Voice input",
        HTML(ullme_icon_svg("mic"))
      ),
      tags$button(
        id = "ullme_submit_btn",
        class = "ullme-submit-button",
        type = "button",
        `aria-label` = "Submit chat",
        title = "Send message",
        HTML(ullme_icon_svg("send"))
      )
    )
  )
}


ullme_audio_recording_ui = function() {
  restore.point("ullme_audio_recording_ui")
  tags$div(
    id = "ullme_recording_panel",
    class = "ullme-recording-panel",
    tags$button(
      id = "ullme_recording_cancel",
      class = "ullme-recording-cancel",
      type = "button",
      `aria-label` = "Cancel recording",
      title = "Cancel recording",
      "Cancel"
    ),
    tags$div(
      class = "ullme-recording-status",
      tags$span(class="ullme-recording-dot"),
      tags$span(id="ullme_recording_timer", class="ullme-recording-timer", "0:00"),
      tags$span(class="ullme-recording-label", "Recording"),
      tags$canvas(
        id = "ullme_recording_wave",
        class = "ullme-recording-wave",
        width = "180",
        height = "34",
        `aria-label` = "Recording level"
      )
    ),
    tags$div(
      class = "ullme-recording-options",
      tags$select(
        id = "ullme_audio_format",
        class = "ullme-audio-select",
        `aria-label` = "Audio format",
        title = "Audio format",
        tags$option(value="auto", selected="selected", "Auto"),
        tags$option(value="webm", "WebM"),
        tags$option(value="ogg", "Ogg"),
        tags$option(value="mp4", "MP4")
      ),
      tags$select(
        id = "ullme_audio_quality",
        class = "ullme-audio-select",
        `aria-label` = "Audio quality",
        title = "Audio quality",
        tags$option(value="standard", selected="selected", "Standard"),
        tags$option(value="small", "Small"),
        tags$option(value="high", "High")
      ),
      tags$select(
        id = "ullme_mic_sensitivity",
        class = "ullme-audio-select",
        `aria-label` = "Mic sensitivity",
        title = "Mic sensitivity",
        tags$option(value="1", "Natural"),
        tags$option(value="2", "Normal"),
        tags$option(value="3", selected="selected", "Boost"),
        tags$option(value="5", "High"),
        tags$option(value="8", "Max")
      )
    ),
    tags$button(
      id = "ullme_recording_finish",
      class = "ullme-recording-finish",
      type = "button",
      `aria-label` = "Finish recording",
      title = "Finish recording",
      "Done"
    )
  )
}


ullme_icon_svg = function(name) {
  restore.point("ullme_icon_svg")
  icons = list(
    panel = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="4" width="16" height="16" rx="3"></rect><path d="M9 4v16"></path></svg>',
    image = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2"></rect><circle cx="8.5" cy="10" r="1.5"></circle><path d="M21 15l-5-5L5 19"></path></svg>',
    camera = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h3l2-3h6l2 3h3a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z"></path><circle cx="12" cy="13" r="4"></circle></svg>',
    mic = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3z"></path><path d="M19 10v2a7 7 0 0 1-14 0v-2"></path><path d="M12 19v3"></path></svg>',
    send = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14"></path><path d="M13 6l6 6-6 6"></path></svg>',
    plus = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14"></path><path d="M5 12h14"></path></svg>',
    user = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"></circle><path d="M4 21a8 8 0 0 1 16 0"></path></svg>',
    users = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="9" cy="8" r="3"></circle><path d="M3 20a6 6 0 0 1 12 0"></path><circle cx="17" cy="9" r="2.5"></circle><path d="M14 16a5 5 0 0 1 7 4"></path></svg>',
    upload = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 16V4"></path><path d="M7 9l5-5 5 5"></path><path d="M5 20h14"></path></svg>',
    sparkles = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3l1.4 4.1L17.5 8.5l-4.1 1.4L12 14l-1.4-4.1-4.1-1.4 4.1-1.4L12 3z"></path><path d="M18.5 14l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8.8-2.2z"></path></svg>',
    folder = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 7h7l2 2h9v10H3z"></path><path d="M3 7V5h7l2 2"></path></svg>',
    tutor = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"></circle><path d="M5 21a7 7 0 0 1 14 0"></path><path d="M18 4l2-2M19 8h3"></path></svg>',
    settings = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="3"></circle><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2"></path></svg>',
    analytics = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 20V10"></path><path d="M10 20V4"></path><path d="M16 20v-7"></path><path d="M22 20H2"></path></svg>',
    undo = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="M9 8l-4 4 4 4"></path><path d="M5 12h8a4 4 0 0 1 4 4"></path></svg>',
    redo = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="M15 8l4 4-4 4"></path><path d="M19 12h-8a4 4 0 0 0-4 4"></path></svg>'
  )
  icons[[name]]
}


ullme_handle_semester_select = function(semester=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_semester_select")
  semester = toupper(paste0(semester)[1])
  if (is.na(semester)) return(invisible(NULL))
  index = tryCatch(ullme_semester_index(semester), error=function(e) NA_integer_)
  if (is.na(index)) return(invisible(NULL))

  app$semester = semester
  ullme_refresh_course_state(app=app)
  ullme_send_course_state(app=app)
  invisible(app$semester)
}


ullme_handle_course_select = function(courseid=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_course_select")
  courseid = paste0(courseid)[1]
  if (is.na(courseid)) courseid = ""
  if (nzchar(courseid) && !courseid %in% app$courseids) return(invisible(NULL))

  app$courseid = courseid
  ullme_send_course_state(app=app)
  invisible(app$courseid)
}


ullme_handle_add_course = function(courseid=NULL, coursename="", app=getApp(), ...) {
  restore.point("ullme_handle_add_course")
  if (!app$role %in% c("teacher", "student")) return(invisible(NULL))
  courseid = tryCatch(ullme_clean_courseid(courseid), error=function(e) "")
  if (!nzchar(courseid)) return(invisible(NULL))

  if (identical(app$role, "teacher")) {
    result = tryCatch(
      ullme_create_teacher_course(
        courseid=courseid,
        coursename=coursename,
        app=app
      ),
      error=function(e) NULL
    )
    if (is.null(result) || !isTRUE(result$ok)) return(invisible(NULL))
  } else {
    ullme_make_course(
      main_dir=app$glob$main_dir,
      userid=ullme_app_role_storage_id(app=app),
      role=app$role,
      semester=app$semester,
      courseid=courseid,
      coursename=coursename
    )
  }
  app$courseid = courseid
  ullme_refresh_course_state(app=app)
  app$courseid = courseid
  ullme_send_course_state(app=app)
  invisible(app$courseid)
}


ullme_handle_course_settings_save = function(coursename="", app=getApp(), ...) {
  restore.point("ullme_handle_course_settings_save")
  if (is.null(app$courseid) || !nzchar(app$courseid)) return(invisible(NULL))
  course = list(courseid=app$courseid, coursename=coursename)
  ullme_save_course_settings(app=app, course=course)
  ullme_send_course_state(app=app)
  invisible(course)
}


ullme_handle_material_category = function(category="general", app=getApp(), ...) {
  restore.point("ullme_handle_material_category")
  category = paste0(category)[1]
  if (identical(category, "root")) {
    app$material_category = "root"
    return(invisible(app$material_category))
  }
  if (!category %in% ullme_course_material_categories()) return(invisible(NULL))
  app$material_category = category
  invisible(app$material_category)
}


ullme_handle_material_upload_destination = function(path="", tree=NULL,
                                                     app=getApp(), ...) {
  restore.point("ullme_handle_material_upload_destination")
  app$material_upload_directory = ""
  app$material_upload_tree = NULL
  original_path = paste0(path)[1]
  result = tryCatch({
    course_dir = ullme_active_course_dir(app=app)
    if (is.null(course_dir)) stop("Select a course first.")
    path = .ullme_material_relative_path(path, allow_root=TRUE)
    category = if (nzchar(path)) {
      strsplit(path, "/", fixed=TRUE)[[1]][[1]]
    } else {
      "root"
    }
    if (!identical(category, "root") &&
        !category %in% ullme_course_material_categories()) {
      stop("Invalid material upload category.")
    }
    material_dir = file.path(course_dir, "materials")
    target = .ullme_material_path(
      material_dir,
      path,
      must_exist=TRUE,
      allow_root=TRUE
    )
    if (!dir.exists(target)) stop("The material upload destination is not a directory.")
    app$material_category = category
    app$material_upload_directory = path
    app$material_upload_tree = ullme_prepare_material_upload_tree(
      tree=tree,
      destination=path,
      material_dir=material_dir
    )
    if (length(app$material_upload_tree$directories %||% character(0))) {
      ullme_send_course_state(app=app)
    }
    list(ok=TRUE, path=path, message="")
  }, error=function(e) {
    list(ok=FALSE, path=original_path, message=conditionMessage(e))
  })
  callJS(
    .fun="window.ullme.materialUploadDestinationReady",
    .args=list(result),
    .app=app
  )
  invisible(result)
}


ullme_handle_material_upload = function(id, value, app=getApp(), ...) {
  restore.point("ullme_handle_material_upload")
  if (is.null(value) || NROW(value) == 0) return(invisible(NULL))
  category = sub("^ullme_material_upload_", "", paste0(id)[1])
  if (!identical(category, "root") &&
      !category %in% ullme_course_material_categories()) {
    category = app$material_category
  }
  if (is.null(category) ||
      (!identical(category, "root") &&
       !category %in% ullme_course_material_categories())) {
    category = "root"
  }
  app$material_category = category
  on.exit({
    app$material_upload_directory = if (identical(category, "root")) "" else category
    app$material_upload_tree = NULL
  }, add=TRUE)
  result = tryCatch({
    destination = paste0(app$material_upload_directory %||% "")[1]
    if (is.na(destination)) {
      stop("No valid material upload destination was selected.")
    }
    destination = .ullme_material_relative_path(destination, allow_root=TRUE)
    destination_category = if (nzchar(destination)) {
      strsplit(destination, "/", fixed=TRUE)[[1]][[1]]
    } else {
      "root"
    }
    if (!identical(destination_category, category)) {
      stop("The upload destination does not match the selected material category.")
    }
    ullme_store_material_uploads(
      app=app,
      value=value,
      category=category,
      destination=destination
    )
    ullme_send_course_state(app=app)
    list(ok=TRUE, message="")
  }, error=function(e) {
    list(ok=FALSE, message=conditionMessage(e))
  })
  callJS(
    .fun = "window.ullme.materialUploadComplete",
    .args = list(id, result),
    .app = app
  )
  invisible(result)
}


ullme_handle_material_delete = function(category=NULL, path=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_material_delete")
  category = paste0(category)[1]
  path = paste0(path)[1]
  if (is.na(category) || is.na(path)) return(invisible(NULL))
  ullme_delete_material_file(app=app, category=category, path=path)
  ullme_send_course_state(app=app)
  invisible(TRUE)
}


ullme_handle_material_operation = function(action=NULL, paths=NULL,
                                            destination=NULL,
                                            app=getApp(), ...) {
  restore.point("ullme_handle_material_operation")
  result = tryCatch({
    course_dir = ullme_active_course_dir(app=app)
    if (is.null(course_dir)) stop("Select a course first.")
    ullme_apply_material_file_operation(
      action=action,
      paths=unlist(paths, use.names=FALSE),
      destination=destination,
      app=app
    )
    list(ok=TRUE, message="Material files updated.")
  }, error=function(e) {
    list(ok=FALSE, message=conditionMessage(e))
  })
  if (isTRUE(result$ok)) ullme_send_course_state(app=app)
  callJS(
    .fun="window.ullme.materialOperationComplete",
    .args=list(result),
    .app=app
  )
  invisible(result)
}


ullme_handle_material_convert = function(mode=NULL, paths=NULL,
                                          app=getApp(), ...) {
  restore.point("ullme_handle_material_convert")
  result = tryCatch({
    selected = ullme_material_conversion_paths_for_mode(paths, mode=mode)
    target = if (mode %in% c("all-md-txt", "all-overwrite")) {
      "md-txt"
    } else if (identical(mode, "pdf-txt")) {
      "txt"
    } else {
      "md"
    }
    overwrite = identical(mode, "all-overwrite")
    ullme_convert_material_files(
      paths=selected,
      to=target,
      overwrite=overwrite,
      skip_existing=!overwrite,
      origin="ui",
      app=app
    )
  }, error=function(e) {
    list(ok=FALSE, status="error", message=conditionMessage(e))
  })
  if (isTRUE(result$ok) && identical(result$status, "committed")) {
    ullme_send_course_state(app=app)
  }
  callJS(
    .fun="window.ullme.materialConversionComplete",
    .args=list(result),
    .app=app
  )
  invisible(result)
}


ullme_handle_material_create_directory = function(path=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_material_create_directory")
  result = tryCatch({
    course_dir = ullme_active_course_dir(app=app)
    if (is.null(course_dir)) stop("Select a course first.")
    create_material_directory(path=path, app=app)
    list(ok=TRUE, message="Material folder created.")
  }, error=function(e) {
    list(ok=FALSE, message=conditionMessage(e))
  })
  if (isTRUE(result$ok)) ullme_send_course_state(app=app)
  callJS(
    .fun="window.ullme.materialOperationComplete",
    .args=list(result),
    .app=app
  )
  invisible(result)
}


ullme_refresh_course_state = function(app=getApp()) {
  restore.point("ullme_refresh_course_state")
  userid = ullme_app_role_storage_id(app=app)
  app$courseids = ullme_user_courseids(
    main_dir=app$glob$main_dir,
    userid=userid,
    role=app$role,
    semester=app$semester
  )
  app$courseid = ullme_selected_courseid(
    courseids=app$courseids,
    preferred=app$courseid
  )
  invisible(app$courseids)
}


ullme_send_course_state = function(app=getApp()) {
  restore.point("ullme_send_course_state")
  summary = ullme_course_summary_for_js(app=app)
  callJS(
    .fun = "window.ullme.updateCourseList",
    .args = list(
      as.list(app$courseids),
      app$courseid,
      app$role %in% c("teacher", "student"),
      summary,
      app$semester
    ),
    .app = app
  )
  invisible(TRUE)
}


ullme_course_ai_tutor_stubs = function(app=getApp()) {
  restore.point("ullme_course_ai_tutor_stubs")
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) return(list())
  ids = ullme_definition_ids(ullme_course_ai_tutors_dir(course_dir))
  lapply(ids, function(tutorid) list(
    tutorid=tutorid,
    label=tutorid,
    loading=TRUE
  ))
}


ullme_send_course_shell_state = function(app=getApp()) {
  restore.point("ullme_send_course_shell_state")
  summary = list(
    course=list(courseid=app$courseid %||% ""),
    material=list(),
    material_tree=list(),
    ai_tutors=ullme_course_ai_tutor_stubs(app=app),
    ai_tutors_loading=TRUE,
    ai_tutor_catalog=list(),
    edit_history=list(),
    course_files=list()
  )
  callJS(
    .fun = "window.ullme.updateCourseList",
    .args = list(
      as.list(app$courseids),
      app$courseid,
      app$role %in% c("teacher", "student"),
      summary,
      app$semester
    ),
    .app = app
  )
  invisible(TRUE)
}


ullme_course_summary_for_js = function(app=getApp()) {
  restore.point("ullme_course_summary_for_js")
  summary = ullme_course_summary(app=app)
  if (is.null(summary)) {
    summary = list(course=NULL, material=list())
  } else {
    summary$material = lapply(summary$material, as.list)
  }
  if (identical(app$role, "teacher")) {
    course_dir = ullme_active_course_dir(app=app)
    summary$ai_tutors = ullme_course_ai_tutors(app=app)
    summary$edit_history = if (is.null(course_dir)) list() else list(
      course_settings=ullme_edit_history_state(
        scope="course_settings",
        app=app
      )
    )
    summary$ai_tutor_catalog = ullme_ai_tutor_catalog(app=app)
    summary$allowed_users = ullme_allowed_users_for_js(app=app)
    summary$student_urls = ullme_course_student_urls_for_js(app=app)
    summary$course_files = if (is.null(course_dir)) list() else
      ullme_course_file_records(course_dir)
    summary$material_tree = if (is.null(course_dir)) list() else
      ullme_material_tree(file.path(course_dir, "materials"))
  } else {
    summary$ai_tutors = list()
    summary$edit_history = list()
    summary$ai_tutor_catalog = list()
    summary$course_files = list()
    course_dir = ullme_active_course_dir(app=app)
    summary$material_tree = if (is.null(course_dir)) list() else
      ullme_material_tree(file.path(course_dir, "materials"))
  }
  summary
}


ullme_init_app = function(session=NULL, app=getApp()) {
  restore.point("ullme_init_app")
  ullme_init_storage(main_dir=app$glob$main_dir, app=app)
  if (identical(app$role, "student")) {
    ullme_student_session_stats_init(app=app)
    ullme_init_student_app(session=session, app=app)
    ullme_refresh_model_catalog(app=app)
  } else {
    # Show the course and Tutor navigation before computing instance
    # suggestions, file matches, histories, and conversion metadata.
    ullme_send_course_shell_state(app=app)
    later::later(function() {
      ullme_send_course_state(app=app)
    }, delay=0.01)
    later::later(function() {
      ullme_refresh_model_catalog(app=app)
    }, delay=0.02)
    ullme_init_teacher_usage_statistics(app=app)
  }
}


ullme_handle_chat_submit_safe = function(..., session=NULL, app=getApp()) {
  restore.point("ullme_handle_chat_submit_safe")
  args = list(...)
  message_id = paste0(args$assistantMessageId %||% "")[1]
  if (identical(app$catch_chat_errors, FALSE)) {
    return(do.call(
      ullme_handle_chat_submit,
      c(args, list(session=session, app=app))
    ))
  }
  tryCatch(
    do.call(
      ullme_handle_chat_submit,
      c(args, list(session=session, app=app))
    ),
    error=function(error) {
      request = if (nzchar(message_id)) app$chat_requests[[message_id]] else NULL
      if (!is.null(request)) {
        request$active = FALSE
        if (!is.null(request$controller)) {
          try(request$controller$cancel("Request setup failed"), silent=TRUE)
        }
        app$chat_requests[[message_id]] = NULL
        app$chat_tasks[[message_id]] = NULL
        if (identical(app$active_chat_request, request)) {
          app$active_chat_request = NULL
        }
      }
      app$chat_response_active = FALSE
      if (identical(app$role, "student")) {
        stats = if (is.null(request)) {
          ullme_student_stats_request(
            model=args$model %||% app$api_config$model,
            app=app
          )
        } else {
          request$stats_request
        }
        reply = if (is.null(request) || is.null(request$state)) {
          ""
        } else {
          request$state$text %||% ""
        }
        ullme_student_stats_append(
          stats,
          reply=reply,
          error_code="setup_error",
          app=app
        )
      }
      message = paste0(
        "The assistant request could not start: ",
        ullme_safe_ai_error(error, app$api_config)
      )
      try(
        ullme_send_chat_stream_update(
          message_id=message_id,
          done=TRUE,
          error=message,
          app=app
        ),
        silent=TRUE
      )
      invisible(NULL)
    }
  )
}


ullme_handle_chat_submit = function(id=NULL, text="", model=NULL,
                                  context=NULL, uploads=NULL,
                                  instance_builder=NULL,
                                  clientMessageId=NULL, assistantMessageId=NULL,
                                  session=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_chat_submit")
  text = paste0(text, collapse="\n")
  has_uploads = length(uploads) > 0
  has_instance_builder = is.list(instance_builder)
  if (!nzchar(trimws(text)) && !has_uploads && !has_instance_builder) {
    return(invisible(NULL))
  }
  if (is.null(assistantMessageId) || !nzchar(assistantMessageId)) {
    assistantMessageId = paste0("assistant_", as.integer(runif(1, 1, 1e9)))
  }
  if (isTRUE(app$chat_response_active)) {
    callJS(
      .fun="window.ullme.receiveAssistantStream",
      .args=list(
        assistantMessageId,
        "",
        "",
        "",
        "",
        TRUE,
        "Wait for the current response to finish before sending another message."
      ),
      .app=app
    )
    return(invisible(NULL))
  }
  model = ullme_chat_model_for_uploads(
    model=model,
    has_uploads=has_uploads,
    app=app
  )
  ullme_chat_debug(
    app,
    "handle_chat selected model=", model,
    " uploads=", length(uploads)
  )
  if (identical(app$role, "student")) {
    return(ullme_handle_student_tutor_submit(
      text=text,
      model=model,
      uploads=uploads,
      clientMessageId=clientMessageId,
      assistantMessageId=assistantMessageId,
      app=app
    ))
  }
  stats_request = if (identical(app$role, "student")) {
    ullme_student_stats_request(
      model=model %||% app$api_config$model,
      app=app
    )
  } else {
    NULL
  }
  ullme_send_chat_stream_update(
    message_id=assistantMessageId,
    text="Preparing your Tutor\u2026",
    done=FALSE,
    app=app
  )

  ai_input = if (nzchar(trimws(text))) text else "[uploaded image]"
  interaction_kind = "chat"
  task_profile = ""
  instance_builder_tutorid = ""
  if (has_instance_builder) {
    tutorid = paste0(instance_builder$tutorid %||% "")[1]
    guidance = paste0(instance_builder$guidance %||% text, collapse="\n")
    if (identical(app$catch_chat_errors, FALSE)) {
      built = ullme_instance_builder_request(tutorid, guidance, app=app)
    } else {
      built = tryCatch(
        ullme_instance_builder_request(tutorid, guidance, app=app),
        error=function(e) e
      )
      if (inherits(built, "error")) {
        ullme_send_chat_stream_update(
          message_id=assistantMessageId,
          done=TRUE,
          error=conditionMessage(built),
          app=app
        )
        if (identical(app$role, "student")) {
          ullme_student_stats_append(
            stats_request,
            error_code="setup_error",
            app=app
          )
        }
        return(invisible(NULL))
      }
    }
    ai_input = built
    interaction_kind = "instance_builder"
    task_profile = "instance_builder"
    course_dir = ullme_active_course_dir(app=app)
    instance_builder_tutorid = tutorid
    if (nzchar(trimws(guidance))) {
      try(
        ullme_store_form_input(
          guidance,
          "instance_builder",
          course_dir=course_dir,
          app=app
        ),
        silent=TRUE
      )
    }
    try(
      callJS(
        .fun="window.ullme.replaceUserMessage",
        .args=list(clientMessageId, ai_input),
        .app=app
      ),
      silent=TRUE
    )
  }
  context_instruction = NULL
  if (identical(app$role, "teacher") && is.list(context)) {
    open_file = paste0(context$course_file %||% "")[1]
    context_instruction = paste0(
      "The teacher is currently working in course '", app$courseid %||% "",
      "', studio view '", paste0(context$studio_view %||% "")[1], "'",
      if (nzchar(open_file)) paste0(", with course file '", open_file, "' open") else "",
      "."
    )
  }
  system_instructions = paste(
    c(context_instruction),
    collapse="\n\n"
  )
  if (!nzchar(system_instructions)) system_instructions = NULL
  if (identical(app$role, "student")) {
    ullme_student_chat_history_append(
      role="user",
      text=ai_input,
      message_id=clientMessageId %||% "",
      app=app
    )
  }
  interaction_dir = ullme_ai_interaction_start(
    input=ai_input,
    visible_text=text,
    model=model %||% app$api_config$model,
    kind=interaction_kind,
    app=app
  )
  if (ullme_uses_fake_ai(app=app)) {
    answer = paste0("Fake AI answer to:\n", ai_input)
    ullme_student_stats_mark_output(stats_request)
    callJS(
      .fun="window.ullme.receiveAssistantMessage",
      .args=list(
        assistantMessageId,
        answer,
        ullme_chat_output_html(answer, app=app)
      ),
      .app=app
    )
    ullme_ai_interaction_finish(interaction_dir, text=answer)
    if (identical(app$role, "student")) {
      ullme_student_chat_history_append(
        role="assistant",
        text=answer,
        message_id=assistantMessageId,
        app=app
      )
      ullme_send_student_chat_history(app=app)
      ullme_student_stats_append(
        stats_request,
        reply=answer,
        app=app
      )
    }
    return(invisible(answer))
  }

  app$chat_response_active = TRUE
  start_instance_builder_retry = NULL
  finish = function(status="completed", text="", thinking="", error="",
                    error_code="") {
    builder_result = NULL
    if (identical(status, "completed") &&
        nzchar(request$instance_builder_tutorid %||% "")) {
      builder_result = ullme_apply_instance_builder_response(
        tutorid=request$instance_builder_tutorid,
        text=text,
        app=app
      )
      can_retry = !isTRUE(builder_result$ok) && nzchar(trimws(text)) &&
        request$instance_builder_retry_count <
          (app$instance_builder_retries %||% 1L)
      if (isTRUE(can_retry)) {
        request$instance_builder_retry_count =
          request$instance_builder_retry_count + 1L
        start_instance_builder_retry(
          previous_output=text,
          error=builder_result$message
        )
        return(invisible(FALSE))
      }
      ullme_send_chat_stream_update(
        message_id=assistantMessageId,
        text=text,
        thinking=thinking,
        done=TRUE,
        error=if (isTRUE(builder_result$ok)) "" else builder_result$message,
        activity=if (isTRUE(builder_result$ok)) builder_result$message else "",
        app=app
      )
    }
    request$active = FALSE
    app$chat_response_active = FALSE
    app$chat_tasks[[assistantMessageId]] = NULL
    app$chat_requests[[assistantMessageId]] = NULL
    if (identical(app$active_chat_request, request)) {
      app$active_chat_request = NULL
    }
    ullme_ai_interaction_finish(
      interaction_dir, status=status, text=text,
      thinking=thinking, error=error
    )
    if (identical(app$role, "student") && nzchar(text)) {
      ullme_student_chat_history_append(
        role="assistant",
        text=text,
        message_id=assistantMessageId,
        app=app
      )
      ullme_send_student_chat_history(app=app)
    }
    if (identical(app$role, "student")) {
      ullme_student_stats_append(
        stats_request,
        reply=text,
        error_code=error_code,
        app=app
      )
    }
  }
  fail = function(error, text="", thinking="") {
    message = paste0(
      "I could not reach the configured model: ",
      ullme_safe_ai_error(error, app$api_config)
    )
    on.exit(if (isTRUE(request$active)) {
      finish(
        status="error", text=text, thinking=thinking, error=message,
        error_code="provider_error"
      )
    }, add=TRUE)
    ullme_send_chat_stream_update(
      message_id=assistantMessageId,
      text=text,
      thinking=thinking,
      done=TRUE,
      error=message,
      app=app
    )
    error_code = if (grepl(
      "timed out",
      tolower(conditionMessage(error)),
      fixed=TRUE
    )) "timeout" else "provider_error"
    finish(
      status="error", text=text, thinking=thinking, error=message,
      error_code=error_code
    )
    NULL
  }
  request = new.env(parent=emptyenv())
  request$active = TRUE
  request$controller = NULL
  request$state = NULL
  request$interaction_dir = interaction_dir
  request$received_provider_output = FALSE
  request$waiting_for_approval = FALSE
  request$message_id = assistantMessageId
  request$tool_event_seq = 0L
  request$instance_builder_tutorid = instance_builder_tutorid
  request$instance_builder_retry_count = 0L
  request$stats_request = stats_request
  app$chat_requests[[assistantMessageId]] = request
  app$active_chat_request = request
  start_instance_builder_retry = function(previous_output, error) {
    retry_number = request$instance_builder_retry_count
    retry_limit = app$instance_builder_retries %||% 1L
    retry_prompt = ullme_instance_builder_retry_prompt(
      previous_output=previous_output,
      error=error
    )
    ullme_send_chat_stream_update(
      message_id=assistantMessageId,
      text="",
      thinking="",
      done=FALSE,
      activity=paste0(
        "Correcting invalid YAML (retry ", retry_number,
        " of ", retry_limit, ")\u2026"
      ),
      app=app
    )
    retry_stream_fun = ullme_start_custom_ai_stream
    retry_args = list(
      input=retry_prompt,
      model=model,
      context=context %||% list(),
      system_instructions=system_instructions,
      include_thinking=isTRUE(app$show_chat_thinking),
      task_profile="instance_builder",
      on_update=function(text, thinking, done) {
        if (!isTRUE(request$active)) return(invisible(NULL))
        request$received_provider_output = request$received_provider_output ||
          nzchar(text) || nzchar(thinking)
        ullme_send_chat_stream_update(
          message_id=assistantMessageId,
          text=text,
          thinking=thinking,
          done=FALSE,
          activity=if (isTRUE(done)) "Validating corrected YAML\u2026" else "",
          app=app
        )
      },
      app=app
    )
    job = tryCatch(do.call(retry_stream_fun, retry_args), error=function(e) e)
    if (inherits(job, "error")) return(invisible(fail(job)))
    request$controller = job$controller
    request$state = job$state
    task = promises::then(
      ullme_promise_timeout(job$promise, seconds=app$chat_timeout_seconds),
      onFulfilled=function(value) {
        if (!isTRUE(request$active)) return(invisible(NULL))
        finish(text=value$text, thinking=value$thinking)
        value
      },
      onRejected=function(error) {
        if (!isTRUE(request$active)) return(invisible(NULL))
        if (identical(app$catch_chat_errors, FALSE)) stop(error)
        fail(error, text=job$state$text, thinking=job$state$thinking)
      }
    )
    app$chat_tasks[[assistantMessageId]] = task
    invisible(task)
  }
  connection_status = ullme_ai_connection_status(model=model, app=app)
  ullme_send_chat_stream_update(
    message_id=assistantMessageId,
    text=connection_status,
    done=FALSE,
    app=app
  )

  {
    stream_fun = ullme_start_custom_ai_stream
    ullme_chat_debug(
      app,
      "handle_chat stream branch begin backend=",
      "custom"
    )
    stream_on_update = function(text, thinking, done) {
      ullme_chat_debug(
        app,
        "handle_chat on_update callback begin done=", done,
        " text_bytes=", nchar(paste0(text, collapse=""), type="bytes"),
        " thinking_bytes=", nchar(paste0(thinking, collapse=""), type="bytes")
      )
      if (!isTRUE(request$active)) return(invisible(NULL))
      if (nzchar(text) || nzchar(thinking)) {
        request$received_provider_output = TRUE
      }
      if (nzchar(trimws(text))) {
        ullme_student_stats_mark_output(stats_request)
      }
      ullme_send_chat_stream_update(
        message_id=assistantMessageId,
        text=text,
        thinking=thinking,
        done=isTRUE(done) && !identical(task_profile, "instance_builder"),
        app=app
      )
      ullme_chat_debug(
        app,
        "handle_chat on_update callback end done=", done
      )
    }
    stream_on_event = function(type, content) {
      ullme_chat_debug(app, "handle_chat on_event callback begin type=", type)
      if (!isTRUE(request$active)) return(invisible(NULL))
      if (type %in% c("tool_request", "tool_result")) {
        request$received_provider_output = TRUE
      }
      ullme_chat_debug(app, "handle_chat on_event callback end type=", type)
      invisible(NULL)
    }
    start_stream = function() {
      stream_args = list(
        input=ai_input,
        model=model,
        context=context %||% list(),
        system_instructions=system_instructions,
        include_thinking=isTRUE(app$show_chat_thinking),
        task_profile=task_profile,
        on_update=stream_on_update,
        on_event=stream_on_event,
        app=app
      )
      stream_args$uploads = uploads
      do.call(stream_fun, stream_args)
    }
    if (identical(app$catch_chat_errors, FALSE)) {
      job = start_stream()
    } else {
      job = tryCatch(start_stream(), error=function(e) e)
      if (inherits(job, "error")) {
        return(invisible(fail(job)))
      }
    }
    ullme_chat_debug(app, "handle_chat stream job ready")
    request$controller = job$controller
    request$state = job$state
    ullme_student_stats_attach_chat(
      stats_request,
      job$chat,
      usage_start=job$usage_start
    )
    later::later(function() {
      if (!isTRUE(request$active) ||
          isTRUE(request$received_provider_output)) {
        return(invisible(NULL))
      }
      ullme_send_chat_stream_update(
        message_id=assistantMessageId,
        text=ullme_ai_connection_status(
          model=model,
          waiting=TRUE,
          app=app
        ),
        done=FALSE,
        app=app
      )
    }, delay=12)
    later::later(function() {
      if (!isTRUE(request$active) ||
          isTRUE(request$received_provider_output)) {
        return(invisible(NULL))
      }
      seconds = app$chat_connect_timeout_seconds %||% 60
      try(
        job$controller$cancel("Model connection timed out"),
        silent=TRUE
      )
      error = simpleError(paste0(
        "The provider connection opened, but ",
        paste0(model %||% app$api_config$model)[1],
        " did not begin responding within ",
        format(seconds, trim=TRUE),
        " seconds."
      ))
      if (identical(app$catch_chat_errors, FALSE)) stop(error)
      fail(error)
    }, delay=app$chat_connect_timeout_seconds %||% 60)
    task = promises::then(
      ullme_promise_timeout(
        job$promise,
        seconds=app$chat_timeout_seconds,
        is_paused=function() isTRUE(request$waiting_for_approval)
      ),
      onFulfilled=function(value) {
        ullme_chat_debug(app, "handle_chat promise fulfilled")
        if (!isTRUE(request$active)) return(invisible(NULL))
        finish(text=value$text, thinking=value$thinking)
        value
      },
      onRejected=function(error) {
        ullme_chat_debug(
          app,
          "handle_chat promise rejected message=", conditionMessage(error)
        )
        if (!isTRUE(request$active)) return(invisible(NULL))
        if (grepl(
          "timed out",
          tolower(conditionMessage(error)),
          fixed=TRUE
        )) {
          try(job$controller$cancel("Model request timed out"), silent=TRUE)
        }
        if (identical(app$catch_chat_errors, FALSE)) stop(error)
        fail(error, text=job$state$text, thinking=job$state$thinking)
      }
    )
  }
  app$chat_tasks[[assistantMessageId]] = task
  invisible(task)
}


ullme_handle_chat_cancel = function(assistantMessageId=NULL,
                                     app=getApp(), ...) {
  message_id = paste0(assistantMessageId %||% "")[1]
  if (is.na(message_id) || !nzchar(message_id)) return(invisible(FALSE))
  request = app$chat_requests[[message_id]]
  if (is.null(request) || !isTRUE(request$active)) return(invisible(FALSE))
  request$active = FALSE
  if (!is.null(request$controller)) {
    try(request$controller$cancel("Stopped by user"), silent=TRUE)
  }
  ullme_cancel_change_waiters(
    message_id=message_id,
    reason="The assistant request was stopped.",
    app=app
  )
  text = if (is.null(request$state)) "" else request$state$text %||% ""
  thinking = if (is.null(request$state)) "" else request$state$thinking %||% ""
  app$chat_response_active = FALSE
  app$chat_tasks[[message_id]] = NULL
  app$chat_requests[[message_id]] = NULL
  if (identical(app$active_chat_request, request)) {
    app$active_chat_request = NULL
  }
  ullme_ai_interaction_finish(
    request$interaction_dir,
    status="cancelled",
    text=text,
    thinking=thinking
  )
  if (identical(app$role, "student") && nzchar(text)) {
    ullme_student_live_history_append(
      role="assistant",
      text=text,
      message_id=message_id,
      app=app
    )
    ullme_send_student_chat_history(app=app)
  }
  if (identical(app$role, "student")) {
    app$student_pending_workflow = NULL
    ullme_student_stats_append(
      request$stats_request,
      reply=text,
      error_code="cancelled",
      app=app
    )
  }
  ullme_send_chat_stream_update(
    message_id=message_id,
    text=if (nzchar(text)) text else "Stopped.",
    thinking=thinking,
    done=TRUE,
    app=app
  )
  invisible(TRUE)
}


ullme_send_chat_stream_update = function(message_id, text="", thinking="",
                                          done=FALSE, error="", activity="",
                                          waiting_for_user=FALSE,
                                          app=getApp()) {
  restore.point("ullme_send_chat_stream_update")
  text = paste0(text %||% "", collapse="")
  thinking = if (isTRUE(app$show_chat_thinking)) {
    paste0(thinking %||% "", collapse="")
  } else {
    ""
  }
  callJS(
    .fun="window.ullme.receiveAssistantStream",
    .args=list(
      message_id,
      text,
      ullme_chat_output_html(text, app=app),
      thinking,
      ullme_chat_output_html(thinking, app=app),
      isTRUE(done),
      paste0(error %||% "")[1],
      paste0(activity %||% "")[1],
      isTRUE(waiting_for_user)
    ),
    .app=app
  )
  invisible(TRUE)
}


ullme_handle_image_upload = function(id, value, session, app=getApp(), ...) {
  restore.point("ullme_handle_image_upload")
  if (is.null(value) || NROW(value) == 0) return(invisible(NULL))

  upload_dir = ullme_session_upload_dir(session=session, app=app)
  dir.create(upload_dir, recursive=TRUE, showWarnings=FALSE)

  clean_names = ullme_clean_file_name(value$name)
  upload_ids = paste0(
    "img_",
    format(Sys.time(), "%Y%m%d%H%M%S"),
    "_",
    seq_len(NROW(value))
  )
  target_names = paste0(upload_ids, "_", clean_names)
  target_paths = file.path(upload_dir, target_names)
  copied = file.copy(value$datapath, target_paths, overwrite=TRUE)
  if (!any(copied)) return(invisible(NULL))

  session_dir = basename(upload_dir)
  urls = paste(
    app$uploads_resource_prefix %||% "ullme-uploads",
    session_dir,
    target_names,
    sep="/"
  )
  records = Map(
    f = ullme_upload_record,
    id = upload_ids[copied],
    name = clean_names[copied],
    size = value$size[copied],
    type = value$type[copied],
    path = normalizePath(target_paths[copied], winslash="/", mustWork=FALSE),
    url = urls[copied]
  )

  callJS(
    .fun = "window.ullme.receiveStoredUploads",
    .args = list(records),
    .app = app
  )
  invisible(records)
}


ullme_upload_record = function(id, name, size, type, path, url) {
  restore.point("ullme_upload_record")
  list(
    id = id,
    name = name,
    size = size,
    type = type,
    path = path,
    url = url
  )
}


ullme_session_upload_dir = function(session, app=getApp()) {
  restore.point("ullme_session_upload_dir")
  file.path(app$uploads_dir, ullme_session_dir_name(session=session))
}


ullme_session_dir_name = function(session) {
  restore.point("ullme_session_dir_name")
  token = session$token
  if (is.null(token) || !nzchar(token)) token = "session"
  ullme_clean_file_name(token)
}


ullme_clean_file_name = function(x) {
  restore.point("ullme_clean_file_name")
  x = basename(x)
  x = ullme_transliterate_german(x)
  x = gsub("[^A-Za-z0-9._-]+", "_", x)
  x = gsub("^_+|_+$", "", x)
  x[!nzchar(x)] = "upload"
  x
}


ullme_transliterate_german = function(x) {
  restore.point("ullme_transliterate_german")
  x = enc2utf8(paste0(x))
  replacements = c(
    "\u00c4"="Ae", "\u00d6"="Oe", "\u00dc"="Ue",
    "\u00e4"="ae", "\u00f6"="oe", "\u00fc"="ue",
    "\u00df"="ss", "\u1e9e"="SS"
  )
  for (letter in names(replacements)) {
    x = gsub(letter, replacements[[letter]], x, fixed=TRUE, useBytes=TRUE)
  }
  stringi::stri_trans_general(x, "Latin-ASCII")
}


ullme_clean_relative_upload_path = function(path) {
  path = gsub("\\\\", "/", paste0(path)[1])
  if (!ullme_safe_relative_material_path(path)) {
    stop("A dropped folder contains an unsafe relative path.")
  }
  parts = strsplit(path, "/", fixed=TRUE)[[1]]
  cleaned = vapply(parts, ullme_clean_file_name, character(1))
  .ullme_material_relative_path(paste(cleaned, collapse="/"))
}


ullme_prepare_material_upload_tree = function(tree, destination, material_dir) {
  if (is.null(tree) || !is.list(tree)) return(NULL)
  files = unlist(tree$files %||% list(), use.names=TRUE)
  directories = unlist(tree$directories %||% list(), use.names=FALSE)
  if (length(files) > 5000L || length(directories) > 5000L) {
    stop("The dropped folder contains too many entries.")
  }
  if (length(files) && (
    is.null(names(files)) ||
    any(!nzchar(names(files))) ||
    anyDuplicated(names(files))
  )) {
    stop("The dropped folder has invalid upload metadata.")
  }
  if (length(files)) {
    upload_names = basename(names(files))
    if (!identical(upload_names, names(files)) || anyDuplicated(upload_names)) {
      stop("The dropped folder has invalid upload filenames.")
    }
    files = stats::setNames(
      vapply(files, ullme_clean_relative_upload_path, character(1)),
      upload_names
    )
  } else {
    files = character(0)
  }
  if (length(directories)) {
    directories = unique(vapply(
      directories,
      ullme_clean_relative_upload_path,
      character(1)
    ))
    for (directory in directories) {
      target = .ullme_material_path(
        material_dir,
        ullme_material_child_path(destination, directory)
      )
      if (!dir.exists(target) &&
          !dir.create(target, recursive=TRUE, showWarnings=FALSE)) {
        stop("Could not create a folder from the dropped directory.")
      }
    }
  }
  list(destination=destination, files=files, directories=directories)
}


ullme_uses_fake_ai = function(app=getApp()) {
  restore.point("ullme_uses_fake_ai")
  if (!is.null(app$api_config$provider)) {
    return(identical(app$api_config$provider, "fake"))
  }
  if (is.null(app$uses_fake_ai)) return(TRUE)
  isTRUE(app$uses_fake_ai)
}
