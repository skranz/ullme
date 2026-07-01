ullme_teacher_info_dir = function(main_dir=ullme_main_dir()) {
  file.path(main_dir, "teacher_info")
}


ullme_teacher_info_source_dir = function() {
  ullme_package_dir("teacher_info")
}


ullme_init_teacher_info = function(main_dir=ullme_main_dir()) {
  source = ullme_teacher_info_source_dir()
  target = ullme_teacher_info_dir(main_dir=main_dir)
  dir.create(target, recursive=TRUE, showWarnings=FALSE)
  if (!dir.exists(source)) return(invisible(target))

  files = list.files(
    source,
    recursive=TRUE,
    full.names=FALSE,
    all.files=TRUE,
    no..=TRUE,
    include.dirs=FALSE
  )
  for (relative in files) {
    from = file.path(source, relative)
    to = file.path(target, relative)
    if (file.exists(to)) next
    dir.create(dirname(to), recursive=TRUE, showWarnings=FALSE)
    file.copy(from, to, overwrite=FALSE, copy.mode=TRUE)
  }
  invisible(target)
}


ullme_teacher_project_state = function(app=getApp()) {
  semester_courses = ullme_user_courseids(
    main_dir=app$glob$main_dir,
    userid=app$userid,
    role="teacher",
    semester=app$semester
  )
  all_courses = ullme_list_courses(
    teacherid=app$userid,
    main_dir=app$glob$main_dir
  )
  course_dir = ullme_active_course_dir(app=app)
  if (is.null(course_dir)) {
    material = list()
    organization = list(indexes=list(), unassigned=list())
    tutors = list()
  } else {
    material = ullme_course_material_files(course_dir)
    organization = ullme_course_organization_payload(course_dir)
    tutors = ullme_course_ai_tutors(app=app)
  }
  category_counts = vapply(material, length, integer(1))
  material_count = sum(category_counts)
  enabled_tutors = sum(vapply(
    tutors,
    function(tutor) !identical(tutor$enabled, FALSE),
    logical(1)
  ))
  list(
    semester=app$semester,
    selected_course=app$courseid %||% "",
    courses_this_semester=length(semester_courses),
    courses_all_semesters=length(unique(all_courses)),
    course_ids=as.list(semester_courses),
    material_files=material_count,
    material_by_category=as.list(category_counts),
    object_indexes=length(organization$indexes %||% list()),
    unassigned_materials=length(organization$unassigned %||% list()),
    installed_ai_tutors=length(tutors),
    enabled_ai_tutors=enabled_tutors,
    available_ai_tutor_definitions=length(ullme_ai_tutor_catalog(app=app)),
    available_skills=length(ullme_skill_catalog(app=app)),
    active_skill=app$active_skillid %||% ""
  )
}


ullme_teacher_next_steps = function(state) {
  steps = character(0)
  if (state$courses_this_semester == 0) {
    steps = c(steps, "Create the first course for the selected semester.")
  } else if (!nzchar(state$selected_course)) {
    steps = c(steps, "Select a course to inspect or edit.")
  } else {
    if (state$material_files == 0) {
      steps = c(steps, "Upload teaching materials to the selected course.")
    }
    if (state$material_files > 0 &&
        (state$object_indexes == 0 || state$unassigned_materials > 0)) {
      steps = c(
        steps,
        "Review course organization or ask the AI to propose object indexes."
      )
    }
    if (state$installed_ai_tutors == 0) {
      steps = c(steps, "Add an AI Tutor to the course when the materials are ready.")
    }
    if (state$material_files > 0 && state$installed_ai_tutors > 0) {
      steps = c(
        steps,
        "Review Tutor definitions and test whether their material roles are satisfied."
      )
    }
  }
  if (length(steps) == 0) {
    steps = "Ask for help with materials, organization, AI Tutors, Skills, or definitions."
  }
  as.list(steps)
}


