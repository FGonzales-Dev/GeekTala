"""Apple Notes (JSON from dump_notes.js) -> a folder of Markdown files for
Noote's Import Folder….

Usage: python3 -I to_markdown.py notes.json OUTPUT_DIR

One .md file per note, in folders mirroring Apple Notes; each file's date is
the note's last edit. Images and other attachments go into an
`_attachments/<note>/` folder beside the note and are linked from it, so
Import Folder… brings them in (images as pictures, other files as file
blocks). Prints only counts, never note contents.
"""

import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from html.parser import HTMLParser
from urllib.parse import quote

VOID = {'br', 'img', 'hr', 'meta', 'input'}
BLOCK = {'div', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li',
         'table', 'tbody', 'thead', 'tr', 'td', 'th', 'object', 'blockquote',
         'pre', 'body', 'html'}
IMAGE_EXT = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'}
CONVERT_EXT = {'heic', 'heif', 'tif', 'tiff'}   # -> jpg with sips
IMG_TOKEN = '\x00IMG:'


class Node:
    def __init__(self, tag, attrs=None, parent=None):
        self.tag, self.attrs, self.parent, self.children = tag, dict(attrs or []), parent, []


class TreeBuilder(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node('root')
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs, self.cur)
        self.cur.children.append(node)
        if tag not in VOID:
            self.cur = node

    def handle_startendtag(self, tag, attrs):
        self.cur.children.append(Node(tag, attrs, self.cur))

    def handle_endtag(self, tag):
        n = self.cur
        while n is not self.root and n.tag != tag:
            n = n.parent
        if n is not self.root:
            self.cur = n.parent

    def handle_data(self, data):
        self.cur.children.append(data)


def parse(html):
    b = TreeBuilder()
    b.feed(html)
    b.close()
    return b.root


# ---------------------------------------------------------------- per note

class Ctx:
    """Where the note being converted keeps its attachments."""
    folder = None          # absolute folder of the .md file
    base = None            # the note's file name without .md
    written = 0            # attachment files written for this note
    inline_images = 0
    inline_hashes = set()  # Apple also lists an embedded picture as a file

    @classmethod
    def start(cls, folder, base):
        cls.folder, cls.base, cls.written, cls.inline_images = folder, base, 0, 0
        cls.inline_hashes = set()

    @classmethod
    def attachment_dir(cls):
        d = os.path.join(cls.folder, '_attachments', cls.base)
        os.makedirs(d, exist_ok=True)
        return d

    @classmethod
    def add_file(cls, src, name):
        """Copies an attachment beside the note (HEIC/TIFF images converted
        to JPEG); returns (relative path, is image)."""
        stem, ext = os.path.splitext(name)
        ext = ext.lower().lstrip('.')
        cls.written += 1
        n = cls.written
        if ext in CONVERT_EXT:
            target = os.path.join(cls.attachment_dir(), f'{n}-{safe_name(stem, "image")}.jpg')
            r = subprocess.run(['sips', '-s', 'format', 'jpeg', src, '--out', target],
                               capture_output=True)
            if r.returncode == 0:
                return os.path.relpath(target, cls.folder), True
        target = os.path.join(cls.attachment_dir(), f'{n}-{safe_name(name, "file")}')
        shutil.copyfile(src, target)
        return os.path.relpath(target, cls.folder), ext in IMAGE_EXT

    @classmethod
    def add_image_bytes(cls, data, ext):
        cls.written += 1
        target = os.path.join(cls.attachment_dir(), f'{cls.written}-image.{ext}')
        with open(target, 'wb') as f:
            f.write(data)
        cls.inline_images += 1
        cls.inline_hashes.add(hashlib.sha256(data).hexdigest())
        return os.path.relpath(target, cls.folder)


def link(rel):
    return quote(rel.replace(os.sep, '/'))


def inline_image(node):
    """An <img> with the picture embedded (data: URI) -> a token the block
    writer turns into its own image line."""
    src = node.attrs.get('src', '')
    m = re.match(r'data:image/([a-zA-Z0-9.+-]+);base64,(.*)', src, re.S)
    if not m:
        return ''
    ext = {'jpeg': 'jpg', 'svg+xml': None}.get(m.group(1).lower(), m.group(1).lower())
    if ext not in IMAGE_EXT:
        return ''
    try:
        data = base64.b64decode(m.group(2))
    except Exception:
        return ''
    return '\n' + IMG_TOKEN + Ctx.add_image_bytes(data, ext) + '\x00\n'


