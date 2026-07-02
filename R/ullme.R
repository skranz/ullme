

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
                      uses_fake_ai=NULL, max_upload_mb=100,
                      api_key_file=NULL,
                      api_provider=c("fake", "nvidia", "local"),
                      api_model=NULL, api_base_url=NULL,
                      render_chat_markdown=TRUE) {
  restore.point(".ullme_app")
  app = eventsApp()
  glob = app$glob

  role = match.arg(role)
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
  # Shiny's upload limit is process-wide, even though upload state is per app.
  current_upload_limit = getOption("shiny.maxRequestSize", 5 * 1024^2)
  options(shiny.maxRequestSize=max(current_upload_limit, max_upload_mb * 1024^2))

  # app is per Shiny app instance; app$glob is shared across all instances.
  # Store only truly shared values in glob and keep user-specific state on app.
  glob$main_dir = main_dir
  app$userid = ullme_clean_user_name(userid)

  app$teacherid = if (is.null(teacherid)) app$userid else
    ullme_clean_user_name(teacherid)
  app$role = role
  app$app_kind = role
  app$allowed_roles = role
  app$semester = ullme_semester()
  app$uses_fake_ai = identical(app$api_config$provider, "fake")
  app$render_chat_markdown = isTRUE(render_chat_markdown)
  app$teacher_chats = list()
  app$api_models = app$api_config$model
  app$api_models_error = NULL
  app$user_dir = ullme_user_dir(main_dir=main_dir, userid=app$userid)
  app$role_user_dir = ullme_role_user_dir(main_dir=main_dir, userid=app$userid, role=app$role)
  app$cur_session_dir = ullme_cur_session_dir(user_dir=app$user_dir)
  app$uploads_dir = ullme_cur_session_images_dir(cur_session_dir=app$cur_session_dir)
  app$audio_dir = ullme_cur_session_audio_dir(cur_session_dir=app$cur_session_dir)
  app$definition_downloads_dir = file.path(app$cur_session_dir, "definition_downloads")
  app$definition_imports = list()
  app$pending_changes = list()
  app$change_results = list()
  app$courseids = ullme_user_courseids(
    main_dir=main_dir,
    userid=app$userid,
    role=app$role,
    semester=app$semester
  )
  app$courseid = ullme_selected_courseid(app$courseids)
  app$material_category = "general"
  app$material_upload_directory = "general"
  app$active_skillid = ""

  ullme_add_resource_paths(app=app)
  app$ui = ullme_app_ui(app=app)
  ullme_register_handlers(app=app)

  appInitHandler(function(...) {
    restore.point("ullme_init")
    ullme_init_app()
  })
  app
}


