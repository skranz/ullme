# Core ideas

- We currently try to save everything in a well-structured file system instead of a data base. Seems to make debugging / adaption easier.

- Roles: "teacher", "student", "admin"

- A "user" can in principle have different roles, but "teacher" and "admin" roles will be restriced.

- Each teacher can have multiple "courses". Courses are assigned to semester, multiple students can be registered to a course.

- Settings can live on a course, user, or general level. Course setting can refine user settings, user settings can refine general settings. Essentially, if you don't specify a particular setting field on a deeper level, we use the value from the higher level as default.

- Settings can be edited by hand using YAML files. Some very common settings can also have some nicer UI interface. 

- The AI shall also be able to change settings via tool calls. Importantly, the tool calls will be more limited, e.g. the AI cannot determine the user for which the setting is changed, but the user is determined by the App, i.e. this disallows the AI to change settings for other users. 





# UI Design

- Try to make it look similar to known, widely used AI chat interfaces. 


# Code Design

- Use shinyEvents functionality which tries to work event-based instead of reactivity based shiny approach.

- Try to put pure client functionality into dedicated .js code, only use R code where server is needed. E.g. if user submits a chat text and new output window will be generated below, this should ideally be done via js. But on the server side, we of course need to get the input text to start the API call to the AI. 

- Start regular R functions with a `restore.point("funname")` call. Example helper functions like `example()` are exempt and should not start with a restore point.

- Use `=` instead of `<-` in R code.