ullme_teacher_project_state_text = function(app=getApp()) {
  state = ullme_teacher_project_state(app=app)
  next_steps = ullme_teacher_next_steps(state)
  paste0(
    "Current teacher project state:\n",
    "- Semester: ", state$semester, "\n",
    "- Courses this semester: ", state$courses_this_semester, "\n",
    "- Selected course: ",
    if (nzchar(state$selected_course)) state$selected_course else "none",
    "\n",
    "- Material files: ", state$material_files, "\n",
    "- Object indexes: ", state$object_indexes,
    "; unassigned materials: ", state$unassigned_materials, "\n",
    "- AI Tutors installed/enabled: ", state$installed_ai_tutors, "/",
    state$enabled_ai_tutors, "\n",
    "- Available Tutor definitions: ", state$available_ai_tutor_definitions,
    "; Skills: ", state$available_skills,
    if (nzchar(state$active_skill)) {
      paste0("; active Skill: ", state$active_skill)
    } else {
      "; active Skill: none"
    },
    "\nSuggested next steps:\n",
    paste0("- ", unlist(next_steps), collapse="\n")
  )
}


ullme_teacher_info_documents = function(app=getApp()) {
  root = ullme_teacher_info_dir(app$glob$main_dir)
  if (!dir.exists(root)) return(list())
  files = list.files(
    root,
    pattern="\\.(md|txt)$",
    recursive=TRUE,
    full.names=TRUE,
    ignore.case=TRUE
  )
  lapply(sort(files), function(path) {
    list(
      id=tools::file_path_sans_ext(basename(path)),
      path=gsub("\\\\", "/", sub(
        paste0(
          "^",
          gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1",
               normalizePath(root, winslash="/")),
          "/?"
        ),
        "",
        normalizePath(path, winslash="/")
      )),
      content=paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n")
    )
  })
}


ullme_teacher_info_search = function(topic="overview", query="", app=getApp(),
                                      max_documents=4L, max_chars=5000L) {
  topic = tolower(trimws(paste0(topic %||% "overview")[1]))
  query = trimws(paste0(query %||% "")[1])
  if (topic %in% c("state", "project", "project_state", "next", "next_steps")) {
    state = ullme_teacher_project_state(app=app)
    return(list(
      topic="project_state",
      state=state,
      next_steps=ullme_teacher_next_steps(state)
    ))
  }

  documents = ullme_teacher_info_documents(app=app)
  if (length(documents) == 0) {
    return(list(topic=topic, documents=list(),
                message="No teacher-information documents are installed."))
  }
  terms = unique(tolower(c(
    if (!topic %in% c("", "all", "overview")) topic else character(0),
    unlist(strsplit(query, "[^[:alnum:]_-]+"))
  )))
  terms = terms[nzchar(terms)]
  scores = vapply(documents, function(document) {
    haystack = tolower(paste(document$id, document$path, document$content))
    if (length(terms) == 0) {
      if (identical(document$id, "overview")) 10 else 1
    } else {
      sum(vapply(terms, function(term) {
        length(gregexpr(term, haystack, fixed=TRUE)[[1]][
          gregexpr(term, haystack, fixed=TRUE)[[1]] > 0
        ])
      }, integer(1)))
    }
  }, numeric(1))
  keep = which(scores > 0)
  if (length(keep) == 0) {
    return(list(topic=topic, query=query, documents=list(),
                message="No matching teacher-information document was found."))
  }
  keep = head(keep[order(scores[keep], decreasing=TRUE)], max_documents)
  matches = lapply(keep, function(index) {
    document = documents[[index]]
    document$content = substr(document$content, 1, max_chars)
    document$score = scores[[index]]
    document
  })
  list(topic=topic, query=query, documents=matches)
}


utool_teacher_info = function(topic="overview", query="", app=getApp()) {
  ullme_teacher_info_search(topic=topic, query=query, app=app)
}