ullme_add_resource_paths = function(app=getApp()) {
  restore.point("ullme_add_resource_paths")
  www_dir = ullme_www_dir()
  dir.create(app$uploads_dir, recursive=TRUE, showWarnings=FALSE)
  dir.create(app$audio_dir, recursive=TRUE, showWarnings=FALSE)
  dir.create(app$definition_downloads_dir, recursive=TRUE, showWarnings=FALSE)

  shiny::addResourcePath(prefix="ullme", directoryPath=www_dir)
  shiny::addResourcePath(prefix="ullme-uploads", directoryPath=app$uploads_dir)
  shiny::addResourcePath(prefix="ullme-audio", directoryPath=app$audio_dir)
  shiny::addResourcePath(
    prefix="ullme-definition-downloads",
    directoryPath=app$definition_downloads_dir
  )
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
    fun = ullme_handle_chat_submit,
    app = app
  )
  changeHandler(
    id = "ullme_image_upload",
    fun = ullme_handle_image_upload,
    app = app
  )
  lapply(ullme_course_material_categories(), function(category) {
    changeHandler(
      id = paste0("ullme_material_upload_", category),
      fun = ullme_handle_material_upload,
      app = app
    )
  })
  lapply("skill", function(kind) {
    changeHandler(
      id = paste0("ullme_definition_import_", kind),
      fun = ullme_handle_definition_import_upload,
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
    eventId = "ullme_ai_tutor_toggle_event",
    id = NULL,
    fun = ullme_handle_ai_tutor_toggle,
    app = app
  )
  eventHandler(
    eventId = "ullme_ai_tutor_save_event",
    id = NULL,
    fun = ullme_handle_ai_tutor_save,
    app = app
  )
  eventHandler(
    eventId = "ullme_ai_tutor_instances_save_event",
    id = NULL,
    fun = ullme_handle_ai_tutor_instances_save,
    app = app
  )
  eventHandler(
    eventId = "ullme_skill_activate_event",
    id = NULL,
    fun = ullme_handle_skill_activate,
    app = app
  )
  eventHandler(
    eventId = "ullme_skill_clear_event",
    id = NULL,
    fun = ullme_handle_skill_clear,
    app = app
  )
  eventHandler(
    eventId = "ullme_definition_action_event",
    id = NULL,
    fun = ullme_handle_definition_action,
    app = app
  )
  eventHandler(
    eventId = "ullme_definition_chat_event",
    id = NULL,
    fun = ullme_handle_definition_chat,
    app = app
  )
  eventHandler(
    eventId = "ullme_agent_settings_open_event",
    id = NULL,
    fun = ullme_handle_agent_settings_open,
    app = app
  )
  eventHandler(
    eventId = "ullme_agent_settings_save_event",
    id = NULL,
    fun = ullme_handle_agent_settings_save,
    app = app
  )
  eventHandler(
    eventId = "ullme_change_approval_event",
    id = NULL,
    fun = ullme_handle_change_approval,
    app = app
  )
  eventHandler(
    eventId = "ullme_change_undo_event",
    id = NULL,
    fun = ullme_handle_change_undo,
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
  tagList(
  tags$head(
      tags$meta(name="viewport", content="width=device-width, initial-scale=1"),
      tags$link(rel="stylesheet", type="text/css", href="ullme/ullme-chat.css"),
      tags$script(src="ullme/ullme-materials.js"),
      tags$script(src="ullme/ullme-chat.js"),
      tags$script(src="ullme/ullme-tutors.js"),
      tags$script(src="ullme/ullme-audio.js")
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
        tags$input(
          id = "ullme_audio_upload",
          class = "ullme-file-input",
          type = "file",
          accept = "audio/*"
        ),
        if (identical(app$app_kind, "teacher")) tagList(
          tags$input(
            id = "ullme_definition_import_skill",
            class = "ullme-file-input",
            type = "file",
            accept = ".zip,application/zip"
          ),
          lapply(ullme_course_material_categories(), function(category) {
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


ullme_chat_pane_ui = function(app=getApp(), show_header=FALSE) {
  restore.point("ullme_chat_pane_ui")
  intro = ullme_intro_msg()
  intro_html = ullme_chat_output_html(intro$text, app=app)
  tags$section(
    class = "ullme-chat-pane",
    if (isTRUE(show_header)) tags$header(
      class="ullme-ai-pane-header",
      tags$div(
        class="ullme-ai-pane-heading",
        tags$span(class="ullme-ai-pane-title", "AI assistant")
      ),
      tags$button(
        id="ullme_ai_pane_toggle",
        class="ullme-icon-button",
        type="button",
        `aria-label`="Collapse AI pane",
        title="Collapse AI pane",
        HTML(ullme_icon_svg("panel"))
      )
    ),
    tags$section(
      id = "ullme_chat_messages",
      class = "ullme-chat-messages",
      `data-intro-role` = intro$role,
      `data-intro-text` = intro$text,
      `data-intro-meta` = intro$meta,
      `data-intro-html` = intro_html
    ),
    ullme_composer_ui()
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
        tags$input(type="text", value=app$userid, readonly="readonly")
      ),
      if (identical(app$app_kind, "teacher")) tags$div(
        class = "ullme-teacher-library-links",
        tags$button(
          id = "ullme_manage_skills_btn",
          class = "ullme-settings-link",
          type = "button",
          "Skill Library"
        ),
        tags$button(
          id = "ullme_agent_settings_btn",
          class = "ullme-settings-link",
          type = "button",
          "Agent tools & change history"
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
    ullme_ai_tutors_ui(app=app),
    ullme_material_ui(app=app),
    ullme_course_file_ui(app=app),
    ullme_course_settings_ui(app=app)
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
    list(view="materials", label="Materials", icon="folder"),
    list(view="settings", label="Settings", icon="settings"),
    list(view="history", label="History", icon="history")
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
          tags$span("Add AI Tutor")
        ),
        tags$button(
          type="button",
          role="menuitem",
          `data-add-kind`="skills",
          HTML(ullme_icon_svg("sparkles")),
          tags$span("Add Skill")
        )
      )
    ),
    lapply(seq_along(items), function(i) {
      item = items[[i]]
      tagList(
        if (i == 2) tags$div(
          id="ullme_tutor_nav_items",
          class="ullme-dynamic-nav-items",
          `aria-label`="Course AI Tutors"
        ),
        if (i == 2) tags$div(
          id="ullme_skill_nav_items",
          class="ullme-dynamic-nav-items",
          `aria-label`="Active Skills"
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
    })
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
      tags$div(class="ullme-panel-title", "Course Settings"),
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
      tags$div(class="ullme-field-label", "Times"),
      tags$div(
        id = "ullme_course_times",
        class = "ullme-times-grid",
        lapply(seq_len(3), function(i) ullme_time_slot_ui(i))
      ),
      tags$button(
        id = "ullme_course_settings_save",
        class = "ullme-primary-action",
        type = "button",
        "Save"
      )
    )
  )
}


ullme_time_slot_ui = function(i) {
  restore.point("ullme_time_slot_ui")
  tags$div(
    class = "ullme-time-slot",
    `data-slot` = i,
    tags$select(
      class = "ullme-time-weekday",
      `aria-label` = paste("Weekday", i),
      tags$option(value="", ""),
      lapply(
        c("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"),
        function(day) tags$option(value=day, ullme_title_case(day))
      )
    ),
    tags$input(class="ullme-time-start", type="time", `aria-label`=paste("Start time", i)),
    tags$input(class="ullme-time-end", type="time", `aria-label`=paste("End time", i))
  )
}


ullme_material_ui = function(app=getApp()) {
  restore.point("ullme_material_ui")
  tags$section(
    id = "ullme_material_panel",
    class = "ullme-material ullme-course-content-panel ullme-course-content-panel-active",
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
  if (!isTRUE(app$render_chat_markdown)) return("")
  paste0(commonmark::markdown_html(text), collapse="\n")
}


ullme_composer_ui = function() {
  restore.point("ullme_composer_ui")
  tags$footer(
    class = "ullme-composer-wrap",
    tags$section(
      id = "ullme_active_skill",
      class = "ullme-active-skill",
      `aria-live` = "polite"
    ),
    tags$div(
      class = "ullme-composer",
      ullme_audio_recording_ui(),
      tags$div(
        id = "ullme_upload_preview",
        class = "ullme-upload-preview",
        `aria-live` = "polite"
      ),
      tags$button(
        id = "ullme_skills_btn",
        class = "ullme-icon-button ullme-skills-button",
        type = "button",
        `aria-label` = "Choose a skill",
        title = "Skills",
        HTML(ullme_icon_svg("sparkles"))
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
    mic = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3z"></path><path d="M19 10v2a7 7 0 0 1-14 0v-2"></path><path d="M12 19v3"></path></svg>',
    send = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14"></path><path d="M13 6l6 6-6 6"></path></svg>',
    plus = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14"></path><path d="M5 12h14"></path></svg>',
    user = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"></circle><path d="M4 21a8 8 0 0 1 16 0"></path></svg>',
    upload = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 16V4"></path><path d="M7 9l5-5 5 5"></path><path d="M5 20h14"></path></svg>',
    sparkles = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3l1.4 4.1L17.5 8.5l-4.1 1.4L12 14l-1.4-4.1-4.1-1.4 4.1-1.4L12 3z"></path><path d="M18.5 14l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8.8-2.2z"></path></svg>',
    folder = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 7h7l2 2h9v10H3z"></path><path d="M3 7V5h7l2 2"></path></svg>',
    tutor = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"></circle><path d="M5 21a7 7 0 0 1 14 0"></path><path d="M18 4l2-2M19 8h3"></path></svg>',
    settings = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="3"></circle><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2"></path></svg>',
    history = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12a8 8 0 1 0 2-5.3"></path><path d="M4 4v6h6M12 7v5l3 2"></path></svg>'
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
  app$active_skillid = ""
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
  app$active_skillid = ""
  ullme_send_course_state(app=app)
  invisible(app$courseid)
}


ullme_handle_add_course = function(courseid=NULL, coursename="", times=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_add_course")
  if (!app$role %in% c("teacher", "student")) return(invisible(NULL))
  courseid = tryCatch(ullme_clean_courseid(courseid), error=function(e) "")
  if (!nzchar(courseid)) return(invisible(NULL))

  if (identical(app$role, "teacher")) {
    result = tryCatch(
      ullme_create_teacher_course(
        courseid=courseid,
        coursename=coursename,
        times=times,
        app=app
      ),
      error=function(e) NULL
    )
    if (is.null(result) || !isTRUE(result$ok)) return(invisible(NULL))
  } else {
    ullme_make_course(
      main_dir=app$glob$main_dir,
      userid=app$userid,
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


ullme_handle_course_settings_save = function(coursename="", times=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_course_settings_save")
  if (is.null(app$courseid) || !nzchar(app$courseid)) return(invisible(NULL))
  course = list(courseid=app$courseid, coursename=coursename, times=times)
  ullme_save_course_settings(app=app, course=course)
  ullme_send_course_state(app=app)
  invisible(course)
}


ullme_handle_material_category = function(category="general", app=getApp(), ...) {
  restore.point("ullme_handle_material_category")
  category = paste0(category)[1]
  if (!category %in% ullme_course_material_categories()) return(invisible(NULL))
  app$material_category = category
  invisible(app$material_category)
}


ullme_handle_material_upload_destination = function(path="general",
                                                     app=getApp(), ...) {
  restore.point("ullme_handle_material_upload_destination")
  app$material_upload_directory = ""
  original_path = paste0(path)[1]
  result = tryCatch({
    course_dir = ullme_active_course_dir(app=app)
    if (is.null(course_dir)) stop("Select a course first.")
    path = .ullme_material_relative_path(path)
    category = strsplit(path, "/", fixed=TRUE)[[1]][[1]]
    if (!category %in% ullme_course_material_categories()) {
      stop("Invalid material upload category.")
    }
    material_dir = file.path(course_dir, "materials")
    target = .ullme_material_path(material_dir, path, must_exist=TRUE)
    if (!dir.exists(target)) stop("The material upload destination is not a directory.")
    app$material_category = category
    app$material_upload_directory = path
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
  if (!category %in% ullme_course_material_categories()) category = app$material_category
  if (is.null(category) || !category %in% ullme_course_material_categories()) category = "general"
  app$material_category = category
  on.exit({
    app$material_upload_directory = category
  }, add=TRUE)
  result = tryCatch({
    destination = paste0(app$material_upload_directory %||% "")[1]
    if (is.na(destination) || !nzchar(destination)) {
      stop("No valid material upload destination was selected.")
    }
    destination_category = strsplit(destination, "/", fixed=TRUE)[[1]][[1]]
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
  app$courseids = ullme_user_courseids(
    main_dir=app$glob$main_dir,
    userid=app$userid,
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


ullme_course_summary_for_js = function(app=getApp()) {
  restore.point("ullme_course_summary_for_js")
  summary = ullme_course_summary(app=app)
  if (is.null(summary)) {
    summary = list(course=NULL, material=list())
  } else {
    summary$material = lapply(summary$material, as.list)
  }
  if (identical(app$role, "teacher")) {
    summary$ai_tutors = ullme_course_ai_tutors(app=app)
    summary$ai_tutor_catalog = ullme_ai_tutor_catalog(app=app)
    summary$skills = ullme_skill_catalog_for_js(app=app)
    summary$course_skills = ullme_course_skills_for_js(app=app)
    summary$active_skill = ullme_skill_for_js(ullme_active_skill(app=app))
    course_dir = ullme_active_course_dir(app=app)
    summary$course_files = if (is.null(course_dir)) list() else
      ullme_course_file_records(course_dir)
    summary$material_tree = if (is.null(course_dir)) list() else
      ullme_material_tree(file.path(course_dir, "materials"))
  } else {
    summary$ai_tutors = list()
    summary$ai_tutor_catalog = list()
    summary$skills = list()
    summary$course_skills = list()
    summary$active_skill = NULL
    summary$course_files = list()
    course_dir = ullme_active_course_dir(app=app)
    summary$material_tree = if (is.null(course_dir)) list() else
      ullme_material_tree(file.path(course_dir, "materials"))
  }
  summary
}


ullme_init_app = function(app=getApp()) {
  restore.point("ullme_init_app")
  ullme_init_storage(main_dir=app$glob$main_dir, app=app)
  ullme_send_course_state(app=app)
  ullme_refresh_model_catalog(app=app)
}


ullme_handle_chat_submit = function(id=NULL, text="", model=NULL, skillid=NULL,
                                  context=NULL, uploads=NULL,
                                  clientMessageId=NULL, assistantMessageId=NULL,
                                  session=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_chat_submit")
  text = paste0(text, collapse="\n")
  has_uploads = length(uploads) > 0
  if (!nzchar(trimws(text)) && !has_uploads) return(invisible(NULL))

  ai_input = if (nzchar(trimws(text))) text else "[uploaded image]"
  skill = ullme_active_skill(app=app)
  requested_skillid = paste0(skillid %||% "")[1]
  if (!is.null(skill) && nzchar(requested_skillid) && !identical(requested_skillid, skill$skillid)) {
    skill = NULL
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
    c(if (is.null(skill)) NULL else skill$instructions, context_instruction),
    collapse="\n\n"
  )
  if (!nzchar(system_instructions)) system_instructions = NULL
  answer = tryCatch(
    ullme_ask_ai(
      input=ai_input,
      model=model,
      context=context %||% list(),
      system_instructions=system_instructions,
      app=app
    ),
    error=function(e) paste0(
      "I could not reach the configured model: ",
      ullme_safe_ai_error(e, app$api_config)
    )
  )
  if (is.null(assistantMessageId) || !nzchar(assistantMessageId)) {
    assistantMessageId = paste0("assistant_", as.integer(runif(1, 1, 1e9)))
  }
  callJS(
    .fun = "window.ullme.receiveAssistantMessage",
    .args = list(
      assistantMessageId,
      answer,
      ullme_chat_output_html(answer, app=app)
    ),
    .app = app
  )
  invisible(answer)
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
  urls = paste("ullme-uploads", session_dir, target_names, sep="/")
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
  x = gsub("[^A-Za-z0-9._-]+", "_", x)
  x = gsub("^_+|_+$", "", x)
  x[!nzchar(x)] = "upload"
  x
}


ullme_uses_fake_ai = function(app=getApp()) {
  restore.point("ullme_uses_fake_ai")
  if (!is.null(app$api_config$provider)) {
    return(identical(app$api_config$provider, "fake"))
  }
  if (is.null(app$uses_fake_ai)) return(TRUE)
  isTRUE(app$uses_fake_ai)
}
