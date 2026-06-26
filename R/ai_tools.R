# Tool function to generate a course
utool_make_course = function(context, courseid, coursename,semester=NULL) {
  user = from_context("user")


}


from_context = function(var, context=parent.frame()$context) {
  context[[var]]
}
