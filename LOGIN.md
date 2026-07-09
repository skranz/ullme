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
<main_dir>/general/teachers.yaml
```

The file maps teacher IDs to the main user's normalized userid:

```yaml
skranz: sebastian_kranz
esol: erin_solstice
```

Run `ullme_make_teacher_dirs(main_dir)` after editing this file, or let teacher
login create missing directories. Each teacher has:

```text
<main_dir>/teachers/<teacherid>/config/allowed_users.yaml
```

Example:

```yaml
sebastian_kranz:
  main_teacher: true
  can_set_users: true

max_mustermann:
  can_set_users: false
```

The main teacher from `general/teachers.yaml` is always restored with
`main_teacher: true` and `can_set_users: true`; the Teacher Studio users view
does not allow removing that user. Users with `can_set_users: true` can edit
this table in the bottom-left Users settings view.

Both teacher and student login convert the authenticated email through
`email2userid`, defaulting to `ullme_email2userid()`. The default accepts only
`@uni-ulm.de` addresses and normalizes the local part by replacing
non-alphanumeric runs with `_`. The original email is stored in:

```text
<main_dir>/users/<userid>/email.txt
```

Each user also receives a stable random student ID in
`<main_dir>/users/<userid>/studentid.txt`; student role storage lives below
`<main_dir>/students/<studentid>`. The user's current teacher memberships are
mirrored in `<main_dir>/users/<userid>/teacherids.txt`.

If a teacher login has access to multiple teacher IDs, uLLMe first shows a
workspace chooser and initializes the selected teacher workspace only after
that choice.

## Security assessment

This is reasonable only for a low-risk deployment when all of the following
hold:

- the app is served exclusively over HTTPS;
- the shinyEventsLogin backend is genuinely authenticating users;
- teacher user authorization is maintained carefully;
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
