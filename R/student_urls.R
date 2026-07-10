ullme_normalize_base_url = function(base_url) {
  restore.point("ullme_normalize_base_url")
  base_url = trimws(paste0(base_url %||% "")[1])
  sub("/+$", "", base_url)
}


ullme_url_path_join = function(...) {
  restore.point("ullme_url_path_join")
  parts = trimws(paste0(c(...)))
  parts = parts[nzchar(parts)]
  if (length(parts) == 0) return("")
  first = sub("/+$", "", parts[[1]])
  rest = vapply(parts[-1], function(part) {
    utils::URLencode(gsub("^/+|/+$", "", part), reserved=TRUE)
  }, character(1), USE.NAMES=FALSE)
  paste(c(first, rest), collapse="/")
}


ullme_student_course_base_url = function(base_url_student, teacherid,
                                          courseid) {
  restore.point("ullme_student_course_base_url")
  base_url_student = ullme_normalize_base_url(base_url_student)
  if (!nzchar(base_url_student)) return("")
  ullme_url_path_join(base_url_student, teacherid, courseid)
}


ullme_student_course_url = function(base_url_student, teacherid, courseid,
                                    semester=NULL, tutorid=NULL,
                                    instanceid=NULL) {
  restore.point("ullme_student_course_url")
  url = ullme_student_course_base_url(
    base_url_student=base_url_student,
    teacherid=teacherid,
    courseid=courseid
  )
  if (!nzchar(url)) return("")
  query = list(
    sem=semester,
    tutor=tutorid,
    inst=instanceid
  )
  query = query[vapply(query, function(value) {
    value = paste0(value %||% "")[1]
    !is.na(value) && nzchar(value)
  }, logical(1))]
  if (length(query) == 0) return(url)
  paste0(
    url,
    "?",
    paste(vapply(names(query), function(name) {
      paste0(
        utils::URLencode(name, reserved=TRUE),
        "=",
        utils::URLencode(paste0(query[[name]])[1], reserved=TRUE)
      )
    }, character(1)), collapse="&")
  )
}


ullme_course_student_urls_for_js = function(app=getApp()) {
  restore.point("ullme_course_student_urls_for_js")
  base_url_student = app$base_url_student %||% ""
  teacherid = app$teacherid %||% ""
  courseid = app$courseid %||% ""
  semester = app$semester %||% ""
  base_url = ullme_student_course_base_url(
    base_url_student=base_url_student,
    teacherid=teacherid,
    courseid=courseid
  )
  if (!nzchar(base_url) || !nzchar(courseid)) {
    return(list(base_url="", urls=list(), text=""))
  }
  tutors = ullme_course_ai_tutors(app=app)
  tutors = tutors[vapply(tutors, function(tutor) {
    !identical(tutor$enabled, FALSE)
  }, logical(1))]
  lines = unlist(lapply(tutors, function(tutor) {
    tutorid = tutor$tutorid %||% ""
    instances = tutor$instances %||% list()
    if (identical(tutor$multiple_instances, FALSE) ||
        length(instances) == 0) {
      return(ullme_student_course_url(
        base_url_student=base_url_student,
        teacherid=teacherid,
        courseid=courseid,
        semester=semester,
        tutorid=tutorid
      ))
    }
    vapply(instances, function(instance) {
      ullme_student_course_url(
        base_url_student=base_url_student,
        teacherid=teacherid,
        courseid=courseid,
        semester=semester,
        tutorid=tutorid,
        instanceid=instance$instanceid %||% ""
      )
    }, character(1))
  }), use.names=FALSE)
  lines = lines[nzchar(lines)]
  list(
    base_url=base_url,
    urls=as.list(lines),
    text=paste(lines, collapse="\n")
  )
}
