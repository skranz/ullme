# Login

Both constructors accept:

```r
login_check = c("none", "sel")
login_args = list()
```

`login_check="none"` preserves the previous behavior. `login_check="sel"`
uses [`skranz/shinyEventsLogin`](https://github.com/skranz/shinyEventsLogin).
Install it separately:

```r
remotes::install_github("skranz/shinyEventsLogin")
```

`login_args` is forwarded to `shinyEventsLogin::loginModule()`. uLLMe requires
an actual authentication backend and rejects username-only configurations.
Supported configurations include:

- a non-empty `fixed.password`;
- a configured shinyEventsLogin signup database; or
- a configured query/cookie token backend.

For a small, low-risk deployment, a shared password can be supplied from an
environment variable:

```r
app = teacherApp(
  main_dir,
  login_check="sel",
  login_args=list(
    fixed.password=Sys.getenv("ULLME_LOGIN_PASSWORD")
  )
)
```

Do not put the password directly into source control. A fixed password is
shared authentication and cannot identify who actually knows it.

## Teacher authorization

Teacher login additionally requires:

```text
<main_dir>/allowed_teachers.yaml
```

The file maps authenticated, lowercase email addresses to teacher IDs:

```yaml
teacher.one@example.org: teacher_one
teacher.two@example.org: teacher_two
delegate@example.org: teacher_one
```

Multiple addresses may map to the same teacher. Teacher IDs determine the
teacher storage directory and must use uLLMe's normal safe ID format. The
mapping is checked both by the login module and again before uLLMe initializes
the teacher workspace.

For students, the authenticated email is converted to a stable SHA-256-based
internal user ID. The email itself is shown in personal settings but is not
used as a filesystem path.

## Security assessment

This is reasonable only for a low-risk deployment when all of the following
hold:

- the app is served exclusively over HTTPS;
- the shinyEventsLogin backend is genuinely authenticating users;
- teacher email authorization is maintained carefully;
- server logs and the main directory are access-controlled; and
- secrets and token files are outside source control.

There are important upstream limitations:

- shinyEventsLogin describes itself as "probably not very secure";
- its password hashing uses a single fast SHA-512 operation with a salt rather
  than a modern password hashing function such as Argon2id; and
- its cookie/token implementation is not a modern audited identity system.

Consequently, password-based shinyEventsLogin should not protect high-risk or
sensitive data without first patching the password logging and password
storage. For anything beyond a modest course deployment, prefer authentication
at a trusted reverse proxy or institutional OIDC/SAML layer and use uLLMe's
teacher mapping only for authorization.

uLLMe does avoid initializing protected course state before authentication.
Authenticated sessions receive random, session-specific static-resource
prefixes that are removed when the Shiny session ends. These measures reduce
accidental cross-user exposure but do not turn shinyEventsLogin into a
high-assurance authentication system.
