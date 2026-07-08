ullme_tool_perm = function(course_must_exist=FALSE, only_teacher=TRUE,
                            mutates=FALSE) {
  restore.point("ullme_tool_perm")
  as.list(environment())
}


ullme_tool_registry = function() {
  restore.point("ullme_tool_registry")
  list(
    cur_user=list(
      description="Get the current user's ID, role, and allowed roles.",
      perm=ullme_tool_perm(only_teacher=FALSE)
    ),
    teacher_info=list(
      description="Get current-user project state, suggested next steps, or search the read-only uLLMe teacher information library.",
      perm=ullme_tool_perm(only_teacher=TRUE)
    ),
    list_courses=list(
      description="List courses owned by the current teacher, optionally for one semester.",
      perm=ullme_tool_perm(only_teacher=TRUE)
    ),
    list_material_files=list(
      description="List material files in one of the current teacher's courses.",
      perm=ullme_tool_perm(course_must_exist=TRUE)
    ),
    read_definition_yaml=list(
      description="Read the YAML metadata of an AI Tutor or Skill visible to the current teacher.",
      perm=ullme_tool_perm()
    ),
    list_ai_tutors=list(
      description="List the complete course-local AI Tutors in the selected course, including instance counts.",
      perm=ullme_tool_perm()
    ),
    read_tutor_instances_yaml=list(
      description="Read the complete instances.yml assignment YAML for a course AI Tutor.",
      perm=ullme_tool_perm()
    ),
    list_skills=list(
      description="List the Skill definitions visible to the current teacher, including source and description.",
      perm=ullme_tool_perm()
    ),
    read_course_file=list(
      description="Read an authorized text file from one of the current teacher's courses.",
      perm=ullme_tool_perm(course_must_exist=TRUE)
    ),
    list_changes=list(
      description="List recent ULLME-managed file changes that can be inspected or undone.",
      perm=ullme_tool_perm()
    ),
    change_status=list(
      description="Check whether a proposed change is pending, committed, rejected, or failed.",
      perm=ullme_tool_perm(),
      arguments=list(operation_id=list(required=TRUE))
    ),
    copy_material=list(
      description="Copy one material file between authorized folders or courses of the current teacher.",
      perm=ullme_tool_perm(course_must_exist=TRUE, mutates=TRUE)
    ),
    rewrite_definition_yaml=list(
      description="Validate and replace YAML for a course AI Tutor or editable personal Skill.",
      perm=ullme_tool_perm(mutates=TRUE)
    ),
    rewrite_tutor_instances_yaml=list(
      description="Validate and replace the complete instances.yml assignments for a course AI Tutor.",
      perm=ullme_tool_perm(mutates=TRUE)
    ),
    write_rtutor_instances_yaml=list(
      description="Validate and immediately write the complete instances.yml for the selected course AI Tutor using the backed-up transaction history, then return validation and assignment details.",
      perm=ullme_tool_perm(mutates=TRUE)
    ),
    convert_material_files=list(
      description="Convert one or several recursive material documents. Pandoc handles supported document formats; PDF supports only explicit conversion to txt via pdftotext. Paths are relative to materials and may be comma- or newline-separated; an empty or 'preferred' target uses the AI Tutor definition preference.",
      perm=ullme_tool_perm(course_must_exist=TRUE, mutates=TRUE)
    ),
    rewrite_course_text_file=list(
      description="Validate and replace a text file in one of the current teacher's courses.",
      perm=ullme_tool_perm(course_must_exist=TRUE, mutates=TRUE)
    ),
    undo_change=list(
      description="Undo a prior ULLME-managed change if none of its target files have changed since.",
      perm=ullme_tool_perm(mutates=TRUE)
    )
  )
}


ullme_tool = function(name, descr=NULL, perm=NULL, app=getApp()) {
  restore.point("ullme_tool")
  registry = ullme_tool_registry()
  spec = registry[[name]]
  if (is.null(spec)) stop("Unknown uLLMe tool: ", name)
  if (is.null(descr)) descr = spec$description
  if (is.null(perm)) perm = spec$perm

  fun_name = paste0("utool_", name)
  namespace = environment(ullme_tool)
  implementation = get(fun_name, envir=namespace, inherits=FALSE)
  implementation_formals = formals(implementation)
  hidden = c("app", "userid", "teacherid")
  tool_args = setdiff(names(implementation_formals), hidden)

  tool_fun = function() {
    args = as.list(environment())
    ullme_execute_tool(
      implementation=implementation,
      args=args,
      perm=perm,
      app=app
    )
  }
  formals(tool_fun) = implementation_formals[tool_args]
  environment(tool_fun) = list2env(
    list(
      implementation=implementation,
      perm=perm,
      app=app
    ),
    parent=namespace
  )

  ellmer::tool(
    fun=tool_fun,
    name=name,
    description=descr,
    arguments=ullme_tool_arg_defs(tool_args, specs=spec$arguments %||% list())
  )
}


ullme_tools = function(app=getApp()) {
  restore.point("ullme_tools")
  tool_names = names(ullme_tool_registry())
  tools = lapply(tool_names, ullme_tool, app=app)
  names(tools) = tool_names
  tools
}


ullme_execute_tool = function(implementation, args, perm, app=getApp()) {
  restore.point("ullme_execute_tool")
  checked = ullme_check_tool_args(args=args, perm=perm, app=app)
  if (!isTRUE(checked$ok)) {
    return(list(ok=FALSE, status="rejected", message=checked$message))
  }
  result = tryCatch(
    do.call(implementation, c(args, list(app=app))),
    error=function(e) list(ok=FALSE, status="error", message=conditionMessage(e))
  )
  if (is.list(result) &&
      identical(result$status %||% "", "pending_approval")) {
    return(ullme_wait_for_change_approval(result, app=app))
  }
  result
}