# ---------------------------------------------------------------- inline

ESCAPE = re.compile(r'([\\`*\[\]~|])')
# Left exactly as written: escapes in a web or email address would show up
# as literal backslashes once the editor turns it into a link.
ADDRESS = re.compile(r'(https?://[^\s<>]+|www\.[^\s<>]+|[\w.+-]+@[\w-]+\.[\w.-]+)')
# `_` only starts or ends italics next to a non-letter; snake_case is safe.
EDGE_UNDERSCORE = re.compile(r'(?<![A-Za-z0-9])_|_(?![A-Za-z0-9])')


def esc(text):
    parts = ADDRESS.split(text)
    return ''.join(
        part if i % 2 else EDGE_UNDERSCORE.sub(r'\\_', ESCAPE.sub(r'\\\1', part))
        for i, part in enumerate(parts)
    )


def esc_line_start(line):
    """Stop plain text being read as a heading, list, quote or rule."""
    m = re.match(r'^(\s*)(#{1,6}\s|>|[-+*]\s|\d+[.)]\s)', line)
    if m:
        lead = m.group(1)
        rest = line[len(lead):]
        if rest[0].isdigit():
            num = re.match(r'\d+', rest).group(0)
            return lead + num + '\\' + rest[len(num):]
        return lead + '\\' + rest
    return line


def inline(node, code=False):
    """Markdown for inline content; '\n' marks a line break."""
    if isinstance(node, str):
        text = node.replace('\xa0', ' ')
        return text if code else esc(text)
    tag = node.tag
    if tag == 'br':
        return '\n'
    if tag == 'img':
        return inline_image(node)
    inner = ''.join(inline(c, code or tag == 'tt') for c in node.children)
    if tag == 'tt' and not code:
        return wrap_code(inner)
    if tag in ('b', 'strong'):
        return wrap(inner, '**')
    if tag in ('i', 'em'):
        return wrap(inner, '_')
    if tag in ('strike', 's', 'del'):
        return wrap(inner, '~~')
    if tag == 'a' and node.attrs.get('href'):
        label = inner.strip() or node.attrs['href']
        return f"[{label}]({node.attrs['href'].replace(')', '%29').replace(' ', '%20')})"
    return inner  # u, font, span, …: text only


def wrap(inner, mark):
    """`**x**`, keeping surrounding spaces outside the markers."""
    if not inner.strip():
        return inner
    lead = inner[:len(inner) - len(inner.lstrip())]
    trail = inner[len(inner.rstrip()):]
    parts = inner.strip().split('\n')
    return lead + '\n'.join(
        f'{mark}{p.strip()}{mark}' if p.strip() and not p.startswith(IMG_TOKEN) else p
        for p in parts) + trail


def wrap_code(inner):
    if not inner.strip():
        return inner
    out = []
    for p in inner.split('\n'):
        if not p.strip():
            out.append(p)
            continue
        fence = '``' if '`' in p else '`'
        pad = ' ' if p.startswith('`') or p.endswith('`') else ''
        out.append(f'{fence}{pad}{p}{pad}{fence}')
    return '\n'.join(out)


def plain_text(node):
    if isinstance(node, str):
        return node.replace('\xa0', ' ')
    if node.tag == 'br':
        return '\n'
    return ''.join(plain_text(c) for c in node.children)


def is_all_tt(node):
    """A line whose text is all monospaced (Apple Notes' "Monostyled")."""
    has_text = False

    def walk(n, in_tt):
        nonlocal has_text
        if isinstance(n, str):
            if n.strip():
                has_text = True
                return in_tt
            return True
        if n.tag == 'br':
            return True
        if n.tag == 'img':
            return False
        return all(walk(c, in_tt or n.tag == 'tt') for c in n.children)

    return walk(node, False) and has_text


# ---------------------------------------------------------------- blocks

def is_block(node):
    return not isinstance(node, str) and node.tag in BLOCK


class Writer:
    def __init__(self):
        self.blocks = []   # list of (kind, text)

    def para(self, md):
        for line in md.split('\n'):
            stripped = line.strip()
            if stripped.startswith(IMG_TOKEN):
                rel = stripped[len(IMG_TOKEN):].rstrip('\x00')
                self.blocks.append(('img', f'![]({link(rel)})'))
            elif stripped:
                self.blocks.append(('p', esc_line_start(stripped)))
            else:
                self.blocks.append(('blank', ''))

    def code_line(self, text):
        self.blocks.append(('code', text))

    def raw(self, kind, text):
        self.blocks.append((kind, text))


