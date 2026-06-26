example = function() {
  library(ullme)
  restore.point.options(display.restore.point = TRUE)
  main_dir = "C:/libraries/ullme/ullme_main"
  app = ullmeApp(main_dir)
  viewApp(app,launch.browser = TRUE)
}


ullmeApp = function(main_dir, username="skranz", role="teacher", uses_fake_ai=TRUE) {
  restore.point("ullmeApp")
  app = eventsApp()
  glob = app$glob
  glob$main_dir = main_dir
  glob$username = ullme_clean_user_name(username)
  glob$role = ullme_normalize_role(role)
  glob$uses_fake_ai = uses_fake_ai
  glob$user_dir = ullme_user_dir(main_dir=main_dir, username=glob$username)
  glob$role_user_dir = ullme_role_user_dir(main_dir=main_dir, username=glob$username, role=glob$role)
  glob$cur_session_dir = ullme_cur_session_dir(user_dir=glob$user_dir)
  glob$uploads_dir = ullme_cur_session_images_dir(cur_session_dir=glob$cur_session_dir)
  glob$audio_dir = ullme_cur_session_audio_dir(cur_session_dir=glob$cur_session_dir)

  ullme_add_resource_paths(app=app)
  app$ui = ullme_app_ui()
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
  dir.create(app$glob$uploads_dir, recursive=TRUE, showWarnings=FALSE)
  dir.create(app$glob$audio_dir, recursive=TRUE, showWarnings=FALSE)

  shiny::addResourcePath(prefix="ullme", directoryPath=www_dir)
  shiny::addResourcePath(prefix="ullme-uploads", directoryPath=app$glob$uploads_dir)
  shiny::addResourcePath(prefix="ullme-audio", directoryPath=app$glob$audio_dir)
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
  dir.create(app$glob$cur_session_dir, recursive=TRUE, showWarnings=FALSE)
  dir.create(app$glob$uploads_dir, recursive=TRUE, showWarnings=FALSE)
  dir.create(app$glob$audio_dir, recursive=TRUE, showWarnings=FALSE)
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
  ullme_register_audio_handlers(app=app)
  invisible(TRUE)
}


ullme_app_ui = function() {
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
        class = "ullme-app",
        tags$aside(
          class = "ullme-sidebar",
          tags$button(
            id = "ullme_sidebar_close",
            class = "ullme-icon-button ullme-sidebar-close",
            type = "button",
            `aria-label` = "Hide sidebar",
            title = "Hide sidebar",
            HTML(ullme_icon_svg("panel"))
          ),
          tags$div(
            class = "ullme-brand",
            tags$div(class="ullme-brand-title", "uLLMe", title="Uni Ulm LLM for Economics Education: klein zählt doppelt!"),
            tags$div(class="ullme-brand-note", "created by Sebastian Kranz")
          )
        ),
        tags$main(
          class = "ullme-main",
          tags$header(
            class = "ullme-topbar",
            tags$button(
              id = "ullme_sidebar_toggle",
              class = "ullme-icon-button ullme-sidebar-toggle",
              type = "button",
              `aria-label` = "Toggle sidebar",
              title = "Show sidebar",
              HTML(ullme_icon_svg("panel"))
            ),
            tags$div(class="ullme-chat-title", "Example chat"),
            tags$div(class="ullme-topbar-actions")
          ),
          tags$section(
            id = "ullme_chat_messages",
            class = "ullme-chat-messages",
            `data-intro-role` = intro$role,
            `data-intro-text` = intro$text,
            `data-intro-meta` = intro$meta
          ),
          ullme_composer_ui()
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
        )
      )
    )
  )
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
    send = '<svg class="ullme-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14"></path><path d="M13 6l6 6-6 6"></path></svg>'
  )
  icons[[name]]
}


ullme_init_app = function(app=getApp()) {
  restore.point("ullme_init_app")
  ullme_init_storage(main_dir=app$glob$main_dir, app=app)
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
  file.path(app$glob$uploads_dir, ullme_session_dir_name(session=session))
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
  isTRUE(app$glob$uses_fake_ai)
}
