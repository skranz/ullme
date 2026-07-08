library(ullme)

main_dir = tempfile("ullme-usage-statistics-")
source_dir = file.path(main_dir, "session_stats")
dir.create(source_dir, recursive=TRUE)

app = new.env(parent=emptyenv())
app$glob = list(main_dir=main_dir)
app$userid = "teacher_a"
app$role = "teacher"

write_session = function(id, teacherid, semester, courseid, requests=1L,
                          error="") {
  value = data.frame(
    date=rep("2026-07-05T10:00:00+0200", requests),
    teacherid=teacherid,
    semester=semester,
    courseid=courseid,
    tutorid="tutor_a",
    model="model_a",
    input_token=10,
    output_token=20,
    thinking_token=2,
    ttf_ms=100,
    total_sec=1.5,
    error=error,
    stringsAsFactors=FALSE
  )
  utils::write.csv(
    value,
    file.path(source_dir, paste0(id, ".csv")),
    row.names=FALSE,
    na=""
  )
}

write_session(
  "AAAAAAAAAAAAAAAA",
  "teacher_a",
  "SS26",
  "course_a",
  requests=2L
)
write_session(
  "BBBBBBBBBBBBBBBB",
  "teacher_a",
  "WS2526",
  "course_a"
)
write_session(
  "CCCCCCCCCCCCCCCC",
  "teacher_b",
  "SS26",
  "course_b",
  requests=4L
)

first = ullme_usage_statistics_update(app=app)
statistics_dir = ullme_usage_statistics_dir(app=app)
daily_path = file.path(statistics_dir, "teacher_daily.csv")
totals_path = file.path(statistics_dir, "teacher_totals.csv")
manifest_path = file.path(statistics_dir, "source_manifest.csv")
daily = utils::read.csv(daily_path, stringsAsFactors=FALSE)
totals = utils::read.csv(totals_path, stringsAsFactors=FALSE)
manifest = utils::read.csv(manifest_path, stringsAsFactors=FALSE)

stopifnot(
  identical(first$status, "ready"),
  first$changed == 3L,
  first$deleted == 0L,
  sum(daily$requests) == 3L,
  totals$requests[[1]] == 3L,
  totals$sessions[[1]] == 2L,
  identical(sort(unique(daily$semester)), c("SS26", "WS2526")),
  NROW(manifest) == 3L,
  sum(manifest$teacher_match) == 2L,
  dir.exists(file.path(statistics_dir, "courses")),
  length(list.files(file.path(statistics_dir, "courses"))) == 2L
)

unchanged = ullme_usage_statistics_update(app=app)
stopifnot(unchanged$changed == 0L, unchanged$deleted == 0L)

write_session(
  "AAAAAAAAAAAAAAAA",
  "teacher_a",
  "SS26",
  "course_a",
  requests=3L
)
changed = ullme_usage_statistics_update(app=app)
totals = utils::read.csv(totals_path, stringsAsFactors=FALSE)
stopifnot(
  changed$changed == 1L,
  totals$requests[[1]] == 4L,
  totals$sessions[[1]] == 2L
)

file.remove(file.path(source_dir, "BBBBBBBBBBBBBBBB.csv"))
deleted = ullme_usage_statistics_update(app=app)
totals = utils::read.csv(totals_path, stringsAsFactors=FALSE)
stopifnot(
  deleted$deleted == 1L,
  totals$requests[[1]] == 3L,
  totals$sessions[[1]] == 1L,
  length(list.files(file.path(statistics_dir, "courses"))) == 1L
)

legacy = data.frame(
  date="2026-07-06T10:00:00+0200",
  teacherid="teacher_a",
  courseid="legacy_course",
  tutorid="legacy_tutor",
  model="legacy_model",
  input_token=5,
  output_token=8,
  thinking_token=NA,
  seconds_until_output=0.25,
  error="",
  stringsAsFactors=FALSE
)
utils::write.csv(
  legacy,
  file.path(source_dir, "DDDDDDDDDDDDDDDD.csv"),
  row.names=FALSE,
  na=""
)
legacy_result = ullme_usage_statistics_update(app=app)
daily = utils::read.csv(daily_path, stringsAsFactors=FALSE)
legacy_row = daily[daily$courseid == "legacy_course", , drop=FALSE]
stopifnot(
  legacy_result$changed == 1L,
  NROW(legacy_row) == 1L,
  identical(legacy_row$semester[[1]], "unknown"),
  legacy_row$ttf_ms_sum[[1]] == 250,
  legacy_row$total_sec_n[[1]] == 0
)

writeLines(
  "date,teacherid",
  file.path(source_dir, "EEEEEEEEEEEEEEEE.csv")
)
malformed = ullme_usage_statistics_update(app=app)
stopifnot(
  malformed$changed == 1L,
  length(malformed$errors) == 1L,
  grepl("Missing columns", malformed$errors[[1]], fixed=TRUE)
)

ui = htmltools::renderTags(ullme_usage_statistics_ui(app=app))
ui_text = paste(ui$head, ui$html, collapse="\n")
navigation = htmltools::renderTags(ullme_studio_navigation_ui(app=app))
navigation_text = paste(
  navigation$head,
  navigation$html,
  collapse="\n"
)
teacher_js = paste(
  readLines(
    file.path("inst", "www", "ullme-teacher.js"),
    warn=FALSE,
    encoding="UTF-8"
  ),
  collapse="\n"
)
stopifnot(
  grepl("ullme_usage_statistics_panel", ui_text, fixed=TRUE),
  grepl("ullme-course-content-panel-active", ui_text, fixed=TRUE),
  grepl("ullme_usage_daily_chart", ui_text, fixed=TRUE),
  grepl("ullme_usage_refresh_btn", ui_text, fixed=TRUE),
  grepl('data-studio-view="usage"', navigation_text, fixed=TRUE),
  grepl('studioView: "usage"', teacher_js, fixed=TRUE)
)

ullme_remove_checked_directory(
  main_dir,
  root=dirname(main_dir),
  expected_name=basename(main_dir),
  label="usage statistics test directory"
)
