# Core ideas

- We currently try to save everything in a well-structured file system instead of a data base. Seems to make debugging / adaption easier.

- Applications have one fixed role: `"teacher"` or `"student"`.

- Teacher-only capabilities are exposed by `teacherApp()`; `studentApp()` does
  not provide a role switch or render Teacher Studio controls.

- Each teacher can have multiple "courses". Courses are assigned to semester, multiple students can be registered to a course.

- Settings can live on a course, user, or general level. Course setting can refine user settings, user settings can refine general settings. Essentially, if you don't specify a particular setting field on a deeper level, we use the value from the higher level as default.

- Settings can be edited by hand using YAML files. Some very common settings can also have some nicer UI interface. 

- The AI shall also be able to change settings via tool calls. Importantly, the tool calls will be more limited, e.g. the AI cannot determine the user for which the setting is changed, but the user is determined by the App, i.e. this disallows the AI to change settings for other users. 





# UI Design

- Try to make it look similar to known, widely used AI chat interfaces. 

- Teacher mode uses the [Teacher Studio](TEACHER_STUDIO.md): a course
  workspace for materials, editable text files, course-local AI Tutors and
  their instances, active Skills, and a collapsible context-aware AI pane.

Create fixed-role applications with:

```r
teacher_app = teacherApp(
  main_dir,
  userid="sebastian_kranz",
  teacherid="skranz",
  base_url_student="https://example.org/student"
)
student_app = studentApp(
  main_dir,
  userid="student_userid",
  teacherid="skranz",
  courseid="course_id",
  tutorid="optional_tutor_id",
  instanceid="optional_instance_id"
)
```

Roles are fixed by the constructor and cannot be switched inside an app.
Both constructors accept `login_check="none"` (the default) or
`login_check="sel"` for the optional shinyEventsLogin integration. See
[LOGIN.md](LOGIN.md) for configuration, user identity, teacher authorization, and the
security limitations. Common login options can be passed directly: use
`login_fixed_password` for a simple shared-password deployment, or
`login_db_dir`/`dbname` plus `smtp`, `app.url`, and optionally
`email.text.fun` for email signup and password reset. Raw
`login_args=list(...)` remains available for less common
`shinyEventsLogin::loginModule()` options.
Both constructors accept an `email2userid` function. The default
`ullme_email2userid()` accepts `@uni-ulm.de` email addresses and normalizes the
local part by replacing non-alphanumeric runs with `_`. The original email is
stored in `main_dir/users/<userid>/email.txt`.
Teacher workspaces are identified by `teacherid`, usually different from the
main teacher's `userid`. Configure them in
`main_dir/general/teachers.yaml`, then run `ullme_make_teacher_dirs(main_dir)`
or let teacher login initialize missing config directories. Per-teacher access
lives in `main_dir/teachers/<teacherid>/config/allowed_users.yaml` and can be
edited in Teacher Studio through the bottom-left Users settings view.
For student apps, `teacherid`, `courseid`, `tutorid`, and `instanceid` can
instead be supplied as URL query parameters. A constructor argument always
takes precedence over the corresponding URL value. `teacherid` and `courseid`
are required; when no tutor or instance is specified, the student can switch
it in the sidebar.
When `teacherApp(base_url_student=...)` is set, Course Settings show the
course's student app URL:

```text
<base_url_student>/<teacherid>/<courseid>
```

and one copyable URL per enabled Tutor or Tutor instance using query arguments
`sem`, `tutor`, and `inst`. `studentApp()` accepts these aliases, chooses a
default semester for the course when `sem` is missing, and lets students switch
semester, Tutor, and instance in the header when alternatives exist.
Assistant output is rendered as CommonMark Markdown by default. Pass
`render_chat_markdown=FALSE` to either constructor for literal plain text.
Responses stream asynchronously by default; pass `stream_chat=FALSE` to wait
for complete responses. Both constructors accept `stream_backend`,
`catch_chat_errors`, `chat_debug`, `sync_chat`, `enable_ai_tools`, and
`show_chat_thinking`; use `stream_backend="custom"` for the custom
OpenAI-compatible streaming backend. When `show_chat_thinking=TRUE`,
provider-supplied thinking content is shown in a closed, expandable field when
present. The student app's Personal settings menu also offers System, Light,
and Dark appearance modes; this browser-local choice can later be replaced by
a persisted user setting.
Teacher AI requests and responses are stored below the active course's
`ai_interactions/` directory by default; pass
`store_ai_interactions=FALSE` to disable this debugging log. Student apps
default to `never_save_chats=TRUE`, which overrides Tutor chat-history settings,
hides the history sidebar, and prevents prompts and replies from being stored.
Content-free aggregate usage rows are still written to `session_stats/`.
The teacher app opens on a global Usage dashboard that summarizes these
anonymous records across the teacher's courses and semesters. Its cached
incremental aggregates are stored below the teacher's
`usage_statistics/` directory.


# Code Design

- Use shinyEvents functionality which tries to work event-based instead of reactivity based shiny approach.

- Try to put pure client functionality into dedicated .js code, only use R code where server is needed. E.g. if user submits a chat text and new output window will be generated below, this should ideally be done via js. But on the server side, we of course need to get the input text to start the API call to the AI. 

- Start regular R functions with a `restore.point("funname")` call. Example helper functions like `example()` are exempt and should not start with a restore point.

- Use `=` instead of `<-` in R code.

