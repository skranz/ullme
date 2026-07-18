ullme_tutor_node_editor_ui = function() {
  restore.point("ullme_tutor_node_editor_ui")
  tags$section(
    id="ullme_node_editor_panel",
    class="ullme-assistant-panel ullme-node-editor-panel",
    role="tabpanel",
    `aria-labelledby`="ullme_node_editor_tab",
    tags$div(
      class="ullme-node-editor-head",
      tags$strong(id="ullme_node_editor_title", "Workflow node"),
      tags$button(
        id="ullme_node_editor_new",
        class="ullme-secondary-action",
        type="button",
        "New node"
      )
    ),
    tags$label(
      class="ullme-node-editor-field",
      tags$span("Node ID"),
      tags$input(
        id="ullme_node_editor_id",
        type="text",
        autocomplete="off",
        spellcheck="false",
        placeholder="new_node"
      )
    ),
    tags$label(
      class="ullme-node-editor-field ullme-node-editor-yaml-field",
      tags$span("Node YAML"),
      tags$textarea(
        id="ullme_node_editor_yaml",
        spellcheck="false",
        `aria-label`="Workflow node YAML"
      )
    ),
    tags$div(
      id="ullme_node_editor_status",
      class="ullme-node-editor-status",
      role="status",
      `aria-live`="polite",
      "Click a node in the diagram, or create a new node."
    ),
    tags$div(
      class="ullme-node-editor-actions",
      tags$button(
        id="ullme_node_editor_delete",
        class="ullme-danger-action",
        type="button",
        "Delete node"
      ),
      tags$button(
        id="ullme_node_editor_save",
        class="ullme-primary-action",
        type="button",
        "Save node"
      )
    )
  )
}


ullme_clean_tutor_node_id = function(nodeid) {
  restore.point("ullme_clean_tutor_node_id")
  nodeid = paste0(nodeid %||% "")[1]
  if (is.na(nodeid) || !grepl("^[A-Za-z][A-Za-z0-9_]*$", nodeid)) {
    stop(
      "Node IDs must start with a letter and contain only letters, numbers, or underscores.",
      call.=FALSE
    )
  }
  nodeid
}


ullme_save_course_ai_tutor_node = function(tutorid, nodeid,
                                            action=c("save", "create", "delete"),
                                            yaml_content=NULL,
                                            app=getApp()) {
  restore.point("ullme_save_course_ai_tutor_node")
  if (!identical(app$role, "teacher")) stop("Only teachers can edit AI Tutors.")
  tutorid = ullme_clean_definition_id(tutorid)
  nodeid = ullme_clean_tutor_node_id(nodeid)
  action = match.arg(action)
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) stop("Select a course first.")
  path = ullme_existing_course_ai_tutor_path(course_dir, tutorid)
  if (!file.exists(path)) stop("This AI Tutor is not part of the course.")
  definition = yaml::read_yaml(path)
  if (!is.list(definition)) stop("The course AI Tutor YAML is invalid.")
  nodes = definition$nodes %||% list()
  if (!is.list(nodes) || is.null(names(nodes))) {
    stop("The course AI Tutor has no valid node mapping.")
  }

  exists = nodeid %in% names(nodes)
  if (identical(action, "create") && exists) {
    stop("A workflow node named '", nodeid, "' already exists.")
  }
  if (action %in% c("save", "delete") && !exists) {
    stop("The workflow node '", nodeid, "' no longer exists.")
  }

  if (identical(action, "delete")) {
    nodes[[nodeid]] = NULL
  } else {
    parsed = ullme_parse_yaml_text(
      paste0(yaml_content %||% "", collapse="\n"),
      label=paste0("Node ", nodeid)
    )
    ullme_validation_stop(parsed, prefix="Node YAML is invalid")
    node = parsed$value
    if (!is.list(node) || is.null(names(node)) || !length(node)) {
      stop("Node YAML must be a non-empty YAML mapping.", call.=FALSE)
    }
    nodes[[nodeid]] = node
  }
  definition$nodes = nodes
  content = ullme_ai_tutor_yaml(definition)
  validity = ullme_tutor_validation_state(tutorid=tutorid, content=content)

  operation = ullme_new_change(
    action="definition_edit",
    summary=paste0(
      if (identical(action, "delete")) "Delete" else
        if (identical(action, "create")) "Create" else "Save",
      " workflow node ", nodeid, " in ", tutorid
    ),
    origin="ui",
    details=list(
      kind="tutor_node",
      definitionid=tutorid,
      nodeid=nodeid,
      action=action,
      source="course"
    ),
    changes=list(ullme_change_write(path, content)),
    app=app
  )
  result = ullme_submit_change(operation, app=app)
  if (!isTRUE(result$ok)) stop(result$message %||% "Could not update the workflow node.")
  result$validation = validity
  result
}


ullme_handle_ai_tutor_node = function(tutorid=NULL, nodeid=NULL,
                                       action="save", yaml_content=NULL,
                                       app=getApp(), ...) {
  restore.point("ullme_handle_ai_tutor_node")
  result = tryCatch({
    saved = ullme_save_course_ai_tutor_node(
      tutorid=tutorid,
      nodeid=nodeid,
      action=action,
      yaml_content=yaml_content,
      app=app
    )
    ullme_send_course_state(app=app)
    list(
      ok=TRUE,
      message=paste0("Workflow node ", action, "d."),
      tutorid=tutorid,
      nodeid=nodeid,
      action=action,
      validation=saved$validation
    )
  }, error=function(error) {
    list(
      ok=FALSE,
      message=conditionMessage(error),
      tutorid=tutorid,
      nodeid=nodeid,
      action=action
    )
  })
  callJS(
    .fun="window.ullmeTutorFlow.nodeMutationComplete",
    .args=list(result),
    .app=app
  )
  invisible(result)
}
