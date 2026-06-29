
ullme_teacher_dirs = function(teacherid=NULL, main_dir=ullme_main_dir()) {
  dirs = list.dirs(file.path(main_dir, "teachers"),recursive = FALSE)
  if (is.null(teacherid)) {
    return(dirs)
  }
  keep = basename(dirs) %in% teacherid
  dirs[keep]
}

ullme_semester_dirs = function(teacherid=NULL, semester=NULL, courseid=NULL, main_dir = ullme_main_dir()) {
  restore.point("ullme_semester_dirs")
  if (!is.null(courseid)) {
    course_dirs = ullme_course_dirs(teacherid=teacherid, semester=semester, courseid=courseid, main_dir=maind_dir)
    return(unique(dirname(course_dirs)))
  }

  teacher_dirs = ullme_teacher_dirs(teacherid, main_dir)
  dirs = list.dirs(teacher_dirs,recursive = FALSE)
  if (is.null(semester) & is.null(courseid)) {
    return(dirs)
  }
  keep = basename(dirs) %in% semester
  dirs[keep]


}

ullme_course_dirs = function(teacherid=NULL, semester=NULL,courseid=NULL, course_pattern = NULL,  main_dir=ullme_main_dir()) {
  semester_dirs = ulme_semester_dirs(teacherid, semester, main_dir)
  dirs = list.dirs(semester_dirs,recursive = FALSE)
  if (!is.null(course_pattern)) {
    keep = stri_detect_regex(basename(dirs), course_pattern)
    dirs = dirs[keep]
  } else if (!is.null(courseid)) {
    keep = basename(dirs) %in% courseid
    dirs = dirs[keep]
  }
  dirs
}


ullme_list_courses = function(teacherid=NULL, semester=NULL, courseid=NULL, course_pattern = NULL, main_dir=ullme_main_dir()) {
  basename(ulme_course_dirs(teacherid, semester,courseid, course_pattern, main_dir))
}

ullme_list_teachers = function(teacherid=NULL, main_dir=ullme_main_dir()) {
  basename(ulme_teacher_dirs(teacherid, main_dir))
}

ullme_list_semesters = function(teacherid=NULL, courseid=NULL, main_dir=ullme_main_dir()) {
  basename(ulme_semester_dirs(teacherid=teacherid, courseid=courseid, main_dir))
}
