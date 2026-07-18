ullme_tutor_validation_ui = function() {
  restore.point("ullme_tutor_validation_ui")
  tagList(
    tags$div(
      id="ullme_tutor_validation_notice",
      class="ullme-tutor-validation-notice",
      role="status",
      `aria-live`="assertive"
    ),
    tags$section(
      id="ullme_tutor_validation_panel",
      class="ullme-assistant-panel ullme-tutor-validation-panel",
      role="tabpanel",
      `aria-labelledby`="ullme_tutor_validation_tab",
      tags$div(class="ullme-tutor-validation-icon", "!"),
      tags$h2("Tutor definition is invalid"),
      tags$p(
        "This Tutor remains editable, but students cannot use it until all errors are fixed."
      ),
      tags$ul(id="ullme_tutor_validation_errors"),
      tags$p(
        class="ullme-tutor-validation-guidance",
        "Open Tutor YAML or a workflow node, correct the definition, and save again."
      )
    )
  )
}
