// Apple Notes -> JSON on stdout: every note's folder path, title, HTML
// body, dates, and its attachments saved as files into $SAVE_DIR (Notes is
// sandboxed, so that must be somewhere it can write, e.g. ~/Downloads).
// Unnamed attachments are tables, which are already in the HTML body.
// Run by export.sh.
ObjC.import('stdlib');
const Notes = Application('Notes');
const saveDir = $.getenv('SAVE_DIR');
let saveCount = 0;
const out = { folders: [], notes: [] };
const seenNotes = new Set();
function iso(d) { try { return d.toISOString(); } catch (e) { return null; } }
function walk(folder, path) {
  const here = path.concat([folder.name()]);
  out.folders.push(here);
  const notes = folder.notes;
  for (let i = 0; i < notes.length; i++) {
    const n = notes[i];
    const id = n.id();
    if (seenNotes.has(id)) continue;
    seenNotes.add(id);
    const locked = n.passwordProtected();
    let body = null;
    if (!locked) { try { body = n.body(); } catch (e) { body = null; } }
    const files = [];
    try {
      const atts = n.attachments;
      for (let j = 0; j < atts.length; j++) {
        const name = atts[j].name() || '';
        if (!name) continue;
        let saved = null;
        for (let attempt = 0; attempt < 2 && !saved; attempt++) {
          const target = saveDir + '/' + (saveCount++) + '-' + name.replace(/[\/:]/g, ' ');
          try { Notes.save(atts[j], { in: Path(target) }); saved = target; } catch (e) { delay(0.5); }
        }
        files.push({ name: name, saved: saved });
      }
    } catch (e) {}
    out.notes.push({ id, folder: here, name: n.name(), body, locked,
      created: iso(n.creationDate()), modified: iso(n.modificationDate()), files });
  }
  const subs = folder.folders;
  for (let i = 0; i < subs.length; i++) walk(subs[i], here);
}
const accounts = Notes.accounts;
for (let a = 0; a < accounts.length; a++) {
  const all = accounts[a].folders;
  // Top-level folders are the ones that aren't anyone's subfolder.
  const childIds = new Set();
  for (let i = 0; i < all.length; i++) {
    const subs = all[i].folders;
    for (let j = 0; j < subs.length; j++) childIds.add(subs[j].id());
  }
  for (let i = 0; i < all.length; i++) {
    const f = all[i];
    if (childIds.has(f.id())) continue;
    if (f.name() === 'Recently Deleted') continue;
    walk(f, []);
  }
}
JSON.stringify(out);
