example = function() {
  library(ullme)
  restore.point.options(display.restore.point = TRUE)
  main_dir = "C:/libraries/ullme/ullme_main"
  app = ullmeApp(main_dir)
  viewApp(app,launch.browser = TRUE)
}

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

ullmeApp = function(main_dir, username="skranz", role="teacher", allowed_roles = c("teacher","student", "admin"), uses_fake_ai=TRUE) {
  restore.point("ullmeApp")
  app = eventsApp()
  glob = app$glob

  # app is per Shiny app instance; app$glob is shared across all instances.
  # Store only truly shared values in glob and keep user-specific state on app.
  glob$main_dir = main_dir
  app$username = ullme_clean_user_name(username)
  app$allowed_roles = ullme_normalize_roles(allowed_roles)
  app$role = ullme_normalize_role(role)
  if (!app$role %in% app$allowed_roles) {
    stop("role must be one of allowed_roles.")
  }
  app$semester = ullme_semester()
  app$uses_fake_ai = uses_fake_ai
  app$user_dir = ullme_user_dir(main_dir=main_dir, username=app$username)
  app$role_user_dir = ullme_role_user_dir(main_dir=main_dir, username=app$username, role=app$role)
  app$cur_session_dir = ullme_cur_session_dir(user_dir=app$user_dir)
  app$uploads_dir = ullme_cur_session_images_dir(cur_session_dir=app$cur_session_dir)
  app$audio_dir = ullme_cur_session_audio_dir(cur_session_dir=app$cur_session_dir)
  app$courseids = ullme_user_courseids(
    main_dir=main_dir,
    username=app$username,
    role=app$role,
    semester=app$semester
  )
  app$courseid = ullme_selected_courseid(app$courseids)
  app$material_category = "general"

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

  shiny::addResourcePath(prefix="ullme", directoryPath=www_dir)
  shiny::addResourcePath(prefix="ullme-uploads", directoryPath=app$uploads_dir)
  shiny::addResourcePath(prefix="ullme-audio", directoryPath=app$audio_dir)
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
  eventHandler(
    eventId = "ullme_role_select_event",
    id = NULL,
    fun = ullme_handle_role_select,
    app = app
  )
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
    eventId = "ullme_material_delete_event",
    id = NULL,
    fun = ullme_handle_material_delete,
    app = app
  )
  ullme_register_audio_handlers(app=app)
  invisible(TRUE)
}


ullme_app_ui = function(app=getApp()) {
  restore.point("ullme_app_ui")
  intro = ullme_intro_msg()
  tagList(
  tags$head(
      tags$meta(name="viewport", content="width=device-width, initial-scale=1"),
      tags$link(rel="stylesheet", type="text/css", href="ullme/ullme-chat.css"),
      tags$script(src="ullme/ullme-chat.js"),
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
          tags$div(
            class = "ullme-workspace",
            ullme_course_workspace_ui(app=app),
            tags$section(
              class = "ullme-chat-pane",
              tags$section(
                id = "ullme_chat_messages",
                class = "ullme-chat-messages",
                `data-intro-role` = intro$role,
                `data-intro-text` = intro$text,
                `data-intro-meta` = intro$meta
              ),
              ullme_composer_ui()
            )
          )
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
        tags$input(type="text", value=app$username, readonly="readonly")
      )
    )
  )
}


ullme_context_controls_ui = function(app=getApp()) {
  restore.point("ullme_context_controls_ui")
  semesters = ullme_semester_sequence(center=app$semester)
  show_courses = app$role %in% c("teacher", "student")
  tags$div(
    class = "ullme-context-controls",
    tags$div(
      class = "ullme-sidebar-context",
      tags$button(
        id = "ullme_role_select",
        class = "ullme-sidebar-value",
        type = "button",
        `data-value` = app$role,
        `data-options` = paste(app$allowed_roles, collapse="|"),
        `data-kind` = "role",
        `aria-label` = "Role",
        ullme_title_case(app$role),
        tags$span(class = "ullme-sidebar-value-arrow", HTML("&#9662;"))
      ),
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
        class = paste(
          "ullme-sidebar-value ullme-course-select",
          if (!show_courses) "ullme-course-select-hidden" else ""
        ),
        type = "button",
        `data-value` = app$courseid,
        `data-options` = paste(app$courseids, collapse="|"),
        `data-kind` = "course",
        `aria-label` = "Course",
        if (nzchar(app$courseid)) app$courseid else "Course",
        tags$span(class = "ullme-sidebar-value-arrow", HTML("&#9662;"))
      )
    ),
    tags$button(
      id = "ullme_add_course_btn",
      class = paste(
        "ullme-icon-button ullme-add-course-button",
        if (!show_courses) "ullme-add-course-button-hidden" else ""
      ),
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
    ullme_course_tabs_ui(app=app),
    tags$section(
      id = "ullme_activities_panel",
      class = "ullme-course-content-panel ullme-course-content-panel-active",
      `data-course-panel` = "activities"
    ),
    ullme_material_ui(app=app),
    ullme_course_settings_ui(app=app)
  )
}


