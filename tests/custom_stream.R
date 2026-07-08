if (file.exists(file.path("R", "custom_stream.R"))) {
  if (!exists("restore.point")) restore.point = function(...) invisible(NULL)
  getApp = function() app
  source(file.path("R", "courses.R"))
  source(file.path("R", "nvidia_api.R"))
  source(file.path("R", "ai_tools.R"))
  source(file.path("R", "tool_fun.R"))
  source(file.path("R", "teacher_info.R"))
  source(file.path("R", "custom_stream.R"))
} else if (requireNamespace("ullme", quietly=TRUE)) {
  library(ullme)
} else {
  stop("Run this script from the package root or install ullme first.")
}
if (!exists("ullme_chat_debug")) {
  ullme_chat_debug = function(...) invisible(NULL)
}

if (!requireNamespace("jsonlite", quietly=TRUE)) {
  stop("The custom stream offline test requires the jsonlite package.")
}

tiny_png_data_url = paste0(
  "data:image/png;base64,",
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8",
  "/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
)

app = new.env(parent=emptyenv())
app$role = "teacher"
app$enable_ai_tools = TRUE
app$api_config = list(provider="nvidia")
app$uploads_dir = tempfile("ullme-custom-stream-uploads-")
dir.create(file.path(app$uploads_dir, "session"), recursive=TRUE)

fallback_upload = list(
  id="upload_local_1",
  name="plot.png",
  size=nchar(tiny_png_data_url, type="bytes"),
  type="image/png",
  data_url=tiny_png_data_url
)
fallback_message = ullme_custom_stream_user_message(
  "Siehst du das Bild?",
  uploads=list(fallback_upload),
  app=app
)
png_base64 = sub("^data:image/png;base64,", "", tiny_png_data_url)
stopifnot(
  identical(fallback_message$role, "user"),
  is.list(fallback_message$content),
  identical(fallback_message$content[[2]]$type, "image_url"),
  identical(fallback_message$content[[2]]$image_url$url, tiny_png_data_url)
)

stored_path = file.path(app$uploads_dir, "session", "img_123_plot.png")
writeBin(jsonlite::base64_dec(png_base64), stored_path)
stored_upload = list(
  id="img_123",
  name="plot.png",
  size=file.info(stored_path)$size,
  type="image/png",
  data_url="not-used"
)
stored_message = ullme_custom_stream_user_message(
  "Describe this image.",
  uploads=list(stored_upload),
  app=app
)
stopifnot(
  grepl("^data:image/png;base64,", stored_message$content[[2]]$image_url$url),
  !grepl("[[:space:]]", stored_message$content[[2]]$image_url$url),
  !identical(stored_message$content[[2]]$image_url$url, "not-used")
)

tools = ullme_custom_stream_tools(app=app)
tool_names = vapply(
  tools,
  function(tool) tool$`function`$name,
  character(1)
)
stopifnot(
  "cur_user" %in% tool_names,
  "list_material_files" %in% tool_names
)
image_body = ullme_custom_stream_body(
  "Describe this image.",
  model="nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
  messages=list(stored_message),
  app=app
)
stopifnot(length(image_body$tools %||% list()) == 0)

state = new.env(parent=emptyenv())
state$tool_calls = list()
event1 = list(choices=list(list(delta=list(tool_calls=list(list(
  index=0,
  id="call_1",
  type="function",
  `function`=list(name="cur_user", arguments="")
))))))
event2 = list(choices=list(list(delta=list(tool_calls=list(list(
  index=0,
  `function`=list(arguments="{}")
))))))
ullme_custom_stream_accumulate_tool_calls(event1, state)
ullme_custom_stream_accumulate_tool_calls(event2, state)
calls = ullme_custom_stream_normalize_tool_calls(state$tool_calls)
stopifnot(
  length(calls) == 1,
  identical(calls[[1]]$id, "call_1"),
  identical(calls[[1]]$`function`$name, "cur_user"),
  identical(calls[[1]]$`function`$arguments, "{}")
)

cat("custom stream offline checks passed\n")