def block(node, w):
    if isinstance(node, str):
        if node.strip():
            w.para(inline(node))
        return
    tag = node.tag
    if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
        text = ' '.join(inline(c) for c in node.children).replace('\n', ' ').strip()
        if text:
            w.raw('h', '#' * min(int(tag[1]), 3) + ' ' + text)
        return
    if tag in ('ul', 'ol'):
        list_block(node, w, depth=0)
        return
    if tag == 'table':
        table_block(node, w)
        return
    if tag == 'img':
        w.para(inline_image(node))
        return
    if tag in ('div', 'p', 'object', 'blockquote', 'pre', 'body', 'html', 'root',
               'tbody', 'thead', 'tr', 'td', 'th', 'li'):
        children = node.children
        if not any(is_block(c) for c in children):
            if tag in ('div', 'p') and is_all_tt(node):
                for line in plain_text(node).split('\n'):
                    w.code_line(line.rstrip())
                return
            md = ''.join(inline(c) for c in children)
            if not md.strip():
                w.raw('blank', '')
                return
            w.para(md)
            return
        run = []
        for c in children:
            if is_block(c):
                if run:
                    md = ''.join(inline(x) for x in run)
                    if md.strip():
                        w.para(md)
                    run = []
                block(c, w)
            else:
                run.append(c)
        if run:
            md = ''.join(inline(x) for x in run)
            if md.strip():
                w.para(md)
        return
    md = inline(node)
    if md.strip():
        w.para(md)


def strip_tokens(text):
    return re.sub(re.escape(IMG_TOKEN) + r'[^\x00]*\x00', '', text)


def list_block(node, w, depth):
    ordered = node.tag == 'ol'
    number = 1
    indent = '    ' * depth
    for c in node.children:
        if isinstance(c, str) or c.tag == 'br':
            continue
        if c.tag in ('ul', 'ol'):  # Apple Notes nests lists directly
            list_block(c, w, depth + 1)
            continue
        if c.tag != 'li':
            continue
        inline_parts, nested = [], []
        for x in c.children:
            if not isinstance(x, str) and x.tag in ('ul', 'ol'):
                nested.append(x)
            else:
                inline_parts.append(x)
        text = ''.join(inline(x) if not is_block(x) else ' ' + inline_flat(x) for x in inline_parts)
        text = ' '.join(t.strip() for t in strip_tokens(text).split('\n') if t.strip())
        marker = f'{number}.' if ordered else '-'
        w.raw('li', f'{indent}{marker} {text}' if text else f'{indent}{marker}')
        number += 1
        for n in nested:
            list_block(n, w, depth + 1)


def inline_flat(node):
    return ''.join(inline(c) for c in node.children)


def table_block(node, w):
    rows = []

    def collect(n):
        for c in n.children:
            if isinstance(c, str):
                continue
            if c.tag == 'tr':
                rows.append([cell_text(td) for td in c.children
                             if not isinstance(td, str) and td.tag in ('td', 'th')])
            else:
                collect(c)

    collect(node)
    rows = [r for r in rows if r]
    if not rows:
        return
    width = max(len(r) for r in rows)
    rows = [r + [''] * (width - len(r)) for r in rows]
    w.raw('table', '| ' + ' | '.join(rows[0]) + ' |')
    w.raw('table', '|' + '|'.join(['---'] * width) + '|')
    for r in rows[1:]:
        w.raw('table', '| ' + ' | '.join(r) + ' |')


def cell_text(td):
    parts = []

    def walk(n):
        if isinstance(n, str) or not is_block(n):
            parts.append(inline(n))
            return
        before = len(parts)
        for c in n.children:
            walk(c)
        if n.tag in ('div', 'p', 'li') and len(parts) > before:
            parts.append('\n')

    for c in td.children:
        walk(c)
    lines = [l.strip() for l in strip_tokens(''.join(parts)).split('\n') if l.strip()]
    return ' / '.join(lines)


