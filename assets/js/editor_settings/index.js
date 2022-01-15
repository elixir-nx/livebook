import {
  loadLocalSettings,
  storeLocalSettings,
  EDITOR_FONT_SIZE,
  EDITOR_THEME,
} from "../lib/settings";

/**
 * A hook for the editor settings.
 *
 * Those settings are user-specific and only relevant on the client
 * side, so we store them locally in the browser storage, so that
 * they are persisted across application runs.
 */
const EditorSettings = {
  mounted() {
    const settings = loadLocalSettings();

    const editorAutoCompletionCheckbox = this.el.querySelector(
      `[name="editor_auto_completion"][value="true"]`
    );
    const editorAutoSignatureCheckbox = this.el.querySelector(
      `[name="editor_auto_signature"][value="true"]`
    );
    const editorFontSizeCheckbox = this.el.querySelector(
      `[name="editor_font_size"][value="true"]`
    );
    const editorHighContrastCheckbox = this.el.querySelector(
      `[name="editor_high_contrast"][value="true"]`
    );

    editorAutoCompletionCheckbox.checked = settings.editor_auto_completion;
    editorAutoSignatureCheckbox.checked = settings.editor_auto_signature;
    editorFontSizeCheckbox.checked =
      settings.editor_font_size === EDITOR_FONT_SIZE.large ? true : false;
    editorHighContrastCheckbox.checked =
      settings.editor_theme.name === EDITOR_THEME.highContrast.name
        ? true
        : false;

    editorAutoCompletionCheckbox.addEventListener("change", (event) => {
      storeLocalSettings({ editor_auto_completion: event.target.checked });
    });

    editorAutoSignatureCheckbox.addEventListener("change", (event) => {
      storeLocalSettings({ editor_auto_signature: event.target.checked });
    });

    editorFontSizeCheckbox.addEventListener("change", (event) => {
      storeLocalSettings({
        editor_font_size: event.target.checked
          ? EDITOR_FONT_SIZE.large
          : EDITOR_FONT_SIZE.normal,
      });
    });

    editorHighContrastCheckbox.addEventListener("change", (event) => {
      storeLocalSettings({
        editor_theme: event.target.checked
          ? EDITOR_THEME.highContrast
          : EDITOR_THEME.default,
      });
    });
  },
};

export default EditorSettings;
