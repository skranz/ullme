ullme_user_settings_path = function(app=getApp()) {
  file.path(app$user_dir, "settings.yaml")
}


ullme_default_user_settings = function() {
  list(
    agent_tools=list(
      approval=list(
        default="ask",
        read="allow",
        copy_materials="ask",
        rewrite_definitions="ask",
        rewrite_course_files="ask",
        write_object_indexes="ask",
        undo="ask"
      )
    )
  )
}


ullme_normalize_approval_policy = function(value, default="ask") {
  value = tolower(paste0(value %||% default)[1])
  if (!value %in% c("allow", "ask", "deny")) default else value
}


ullme_normalize_user_settings = function(settings) {
  defaults = ullme_default_user_settings()
  if (!is.list(settings)) settings = list()
  settings = utils::modifyList(defaults, settings)
  approval = settings$agent_tools$approval
  for (name in names(defaults$agent_tools$approval)) {
    approval[[name]] = ullme_normalize_approval_policy(
      approval[[name]],
      defaults$agent_tools$approval[[name]]
    )
  }
  settings$agent_tools$approval = approval
  settings
}


ullme_read_user_settings = function(app=getApp()) {
  path = ullme_user_settings_path(app=app)
  if (!file.exists(path)) return(ullme_default_user_settings())
  settings = tryCatch(
    yaml::read_yaml(path, eval.expr=FALSE),
    error=function(e) NULL
  )
  ullme_normalize_user_settings(settings)
}


ullme_agent_approval_policy = function(action, app=getApp()) {
  settings = ullme_read_user_settings(app=app)
  approval = settings$agent_tools$approval
  action = paste0(action)[1]
  ullme_normalize_approval_policy(approval[[action]] %||% approval$default)
}


ullme_user_settings_yaml = function(settings) {
  trimws(yaml::as.yaml(ullme_normalize_user_settings(settings)))
}


ullme_agent_settings_payload = function(app=getApp()) {
  settings = ullme_read_user_settings(app=app)
  list(
    approval=settings$agent_tools$approval,
    history=ullme_change_history(app=app, limit=30L)
  )
}


ullme_send_agent_settings = function(app=getApp()) {
  payload = ullme_agent_settings_payload(app=app)
  callJS(
    .fun="window.ullme.openAgentSettings",
    .args=list(payload),
    .app=app
  )
  invisible(payload)
}


ullme_handle_agent_settings_open = function(app=getApp(), ...) {
  if (!identical(app$role, "teacher")) return(invisible(FALSE))
  ullme_send_agent_settings(app=app)
  invisible(TRUE)
}


ullme_handle_agent_settings_save = function(default="ask", copy_materials="ask",
                                             rewrite_definitions="ask",
                                             rewrite_course_files="ask",
                                             write_object_indexes="ask",
                                             undo="ask", app=getApp(), ...) {
  if (!identical(app$role, "teacher")) return(invisible(FALSE))
  settings = ullme_read_user_settings(app=app)
  values = list(
    default=default,
    read="allow",
    copy_materials=copy_materials,
    rewrite_definitions=rewrite_definitions,
    rewrite_course_files=rewrite_course_files,
    write_object_indexes=write_object_indexes,
    undo=undo
  )
  settings$agent_tools$approval = lapply(values, ullme_normalize_approval_policy)
  operation = ullme_new_change(
    action="user_settings",
    summary="Update agent-tool approval settings",
    origin="ui",
    changes=list(ullme_change_write(
      ullme_user_settings_path(app=app),
      ullme_user_settings_yaml(settings)
    )),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  ullme_send_agent_settings(app=app)
  invisible(result)
}
