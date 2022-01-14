import { loadLocalSettings } from "../../lib/settings"

// This is a port of the One Dark theme to the Monaco editor.
const colors = {
  default: "#abb2bf",
  lightRed: "#e06c75",
  blue: "#61afef",
  gray: "#737a8c",
  green: "#98c379",
  purple: "#c678dd",
  red: "#be5046",
  teal: "#56b6c2",
  peach: "#d19a66",
};

const settings = loadLocalSettings()

const theme = {
  base: "vs-dark",
  inherit: false,
  rules: [
    { token: "", foreground: colors.default },
    { token: "variable", foreground: colors.lightRed },
    { token: "constant", foreground: colors.blue },
    { token: "constant.character.escape", foreground: colors.blue },
    { token: "comment", foreground: colors.gray },
    { token: "number", foreground: colors.blue },
    { token: "regexp", foreground: colors.lightRed },
    { token: "type", foreground: colors.lightRed },
    { token: "string", foreground: colors.green },
    { token: "keyword", foreground: colors.purple },
    { token: "operator", foreground: colors.peach },
    { token: "delimiter.bracket.embed", foreground: colors.red },
    { token: "sigil", foreground: colors.teal },
    { token: "function", foreground: colors.blue },
    { token: "function.call", foreground: colors.default },

    // Markdown specific
    { token: "emphasis", fontStyle: "italic" },
    { token: "strong", fontStyle: "bold" },
    { token: "keyword.md", foreground: colors.lightRed },
    { token: "keyword.table", foreground: colors.lightRed },
    { token: "string.link.md", foreground: colors.blue },
    { token: "variable.md", foreground: colors.teal },
    { token: "string.md", foreground: colors.default },
    { token: "variable.source.md", foreground: colors.default },

    // XML specific
    { token: "tag", foreground: colors.lightRed },
    { token: "metatag", foreground: colors.lightRed },
    { token: "attribute.name", foreground: colors.peach },
    { token: "attribute.value", foreground: colors.green },

    // JSON specific
    { token: "string.key", foreground: colors.lightRed },
    { token: "keyword.json", foreground: colors.blue },
  ],

  colors: {
    "editor.background": settings.editor_background_color,
    "editor.foreground": colors.default,
    "editorLineNumber.foreground": "#636d83",
    "editorCursor.foreground": "#636d83",
    "editor.selectionBackground": "#3e4451",
    "editor.findMatchHighlightBackground": "#528bff3D",
    "editorSuggestWidget.background": "#21252b",
    "editorSuggestWidget.border": "#181a1f",
    "editorSuggestWidget.selectedBackground": "#2c313a",
    "input.background": "#1b1d23",
    "input.border": "#181a1f",
    "editorBracketMatch.border": "#282c34",
    "editorBracketMatch.background": "#3e4451",
  },
};

export default theme;
