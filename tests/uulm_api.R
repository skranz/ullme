library(ullme)

test_main_dir = file.path(
  tempdir(),
  "ullme_main",
  paste0("uulm-api-", as.integer(Sys.time()))
)
dir.create(test_main_dir, recursive=TRUE)
key_file = file.path(test_main_dir, "api-key.txt")
writeLines("dummy-secret", key_file)

config = ullme_api_config(
  api_provider="uulm_api",
  api_key_file=key_file
)
stopifnot(
  identical(config$base_url, ullme_uulm_api_base_url()),
  identical(config$model, ullme_uulm_api_default_model()),
  identical(config$credentials(), "dummy-secret"),
  inherits(try(
    ullme_api_config(api_provider="uulm_api"),
    silent=TRUE
  ), "try-error")
)

app = teacherApp(
  main_dir=test_main_dir,
  userid="teacher",
  api_provider="uulm_api",
  api_key_file=key_file
)
composer = paste0(as.character(ullme_composer_ui(app=app)), collapse="")
stopifnot(
  identical(app$allow_model_selection, TRUE),
  grepl("ullme_model_select", composer, fixed=TRUE)
)

student_app = studentApp(
  main_dir=test_main_dir,
  userid="student",
  teacherid="teacher",
  courseid="course",
  api_provider="uulm_api",
  api_key_file=key_file
)
student_composer = paste0(
  as.character(ullme_composer_ui(app=student_app)),
  collapse=""
)
stopifnot(
  identical(student_app$allow_model_selection, TRUE),
  grepl("ullme_model_select", student_composer, fixed=TRUE)
)

fixed_model_app = teacherApp(
  main_dir=test_main_dir,
  userid="teacher",
  api_provider="uulm_api",
  api_key_file=key_file,
  allow_model_selection=FALSE
)
fixed_model_composer = paste0(
  as.character(ullme_composer_ui(app=fixed_model_app)),
  collapse=""
)
stopifnot(!grepl("ullme_model_select", fixed_model_composer, fixed=TRUE))
