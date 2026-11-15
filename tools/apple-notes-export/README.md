# Apple Notes → Noote

Exports every Apple Notes note to Markdown files that Noote's
**Import Folder…** (the ↑ button in the notes list) brings in.

```bash
tools/apple-notes-export/export.sh            # → ~/Documents/Apple Notes
tools/apple-notes-export/export.sh --replace  # overwrite an earlier export
```

The first run asks for permission to control Notes. Then in Noote, choose
**Import Folder…** and pick the exported folder. If Noote already has a
folder with that name (an earlier import), choose **Add Missing Notes**:
only notes that aren't there yet are added (matched by folder and title),
so notes you've edited in Noote aren't duplicated or overwritten.

What comes over: folders, titles, text, headings, bold/italic/strikethrough,
links, lists, tables, monospaced text (as code), images (as pictures) and
other attachments such as PDFs (as file blocks). Each note keeps its
last-edited date.

What doesn't: checklist ticks (they become bullets), underline, colours and
font sizes, created dates, and locked notes. Attachments Notes refuses to
save through scripting (some voice recordings) are named in the note
instead — drag those out of Apple Notes and into the note by hand.

`dump_notes.js` reads Notes through its scripting dictionary;
`to_markdown.py` converts the result. Neither prints note contents.
