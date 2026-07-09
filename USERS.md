# USERID

The userid will be created by a function email2userid that can be passed to the teacherApp and studentApp.

By default we pass the ullme_email2userid function that only allows @uni-ulm.de email adresses, otherwise cats invalid email and returns NULL as userid and the app shall not allow further login. For the part before @uni-ulm.de we change all non-letters or non-numbers to _. So for sebastian.kranz@uni-ulm.de the userid would become sebastian_kranz. We do not reverse this mapping. Instead the original email address is stored as `email.txt` in the user's directory and read from there when needed.

# TEACHERID and ALLOWED_USERS

The teacherid will typically differ from the main teacher's userid. All teacherid's shall be described in {{main_dir/general/teachers.yaml}}. An example:

```
skranz: sebastian_kranz
esol: erin_solstice
```
Here `skranz` is the teacherid and `sebastian_kranz` the main userid for that teacher. Similar for `esol` and `erin_solstice`.

We shall have a simple function ullme_make_teacher_dirs(main_dir) that reads this file and generates missing teacher directories.

The teacher directory shall have a config subdirectory i.e. it is placed in `{main_dir}/teachers/{teacherid}/config`. There shall be a file `allowed_users.yaml` 

For an example assume `{main_dir}/teachers/skranz/config/allowed_users.yaml` is


```
sebastian_kranz:
  main_teacher: true
  can_set_users: true

max_mustermann:
  can_set_users: false
```

It means that the two users `sebastian_kranz` and `max_mustermann` have access to the teacher studio for the teacher `skranz`.

The teacher studio shall have a users pane that allows to edit the users. The main teacher can never be removed. Only users with can_set_users can edit a teacher's users. Maybe allow to enter email adresses instead of userids, since people know the email adresses not our convention for userids, use the automatic translation function to convert to userid.

# studentid and userid

Every user shall have a random unique studentid. It shall be a random 12 digit letter number combination starting with a letter. In the {maindir}/students folder, we have a folder for this random student id.


# mapping files in {main_dir}/users/{userid} folder

The user folder shall have a studentid.txt file that just contains the studentids and a teacherids.txt file with one row per teacherid the student has access to. The rights will be determined by allowed_users.yaml in the teacher directory but we also want a map in the user directory to see which roles a user has.

If a user log-ins to the teacherapp and has access to multiple teacherid as allowed users let him first choose for which teacher he wants to access.