ullme_course_tabs_ui = function(app=getApp()) {
  restore.point("ullme_course_tabs_ui")
  active = !is.null(app$courseid) && nzchar(app$courseid)
  tags$nav(
    id = "ullme_course_tabs",
    class = paste("ullme-course-tabs", if (!active) "ullme-course-tabs-hidden" else ""),
    tags$button(class="ullme-course-tab ullme-course-tab-active", type="button", `data-course-panel`="activities", "Activities"),
    tags$button(class="ullme-course-tab", type="button", `data-course-panel`="materials", "Materials"),
    tags$button(class="ullme-course-tab", type="button", `data-course-panel`="settings", "Settings")
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
  categories = ullme_course_material_categories()
  tags$section(
    id = "ullme_material_panel",
    class = "ullme-material ullme-course-content-panel",
    `data-course-panel` = "materials",
    tags$div(
      class = "ullme-panel-inner",
      tags$div(
        class = "ullme-panel-head",
        tags$div(class="ullme-panel-title", "Materials"),
        tags$button(
          id = "ullme_material_upload_btn",
          class = "ullme-primary-action",
          type = "button",
          "Upload"
        )
      ),
      tags$div(
        id = "ullme_material_categories",
        class = "ullme-material-categories",
        lapply(seq_along(categories), function(i) {
          category = categories[[i]]
          tags$button(
            class = paste("ullme-material-category", if (i == 1) "ullme-material-category-active" else ""),
            type = "button",
            `data-category` = category,
            ullme_material_category_label(category)
          )
        })
      ),
      tags$div(
        id = "ullme_material_dropzone",
        class = "ullme-material-dropzone",
        tabindex = "0",
        tags$div(class="ullme-material-dropzone-title", "Drop files here"),
        tags$div(
          class="ullme-material-dropzone-meta",
          "Upload to ",
          tags$span(id="ullme_material_drop_label", ullme_material_category_label(categories[[1]]))
        )
      ),
      tags$div(id="ullme_material_files", class="ullme-material-files")
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
    meta = "Thought for a couple of seconds",
    text = "Hi! I am ullme. What would you like to try today?"
  )
}


ullme_composer_ui = function() {
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
        tags$option(value="high", selected="selected", "High"),
        tags$option(value="fast", "Fast"),
        tags$option(value="local", "Local")
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
    user = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="4"></circle><path d="M4 21a8 8 0 0 1 16 0"></path></svg>'
  )
  icons[[name]]
}


ullme_handle_role_select = function(role=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_role_select")
  role = paste0(role)[1]
  if (is.na(role)) return(invisible(NULL))
  role = tryCatch(ullme_normalize_role(role), error=function(e) "")
  if (!role %in% app$allowed_roles) return(invisible(NULL))

  app$role = role
  app$role_user_dir = ullme_role_user_dir(
    main_dir=app$glob$main_dir,
    username=app$username,
    role=app$role
  )
  ullme_refresh_course_state(app=app)
  ullme_send_course_state(app=app)
  invisible(app$role)
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


ullme_handle_add_course = function(courseid=NULL, coursename="", times=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_add_course")
  if (!app$role %in% c("teacher", "student")) return(invisible(NULL))
  courseid = tryCatch(ullme_clean_courseid(courseid), error=function(e) "")
  if (!nzchar(courseid)) return(invisible(NULL))

  ullme_make_course(
    main_dir=app$glob$main_dir,
    username=app$username,
    role=app$role,
    semester=app$semester,
    courseid=courseid,
    coursename=coursename
  )
  app$courseid = courseid
  course = list(courseid=courseid, coursename=paste0(coursename)[1], times=times)
  ullme_save_course_settings(app=app, course=course)
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


ullme_handle_material_upload = function(id, value, app=getApp(), ...) {
  restore.point("ullme_handle_material_upload")
  if (is.null(value) || NROW(value) == 0) return(invisible(NULL))
  category = sub("^ullme_material_upload_", "", paste0(id)[1])
  if (!category %in% ullme_course_material_categories()) category = app$material_category
  if (is.null(category) || !category %in% ullme_course_material_categories()) category = "general"
  app$material_category = category
  ullme_store_material_uploads(app=app, value=value, category=category)
  ullme_send_course_state(app=app)
  callJS(
    .fun = "window.ullme.materialUploadComplete",
    .args = list(id),
    .app = app
  )
  invisible(TRUE)
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


ullme_refresh_course_state = function(app=getApp()) {
  restore.point("ullme_refresh_course_state")
  app$courseids = ullme_user_courseids(
    main_dir=app$glob$main_dir,
    username=app$username,
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
      app$role,
      app$semester
    ),
    .app = app
  )
  invisible(TRUE)
}


ullme_course_summary_for_js = function(app=getApp()) {
  restore.point("ullme_course_summary_for_js")
  summary = ullme_course_summary(app=app)
  if (is.null(summary)) return(NULL)
  summary$material = lapply(summary$material, as.list)
  summary
}


ullme_init_app = function(app=getApp()) {
  restore.point("ullme_init_app")
  ullme_init_storage(main_dir=app$glob$main_dir, app=app)
  ullme_send_course_state(app=app)
}


ullme_handle_chat_submit = function(id=NULL, text="", model=NULL, uploads=NULL,
                                  clientMessageId=NULL, assistantMessageId=NULL,
                                  session=NULL, app=getApp(), ...) {
  restore.point("ullme_handle_chat_submit")
  text = paste0(text, collapse="\n")
  has_uploads = length(uploads) > 0
  if (!nzchar(trimws(text)) && !has_uploads) return(invisible(NULL))

  ai_input = if (nzchar(trimws(text))) text else "[uploaded image]"
  answer = ullme_ask_ai(input=ai_input, uses_fake_ai=ullme_uses_fake_ai(app=app))
  if (is.null(assistantMessageId) || !nzchar(assistantMessageId)) {
    assistantMessageId = paste0("assistant_", as.integer(runif(1, 1, 1e9)))
  }
  callJS(
    .fun = "window.ullme.receiveAssistantMessage",
    .args = list(assistantMessageId, answer),
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
  isTRUE(app$uses_fake_ai)
}
