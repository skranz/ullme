utool_list_courses = function(teacherid = ullme_teacherid(),semester=NULL) {
  ullme_list_courses(teacherid=teacherid, semester=semester)
}


utool_cur_user = function() {
  paste0("userid=", ullme_userid(), "\nrole=", ullme_user_role(), "\nallowed_roles=", paste0(ullme_user_allowed_roles(), collapse=", "))
}

utool_describe_course_docs = function(teacherid = ullme_teacherid(), courseid, semester, doc_types) {
  "Tool not yet implemented"
}
