# English slide conventions

## Use sentence fragments, not sentences

Slide text should be **noun phrases and fragments**, not full sentences. This is the English equivalent of the Japanese 体言止め rule, and the reasoning is the same: the audience reads the line in one glance, and the speaker supplies the verb out loud instead of reading the slide aloud.

| Avoid | Use |
|---|---|
| We reduced deformation by 66% | 66% reduction in deformation |
| The container is difficult to model | Physical modeling intractable |
| We propose a dual-arm strategy | Dual-arm grasping with role separation |
| The success rate was above 90% | Success rate above 90% |

Drop articles where they carry no meaning ("the container deforms" → "container deformation"). Keep them where removing them would be ambiguous.

Headings carry the claim, not the topic. Write "Success rate above 90% across all targets", not "Experimental results".

**The message band at the bottom may use a full clause** if forcing it into a fragment reads awkwardly. Clarity beats consistency there.

## Punctuation and typography

- No terminal periods on fragments. Use them only inside multi-sentence note text
- Use an en dash `–` for ranges (`20–80 mN`), an em dash `—` for parenthetical breaks
- Non-breaking space between value and unit (`80 mN`, `158 mm`); no space before `%`
- Capitalize headings in sentence case ("Dual-arm grasping reduces deformation"), not Title Case — sentence case reads faster
- Spell out numbers below ten in prose, use numerals for all measurements

## Fonts

```css
font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
```

For decks that mix Latin and CJK, list the Latin face first so digits and Roman text do not fall through to the CJK font.

If exporting to Google Slides, `export_pptx.py` sets `Noto Sans JP` by default because it also covers Latin. For an English-only deck, change `FONT_JP` in that script to `Roboto` or `Arial`, both of which Google Slides has natively.

## Terminology

- Define an acronym on first use in the speaker notes, not on the slide — the slide has no room and the audience will not read a parenthetical
- Prefer "this work" over "we" in headings; "we" is fine when speaking
- Keep terminology identical across slides. If it is a "supporting hand" on slide 7, it is not a "support arm" on slide 9
