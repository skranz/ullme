

example = function() {
  library(ullme)
  restore.point.options(display.restore.point = TRUE)
  main_dir = "C:/libraries/ullme/ullme_main"
  api_key_file = "C:/libraries/ullme/nvidia_api_key.txt"
  app = teacherApp(
    main_dir,
    api_key_file = api_key_file,
    api_provider = "nvidia",
    stream_chat = TRUE,
    stream_backend = "custom",
    sync_chat = FALSE,
    catch_chat_errors = FALSE,
    chat_debug = TRUE,
    enable_ai_tools = FALSE,
    show_chat_thinking = FALSE,
    userid="sebastian_kranz",
    teacherid = "skranz"
  )

  #app = teacherApp(main_dir, api_key_file = "C:/libraries/ullme/nvidia_api_key.txt", api_provider="nvidia")
  viewApp(app,launch.browser = TRUE)
}

teacherApp = function(main_dir, userid="skranz", teacherid=NULL,
                       uses_fake_ai=NULL, max_upload_mb=100,
                       api_key_file=NULL,
                       api_provider=c("fake", "nvidia", "local"),
                       api_model=NULL, api_base_url=NULL,
                       render_chat_markdown=TRUE,
                       stream_chat=TRUE,
                       stream_backend=c("ellmer", "custom")[2],
                       catch_chat_errors=TRUE,
                       chat_debug=FALSE,
                       sync_chat=FALSE,
                       enable_ai_tools=TRUE,
                       show_chat_thinking=TRUE,
                       store_ai_interactions=FALSE,
                       base_url_student="",
                       login_check=c("none", "sel"),
                       login_args=list(),
                       email2userid=ullme_email2userid) {
  restore.point("teacherApp")
  if (is.null(teacherid)) teacherid = userid
  .ullme_app(
    main_dir=main_dir,
    userid=userid,
    role="teacher",
    teacherid=teacherid,
    uses_fake_ai=uses_fake_ai,
    max_upload_mb=max_upload_mb,
    render_chat_markdown=render_chat_markdown,
    api_key_file=api_key_file,
    api_provider=api_provider,
    api_model=api_model,
    api_base_url=api_base_url,
    stream_chat=stream_chat,
    stream_backend=stream_backend,
    catch_chat_errors=catch_chat_errors,
    chat_debug=chat_debug,
    sync_chat=sync_chat,
    enable_ai_tools=enable_ai_tools,
    show_chat_thinking=show_chat_thinking,
    store_ai_interactions=store_ai_interactions,
    base_url_student=base_url_student,
    login_check=login_check,
    login_args=login_args,
    email2userid=email2userid
  )
}


ullme_teacher_context_controls_ui = function(app=getApp()) {
  restore.point("ullme_teacher_context_controls_ui")
  ullme_fixed_context_controls_ui(
    app=app,
    role_label="Teacher",
    allow_add_course=TRUE
  )
}


ullme_teacher_workspace_ui = function(app=getApp()) {
  restore.point("ullme_teacher_workspace_ui")
  tags$div(
    class = "ullme-workspace",
    ullme_studio_navigation_ui(app=app),
    tags$button(
      class="ullme-pane-resizer ullme-pane-resizer-nav",
      type="button",
      `data-pane-resizer`="nav",
      `aria-label`="Resize teacher navigation",
      title="Drag to resize navigation"
    ),
    tags$section(
      class="ullme-studio-main",
      ullme_course_workspace_ui(app=app),
      tags$div(id="ullme_definition_mount", class="ullme-definition-mount")
    ),
    tags$button(
      class="ullme-pane-resizer ullme-pane-resizer-ai",
      type="button",
      `data-pane-resizer`="ai",
      `aria-label`="Resize AI assistant",
      title="Drag to resize AI assistant"
    ),
    ullme_chat_pane_ui(app=app, show_header=TRUE)
  )
}
