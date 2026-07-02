studentApp = function(main_dir, userid="student", teacherid=NULL,
                       uses_fake_ai=NULL, max_upload_mb=100,
                       api_key_file=NULL,
                       api_provider=c("fake", "nvidia", "local"),
                       api_model=NULL, api_base_url=NULL) {
  restore.point("studentApp")
  .ullme_app(
    main_dir=main_dir,
    userid=userid,
    role="student",
    teacherid=teacherid,
    uses_fake_ai=uses_fake_ai,
    max_upload_mb=max_upload_mb,
    api_key_file=api_key_file,
    api_provider=api_provider,
    api_model=api_model,
    api_base_url=api_base_url
  )
}


ullme_student_context_controls_ui = function(app=getApp()) {
  restore.point("ullme_student_context_controls_ui")
  ullme_fixed_context_controls_ui(
    app=app,
    role_label="Student",
    allow_add_course=FALSE
  )
}


ullme_student_workspace_ui = function(app=getApp()) {
  restore.point("ullme_student_workspace_ui")
  tags$div(
    class="ullme-workspace ullme-student-workspace",
    ullme_chat_pane_ui(app=app, show_header=FALSE)
  )
}
