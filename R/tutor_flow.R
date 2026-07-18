ullme_node_field_catalog = function() {
  path = system.file("specs", "tutor_node_fields.yml", package="ullme")
  if (!nzchar(path) || !file.exists(path)) {
    path = file.path("inst", "specs", "tutor_node_fields.yml")
  }
  if (!file.exists(path)) return(list())
  value = yaml::read_yaml(path, eval.expr=FALSE)
  value$groups %||% list()
}


ullme_node_field_picker_ui = function(prefix) {
  groups = ullme_node_field_catalog()
  options = lapply(groups, function(group) {
    fields = group$fields %||% list()
    tags$optgroup(
      label=paste0(group$label %||% "Fields")[1],
      lapply(fields, function(field) tags$option(
        value=paste0(field$path %||% "")[1],
        title=paste0(field$long %||% field$short %||% "")[1],
        `data-kind`=paste0(field$kind %||% "field")[1],
        `data-insert`=paste0(field$insert %||% "", collapse="\n"),
        `data-template`=paste0(field$template %||% "", collapse="\n"),
        `data-nested-template`=paste0(field$nested_template %||% "", collapse="\n"),
        paste0(field$label %||% field$path %||% "Field", " — ", field$short %||% "")
      ))
    )
  })
  tags$div(
    class="ullme-node-field-picker",
    tags$span(class="ullme-node-field-picker-label", "Insert"),
    tags$select(
      id=paste0(prefix, "_field"),
      `aria-label`="Insert a field or placeholder into the node YAML",
      title="Choose a field or runtime placeholder to insert into the node YAML.",
      tags$option(value="", "Choose…"),
      options
    ),
    tags$span(
      id=paste0(prefix, "_field_help"),
      class="ullme-node-field-help", title="Choose a field to see its description.",
      `aria-label`="Field description", "?"
    )
  )
}


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
        placeholder="new_node",
        title="Renaming a node also updates start_node, next, and switch_to references."
      )
    ),
    ullme_node_field_picker_ui("ullme_node_editor"),
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
                                            app=getApp(),
                                            original_nodeid=NULL) {
  restore.point("ullme_save_course_ai_tutor_node")
  if (!identical(app$role, "teacher")) stop("Only teachers can edit AI Tutors.")
  tutorid = ullme_clean_definition_id(tutorid)
  nodeid = ullme_clean_tutor_node_id(nodeid)
  action = match.arg(action)
  original_nodeid = if (is.null(original_nodeid) ||
      !nzchar(paste0(original_nodeid %||% "")[1])) {
    nodeid
  } else {
    ullme_clean_tutor_node_id(original_nodeid)
  }
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

  exists = original_nodeid %in% names(nodes)
  if (identical(action, "create") && exists) {
    stop("A workflow node named '", nodeid, "' already exists.")
  }
  if (action %in% c("save", "delete") && !exists) {
    stop("The workflow node '", original_nodeid, "' no longer exists.")
  }

  if (identical(action, "delete")) {
    nodes[[original_nodeid]] = NULL
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
    if (identical(action, "save") && !identical(nodeid, original_nodeid)) {
      if (nodeid %in% names(nodes)) {
        stop("A workflow node named '", nodeid, "' already exists.")
      }
      names(nodes)[match(original_nodeid, names(nodes))] = nodeid
      if (identical(paste0(definition$start_node %||% "")[1], original_nodeid)) {
        definition$start_node = nodeid
      }
      nodes = lapply(nodes, function(item) {
        if (!is.list(item)) return(item)
        if (identical(paste0(item[["next"]] %||% "")[1], original_nodeid)) {
          item[["next"]] = nodeid
        }
        if (is.list(item$switch_to)) {
          item$switch_to = lapply(item$switch_to, function(target) {
            if (identical(paste0(target %||% "")[1], original_nodeid)) {
              nodeid
            } else {
              target
            }
          })
        }
        item
      })
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
      original_nodeid=original_nodeid,
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
                                       original_nodeid=NULL,
                                       app=getApp(), ...) {
  restore.point("ullme_handle_ai_tutor_node")
  result = tryCatch({
    saved = ullme_save_course_ai_tutor_node(
      tutorid=tutorid,
      nodeid=nodeid,
      action=action,
      original_nodeid=original_nodeid,
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
