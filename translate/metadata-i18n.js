// Strings that Plasma reads from metadata.json through KJsonUtils, not from
// code. KJsonUtils resolves "Name[<lang>]" / "Description[<lang>]" in the
// plasmoid's own translation domain, so they belong in template.pot; this shim
// is what puts them there. It is never executed — Messages.sh only feeds it to
// xgettext.
//
// Keep the arguments byte-for-byte identical to metadata.json, otherwise the
// catalog would translate strings that never reach the screen.
i18n("AI Usage Monitor");
i18n("Multi-service AI quota tracker with cost breakdown (Claude, Antigravity, OpenAI, Grok, Kiro, OpenRouter & Mistral)");
