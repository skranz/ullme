# Tool function to generate a course
utool_make_course = function(courseid, coursename, semester=ullme_semester(), app=getApp()) {
  semester = from_context("semester", semester)
  ullme_make_course(
    main_dir=app$glob$main_dir,
    username=app$username,
    role=app$role,
    semester=semester,
    courseid=courseid,
    coursename=coursename
  )
}