ullme_check_tool_args = function(args, perm=ullme_tool_perm(), app=getApp()) {
  restore.point("ullme_check_tool_args")
  if (is.null(app$userid) || !nzchar(app$userid)) {
    return(list(ok=FALSE, message="ULLME could not identify the current user."))
  }
  if (isTRUE(perm$only_teacher) && !identical(app$role, "teacher")) {
    return(list(ok=FALSE, message="This tool is available only in teacher mode."))
  }
  if (isTRUE(perm$course_must_exist) &&
      all(c("semester", "courseid") %in% names(args))) {
    semester = ullme_tool_semester(args$semester, app=app)
    courseid = tryCatch(ullme_clean_courseid(args$courseid), error=function(e) "")
    if (!nzchar(courseid) || !ullme_has_course(
      teacherid=app$userid,
      semester=semester,
      courseid=courseid,
      main_dir=app$glob$main_dir
    )) {
      return(list(
        ok=FALSE,
        message=paste0("Course ", courseid, " in semester ", semester,
                       " does not exist for the current teacher.")
      ))
    }
  }
  list(ok=TRUE)
}


ullme_has_course = function(teacherid, semester, courseid,
                             main_dir=ullme_main_dir()) {
  restore.point("ullme_has_course")
  dir.exists(file.path(
    main_dir, "teachers", ullme_clean_user_name(teacherid),
    "courses", semester, ullme_clean_courseid(courseid)
  ))
}


ullme_tool_semester = function(semester="sel", app=getApp()) {
  restore.point("ullme_tool_semester")
  semester = toupper(paste0(semester %||% "SEL")[1])
  if (semester %in% c("", "SEL")) return(app$semester)
  ullme_semester_index(semester)
  semester
}


ullme_tool_arg_defs = function(args, specs=list()) {
  restore.point("ullme_tool_arg_defs")
  definitions = ullme_tool_arg_spec(args=args, specs=specs)
  lapply(definitions, function(spec) {
    description = spec$description
    required = isTRUE(spec$required)
    switch(
      spec$type,
      string=ellmer::type_string(description, required=required),
      boolean=ellmer::type_boolean(description, required=required),
      number=ellmer::type_number(description, required=required),
      stop("Unsupported tool argument type: ", spec$type)
    )
  })
}


ullme_tool_arg_spec = function(args, specs=list()) {
  restore.point("ullme_tool_arg_spec")
  defaults = ullme_default_tool_arg_spec()
  fields = c("type", "description", "required")
  result = lapply(args, function(arg) {
    spec = utils::modifyList(defaults[[arg]] %||% list(), specs[[arg]] %||% list())
    missing = setdiff(fields, names(spec))
    if (length(missing) > 0) {
      stop("Incomplete specification for tool argument '", arg,
           "'. Missing: ", paste(missing, collapse=", "))
    }
    spec
  })
  names(result) = args
  result
}


ullme_default_tool_arg_spec = function() {
  restore.point("ullme_default_tool_arg_spec")
  list(
    semester=list(type="string", description="Semester such as WS2526 or SS27. Use 'sel' for the selected semester.", required=FALSE),
    topic=list(type="string", description="Information topic, for example overview, materials, tutors, skills, safety, project_state, or next_steps.", required=FALSE),
    query=list(type="string", description="Optional words to search for in the teacher information library.", required=FALSE),
    courseid=list(type="string", description="Course ID owned by the current teacher.", required=TRUE),
    category=list(type="string", description="Material category: general, slides, ps, quiz, or background.", required=FALSE),
    source_semester=list(type="string", description="Source semester, or 'sel' for the selected semester.", required=FALSE),
    source_courseid=list(type="string", description="Source course ID.", required=TRUE),
    source_category=list(type="string", description="Source material category.", required=TRUE),
    source_path=list(type="string", description="Relative source file path within its material category.", required=TRUE),
    target_semester=list(type="string", description="Destination semester, or 'sel' for the selected semester.", required=FALSE),
    target_courseid=list(type="string", description="Destination course ID.", required=TRUE),
    target_category=list(type="string", description="Destination material category.", required=TRUE),
    target_path=list(type="string", description="Relative destination file path. Empty means keep the source filename.", required=FALSE),
    overwrite=list(type="boolean", description="Whether an existing destination may be replaced.", required=FALSE),
    kind=list(type="string", description="Definition kind: tutor or skill.", required=TRUE),
    definitionid=list(type="string", description="AI Tutor or Skill definition ID.", required=TRUE),
    tutorid=list(type="string", description="Course AI Tutor ID used for assignments and preferred document formats.", required=TRUE),
    source=list(type="string", description="Definition source: course or package for Tutors; personal, general, or package for Skills.", required=TRUE),
    yaml_content=list(type="string", description="Complete replacement YAML text.", required=TRUE),
    paths=list(type="string", description="One or more paths relative to the materials directory, separated by commas or newlines.", required=TRUE),
    from=list(type="string", description="Optional Pandoc input format; empty infers it from each file extension.", required=FALSE),
    to=list(type="string", description="Target format, or 'preferred' to use the AI Tutor definition.", required=FALSE),
    path=list(type="string", description="Relative path within the course directory.", required=TRUE),
    content=list(type="string", description="Complete replacement text-file content.", required=TRUE),
    operation_id=list(type="string", description="Change operation ID, or 'last' for the most recent committed change.", required=FALSE),
    limit=list(type="number", description="Maximum number of history entries to return.", required=FALSE)
  )
}
