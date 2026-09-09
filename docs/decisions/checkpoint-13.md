# Checkpoint 13 decisions: Choosing the voice

The Settings screen's Audio section gains a voice picker and a speed slider, and the speaker gains an audio session it never had. A card's pronunciation used to come from `AVSpeechSynthesisVoice(language: "zh-CN")` alone — whichever installed Mandarin voice AVFoundation ranked first, at its own default speed, and silenced outright if the phone's silent switch was on, since nothing had ever told the system this app's speech should play through it. All three are settings now: which installed voice speaks, how fast, and audio that plays regardless of the switch.

One line per decision: what was decided, and why.

D1. Two new columns on the `preference` row, added by migration `v9_voice_and_rate`: `voice_identifier TEXT`, nullable, meaning "let the app choose"; `speech_rate REAL NOT NULL DEFAULT 0.5`, constrained to `AVSpeechUtterance.rate`'s own 0.0-1.0 range. Cited: the same shape checkpoint 6 used for `new_words_per_day` and `speak_on_flip` — one row, no history, seeded to the value that reproduces today's behaviour exactly (no chosen voice, the rate `AVSpeechUtteranceDefaultSpeechRate` itself equals).

D2. `LaoshuKit` stores the voice as a bare `String?` identifier and the rate as a bare `Double`, never an AVFoundation type — it cannot import AVFoundation (`docs/ARCHITECTURE.md`, enforced by `scripts/check-imports`). `Preferences` and `PreferenceStore` gain the two fields and their setters the same way `speakOnFlip` was added; nothing else in the kit reads or writes them, since neither setting changes what a session draws or grades.

D3. `SpeechSpeaker` — still the one file in `Laoshu/` allowed to import AVFoundation — gains `mandarinVoices()`, listing every installed voice whose `language` is exactly `zh-CN`, and `speak(_:voiceIdentifier:rate:)`, which resolves the identifier to an installed `AVSpeechSynthesisVoice` if one still matches, falls back to the first of `mandarinVoices()`, and finally to the old bare `AVSpeechSynthesisVoice(language:)` lookup if the device somehow reports no voices at all. This is this checkpoint's reading of "the speaker's voice-by-language defect" checkpoint 6 named but did not describe: selecting a voice by language alone gives the user no way to ask for a specific one when a device has more than one Mandarin voice installed (the default compact voice and a downloaded enhanced or premium alternative are a real, common case). `SpeechVoiceOption`, a plain `{id, name}` struct with no AVFoundation type in it, is what crosses back out of `SpeechSpeaker.swift` so `SettingsScreen` can list the choices without importing AVFoundation itself.

D4. `SpeechSpeaker.init` now configures `AVAudioSession` to category `.playback`, mode `.spokenAudio`, option `.duckOthers`, and activates it. Cited: this checkpoint's reading of "the audio session," checkpoint 6's other unnamed finding — with no category set at all, `AVSpeechSynthesizer` plays through `.soloAmbient`'s default, which the ring/silent switch mutes. A study app whose whole point is the audio being silenced by a switch the user may not remember is on is a real defect, not a preference; `.duckOthers` rather than fully interrupting other audio, since a card's one-word utterance is short enough not to need the room to itself. A failed activation is swallowed exactly like a missing voice already was (D8 below): speech may then be silenced the way it always was, which is the pre-existing state, not a new failure mode.

D5. Neither setting is carried by `Session` or `LevelTest` the way `direction` and `speakOnFlip` are. `SessionEngine` gains a plain `preferences() throws -> Preferences`, and `SessionView`, `LevelTestView`, and `LevelBrowseView` each read it once, in their existing `.task`, into two `@State` values passed to every `speaker.speak(...)` call. Cited: direction and the new-word count change what a session schedules and how it grades, so `Session` fixes them at the draw and a resumed session keeps what it was drawn with; voice and speed change nothing about scheduling or grading, only what a card sounds like, so there is no scheduling question to answer by carrying them — reading fresh each time a screen opens is simpler and does exactly as much as carrying them would.

D6. The Settings screen's Audio section adds, below the existing toggle: nothing at all if `SpeechSpeaker.mandarinVoices()` is empty (the existing "no voice installed" case, now stated instead of a silent gap); a "Voice" picker, its options `SpeechSpeaker.mandarinVoices()` plus a leading "Default" tagged `nil`, only if more than one voice is installed (a picker with one real choice and a "Default" that means the same thing is clutter, not a setting); and a "Speed" slider, `0...1`, labelled "slower"/"faster" rather than a number, always shown whenever any voice is installed. Every control writes on change with no save button, the existing D8 convention this screen already follows for its other three settings.

D7. No new package dependency, and no change to what a card looks like or how a swipe is graded. Cited: checkpoint 2 D23's pattern, and this checkpoint's own scope: sound only.

## Failure modes

The "Default" picker option and an explicit pick of the same voice that happens to be first in `mandarinVoices()` are indistinguishable in the UI once chosen — both read as whichever voice is actually speaking. Nothing here disambiguates that, and nothing needs to: the letter of D1 is "no chosen voice means the app picks," not "record why."

`.duckOthers` still lets other audio duck rather than stop, so a card's utterance is audible over background music but is not silence-free if something else is playing loudly. This is D4's own tradeoff, not an oversight.

Filtering to exactly `language == "zh-CN"` (D3) excludes a Taiwan Mandarin (`zh-TW`) or Hong Kong Cantonese (`zh-HK`) voice a device might have installed instead of, or alongside, a mainland one — consistent with checkpoint 1 D1's HSK 3.0 syllabus being mainland Mandarin, but a device with only a `zh-TW` voice installed and no `zh-CN` one now reads as having no Mandarin voice at all, the same as before this checkpoint.

## Checks run

- `swift test --package-path LaoshuKit --filter PreferenceTests` — passed, including four new tests for the two settings' defaults, their writers round-tripping, clearing the voice identifier back to "default," the rate's check constraint, and a migration test built on the schema checkpoint 11 shipped, asserting every existing `batch`, `batch_word`, and `review` row survives.
- `swift test --package-path LaoshuKit` — passed, 206 tests total.
- `scripts/check-full` — all six checks and the app build pass.

## Not run here

This environment has no visible simulator window and no UI automation tool (no accessibility-driven `System Events` window, no `idb`) — `osascript` reports zero windows on the `Simulator` process even once frontmost, and `scripts/screenshot` works only because it reads the simulator's framebuffer directly rather than driving a window. The level list alone was screenshotted (checkpoint 9's record); the Settings screen, its new Voice picker and Speed slider, and the change in how a card actually sounds could not be driven or seen here. The user runs this on the phone or in Xcode:

1. Open Settings and confirm the Audio section shows "no Mandarin voice installed" only if genuinely true, otherwise a Speed slider and, if more than one voice is installed, a Voice picker with a working "Default" option.
2. Change the voice and confirm the very next card that speaks — on a study session, a level test, and a browse row's replay button — uses it.
3. Move the Speed slider and confirm the same across all three.
4. Turn the phone's silent switch on and confirm a card still plays its pronunciation.
5. Confirm nothing about the flip, the swipe, or the meaning shown on either card face changed.
