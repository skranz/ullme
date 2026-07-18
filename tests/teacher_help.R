library(ullme)

# Source the development copy so this test can also be run before installation.
source(file.path("R", "teacherApp.R"))
source(file.path("R", "tutor_flow.R"))
source(file.path("R", "tutor_validation.R"))
source(file.path("R", "test_suites.R"))
source(file.path("R", "ullme.R"))

app = new.env(parent=emptyenv())
app$app_kind = "teacher"
app$courseid = ""
app$render_chat_markdown = FALSE
app$adapt_mathjax = FALSE
help_ui = htmltools::renderTags(ullme_teacher_help_ui(app=app))
help_html = paste(help_ui$head, help_ui$html, collapse="\n")
teacher_js = paste(
  readLines(file.path("inst", "www", "ullme-teacher.js"), warn=FALSE),
  collapse="\n"
)
teacher_css = paste(
  readLines(file.path("inst", "www", "ullme-teacher.css"), warn=FALSE),
  collapse="\n"
)
tutor_js = paste(
  readLines(file.path("inst", "www", "ullme-tutors.js"), warn=FALSE),
  collapse="\n"
)
chat_ui_source = paste(
  readLines(file.path("R", "ullme.R"), warn=FALSE),
  collapse="\n"
)
teacher_pane = htmltools::renderTags(
  ullme_chat_pane_ui(app=app, show_header=TRUE, show_help=TRUE)
)
teacher_pane_html = paste(teacher_pane$head, teacher_pane$html, collapse="\n")
plain_chat = htmltools::renderTags(
  ullme_chat_pane_ui(app=app, show_header=FALSE, show_help=FALSE)
)
plain_chat_html = paste(plain_chat$head, plain_chat$html, collapse="\n")

views = c(
  "general", "new_teacher", "usage", "materials", "tests", "ai-tutors",
  "ai-tutors-instances", "ai-tutors-flow",
  "ai-tutors-yaml-definition", "ai-tutors-yaml-instances",
  "settings", "allowed-users", "file"
)

stopifnot(
  all(file.exists(file.path("inst", "help", paste0(views, ".html")))),
  all(vapply(views, function(view) {
    grepl(paste0('data-help-view="', view, '"'), help_html, fixed=TRUE)
  }, logical(1))),
  grepl("Create your first course", help_html, fixed=TRUE),
  grepl("ullme-help-page ullme-help-page-active", help_html, fixed=TRUE),
  grepl('id="ullme_help_tab"', chat_ui_source, fixed=TRUE),
  grepl('id="ullme_ai_chat_tab"', chat_ui_source, fixed=TRUE),
  grepl('id="ullme_help_tab"', teacher_pane_html, fixed=TRUE),
  grepl('id="ullme_ai_chat_panel"', teacher_pane_html, fixed=TRUE),
  grepl('id="ullme_node_editor_tab"', teacher_pane_html, fixed=TRUE),
  grepl('id="ullme_node_editor_yaml"', teacher_pane_html, fixed=TRUE),
  grepl('id="ullme_test_variant_node_tab"', teacher_pane_html, fixed=TRUE),
  grepl('id="ullme_test_variant_node_panel"', teacher_pane_html, fixed=TRUE),
  grepl('id="ullme_tutor_validation_tab"', teacher_pane_html, fixed=TRUE),
  grepl('id="ullme_tutor_validation_errors"', teacher_pane_html, fixed=TRUE),
  grepl("Create your first course", teacher_pane_html, fixed=TRUE),
  !grepl('id="ullme_help_tab"', plain_chat_html, fixed=TRUE),
  grepl('id="ullme_chat_messages"', plain_chat_html, fixed=TRUE),
  grepl("activateAssistantTab", teacher_js, fixed=TRUE),
  grepl('showHelpForView("new_teacher")', teacher_js, fixed=TRUE),
  grepl('id: "flow", label: "Flow"', tutor_js, fixed=TRUE),
  grepl("Changes save automatically", tutor_js, fixed=TRUE),
  grepl('panel.addEventListener("focusout"', tutor_js, fixed=TRUE),
  !grepl('save.textContent = "Save assignments"', tutor_js, fixed=TRUE),
  grepl("ullme_send_course_shell_state", chat_ui_source, fixed=TRUE),
  grepl("Still computing", tutor_js, fixed=TRUE),
  grepl("ai-tutors-yaml-definition", tutor_js, fixed=TRUE),
  grepl('src="ullme/ullme-tutor-flow.js"', chat_ui_source, fixed=TRUE),
  grepl('src="ullme/ullme-tests.js"', chat_ui_source, fixed=TRUE),
  grepl('href="ullme/ullme-tests.css"', chat_ui_source, fixed=TRUE),
  grepl('href="ullme/ullme-tutor-flow.css"', chat_ui_source, fixed=TRUE),
  grepl("showHelpForView(panelName)", teacher_js, fixed=TRUE),
  grepl("ullme-ai-pane-collapsed .ullme-assistant-panel", teacher_css, fixed=TRUE)
)
