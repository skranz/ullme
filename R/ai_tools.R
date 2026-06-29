example = function() {
  name = "describe_course_docs"
  ullme_tool(name)
}

ullme_tool = function(name, descr="",perm=ullme_tool_perm()) {
  restore.point("ullme_tool")
  fun_name = stringi::stri_c("utool_", name)
  namespace = asNamespace("ullme")
  fun = get(fun_name, envir = namespace, inherits = FALSE)
  args = names(formals(fun))

  # these arguments will be set by uLLMe
  auto_args = c("userid","teacherid")

  # these arguments can be specified by the tool-calling LLM
  tool_args = setdiff(args, auto_args)

  # generate the actual tool fun
  tool_fun_str = paste0('function(', paste0(tool_args, collapse=","),') {
  userid = ullme_userid()
  teacherid = ullme_teacherid()
  args = as.list(environment())
  res = ullme_check_tool_args(args, course_must_exist=', course_must_exist,')
  if (!res$ok) {
    return(res$msg)
  }
  ', fun_name,'(',paste0(args,"=", args, collapse=","),')
}')
  cat(tool_fun_str)

  tool_fun = eval(parse(text = tool_fun_str))

  arg_types = ullme_tool_arg_defs(tool_args)


  el_tool = ellmer::tool(
    fun = tool_fun,
    name = name,
    description = descr,
    arguments = arg_types[tool_args]
  )

  el_tool

}

ullme_tools = function() {
  li = list(
    ullme_tool("list_courses", "Get the list of existing courses. If 'semester' is not null only list coursed from that semester. 'teacherid' is the userid of the teacher of whom we want to list the courses."),
    ullme_tool("cur_user", "Get the userid of the current user, the role and the possible roles.")
  )
  names = sapply(li, function(et) et@name)
  names(li) = names
  li
}

ullme_check_tool_args = function(args, perm = ullme_perm()) {
  if (is.null(args$userid)) {
    return(list(ok=FALSE, msg="No valid userid identified by ullme. Seems a bug in the R package."))
  }
  arg_names = names(args)

  if (isTRUE(perm$only_teacher)) {
    if (!identical(args$userid & args$teacherid)) {
      return(list(ok=FALSE, msg = "This tool can only be called by the teacher of the course."))
    }
  }

  if (isTRUE(perm$course_must_exist) & all(c("teacherid","semester","courseid") %in% arg_names)) {
    has_course = ullme_has_course(teacherid, semester, courseid)
    if (!has_course) {
      return(list(ok=FALSE, msg=paste0("Course ", courseid, " in semester ", semester, " for teacher ", teacherid, " does not exist.")))
    }
  }
  return(list(ok=TRUE))
}

ullme_has_course = function(teacherid, semester, courseid, main_dir=ullme_main_dir()) {
  dir.exists(file.path(main_dir, "teachers", teacherid, "courses", semester, courseid))
}

# Use defaults if not in specs
ullme_tool_arg_spec = function(args, specs = list()) {
  def_specs = ullme_default_tool_arg_spec()
  fields = c("type", "description", "required")

  res = lapply(args, function(arg) {
    def = def_specs[[arg]]
    given = specs[[arg]]

    if (is.null(def)) def = list()
    if (is.null(given)) given = list()

    spec = utils::modifyList(def, given)
    missing = setdiff(fields, names(spec))

    if (length(missing) > 0) {
      stop(
        "Incomplete specification for argument '", arg, "'. Missing: ",
        stringi::stri_c(missing, collapse = ", ")
      )
    }

    spec
  })

  names(res) = args
  res
}


ullme_default_tool_arg_spec = function() {
  list(
    teacherid = list(type="string", description="teacherid is the userid of the teacher a course belongs to.", required=TRUE),
    courseid = list(type="string", description="courseid you can use the tool list_courses to get courseids.", required=TRUE),
    semester = list(type="string", description= "The semester containing the course, e.g. WS2526 or SS27. Special cases: 'all' means all semester and 'sel' the currently selected semester.", required=TRUE),
  )
}



ullme_tool_perm = function(course_must_exist=TRUE, only_teacher=TRUE) {
  as.list(environment())
}


