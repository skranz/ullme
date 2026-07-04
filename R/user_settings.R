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
  override = paste0(app$agent_approval_override %||% "")[1]
  if (override %in% c("allow", "ask", "deny")) return(override)
  settings = ullme_read_user_settings(app=app)
  approval = settings$agent_tools$approval
  action = paste0(action)[1]
  ullme_normalize_approval_policy(approval[[action]] %||% approval$default)
}


ullme_user_settings_yaml = function(settings) {
  trimws(yaml::as.yaml(ullme_normalize_user_settings(settings)))
}

