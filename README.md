


# UI Design

- Try to make it look similar to known, widely used AI chat interfaces. 


# Code Design

- Use shinyEvents functionality which tries to work event-based instead of reactivity based shiny approach.

- Try to put pure client functionality into dedicated .js code, only use R code where server is needed. E.g. if user submits a chat text and new output window will be generated below, this should ideally be done via js. But on the server side, we of course need to get the input text to start the API call to the AI. 

- Start regular R functions with a `restore.point("funname")` call. Example helper functions like `example()` are exempt and should not start with a restore point.

- Use `=` instead of `<-` in R code.

