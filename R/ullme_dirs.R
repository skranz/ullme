ullme_teacher_dirs = function(teacherid=NULL, main_dir=ullme_main_dir()) {
  root = file.path(main_dir, "teachers")
  if (!dir.exists(root)) return(character(0))
  dirs = list.dirs(root, recursive=FALSE, full.names=TRUE)
  if (!is.null(teacherid)) dirs = dirs[basename(dirs) %in% teacherid]
  dirs
}


ullme_semester_dirs = function(teacherid=NULL, semester=NULL, courseid=NULL,
                                main_dir=ullme_main_dir()) {
  teacher_dirs = ullme_teacher_dirs(teacherid=teacherid, main_dir=main_dir)
  roots = file.path(teacher_dirs, "courses")
  dirs = unlist(lapply(roots[dir.exists(roots)], function(root) {
    list.dirs(root, recursive=FALSE, full.names=TRUE)
  }), use.names=FALSE)
  if (!is.null(semester)) dirs = dirs[basename(dirs) %in% semester]
  if (!is.null(courseid)) {
    dirs = dirs[vapply(dirs, function(dir) {
      any(dir.exists(file.path(dir, courseid)))
    }, logical(1))]
  }
  unique(dirs)
}


ullme_course_dirs = function(teacherid=NULL, semester=NULL, courseid=NULL,
                              course_pattern=NULL, main_dir=ullme_main_dir()) {
  semester_dirs = ullme_semester_dirs(
    teacherid=teacherid,
    semester=semester,
    main_dir=main_dir
  )
  dirs = unlist(lapply(semester_dirs, function(dir) {
    list.dirs(dir, recursive=FALSE, full.names=TRUE)
  }), use.names=FALSE)
  if (!is.null(course_pattern)) {
    dirs = dirs[stringi::stri_detect_regex(basename(dirs), course_pattern)]
  } else if (!is.null(courseid)) {
    dirs = dirs[basename(dirs) %in% courseid]
  }
  unique(dirs)
}


ullme_list_courses = function(teacherid=NULL, semester=NULL, courseid=NULL,
                               course_pattern=NULL, main_dir=ullme_main_dir()) {
  basename(ullme_course_dirs(
    teacherid=teacherid,
    semester=semester,
    courseid=courseid,
    course_pattern=course_pattern,
    main_dir=main_dir
  ))
}


ullme_list_teachers = function(teacherid=NULL, main_dir=ullme_main_dir()) {
  basename(ullme_teacher_dirs(teacherid=teacherid, main_dir=main_dir))
}


ullme_list_semesters = function(teacherid=NULL, courseid=NULL,
                                 main_dir=ullme_main_dir()) {
  basename(ullme_semester_dirs(
    teacherid=teacherid,
    courseid=courseid,
    main_dir=main_dir
  ))
}