def render(blocks):
    out = []
    prev = None
    code = []

    def flush_code():
        while code and not code[-1].strip():
            code.pop()
        if code:
            fence = '````' if any('```' in l for l in code) else '```'
            out.append(fence + '\n' + '\n'.join(code) + '\n' + fence)
        code.clear()

    for kind, text in blocks:
        if kind == 'code':
            if not code and not text.strip():
                continue
            code.append(text)
            prev = kind
            continue
        if code:
            flush_code()
        if kind == 'blank':
            prev = kind
            continue
        if kind in ('li', 'table') and prev == kind:
            out[-1] += '\n' + text
        else:
            out.append(text)
        prev = kind
    flush_code()
    return '\n\n'.join(out).strip() + '\n'


# ---------------------------------------------------------------- notes

def note_markdown(note, stats):
    w = Writer()
    block(parse(note['body'] or ''), w)
    blocks = w.blocks
    # Apple Notes repeats the title as the first line of the body.
    name = (note['name'] or '').strip()
    for i, (kind, text) in enumerate(blocks):
        if kind == 'blank':
            continue
        if kind != 'img':
            bare = re.sub(r'^#+\s*', '', text)
            bare = re.sub(r'[*_~`\\]', '', bare).strip()
            if bare == re.sub(r'[*_~`\\]', '', name).strip():
                blocks = blocks[i + 1:]
        break
    md = render(blocks) if blocks else ''

    # Files attached to the note go at the end (Apple doesn't say where in
    # the note they were): images as pictures, anything else as a link on
    # its own line (a file block once imported). Ones Notes wouldn't save
    # are named instead.
    lines, unsaved = [], []
    for f in note.get('files', []):
        src = f.get('saved')
        if not src or not os.path.exists(src):
            unsaved.append(f['name'])
            continue
        with open(src, 'rb') as fh:
            if hashlib.sha256(fh.read()).hexdigest() in Ctx.inline_hashes:
                continue  # already in the note, where it was
        rel, is_image = Ctx.add_file(src, f['name'])
        if is_image:
            lines.append(f'![]({link(rel)})')
            stats['images'] += 1
        else:
            lines.append(f'[{esc(f["name"])}]({link(rel)})')
            stats['files'] += 1
    stats['images'] += Ctx.inline_images
    stats['unsaved'] += len(unsaved)
    if lines or unsaved:
        section = ['## Attachments', ''] + [l + '\n' for l in lines]
        if unsaved:
            section.append('_Still in Apple Notes (couldn\'t be copied): '
                           + ', '.join(esc(u) for u in unsaved) + '._')
        md += ('\n' if md.strip() else '') + '\n'.join(section).rstrip() + '\n'
    return md


def safe_name(name, fallback='Untitled'):
    name = re.sub(r'[\x00-\x1f/\\:*?"<>|]', ' ', name or '').strip().strip('.')
    name = re.sub(r'\s+', ' ', name)[:100].strip()
    return name or fallback


def main():
    data = json.load(open(sys.argv[1]))
    out_dir = sys.argv[2]
    os.makedirs(out_dir, exist_ok=False)
    used = set()
    stats = {'notes': 0, 'images': 0, 'files': 0, 'unsaved': 0, 'title_only': 0}
    for note in data['notes']:
        folder = os.path.join(out_dir, *[safe_name(p, 'Folder') for p in note['folder']])
        os.makedirs(folder, exist_ok=True)
        base = safe_name(note['name'])
        path = os.path.join(folder, base + '.md')
        k = 2
        while path.lower() in used:
            path = os.path.join(folder, f'{base} ({k}).md')
            k += 1
        used.add(path.lower())
        Ctx.start(folder, os.path.splitext(os.path.basename(path))[0])
        md = note_markdown(note, stats)
        if not md.strip():
            stats['title_only'] += 1
        with open(path, 'w', encoding='utf-8') as f:
            f.write(md)
        when = note['modified'] or note['created']
        if when:
            ts = datetime.fromisoformat(when.replace('Z', '+00:00')).timestamp()
            os.utime(path, (ts, ts))
        stats['notes'] += 1
    for f in data['folders']:
        os.makedirs(os.path.join(out_dir, *[safe_name(p, 'Folder') for p in f]), exist_ok=True)
    print(f"wrote {stats['notes']} notes with {stats['images']} images and "
          f"{stats['files']} other files; {stats['unsaved']} attachments "
          f"couldn't be copied out of Notes; {stats['title_only']} notes have "
          f"only a title")


if __name__ == '__main__':
    main()
